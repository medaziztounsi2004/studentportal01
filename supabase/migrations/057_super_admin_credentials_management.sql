-- ============================================================================
-- MIGRATION 057: SUPER ADMIN CREDENTIALS & PASSWORD MANAGEMENT
-- ============================================================================
-- Description:
--   1. Authoritative SECURITY DEFINER RPC for super admins to reset/set passwords
--   2. Keeps auth.users encrypted_password and public.users initial_password in sync
--   3. Guarantees super admins can unhide and update school passwords reliably
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE OR REPLACE FUNCTION public.super_admin_reset_password(
    p_user_id UUID,
    p_new_password TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, extensions
AS $$
DECLARE
    v_caller_role TEXT;
    v_user_email TEXT;
BEGIN
    -- 1. Authorization: Only super_admin can invoke this function
    v_caller_role := public.get_user_role();
    IF v_caller_role != 'super_admin' AND NOT public.is_super_admin() THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Forbidden: Seul le super administrateur est autorisé à réinitialiser les mots de passe.'
        );
    END IF;

    -- 2. Validation
    IF p_new_password IS NULL OR length(trim(p_new_password)) < 6 THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Le mot de passe doit comporter au moins 6 caractères.'
        );
    END IF;

    -- 3. Check target user exists
    SELECT email INTO v_user_email FROM public.users WHERE id = p_user_id;
    IF v_user_email IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Utilisateur introuvable.'
        );
    END IF;

    -- 4. Update auth.users encrypted_password using bcrypt
    UPDATE auth.users
    SET encrypted_password = extensions.crypt(p_new_password, extensions.gen_salt('bf')),
        updated_at = NOW()
    WHERE id = p_user_id;

    -- 5. Update public.users initial_password for SaaS console visibility
    UPDATE public.users
    SET initial_password = p_new_password,
        force_password_change = false,
        updated_at = NOW()
    WHERE id = p_user_id;

    RETURN jsonb_build_object(
        'success', true,
        'password', p_new_password
    );
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', false,
        'error', SQLERRM
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.super_admin_reset_password(UUID, TEXT) TO authenticated;
