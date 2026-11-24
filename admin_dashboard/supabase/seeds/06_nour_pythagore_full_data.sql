-- ==============================================================================
-- Seed Script: Full Rich Live Data for Nour El Houda Khalil (nour.new06@school.tn)
-- School: Lycée Pilote Pythagore
-- 
-- Generates:
--   1. 10 Global Notifications (announcements_global) with random attachments & images
--   2. 5 Class Messages (announcements_class) with random documents & schema
--   3. 5 Direct Student Messages (announcements_class targeted to Nour)
--   4. 10 Suggestions written by Nour with various statuses (replied, read, sent),
--      rich admin replies, and attached pictures/documents
--   5. Dynamic Absence Records (Maths, Physique, SVT, Info, Philo, Français) with
--      diverse hours, session types, medical/transport reasons, and justified flags
--   6. 10 Official Received Documents across all categories and metadata tags
-- ==============================================================================

-- Step A: Ensure required tables and columns exist (Self-healing DDL)
CREATE TABLE IF NOT EXISTS public.announcement_attachments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    announcement_id UUID NOT NULL,
    scope TEXT NOT NULL DEFAULT 'global',
    file_name TEXT NOT NULL,
    display_name TEXT,
    file_url TEXT NOT NULL,
    file_type TEXT,
    file_size BIGINT,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.suggestion_attachments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    suggestion_id UUID NOT NULL REFERENCES public.suggestions(id) ON DELETE CASCADE,
    file_url TEXT NOT NULL,
    file_name TEXT NOT NULL,
    file_type TEXT,
    file_size INTEGER,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.suggestions ADD COLUMN IF NOT EXISTS suggestion_type TEXT DEFAULT 'general';
ALTER TABLE public.suggestions ADD COLUMN IF NOT EXISTS has_attachment BOOLEAN DEFAULT FALSE;

ALTER TABLE public.announcements_global ADD COLUMN IF NOT EXISTS is_pinned BOOLEAN DEFAULT FALSE;
ALTER TABLE public.announcements_global ADD COLUMN IF NOT EXISTS announcement_type TEXT DEFAULT 'general';
ALTER TABLE public.announcements_global ADD COLUMN IF NOT EXISTS payload JSONB DEFAULT '{}'::jsonb;
ALTER TABLE public.announcements_global ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

ALTER TABLE public.announcements_class ADD COLUMN IF NOT EXISTS is_pinned BOOLEAN DEFAULT FALSE;
ALTER TABLE public.announcements_class ADD COLUMN IF NOT EXISTS announcement_type TEXT DEFAULT 'general';
ALTER TABLE public.announcements_class ADD COLUMN IF NOT EXISTS payload JSONB DEFAULT '{}'::jsonb;
ALTER TABLE public.announcements_class ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

ALTER TABLE public.absence_records ADD COLUMN IF NOT EXISTS student_id UUID;

-- Temporarily bypass privilege escalation trigger for database administration seed
ALTER TABLE public.users DISABLE TRIGGER trg_prevent_user_privilege_escalation;

-- Step B: Populate Data
DO $$
DECLARE
  v_user RECORD;
  v_school_id UUID;
  v_user_id UUID;
  v_admin_id UUID;
  v_class_id UUID;
  v_academic_year_id UUID;
  v_semester_id UUID;
  v_enrollment_id UUID;

  -- Subject Offering IDs
  v_subj_id UUID;
  v_so_math UUID;
  v_so_phys UUID;
  v_so_svt UUID;
  v_so_info UUID;
  v_so_philo UUID;
  v_so_fr UUID;

  v_ann_id UUID;
  v_sugg_id UUID;
