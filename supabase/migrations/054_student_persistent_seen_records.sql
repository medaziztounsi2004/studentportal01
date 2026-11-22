-- ==============================================================================
-- 054: Student Persistent Seen/Read Status Tracking
-- ==============================================================================
-- Description:
--   Enables persistent storage of student read/seen states across devices and reinstalls
--   for:
--     1. Announcements (global notifications)
--     2. Documents
--     3. Messages (class / personal messages)
--     4. Suggestion replies
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.student_seen_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    item_type TEXT NOT NULL CHECK (item_type IN ('announcement', 'document', 'message', 'suggestion_reply')),
    item_id TEXT NOT NULL,
    seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT student_seen_items_unique UNIQUE (student_id, item_type, item_id)
);

CREATE INDEX IF NOT EXISTS idx_student_seen_items_student ON public.student_seen_items(student_id);
CREATE INDEX IF NOT EXISTS idx_student_seen_items_type ON public.student_seen_items(student_id, item_type);

-- Enable RLS
ALTER TABLE public.student_seen_items ENABLE ROW LEVEL SECURITY;

-- Policies
DROP POLICY IF EXISTS "Students can view their own seen items" ON public.student_seen_items;
CREATE POLICY "Students can view their own seen items"
    ON public.student_seen_items FOR SELECT TO authenticated
    USING (student_id = auth.uid() OR public.is_school_admin() OR public.is_super_admin());

DROP POLICY IF EXISTS "Students can insert their own seen items" ON public.student_seen_items;
CREATE POLICY "Students can insert their own seen items"
    ON public.student_seen_items FOR INSERT TO authenticated
    WITH CHECK (student_id = auth.uid() OR public.is_school_admin() OR public.is_super_admin());

DROP POLICY IF EXISTS "Students can update their own seen items" ON public.student_seen_items;
CREATE POLICY "Students can update their own seen items"
    ON public.student_seen_items FOR UPDATE TO authenticated
    USING (student_id = auth.uid() OR public.is_school_admin() OR public.is_super_admin())
    WITH CHECK (student_id = auth.uid() OR public.is_school_admin() OR public.is_super_admin());

DROP POLICY IF EXISTS "Students can delete their own seen items" ON public.student_seen_items;
CREATE POLICY "Students can delete their own seen items"
    ON public.student_seen_items FOR DELETE TO authenticated
    USING (student_id = auth.uid() OR public.is_school_admin() OR public.is_super_admin());

-- RPC: mark a single item as seen
CREATE OR REPLACE FUNCTION public.mark_student_item_seen(
    p_item_type TEXT,
    p_item_id TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Not authenticated');
    END IF;

    INSERT INTO public.student_seen_items (student_id, item_type, item_id, seen_at)
    VALUES (v_user_id, p_item_type, p_item_id, NOW())
    ON CONFLICT (student_id, item_type, item_id)
    DO UPDATE SET seen_at = NOW();

    RETURN jsonb_build_object('success', true, 'student_id', v_user_id, 'item_type', p_item_type, 'item_id', p_item_id);
END;
$$;

-- RPC: batch mark multiple items as seen
CREATE OR REPLACE FUNCTION public.mark_student_items_seen(
    p_item_type TEXT,
    p_item_ids TEXT[]
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
    v_id TEXT;
    v_count INT := 0;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Not authenticated');
    END IF;

    IF p_item_ids IS NOT NULL AND array_length(p_item_ids, 1) > 0 THEN
        FOREACH v_id IN ARRAY p_item_ids LOOP
            INSERT INTO public.student_seen_items (student_id, item_type, item_id, seen_at)
            VALUES (v_user_id, p_item_type, v_id, NOW())
            ON CONFLICT (student_id, item_type, item_id)
            DO UPDATE SET seen_at = NOW();
            v_count := v_count + 1;
        END LOOP;
    END IF;

    RETURN jsonb_build_object('success', true, 'count', v_count);
END;
$$;

-- RPC: get all seen item IDs for current student (optionally filtered by item_type)
CREATE OR REPLACE FUNCTION public.get_student_seen_items(
    p_item_type TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
    v_result JSONB;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object();
    END IF;

    SELECT jsonb_object_agg(item_type, item_ids)
    INTO v_result
    FROM (
        SELECT 
            item_type, 
            jsonb_agg(item_id ORDER BY seen_at DESC) AS item_ids
        FROM public.student_seen_items
        WHERE student_id = v_user_id
          AND (p_item_type IS NULL OR item_type = p_item_type)
        GROUP BY item_type
    ) sub;

    RETURN COALESCE(v_result, jsonb_build_object());
END;
$$;

-- Grants
GRANT ALL ON public.student_seen_items TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.mark_student_item_seen(TEXT, TEXT) TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.mark_student_items_seen(TEXT, TEXT[]) TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_student_seen_items(TEXT) TO authenticated, anon, service_role;
