-- Migration 056: Robust School and User Access Verification
-- Ensures client apps (admin dashboard and student mobile app) can authoritatively
-- verify suspension and active status without being blocked by RLS.

-- 1. Ensure public/authenticated read access to schools so clients can always check is_active/status
DROP POLICY IF EXISTS "Schools viewable by authenticated users" ON public.schools;
CREATE POLICY "Schools viewable by authenticated users"
ON public.schools FOR SELECT
TO authenticated, anon
USING (true);

-- 2. Ensure authenticated users can read their school's subscription status
DROP POLICY IF EXISTS "Subscriptions viewable by authenticated users" ON public.school_subscriptions;
CREATE POLICY "Subscriptions viewable by authenticated users"
ON public.school_subscriptions FOR SELECT
TO authenticated, anon
USING (true);

-- 3. Dedicated authoritative function to verify school status by school ID
CREATE OR REPLACE FUNCTION public.check_school_active_status(p_school_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_school RECORD;
  v_sub RECORD;
  v_is_suspended BOOLEAN := false;
  v_reason TEXT := NULL;
BEGIN
  IF p_school_id IS NULL THEN
    RETURN jsonb_build_object(
      'exists', false,
      'is_suspended', false,
      'is_active', true
    );
  END IF;

  SELECT id, is_active, status
  INTO v_school
  FROM public.schools
  WHERE id = p_school_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'exists', false,
      'is_suspended', true,
      'is_active', false,
      'reason', 'school_not_found'
    );
  END IF;

  IF v_school.is_active = false OR v_school.status IN ('suspended', 'inactive') THEN
    v_is_suspended := true;
    v_reason := 'school_inactive';
  END IF;

  SELECT status
  INTO v_sub
  FROM public.school_subscriptions
  WHERE school_id = p_school_id
  ORDER BY created_at DESC
  LIMIT 1;

  IF FOUND AND v_sub.status = 'suspended' THEN
    v_is_suspended := true;
    v_reason := 'subscription_suspended';
  END IF;

  RETURN jsonb_build_object(
    'exists', true,
    'school_id', v_school.id,
    'is_active', CASE WHEN v_is_suspended THEN false ELSE v_school.is_active END,
    'school_status', v_school.status,
    'sub_status', v_sub.status,
    'is_suspended', v_is_suspended,
    'reason', v_reason
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.check_school_active_status(UUID) TO authenticated, anon, service_role;

-- 4. Authoritative check_user_access_status function
CREATE OR REPLACE FUNCTION public.check_user_access_status()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user RECORD;
  v_school RECORD;
  v_sub RECORD;
  v_is_locked BOOLEAN := false;
  v_reason TEXT := NULL;
BEGIN
  SELECT id, school_id, is_active, account_status, role
  INTO v_user
  FROM public.users
  WHERE id = auth.uid();

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'authenticated', false,
      'is_locked', true,
      'reason', 'user_not_found'
    );
  END IF;

  -- Super admin is never locked out of the system
  IF v_user.role = 'super_admin' THEN
    RETURN jsonb_build_object(
      'authenticated', true,
      'user_id', v_user.id,
      'is_locked', false,
      'user_is_active', true,
      'user_account_status', 'active',
      'reason', NULL
    );
  END IF;

  -- 1. Check user status
  IF v_user.is_active = false OR v_user.account_status IN ('paused_unpaid', 'suspended') THEN
    v_is_locked := true;
    v_reason := 'user_suspended';
  END IF;

  -- 2. Check school status
  IF v_user.school_id IS NOT NULL THEN
    SELECT id, is_active, status
    INTO v_school
    FROM public.schools
    WHERE id = v_user.school_id;

    IF NOT FOUND THEN
      v_is_locked := true;
      v_reason := 'school_suspended';
    ELSIF v_school.is_active = false OR v_school.status IN ('suspended', 'inactive') THEN
      v_is_locked := true;
      v_reason := 'school_suspended';
    END IF;

    SELECT status
    INTO v_sub
    FROM public.school_subscriptions
    WHERE school_id = v_user.school_id
    ORDER BY created_at DESC
    LIMIT 1;

    IF FOUND AND v_sub.status = 'suspended' THEN
      v_is_locked := true;
      v_reason := 'school_suspended';
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'authenticated', true,
    'user_id', v_user.id,
    'school_id', v_user.school_id,
    'is_locked', v_is_locked,
    'user_is_active', v_user.is_active,
    'user_account_status', v_user.account_status,
    'reason', v_reason
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.check_user_access_status() TO authenticated, anon, service_role;
