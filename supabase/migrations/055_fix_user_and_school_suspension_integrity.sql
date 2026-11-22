-- Migration 055: Fix user and school suspension integrity and verification security

-- 1. Update toggle_user_active_status to atomically set is_active AND account_status
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
  SET 
    is_active = p_is_active,
    account_status = CASE WHEN p_is_active THEN 'active' ELSE 'paused_unpaid' END,
    updated_at = NOW()
  WHERE id = ANY(p_user_ids);

  GET DIAGNOSTICS v_count = ROW_COUNT;

  UPDATE public.enrollments
  SET is_active = p_is_active
  WHERE user_id = ANY(p_user_ids);

  RETURN jsonb_build_object('success', true, 'count', v_count);
END;
$$;

GRANT EXECUTE ON FUNCTION public.toggle_user_active_status(UUID[], BOOLEAN) TO authenticated, anon, service_role;

-- 2. Synchronize existing user data across is_active and account_status
UPDATE public.users
SET account_status = 'paused_unpaid'
WHERE is_active = false AND account_status = 'active';

UPDATE public.users
SET is_active = false
WHERE account_status IN ('paused_unpaid', 'suspended') AND is_active = true;

-- 3. Dedicated authoritative function to verify access lock state
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

  -- 1. Check user status
  IF v_user.is_active = false OR v_user.account_status IN ('paused_unpaid', 'suspended') THEN
    v_is_locked := true;
    v_reason := 'user_suspended';
  END IF;

  -- 2. Check school status
  IF v_user.school_id IS NOT NULL THEN
    SELECT id, is_active
    INTO v_school
    FROM public.schools
    WHERE id = v_user.school_id;

    IF FOUND AND (v_school.is_active = false) THEN
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
    'is_locked', v_is_locked,
    'user_is_active', v_user.is_active,
    'user_account_status', v_user.account_status,
    'reason', v_reason
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.check_user_access_status() TO authenticated, service_role;
