-- ==============================================================================
-- 053: Security Fix for User Archiving & Administrative Status Mutation
-- ==============================================================================

-- 1. Upgrade is_school_admin() to recognize service_role and JWT role claims
CREATE OR REPLACE FUNCTION public.is_school_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    auth.role() = 'service_role' OR
    (auth.jwt() -> 'user_metadata' ->> 'role') IN ('super_admin', 'owner', 'admin', 'staff') OR
    (auth.jwt() ->> 'role') IN ('super_admin', 'owner', 'admin', 'staff') OR
    public.get_user_role() IN ('super_admin', 'owner', 'admin', 'staff'),
    false
  );
$$;

-- 2. Upgrade prevent_user_privilege_escalation() to allow service_role and trusted RPC bypass
CREATE OR REPLACE FUNCTION public.prevent_user_privilege_escalation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_is_super BOOLEAN;
  v_req_id TEXT;
BEGIN
  -- Bypass if explicitly permitted by trusted RPC or service_role
  IF current_setting('app.bypass_privilege_check', true) = 'on' OR auth.role() = 'service_role' THEN
    RETURN NEW;
  END IF;

  v_is_super := public.is_super_admin();
  IF v_is_super THEN
    RETURN NEW;
  END IF;

  v_req_id := public.current_request_id();

  -- Disallow regular users from escalating their own role
  IF NEW.role IS DISTINCT FROM OLD.role THEN
    IF NOT public.is_super_admin() THEN
      RAISE EXCEPTION 'P0002: Security violation: Changing user role is strictly restricted to platform administrators.';
    END IF;
  END IF;

  -- Disallow users from altering school_id (tenant hopping)
  IF NEW.school_id IS DISTINCT FROM OLD.school_id THEN
    IF NOT public.is_super_admin() THEN
      RAISE EXCEPTION 'P0002: Security violation: Altering tenant assignment is prohibited.';
    END IF;
  END IF;

  -- Disallow non-admins from changing account_status
  IF NEW.account_status IS DISTINCT FROM OLD.account_status AND NOT public.is_school_admin() THEN
    RAISE EXCEPTION 'P0002: Security violation: Account status is controlled exclusively by school administrators.';
  END IF;

  -- Disallow non-admins from toggling is_active
  IF NEW.is_active IS DISTINCT FROM OLD.is_active AND NOT public.is_school_admin() THEN
    RAISE EXCEPTION 'P0002: Security violation: Cannot alter active status.';
  END IF;

  RETURN NEW;
END;
$$;

-- 3. Dedicated SECURITY DEFINER RPC to safely toggle active status for users
CREATE OR REPLACE FUNCTION public.toggle_user_active_status(p_user_ids UUID[], p_is_active BOOLEAN)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INT;
BEGIN
  PERFORM set_config('app.bypass_privilege_check', 'on', true);

  UPDATE public.users
  SET is_active = p_is_active, updated_at = NOW()
  WHERE id = ANY(p_user_ids);

  GET DIAGNOSTICS v_count = ROW_COUNT;

  UPDATE public.enrollments
  SET is_active = p_is_active
  WHERE user_id = ANY(p_user_ids);

  RETURN jsonb_build_object('success', true, 'count', v_count);
END;
$$;

GRANT EXECUTE ON FUNCTION public.toggle_user_active_status(UUID[], BOOLEAN) TO authenticated, anon, service_role;
