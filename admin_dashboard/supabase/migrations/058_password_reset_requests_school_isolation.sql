-- Migration 058: Add school_id to password_reset_requests and enforce multi-tenant isolation
ALTER TABLE public.password_reset_requests 
ADD COLUMN IF NOT EXISTS school_id UUID REFERENCES public.schools(id) ON DELETE CASCADE;

-- Backfill school_id from users table
UPDATE public.password_reset_requests prr
SET school_id = u.school_id
FROM public.users u
WHERE prr.user_id = u.id AND prr.school_id IS NULL;

-- Index for fast lookup by school_id
CREATE INDEX IF NOT EXISTS idx_password_reset_requests_school_id 
ON public.password_reset_requests(school_id);

-- Drop previous function if return type was UUID
DROP FUNCTION IF EXISTS public.create_password_reset_request(TEXT);

-- Update create_password_reset_request function to store school_id
CREATE OR REPLACE FUNCTION public.create_password_reset_request(p_email TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_identifier TEXT := LOWER(TRIM(COALESCE(p_email, '')));
  v_user       RECORD;
  v_req_id     UUID;
BEGIN
  IF v_identifier = '' THEN
    RAISE EXCEPTION 'Email or matricule is required';
  END IF;

  SELECT id, email, full_name, school_id
  INTO v_user
  FROM public.users
  WHERE LOWER(email) = v_identifier
     OR LOWER(COALESCE(student_code, '')) = v_identifier
  LIMIT 1;

  INSERT INTO public.password_reset_requests (
    id,
    user_id,
    school_id,
    email,
    full_name,
    status,
    requested_at,
    created_at
  )
  VALUES (
    gen_random_uuid(),
    v_user.id,
    v_user.school_id,
    COALESCE(v_user.email, v_identifier),
    COALESCE(v_user.full_name, 'Élève (' || v_identifier || ')'),
    'pending',
    NOW(),
    NOW()
  )
  RETURNING id INTO v_req_id;

  RETURN jsonb_build_object(
    'success', true,
    'request_id', v_req_id,
    'account_linked', v_user.id IS NOT NULL,
    'message', CASE
      WHEN v_user.id IS NOT NULL
        THEN 'Demande enregistrée. L''administration traitera votre demande.'
      ELSE 'Demande enregistrée. Aucun compte immédiatement associé, l''administration vérifiera manuellement.'
    END
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_password_reset_request(TEXT) TO anon, authenticated;