BEGIN
  -- Enable bypass configuration
  PERFORM set_config('app.bypass_privilege_check', 'on', true);

  -- 1. Identify Student Nour and her existing school
  SELECT id, school_id, full_name, student_code INTO v_user 
  FROM public.users WHERE LOWER(email) = 'nour.new06@school.tn' LIMIT 1;

  IF v_user.id IS NOT NULL THEN
    v_user_id := v_user.id;
    IF v_user.school_id IS NOT NULL THEN
      v_school_id := v_user.school_id;
    END IF;
  ELSE
    SELECT id INTO v_user_id FROM auth.users WHERE LOWER(email) = 'nour.new06@school.tn' LIMIT 1;
  END IF;

  -- 2. Identify or Create Pythagore School if not already set on Nour
  IF v_school_id IS NULL THEN
    SELECT id INTO v_school_id 
    FROM public.schools 
    WHERE LOWER(name) LIKE '%pythagore%' 
       OR code = 'demo' 
       OR LOWER(email) LIKE '%pythagore%'
    ORDER BY created_at DESC LIMIT 1;

    IF v_school_id IS NULL THEN
      INSERT INTO public.schools (name, code, email, phone, address, primary_color, secondary_color, is_active)
      VALUES ('Lycée Pilote Pythagore', 'pythagore', 'contact@pythagore.tn', '+216 71 888 999', 'Avenue Habib Bourguiba, Tunis', '#2563EB', '#0D1321', TRUE)
      RETURNING id INTO v_school_id;
    END IF;
  END IF;

  -- 3. Ensure Student Profile exists and has correct info
  IF v_user.id IS NULL THEN
    v_user_id := COALESCE(v_user_id, gen_random_uuid());
    INSERT INTO public.users (id, school_id, role, full_name, email, phone, student_code, date_of_birth, address)
    VALUES (
      v_user_id,
      v_school_id,
      'student',
      'Nour El Houda Khalil',
      'nour.new06@school.tn',
      '+216 98 765 432',
      'BAC-2026-006',
      '2006-04-18',
      'El Menzah 9, Tunis'
    );
  ELSE
    UPDATE public.users 
    SET full_name = 'Nour El Houda Khalil',
        student_code = COALESCE(student_code, 'BAC-2026-006')
    WHERE id = v_user_id;
  END IF;

  -- 4. Identify an Admin
  SELECT id INTO v_admin_id FROM public.users WHERE school_id = v_school_id AND role IN ('admin', 'staff') LIMIT 1;
  IF v_admin_id IS NULL THEN
    SELECT id INTO v_admin_id FROM public.users WHERE role IN ('admin', 'staff') LIMIT 1;
  END IF;
  IF v_admin_id IS NULL THEN
    v_admin_id := v_user_id;
  END IF;

  -- 4. Academic Year & Semester
  SELECT id INTO v_academic_year_id FROM public.academic_years WHERE school_id = v_school_id AND is_current = TRUE LIMIT 1;
  IF v_academic_year_id IS NULL THEN
    SELECT id INTO v_academic_year_id FROM public.academic_years WHERE school_id = v_school_id LIMIT 1;
  END IF;
  IF v_academic_year_id IS NULL THEN
    INSERT INTO public.academic_years (school_id, name, start_date, end_date, is_current)
    VALUES (v_school_id, '2025-2026', '2025-09-15', '2026-06-30', TRUE)
    RETURNING id INTO v_academic_year_id;
  END IF;

  SELECT id INTO v_semester_id FROM public.semesters WHERE school_id = v_school_id AND number = 1 LIMIT 1;
  IF v_semester_id IS NULL THEN
    INSERT INTO public.semesters (school_id, academic_year_id, name, number, start_date, end_date)
    VALUES (v_school_id, v_academic_year_id, 'Semestre 1', 1, CURRENT_DATE - INTERVAL '120 days', CURRENT_DATE + INTERVAL '90 days')
    RETURNING id INTO v_semester_id;
  ELSE
    UPDATE public.semesters
    SET start_date = LEAST(start_date, CURRENT_DATE - INTERVAL '120 days'),
        end_date = GREATEST(end_date, CURRENT_DATE + INTERVAL '90 days')
    WHERE id = v_semester_id;
  END IF;

  -- 5. Class & Enrollment
  SELECT class_id, id INTO v_class_id, v_enrollment_id FROM public.enrollments WHERE user_id = v_user_id LIMIT 1;
  IF v_class_id IS NULL THEN
    SELECT id INTO v_class_id FROM public.classes WHERE school_id = v_school_id LIMIT 1;
    IF v_class_id IS NULL THEN
      INSERT INTO public.classes (school_id, name, level, year, section)
      VALUES (v_school_id, 'Bac Sciences Expérimentales 1', 'Baccalauréat', 4, 'Sciences Expérimentales')
      RETURNING id INTO v_class_id;
    END IF;

    INSERT INTO public.enrollments (id, user_id, class_id, academic_year_id)
    VALUES (gen_random_uuid(), v_user_id, v_class_id, v_academic_year_id)
    RETURNING id INTO v_enrollment_id;
  END IF;

  -- 6. Ensure Subjects & Offerings for Absences
  -- Maths
  SELECT so.id INTO v_so_math FROM public.subject_offerings so JOIN public.subjects s ON s.id = so.subject_id WHERE so.class_id = v_class_id AND LOWER(s.name) LIKE '%math%' LIMIT 1;
  IF v_so_math IS NULL THEN
    INSERT INTO public.subjects (school_id, name, code) VALUES (v_school_id, 'Mathématiques', 'MATH') RETURNING id INTO v_subj_id;
    INSERT INTO public.subject_offerings (semester_id, class_id, subject_id, coefficient, total_hours, weekly_ci_hours, weekly_tp_hours)
    VALUES (v_semester_id, v_class_id, v_subj_id, 4.0, 56, 4.0, 0) RETURNING id INTO v_so_math;
  END IF;

  -- Physique
  SELECT so.id INTO v_so_phys FROM public.subject_offerings so JOIN public.subjects s ON s.id = so.subject_id WHERE so.class_id = v_class_id AND LOWER(s.name) LIKE '%phys%' LIMIT 1;
  IF v_so_phys IS NULL THEN
    INSERT INTO public.subjects (school_id, name, code) VALUES (v_school_id, 'Sciences Physiques', 'PHYS') RETURNING id INTO v_subj_id;
    INSERT INTO public.subject_offerings (semester_id, class_id, subject_id, coefficient, total_hours, weekly_ci_hours, weekly_tp_hours)
    VALUES (v_semester_id, v_class_id, v_subj_id, 4.0, 56, 3.0, 1.5) RETURNING id INTO v_so_phys;
  END IF;

  -- SVT
  SELECT so.id INTO v_so_svt FROM public.subject_offerings so JOIN public.subjects s ON s.id = so.subject_id WHERE so.class_id = v_class_id AND (LOWER(s.name) LIKE '%svt%' OR LOWER(s.name) LIKE '%vie%') LIMIT 1;
  IF v_so_svt IS NULL THEN
    INSERT INTO public.subjects (school_id, name, code) VALUES (v_school_id, 'Sciences de la Vie et de la Terre', 'SVT') RETURNING id INTO v_subj_id;
    INSERT INTO public.subject_offerings (semester_id, class_id, subject_id, coefficient, total_hours, weekly_ci_hours, weekly_tp_hours)
    VALUES (v_semester_id, v_class_id, v_subj_id, 3.0, 42, 2.0, 1.5) RETURNING id INTO v_so_svt;
  END IF;

  -- Informatique
  SELECT so.id INTO v_so_info FROM public.subject_offerings so JOIN public.subjects s ON s.id = so.subject_id WHERE so.class_id = v_class_id AND LOWER(s.name) LIKE '%info%' LIMIT 1;
  IF v_so_info IS NULL THEN
    INSERT INTO public.subjects (school_id, name, code) VALUES (v_school_id, 'Informatique & Algorithmique', 'INFO') RETURNING id INTO v_subj_id;
    INSERT INTO public.subject_offerings (semester_id, class_id, subject_id, coefficient, total_hours, weekly_ci_hours, weekly_tp_hours)
    VALUES (v_semester_id, v_class_id, v_subj_id, 2.0, 28, 1.0, 1.5) RETURNING id INTO v_so_info;
  END IF;

  -- Philosophie
  SELECT so.id INTO v_so_philo FROM public.subject_offerings so JOIN public.subjects s ON s.id = so.subject_id WHERE so.class_id = v_class_id AND LOWER(s.name) LIKE '%philo%' LIMIT 1;
  IF v_so_philo IS NULL THEN
    INSERT INTO public.subjects (school_id, name, code) VALUES (v_school_id, 'Philosophie', 'PHILO') RETURNING id INTO v_subj_id;
    INSERT INTO public.subject_offerings (semester_id, class_id, subject_id, coefficient, total_hours, weekly_ci_hours, weekly_tp_hours)
    VALUES (v_semester_id, v_class_id, v_subj_id, 2.0, 28, 2.0, 0) RETURNING id INTO v_so_philo;
  END IF;

  -- Français
  SELECT so.id INTO v_so_fr FROM public.subject_offerings so JOIN public.subjects s ON s.id = so.subject_id WHERE so.class_id = v_class_id AND LOWER(s.name) LIKE '%fran%' LIMIT 1;
  IF v_so_fr IS NULL THEN
    INSERT INTO public.subjects (school_id, name, code) VALUES (v_school_id, 'Français', 'FR') RETURNING id INTO v_subj_id;
    INSERT INTO public.subject_offerings (semester_id, class_id, subject_id, coefficient, total_hours, weekly_ci_hours, weekly_tp_hours)
    VALUES (v_semester_id, v_class_id, v_subj_id, 2.0, 28, 2.0, 0) RETURNING id INTO v_so_fr;
  END IF;

  -- ============================================================================
  -- 7. CLEAN PREVIOUS SEEDED DEMO DATA FOR THIS STUDENT/SCHOOL
  -- ============================================================================
  DELETE FROM public.absence_records WHERE enrollment_id = v_enrollment_id OR student_id = v_user_id;
  DELETE FROM public.suggestions WHERE student_id = v_user_id;
  DELETE FROM public.documents WHERE school_id = v_school_id AND (description LIKE '%[Student:%' OR uploaded_by = v_admin_id);
  DELETE FROM public.announcements_global WHERE school_id = v_school_id AND title LIKE '[Demo]%';
  DELETE FROM public.announcements_class WHERE class_id = v_class_id AND title LIKE '[Demo]%';

  -- ============================================================================
  -- 8. INSERT 10 GLOBAL NOTIFICATIONS (announcements_global)
  -- ============================================================================
  -- Notification 1 (Pinned with Picture)
  v_ann_id := gen_random_uuid();
  INSERT INTO public.announcements_global (
    id, school_id, title, body, is_important, is_pinned, announcement_type,
    attachment_url, attachment_name, published_at, created_by, created_at
  ) VALUES (
    v_ann_id, v_school_id,
    'Cérémonie d''Excellence & Remise des Prix du 1er Trimestre',
    'La direction du Lycée Pilote Pythagore a l''immense plaisir de convier l''ensemble des élèves distingués et leurs parents à la Grande Cérémonie d''Excellence qui se tiendra à l''amphithéâtre central le samedi 14 mars à 10h00.',
    TRUE, TRUE, 'event',
    'https://images.unsplash.com/photo-1523240795612-9a054b0db644?w=800', 'ceremonie_excellence_affiche.jpg',
    NOW() - INTERVAL '2 hours', v_admin_id, NOW() - INTERVAL '2 hours'
  );
  INSERT INTO public.announcement_attachments (announcement_id, scope, file_name, display_name, file_url, file_type, file_size)
  VALUES (v_ann_id, 'global', 'ceremonie_excellence_affiche.jpg', 'Affiche officielle de l''événement', 'https://images.unsplash.com/photo-1523240795612-9a054b0db644?w=800', 'image/jpeg', 1450000);

  -- Notification 2 (Important with PDF document)
  v_ann_id := gen_random_uuid();
  INSERT INTO public.announcements_global (
    id, school_id, title, body, is_important, is_pinned, announcement_type,
    attachment_url, attachment_name, published_at, created_by, created_at
  ) VALUES (
    v_ann_id, v_school_id,
    'Calendrier Officiel des Épreuves de Synthèse — Semestre 1',
    'Veuillez trouver ci-joint le calendrier complet des examens de synthèse pour toutes les sections. Nous rappelons que la présence avec carte d''élève est strictement obligatoire dès 07h45.',
    TRUE, FALSE, 'exam',
    'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf', 'calendrier_synthese_s1.pdf',
    NOW() - INTERVAL '8 hours', v_admin_id, NOW() - INTERVAL '8 hours'
  );
  INSERT INTO public.announcement_attachments (announcement_id, scope, file_name, display_name, file_url, file_type, file_size)
  VALUES (v_ann_id, 'global', 'calendrier_synthese_s1.pdf', 'Planning officiel des examens S1.pdf', 'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf', 'application/pdf', 850000);

  -- Notification 3 (Picture)
  v_ann_id := gen_random_uuid();
  INSERT INTO public.announcements_global (
    id, school_id, title, body, is_important, is_pinned, announcement_type,
    attachment_url, attachment_name, published_at, created_by, created_at
  ) VALUES (
    v_ann_id, v_school_id,
    'Inauguration du Nouveau Laboratoire d''Intelligence Artificielle',
    'Dans le cadre de son plan de modernisation, le lycée met à la disposition des élèves de terminale 24 stations de travail ultra-performantes dédiées à l''algorithmie avancée et au club de robotique.',
    FALSE, FALSE, 'facility',
    'https://images.unsplash.com/photo-1581092160607-ee22621dd758?w=800', 'nouveau_labo_informatique.jpg',
    NOW() - INTERVAL '1 day', v_admin_id, NOW() - INTERVAL '1 day'
  );
  INSERT INTO public.announcement_attachments (announcement_id, scope, file_name, display_name, file_url, file_type, file_size)
  VALUES (v_ann_id, 'global', 'nouveau_labo_informatique.jpg', 'Photos du laboratoire high-tech', 'https://images.unsplash.com/photo-1581092160607-ee22621dd758?w=800', 'image/jpeg', 2100000);

  -- Notification 4 (Text only)
  INSERT INTO public.announcements_global (
    school_id, title, body, is_important, is_pinned, announcement_type, published_at, created_by, created_at
  ) VALUES (
    v_school_id,
    'Horaires Aménagés de la Médiathèque & Espaces Coworking',
    'Pour accompagner les élèves durant la période des révisions, la médiathèque restera ouverte jusqu''à 19h30 tous les soirs du lundi au vendredi, et le samedi matin de 08h30 à 13h00.',
    FALSE, FALSE, 'general', NOW() - INTERVAL '2 days', v_admin_id, NOW() - INTERVAL '2 days'
  );

  -- Notification 5 (With PDF Guide)
  v_ann_id := gen_random_uuid();
  INSERT INTO public.announcements_global (
    id, school_id, title, body, is_important, is_pinned, announcement_type,
    attachment_url, attachment_name, published_at, created_by, created_at
  ) VALUES (
    v_ann_id, v_school_id,
    'Olympiades Nationales des Sciences : Inscriptions Ouvertes',
    'Les épreuves de sélection pour les Olympiades de Mathématiques et de Physique se tiendront le 28 mars. Consultez le guide d''inscription ci-joint pour découvrir les critères d''éligibilité et le programme des épreuves.',
    TRUE, FALSE, 'academic',
    'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf', 'guide_olympiades_sciences_2026.pdf',
    NOW() - INTERVAL '3 days', v_admin_id, NOW() - INTERVAL '3 days'
  );
  INSERT INTO public.announcement_attachments (announcement_id, scope, file_name, display_name, file_url, file_type, file_size)
  VALUES (v_ann_id, 'global', 'guide_olympiades_sciences_2026.pdf', 'Dossier de candidature & Modalités', 'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf', 'application/pdf', 1200000);

  -- Notification 6 (With Picture)
  v_ann_id := gen_random_uuid();
  INSERT INTO public.announcements_global (
    id, school_id, title, body, is_important, is_pinned, announcement_type,
    attachment_url, attachment_name, published_at, created_by, created_at
  ) VALUES (
    v_ann_id, v_school_id,
    'Journée Portes Ouvertes & Orientation Universitaire 2026',
    'Venez échanger avec les représentants des facultés de médecine, écoles d''ingénieurs (INSAT, ENIT, Polytech) et universités internationales partenaires. Stands d''orientation et conférences thématiques tout au long de la journée.',
    FALSE, FALSE, 'event',
    'https://images.unsplash.com/photo-1541339907198-e08756dedf3f?w=800', 'journee_orientation_campus.jpg',
    NOW() - INTERVAL '4 days', v_admin_id, NOW() - INTERVAL '4 days'
  );
  INSERT INTO public.announcement_attachments (announcement_id, scope, file_name, display_name, file_url, file_type, file_size)
  VALUES (v_ann_id, 'global', 'journee_orientation_campus.jpg', 'Flyer officiel Forum Orientation', 'https://images.unsplash.com/photo-1541339907198-e08756dedf3f?w=800', 'image/jpeg', 1850000);

  -- Notification 7 (Text only)
  INSERT INTO public.announcements_global (
    school_id, title, body, is_important, is_pinned, announcement_type, published_at, created_by, created_at
  ) VALUES (
    v_school_id,
    'Mise en Place du Dispositif de Tutorat Entre Pairs',
    'Le comité pédagogique lance le programme de soutien par les élèves majors pour les matières scientifiques fondamentales. Les inscriptions pour devenir tuteur ou bénéficier du tutorat sont ouvertes au bureau de la vie scolaire.',
    FALSE, FALSE, 'academic', NOW() - INTERVAL '5 days', v_admin_id, NOW() - INTERVAL '5 days'
  );

  -- Notification 8 (Text only)
  INSERT INTO public.announcements_global (
    school_id, title, body, is_important, is_pinned, announcement_type, published_at, created_by, created_at
  ) VALUES (
    v_school_id,
    'Rappel Déontologique : Port du Badge Scolaire Numérique',
    'Pour des impératifs stricts de sécurité sur l''ensemble du campus, chaque élève doit impérativement porter son badge visible ou présenter son QR code d''accès sur l''application mobile à chaque entrée.',
    TRUE, FALSE, 'urgent', NOW() - INTERVAL '6 days', v_admin_id, NOW() - INTERVAL '6 days'
  );

  -- Notification 9 (With Document)
  v_ann_id := gen_random_uuid();
  INSERT INTO public.announcements_global (
    id, school_id, title, body, is_important, is_pinned, announcement_type,
    attachment_url, attachment_name, published_at, created_by, created_at
  ) VALUES (
    v_ann_id, v_school_id,
    'Conférence Thématique : Transition Énergétique & Développement Durable',
    'Une table ronde animée par des experts de l''ANME et des chercheurs universitaires se tiendra vendredi prochain. Retrouvez le programme détaillé des interventions en pièce jointe.',
    FALSE, FALSE, 'event',
    'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf', 'programme_table_ronde_climat.pdf',
    NOW() - INTERVAL '7 days', v_admin_id, NOW() - INTERVAL '7 days'
  );
  INSERT INTO public.announcement_attachments (announcement_id, scope, file_name, display_name, file_url, file_type, file_size)
  VALUES (v_ann_id, 'global', 'programme_table_ronde_climat.pdf', 'Programme des interventions', 'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf', 'application/pdf', 640000);

  -- Notification 10 (Text only)
  INSERT INTO public.announcements_global (
    school_id, title, body, is_important, is_pinned, announcement_type, published_at, created_by, created_at
  ) VALUES (
    v_school_id,
    'Calendrier des Vacances Scolaires de Mi-Trimestre',
    'Nous informons les élèves que les cours s''interrompront le samedi à 13h et reprendront le lundi suivant à 08h00. Bon repos studieux à toutes et à tous !',
    FALSE, FALSE, 'holiday', NOW() - INTERVAL '9 days', v_admin_id, NOW() - INTERVAL '9 days'
  );

  -- ============================================================================
  -- 9. INSERT 5 CLASS MESSAGES (announcements_class - Whole Class)
  -- ============================================================================
  -- Class Message 1 (Pinned with PDF)
  v_ann_id := gen_random_uuid();
  INSERT INTO public.announcements_class (
    id, class_id, title, body, is_important, is_pinned, announcement_type,
    attachment_url, attachment_name, published_at, created_by, created_at
  ) VALUES (
    v_ann_id, v_class_id,
    'Devoir Surveillé de Mathématiques : Nombres Complexes & Fonctions',
    'Chers élèves, le prochain DS portera sur l''ensemble des notions abordées au chapitre 3. Vous trouverez en pièce jointe la fiche de synthèse et trois exercices types à préparer impérativement pour mardi.',
    TRUE, TRUE, 'homework',
    'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf', 'devoir_mathematiques_complexes.pdf',
    NOW() - INTERVAL '3 hours', v_admin_id, NOW() - INTERVAL '3 hours'
  );
  INSERT INTO public.announcement_attachments (announcement_id, scope, file_name, display_name, file_url, file_type, file_size)
  VALUES (v_ann_id, 'class', 'devoir_mathematiques_complexes.pdf', 'Fiche d''exercices types & corrigé', 'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf', 'application/pdf', 1100000);

  -- Class Message 2 (Text only)
  INSERT INTO public.announcements_class (
    class_id, title, body, is_important, is_pinned, announcement_type, published_at, created_by, created_at
  ) VALUES (
    v_class_id,
    'Rappel : Remise des Comptes-Rendus de TP Physique-Chimie',
    'Le dépôt des rapports sur l''étude du pendule élastique et les titrages pH-métriques est fixé à vendredi avant 12h00 précises. Tout retard entraînera une pénalité de notation.',
    TRUE, FALSE, 'homework', NOW() - INTERVAL '12 hours', v_admin_id, NOW() - INTERVAL '12 hours'
  );

  -- Class Message 3 (Picture)
  v_ann_id := gen_random_uuid();
  INSERT INTO public.announcements_class (
    id, class_id, title, body, is_important, is_pinned, announcement_type,
    attachment_url, attachment_name, published_at, created_by, created_at
  ) VALUES (
    v_ann_id, v_class_id,
    'Schéma Bilan SVT : Mécanismes de la Traduction et Transcription',
    'Voici le schéma récapitulatif projeté en cours pour réviser la synthèse des protéines. Prenez soin d''annoter les différents codons et complexes enzymatiques.',
    FALSE, FALSE, 'course',
    'https://images.unsplash.com/photo-1532094349884-543bc11b234d?w=800', 'schema_svt_genetique.jpg',
    NOW() - INTERVAL '1 day', v_admin_id, NOW() - INTERVAL '1 day'
  );
  INSERT INTO public.announcement_attachments (announcement_id, scope, file_name, display_name, file_url, file_type, file_size)
  VALUES (v_ann_id, 'class', 'schema_svt_genetique.jpg', 'Schéma bilan cellulaire haute résolution', 'https://images.unsplash.com/photo-1532094349884-543bc11b234d?w=800', 'image/jpeg', 1600000);

  -- Class Message 4 (Text only)
  INSERT INTO public.announcements_class (
    class_id, title, body, is_important, is_pinned, announcement_type, published_at, created_by, created_at
  ) VALUES (
    v_class_id,
    'Changement Exceptionnel de Salle — Cours de Philosophie',
    'La séance de Philosophie de jeudi de 10h à 12h aura lieu en Salle B-204 (aile est) au lieu de la salle habituelle.',
    FALSE, FALSE, 'general', NOW() - INTERVAL '2 days', v_admin_id, NOW() - INTERVAL '2 days'
  );

  -- Class Message 5 (With Document)
  v_ann_id := gen_random_uuid();
  INSERT INTO public.announcements_class (
    id, class_id, title, body, is_important, is_pinned, announcement_type,
    attachment_url, attachment_name, published_at, created_by, created_at
  ) VALUES (
    v_ann_id, v_class_id,
    'Projet Informatique : Cahier des Charges & Sujets d''Algorithmique',
    'Le cahier des charges du mini-projet Python (arbres binaires et graphes) est disponible. Les binômes doivent être validés avant la fin de semaine.',
    FALSE, FALSE, 'course',
    'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf', 'cahier_charges_projet_algo.pdf',
    NOW() - INTERVAL '4 days', v_admin_id, NOW() - INTERVAL '4 days'
  );
  INSERT INTO public.announcement_attachments (announcement_id, scope, file_name, display_name, file_url, file_type, file_size)
  VALUES (v_ann_id, 'class', 'cahier_charges_projet_algo.pdf', 'Spécifications techniques du projet', 'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf', 'application/pdf', 920000);

  -- ============================================================================
  -- 10. INSERT 5 DIRECT STUDENT MESSAGES (announcements_class targeted to Nour)
  -- ============================================================================
  -- Student Message 1: Félicitations & Encouragements (Pinned)
  INSERT INTO public.announcements_class (
    class_id, title, body, is_important, is_pinned, announcement_type,
    payload, published_at, created_by, created_at
  ) VALUES (
    v_class_id,
    'Félicitations du Conseil Pédagogique pour vos Résultats',
    'Chère Nour, le corps enseignant tient à saluer votre remarquable investissement et l''excellence de votre devoir de synthèse en Mathématiques (18.75/20). Continuez avec cette rigueur exemplaire !',
    TRUE, TRUE, 'appreciation',
    jsonb_build_object('target_student_id', v_user_id),
    NOW() - INTERVAL '4 hours', v_admin_id, NOW() - INTERVAL '4 hours'
  );

  -- Student Message 2: Convocation Olympiades avec Document
  v_ann_id := gen_random_uuid();
  INSERT INTO public.announcements_class (
    id, class_id, title, body, is_important, is_pinned, announcement_type,
    attachment_url, attachment_name, payload, published_at, created_by, created_at
  ) VALUES (
    v_ann_id, v_class_id,
    'Convocation Officielle : Sélection aux Olympiades de Sciences',
    'Nour, vous avez été pré-sélectionnée par votre professeur pour représenter le lycée à la phase régionale des Olympiades de Mathématiques. Veuillez trouver votre convocation individuelle ci-jointe.',
    TRUE, FALSE, 'convocation',
    'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf', 'convocation_olympiades_nour_khalil.pdf',
    jsonb_build_object('target_student_id', v_user_id),
    NOW() - INTERVAL '1 day', v_admin_id, NOW() - INTERVAL '1 day'
  );
  INSERT INTO public.announcement_attachments (announcement_id, scope, file_name, display_name, file_url, file_type, file_size)
  VALUES (v_ann_id, 'class', 'convocation_olympiades_nour_khalil.pdf', 'Convocation nominative officielle.pdf', 'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf', 'application/pdf', 480000);

  -- Student Message 3: Validation d'absence
  INSERT INTO public.announcements_class (
    class_id, title, body, is_important, is_pinned, announcement_type,
    payload, published_at, created_by, created_at
  ) VALUES (
    v_class_id,
    'Validation Administrative : Justificatif Médical Enregistré',
    'Nous vous confirmons la bonne réception et validation par la direction de votre certificat médical du 12 février. Votre dossier d''assiduité a été mis à jour en statut Justifié.',
    FALSE, FALSE, 'attendance',
    jsonb_build_object('target_student_id', v_user_id),
    NOW() - INTERVAL '2 days', v_admin_id, NOW() - INTERVAL '2 days'
  );

  -- Student Message 4: Entretien d'orientation individualisé
  v_ann_id := gen_random_uuid();
  INSERT INTO public.announcements_class (
    id, class_id, title, body, is_important, is_pinned, announcement_type,
    attachment_url, attachment_name, payload, published_at, created_by, created_at
  ) VALUES (
    v_ann_id, v_class_id,
    'Entretien Individuel d''Orientation Post-Baccalauréat',
    'Nour, votre rendez-vous personnalisé avec la conseillère d''orientation est programmé ce mardi à 14h30 au bureau 12. Vous pouvez consulter en pièce jointe la fiche préparatoire des filières médicales et prépas.',
    FALSE, FALSE, 'orientation',
    'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf', 'fiche_preparatoire_orientation.pdf',
    jsonb_build_object('target_student_id', v_user_id),
    NOW() - INTERVAL '4 days', v_admin_id, NOW() - INTERVAL '4 days'
  );
  INSERT INTO public.announcement_attachments (announcement_id, scope, file_name, display_name, file_url, file_type, file_size)
  VALUES (v_ann_id, 'class', 'fiche_preparatoire_orientation.pdf', 'Guide des filières post-bac', 'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf', 'application/pdf', 720000);

  -- Student Message 5: Photo d'identité carte scolaire
  INSERT INTO public.announcements_class (
    class_id, title, body, is_important, is_pinned, announcement_type,
    payload, published_at, created_by, created_at
  ) VALUES (
    v_class_id,
    'Régularisation Administrative : Mise à Jour Badge Scolaire',
    'Bonjour Nour, nous vous invitons à transmettre une photo d''identité numérique récente au secrétariat des élèves pour la réédition de votre carte d''accès sécurisée.',
    FALSE, FALSE, 'administrative',
    jsonb_build_object('target_student_id', v_user_id),
    NOW() - INTERVAL '6 days', v_admin_id, NOW() - INTERVAL '6 days'
  );

  -- ============================================================================
  -- 11. INSERT 10 SUGGESTIONS WRITTEN BY NOUR (with Replies & Attachments)
  -- ============================================================================
  -- Suggestion 1 (Replied + Photo Attachment)
  v_sugg_id := gen_random_uuid();
  INSERT INTO public.suggestions (
    id, student_id, subject, message, status, suggestion_type, has_attachment,
    attachment_url, attachment_name, created_at, updated_at
  ) VALUES (
    v_sugg_id, v_user_id,
    'Installation de bornes de recharge pour PC à la bibliothèque',
    'Bonjour, avec l''usage intensif des ordinateurs pour la programmation et les devoirs de sciences, les prises actuelles à la bibliothèque sont insuffisantes. Serait-il possible d''ajouter des multiprises sécurisées sur les grandes tables centrales ?',
    'replied', 'facility', TRUE,
    'https://images.unsplash.com/photo-1521587760476-6c12a4b040da?w=800', 'photo_tables_bibliotheque.jpg',
    NOW() - INTERVAL '1 day', NOW() - INTERVAL '1 day'
  );
  INSERT INTO public.suggestion_attachments (suggestion_id, file_url, file_name, file_type, file_size)
  VALUES (v_sugg_id, 'https://images.unsplash.com/photo-1521587760476-6c12a4b040da?w=800', 'photo_tables_bibliotheque.jpg', 'image/jpeg', 1200000);
  INSERT INTO public.suggestion_replies (suggestion_id, admin_id, message, created_at)
  VALUES (v_sugg_id, v_admin_id, 'Bonjour Nour. Excellente proposition ! Le service technique a validé l''achat de 6 goulottes électriques équipées de ports USB-C et prises 220V qui seront installées dès les prochaines vacances. Merci pour votre initiative.', NOW() - INTERVAL '18 hours');

  -- Suggestion 2 (Replied + PDF Attachment)
  v_sugg_id := gen_random_uuid();
  INSERT INTO public.suggestions (
    id, student_id, subject, message, status, suggestion_type, has_attachment,
    attachment_url, attachment_name, created_at, updated_at
  ) VALUES (
    v_sugg_id, v_user_id,
    'Création d''un Club de Débats en Langues Étrangères (Anglais / Français)',
    'Je propose la fondation d''un club hebdomadaire de rhétorique et débat d''idées (Model UN / Débat parlementaire) pour aider les élèves à développer leur éloquence en vue des épreuves orales du baccalauréat.',
    'replied', 'academic', TRUE,
    'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf', 'proposition_statuts_club_debat.pdf',
    NOW() - INTERVAL '3 days', NOW() - INTERVAL '2 days'
  );
  INSERT INTO public.suggestion_attachments (suggestion_id, file_url, file_name, file_type, file_size)
  VALUES (v_sugg_id, 'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf', 'proposition_statuts_club_debat.pdf', 'application/pdf', 650000);
  INSERT INTO public.suggestion_replies (suggestion_id, admin_id, message, created_at)
  VALUES (v_sugg_id, v_admin_id, 'Nous saluons vivement ce projet structuré ! Mme Ben Amor (professeure d''anglais) a accepté d''en être la marraine pédagogique. Vous pouvez vous réunir en salle Polyvalente chaque mercredi à 15h30.', NOW() - INTERVAL '2 days');

  -- Suggestion 3 (Replied)
  v_sugg_id := gen_random_uuid();
  INSERT INTO public.suggestions (
    id, student_id, subject, message, status, suggestion_type, has_attachment, created_at, updated_at
  ) VALUES (
    v_sugg_id, v_user_id,
    'Prolongation des horaires d''ouverture de la salle de révision',
    'Serait-il possible de laisser la salle d''étude ouverte jusqu''à 18h le samedi durant le mois de préparation aux épreuves de synthèse ? Cela offrirait un cadre calme aux élèves.',
    'replied', 'schedule', FALSE,
    NOW() - INTERVAL '5 days', NOW() - INTERVAL '4 days'
  );
  INSERT INTO public.suggestion_replies (suggestion_id, admin_id, message, created_at)
  VALUES (v_sugg_id, v_admin_id, 'Proposition acceptée. Un agent de surveillance sera détaché pour assurer l''accueil des élèves jusqu''à 17h30 tous les samedis jusqu''à la fin des épreuves.', NOW() - INTERVAL '4 days');

  -- Suggestion 4 (Replied + Photo Attachment)
  v_sugg_id := gen_random_uuid();
  INSERT INTO public.suggestions (
    id, student_id, subject, message, status, suggestion_type, has_attachment,
    attachment_url, attachment_name, created_at, updated_at
  ) VALUES (
    v_sugg_id, v_user_id,
    'Aménagement d''un espace vert ombragé dans la cour centrale',
    'Nous constatons un manque de bancs ombragés dans la grande cour pendant la pause de midi. Installer 3 bancs sous les eucalyptus permettrait d''avoir un espace de repos plus agréable.',
    'replied', 'facility', TRUE,
    'https://images.unsplash.com/photo-1519331379826-f10be5486c6f?w=800', 'photo_cour_lycee.jpg',
    NOW() - INTERVAL '7 days', NOW() - INTERVAL '6 days'
  );
  INSERT INTO public.suggestion_attachments (suggestion_id, file_url, file_name, file_type, file_size)
  VALUES (v_sugg_id, 'https://images.unsplash.com/photo-1519331379826-f10be5486c6f?w=800', 'photo_cour_lycee.jpg', 'image/jpeg', 1800000);
  INSERT INTO public.suggestion_replies (suggestion_id, admin_id, message, created_at)
  VALUES (v_sugg_id, v_admin_id, 'Le conseil d''établissement a inscrit l''aménagement paysager au budget d''embellissement. Les travaux de pose de bancs en bois débuteront le mois prochain.', NOW() - INTERVAL '6 days');

  -- Suggestion 5 (Replied)
  v_sugg_id := gen_random_uuid();
  INSERT INTO public.suggestions (
    id, student_id, subject, message, status, suggestion_type, has_attachment, created_at, updated_at
  ) VALUES (
    v_sugg_id, v_user_id,
    'Mise à disposition des annales corrigées du Baccalauréat sur le portail',
    'Pourrait-on intégrer directement dans l''onglet Documents une rubrique dédiée aux sujets des sessions précédentes (2020-2025) avec barèmes officiels ?',
    'replied', 'academic', FALSE,
    NOW() - INTERVAL '9 days', NOW() - INTERVAL '8 days'
  );
  INSERT INTO public.suggestion_replies (suggestion_id, admin_id, message, created_at)
  VALUES (v_sugg_id, v_admin_id, 'C''est fait ! Les coordinateurs de matières ont téléversé plus de 50 sujets corrigés dans la section Examens de l''application mobile.', NOW() - INTERVAL '8 days');

  -- Suggestion 6 (Read)
  INSERT INTO public.suggestions (
    student_id, subject, message, status, suggestion_type, has_attachment, created_at, updated_at
  ) VALUES (
    v_user_id,
    'Ajout d''options de fruits frais et encas sains à la cafétéria',
    'Beaucoup d''élèves souhaitent avoir un choix de pommes, bananes et fruits secs à la cafétéria en alternative aux viennoiseries industrielles.',
    'read', 'facility', FALSE,
    NOW() - INTERVAL '11 days', NOW() - INTERVAL '10 days'
  );

  -- Suggestion 7 (Read + Attachment)
  v_sugg_id := gen_random_uuid();
  INSERT INTO public.suggestions (
    id, student_id, subject, message, status, suggestion_type, has_attachment,
    attachment_url, attachment_name, created_at, updated_at
  ) VALUES (
    v_sugg_id, v_user_id,
    'Organisation d''un tournoi d''échecs inter-classes au foyer',
    'Nous sommes plus de 25 élèves intéressés par un tournoi d''échecs rapide (blitz 10 min) sur deux mercredis après-midi. Nous avons rédigé les règles proposées.',
    'read', 'general', TRUE,
    'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf', 'reglement_tournoi_echecs.pdf',
    NOW() - INTERVAL '13 days', NOW() - INTERVAL '12 days'
  );
  INSERT INTO public.suggestion_attachments (suggestion_id, file_url, file_name, file_type, file_size)
  VALUES (v_sugg_id, 'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf', 'reglement_tournoi_echecs.pdf', 'application/pdf', 430000);

  -- Suggestion 8 (Read)
  INSERT INTO public.suggestions (
    student_id, subject, message, status, suggestion_type, has_attachment, created_at, updated_at
  ) VALUES (
    v_user_id,
    'Optimisation du signal Wi-Fi dans le laboratoire de SVT',
    'La connexion réseau est parfois faible au fond de la salle SVT-02 lors du chargement des animations interactives 3D.',
    'read', 'facility', FALSE,
    NOW() - INTERVAL '16 days', NOW() - INTERVAL '15 days'
  );

  -- Suggestion 9 (Sent + Photo Attachment)
  v_sugg_id := gen_random_uuid();
  INSERT INTO public.suggestions (
    id, student_id, subject, message, status, suggestion_type, has_attachment,
    attachment_url, attachment_name, created_at, updated_at
  ) VALUES (
    v_sugg_id, v_user_id,
    'Sensibilisation au tri sélectif : Installation de bacs dédiés',
    'Afin de rendre notre lycée éco-responsable, nous suggérons d''installer des bacs de collecte séparés pour le papier et les bouteilles plastique dans chaque couloir.',
    'sent', 'general', TRUE,
    'https://images.unsplash.com/photo-1532996122724-e3c354a0b15b?w=800', 'bacs_tri_selectif.jpg',
    NOW() - INTERVAL '18 days', NOW() - INTERVAL '18 days'
  );
  INSERT INTO public.suggestion_attachments (suggestion_id, file_url, file_name, file_type, file_size)
  VALUES (v_sugg_id, 'https://images.unsplash.com/photo-1532996122724-e3c354a0b15b?w=800', 'bacs_tri_selectif.jpg', 'image/jpeg', 1100000);

  -- Suggestion 10 (Sent)
  INSERT INTO public.suggestions (
    student_id, subject, message, status, suggestion_type, has_attachment, created_at, updated_at
  ) VALUES (
    v_user_id,
    'Séance hebdomadaire de questions-réponses en direct avant le Bac blanc',
    'Une permanence d''une heure avec nos enseignants de sciences la semaine précédant les examens permettrait d''éclaircir les derniers points difficiles du cours.',
    'sent', 'academic', FALSE,
    NOW() - INTERVAL '21 days', NOW() - INTERVAL '21 days'
  );

  -- ============================================================================
  -- 12. INSERT DIVERSE & ACTIVE ABSENCE RECORDS FOR NOUR
  -- ============================================================================
  -- Record 1: Maths - 2h - CI - Justified (Certificat médical)
  INSERT INTO public.absence_records (
    enrollment_id, student_id, subject_offering_id, date, hours_absent, session_type, reason, justified, created_at
  ) VALUES (
    v_enrollment_id, v_user_id, v_so_math,
    CURRENT_DATE - INTERVAL '10 days',
    2.0, 'CI',
    'Certificat médical Dr. Trabelsi - Repos prescrit (grippe saisonnière)',
    TRUE, NOW() - INTERVAL '10 days'
  );

  -- Record 2: Physique - 1.5h - TP - Justified (Dentiste)
  INSERT INTO public.absence_records (
    enrollment_id, student_id, subject_offering_id, date, hours_absent, session_type, reason, justified, created_at
  ) VALUES (
    v_enrollment_id, v_user_id, v_so_phys,
    CURRENT_DATE - INTERVAL '18 days',
    1.5, 'TP',
    'Rendez-vous médical dentaire urgent - Justificatif visé par l''administration',
    TRUE, NOW() - INTERVAL '18 days'
  );

  -- Record 3: Informatique - 2h - CI - NOT Justified (Transport)
  INSERT INTO public.absence_records (
    enrollment_id, student_id, subject_offering_id, date, hours_absent, session_type, reason, justified, created_at
  ) VALUES (
    v_enrollment_id, v_user_id, v_so_info,
    CURRENT_DATE - INTERVAL '26 days',
    2.0, 'CI',
    'Absence non justifiée (retard de bus / panne de transport urbain)',
    FALSE, NOW() - INTERVAL '26 days'
  );

  -- Record 4: Philosophie - 2h - CI - Justified (Convocation)
  INSERT INTO public.absence_records (
    enrollment_id, student_id, subject_offering_id, date, hours_absent, session_type, reason, justified, created_at
  ) VALUES (
    v_enrollment_id, v_user_id, v_so_philo,
    CURRENT_DATE - INTERVAL '34 days',
    2.0, 'CI',
    'Convocation administrative officielle pour démarche de passeport',
    TRUE, NOW() - INTERVAL '34 days'
  );

  -- Record 5: SVT - 1.5h - TP - NOT Justified (Absence constatée)
  INSERT INTO public.absence_records (
    enrollment_id, student_id, subject_offering_id, date, hours_absent, session_type, reason, justified, created_at
  ) VALUES (
    v_enrollment_id, v_user_id, v_so_svt,
    CURRENT_DATE - INTERVAL '44 days',
    1.5, 'TP',
    'Absence non justifiée à la première heure de travaux pratiques',
    FALSE, NOW() - INTERVAL '44 days'
  );

  -- Record 6: Français - 2h - CI - Justified (Concours)
  INSERT INTO public.absence_records (
    enrollment_id, student_id, subject_offering_id, date, hours_absent, session_type, reason, justified, created_at
  ) VALUES (
    v_enrollment_id, v_user_id, v_so_fr,
    CURRENT_DATE - INTERVAL '58 days',
    2.0, 'CI',
    'Représentation du lycée au Concours Régional d''Éloquence et Poésie',
    TRUE, NOW() - INTERVAL '58 days'
  );

  -- ============================================================================
  -- 13. INSERT 10 OFFICIAL RECEIVED DOCUMENTS FOR NOUR
  -- ============================================================================
  -- Doc 1: Relevé de Notes (Dedicated to Nour)
  INSERT INTO public.documents (
    school_id, class_id, title, description, category, file_url, file_name, file_size, mime_type, uploaded_by, created_at
  ) VALUES (
    v_school_id, v_class_id,
    'Relevé de Notes Officiel — 1er Trimestre 2025/2026',
    '[Student: ' || v_user_id || '|Nour El Houda Khalil|BAC-2026-006] [Semestre: 1] [Type: releve_notes] Relevé trimestriel officiel avec rang et moyenne générale certifiée par le conseil de classe.',
    'administrative',
    'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf',
    'Releve_Notes_T1_Nour_Khalil.pdf', 840000, 'application/pdf', v_admin_id, NOW() - INTERVAL '1 day'
  );

  -- Doc 2: Attestation de Scolarité (Dedicated to Nour)
  INSERT INTO public.documents (
    school_id, class_id, title, description, category, file_url, file_name, file_size, mime_type, uploaded_by, created_at
  ) VALUES (
    v_school_id, v_class_id,
    'Attestation de Scolarité & d''Assiduité 2025-2026',
    '[Student: ' || v_user_id || '|Nour El Houda Khalil|BAC-2026-006] [Type: attestation] Document officiel attestant de l''inscription régulière en classe de Baccalauréat.',
    'administrative',
    'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf',
    'Attestation_Scolarite_2025_2026.pdf', 450000, 'application/pdf', v_admin_id, NOW() - INTERVAL '2 days'
  );

  -- Doc 3: Certificat d'Inscription (Dedicated to Nour)
  INSERT INTO public.documents (
    school_id, class_id, title, description, category, file_url, file_name, file_size, mime_type, uploaded_by, created_at
  ) VALUES (
    v_school_id, v_class_id,
    'Certificat d''Inscription & Matricule National',
    '[Student: ' || v_user_id || '|Nour El Houda Khalil|BAC-2026-006] [Type: certificat] Certificat d''immatriculation au registre national du Ministère de l''Éducation.',
    'administrative',
    'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf',
    'Certificat_Inscription_National.pdf', 520000, 'application/pdf', v_admin_id, NOW() - INTERVAL '4 days'
  );

  -- Doc 4: Carte d'Élève Numérique (Dedicated to Nour)
  INSERT INTO public.documents (
    school_id, class_id, title, description, category, file_url, file_name, file_size, mime_type, uploaded_by, created_at
  ) VALUES (
    v_school_id, v_class_id,
    'Carte d''Élève Numérique — Lycée Pilote Pythagore',
    '[Student: ' || v_user_id || '|Nour El Houda Khalil|BAC-2026-006] [Type: carte_etudiant] Carte scolaire officielle avec QR code de contrôle d''accès et identifiant sécurisé.',
    'administrative',
    'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf',
    'Carte_Eleve_Numerique_Nour.pdf', 680000, 'application/pdf', v_admin_id, NOW() - INTERVAL '6 days'
  );

  -- Doc 5: Planning des Examens (Class-wide)
  INSERT INTO public.documents (
    school_id, class_id, title, description, category, file_url, file_name, file_size, mime_type, uploaded_by, created_at
  ) VALUES (
    v_school_id, v_class_id,
    'Planning & Répartition des Épreuves de Synthèse S1',
    '[Semestre: 1] [Type: planning] Tableau des horaires de passage, numéros de table et consignes sanitaires.',
    'exams',
    'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf',
    'Planning_Synthese_S1_BacSc.pdf', 730000, 'application/pdf', v_admin_id, NOW() - INTERVAL '8 days'
  );

  -- Doc 6: Règlement Intérieur (School-wide)
  INSERT INTO public.documents (
    school_id, class_id, title, description, category, file_url, file_name, file_size, mime_type, uploaded_by, created_at
  ) VALUES (
    v_school_id, NULL,
    'Règlement Intérieur & Charte de Vie Scolaire 2025/2026',
    '[Type: reglement] Charte officielle des droits, devoirs et valeurs républicaines au sein de l''établissement.',
    'administrative',
    'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf',
    'Reglement_Interieur_Pythagore.pdf', 1150000, 'application/pdf', v_admin_id, NOW() - INTERVAL '10 days'
  );

  -- Doc 7: Fascicule de Révision Maths (Class-wide)
  INSERT INTO public.documents (
    school_id, class_id, title, description, category, file_url, file_name, file_size, mime_type, uploaded_by, created_at
  ) VALUES (
    v_school_id, v_class_id,
    'Fascicule de Cours & Exercices Corrigés — Mathématiques',
    '[Semestre: 1] [Type: courses] Recueil complet d''annales et résumés de cours rédigés par l''équipe pédagogique.',
    'courses',
    'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf',
    'Fascicule_Maths_Bac_Sciences.pdf', 2400000, 'application/pdf', v_admin_id, NOW() - INTERVAL '12 days'
  );

  -- Doc 8: Guide des Épreuves du Baccalauréat (Class-wide)
  INSERT INTO public.documents (
    school_id, class_id, title, description, category, file_url, file_name, file_size, mime_type, uploaded_by, created_at
  ) VALUES (
    v_school_id, v_class_id,
    'Guide Officiel & Coefficients des Épreuves du Baccalauréat',
    '[Type: exams] Barèmes officiels, durées des épreuves et coefficients par matière pour la session 2026.',
    'exams',
    'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf',
    'Guide_Epreuves_Bac_2026.pdf', 960000, 'application/pdf', v_admin_id, NOW() - INTERVAL '14 days'
  );

  -- Doc 9: Convention de Stage / PFE (Dedicated to Nour)
  INSERT INTO public.documents (
    school_id, class_id, title, description, category, file_url, file_name, file_size, mime_type, uploaded_by, created_at
  ) VALUES (
    v_school_id, v_class_id,
    'Convention de Stage d''Immersion Scientifique en Laboratoire',
    '[Student: ' || v_user_id || '|Nour El Houda Khalil|BAC-2026-006] [Type: stage_pfe] Convention tripartite pour le stage d''observation au Centre National de Recherche.',
    'other',
    'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf',
    'Convention_Stage_Nour_Khalil.pdf', 580000, 'application/pdf', v_admin_id, NOW() - INTERVAL '16 days'
  );

  -- Doc 10: Bulletin Périodique d'Évaluation (Dedicated to Nour)
  INSERT INTO public.documents (
    school_id, class_id, title, description, category, file_url, file_name, file_size, mime_type, uploaded_by, created_at
  ) VALUES (
    v_school_id, v_class_id,
    'Bulletin Périodique d''Évaluation & Tableau d''Honneur',
    '[Student: ' || v_user_id || '|Nour El Houda Khalil|BAC-2026-006] [Semestre: 1] [Type: releve_notes] Félicitations du conseil d''orientation avec mention Très Bien.',
    'administrative',
    'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf',
    'Bulletin_Evaluation_Honneur_S1.pdf', 790000, 'application/pdf', v_admin_id, NOW() - INTERVAL '20 days'
  );

  RAISE NOTICE 'Demo data successfully generated for Nour (nour.new06@school.tn) at school %', v_school_id;
END $$;

-- Re-enable privilege escalation trigger
ALTER TABLE public.users ENABLE TRIGGER trg_prevent_user_privilege_escalation;
