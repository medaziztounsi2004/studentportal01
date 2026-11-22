import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Pre-seeds standard Tunisian educational data (Collège & Lycée system)
/// for any newly created or clean school.
class SchoolDataSeeder {
  static const String _canonicalTemplateSchoolId = '11111111-1111-1111-1111-111111111111';

  static Future<void> seedSchool({
    required SupabaseClient client,
    required String schoolId,
  }) async {
    try {
      debugPrint('[SchoolDataSeeder] Starting seeding for school: $schoolId');

      // 1. Academic Year (Current year: Sep 1 to Jun 30, strictly without partitions/semesters)
      final existingYears = await client
          .from('academic_years')
          .select('id')
          .eq('school_id', schoolId)
          .limit(1);

      if ((existingYears as List).isEmpty) {
        final now = DateTime.now();
        final currentYear = now.month >= 8 ? now.year : now.year - 1;
        final nextYear = currentYear + 1;
        final yearName = '$currentYear-$nextYear';
        final startDate = '$currentYear-09-01';
        final endDate = '$nextYear-06-30';

        await client.from('academic_years').insert({
          'school_id': schoolId,
          'name': yearName,
          'start_date': startDate,
          'end_date': endDate,
          'is_current': true,
        });
        debugPrint('[SchoolDataSeeder] Created default academic year: $yearName');
      }

      // 2. Structural data: Buildings & Floors (Blocs & Étages)
      final existingBuildings = await client
          .from('buildings')
          .select('id')
          .eq('school_id', schoolId)
          .limit(1);

      if ((existingBuildings as List).isEmpty) {
        final buildingRes = await client.from('buildings').insert({
          'school_id': schoolId,
          'name': 'Bloc A - Principal',
          'code': 'BLOC-A',
          'is_active': true,
        }).select().single();

        final buildingId = buildingRes['id'] as String;

        await client.from('floors').insert([
          {
            'building_id': buildingId,
            'school_id': schoolId,
            'name': 'Rez-de-chaussée',
            'floor_number': 0,
            'is_active': true,
          },
          {
            'building_id': buildingId,
            'school_id': schoolId,
            'name': '1er étage',
            'floor_number': 1,
            'is_active': true,
          },
        ]);
        debugPrint('[SchoolDataSeeder] Created default building and floors');
      }

      // 3. Subjects (Matières)
      final existingSubjects = await client
          .from('subjects')
          .select('id, code')
          .eq('school_id', schoolId);

      final Map<String, String> subjectMap = {}; // template_subject_id -> new_subject_id
      final Map<String, String> existingCodes = {};
      for (final s in (existingSubjects as List)) {
        if (s['code'] != null && s['id'] != null) {
          existingCodes[s['code'] as String] = s['id'] as String;
        }
      }

      // Fetch template subjects
      final templateSubjects = await client
          .from('subjects')
          .select('id, code, name, name_ar, category, color, display_order')
          .eq('school_id', _canonicalTemplateSchoolId);

      for (final s in (templateSubjects as List)) {
        final code = s['code'] as String?;
        final templateId = s['id'] as String;

        if (code != null && existingCodes.containsKey(code)) {
          subjectMap[templateId] = existingCodes[code]!;
          continue;
        }

        try {
          final res = await client.from('subjects').insert({
            'school_id': schoolId,
            'code': s['code'],
            'name': s['name'],
            'name_ar': s['name_ar'],
            'category': s['category'] ?? 'general',
            'color': s['color'] ?? '#3B82F6',
            'is_active': true,
            'display_order': s['display_order'] ?? 1,
          }).select('id').single();

          if (res['id'] != null) {
            subjectMap[templateId] = res['id'] as String;
            if (code != null) existingCodes[code] = res['id'] as String;
          }
        } catch (e) {
          debugPrint('[SchoolDataSeeder] Error inserting subject ${s['code']}: $e');
        }
      }
      debugPrint('[SchoolDataSeeder] Seeded/mapped ${subjectMap.length} subjects');

      // 4. Curriculum (Subjects split into Niveaux & Sections with coefficients)
      final existingCurriculum = await client
          .from('curriculum')
          .select('id')
          .eq('school_id', schoolId)
          .limit(1);

      if ((existingCurriculum as List).isEmpty && subjectMap.isNotEmpty) {
        final templateCurriculum = await client
            .from('curriculum')
            .select('niveau_id, section_id, subject_id, coefficient, exam_types, is_mandatory, weekly_hours')
            .eq('school_id', _canonicalTemplateSchoolId);

        final List<Map<String, dynamic>> newCurriculum = [];
        for (final c in (templateCurriculum as List)) {
          final oldSubId = c['subject_id'] as String?;
          final newSubId = oldSubId != null ? subjectMap[oldSubId] : null;

          if (newSubId != null) {
            newCurriculum.add({
              'school_id': schoolId,
              'niveau_id': c['niveau_id'],
              'section_id': c['section_id'],
              'subject_id': newSubId,
              'coefficient': c['coefficient'],
              'exam_types': c['exam_types'],
              'is_mandatory': c['is_mandatory'] ?? true,
              'is_active': true,
              'weekly_hours': c['weekly_hours'] ?? 0,
            });
          }
        }

        // Insert in batches of 50
        for (int i = 0; i < newCurriculum.length; i += 50) {
          final batch = newCurriculum.sublist(
            i,
            i + 50 > newCurriculum.length ? newCurriculum.length : i + 50,
          );
          try {
            await client.from('curriculum').insert(batch);
          } catch (e) {
            debugPrint('[SchoolDataSeeder] Error inserting curriculum batch: $e');
          }
        }
        debugPrint('[SchoolDataSeeder] Seeded ${newCurriculum.length} curriculum rows');
      }

      // Classes: Explicitly EMPTY. Do NOT create any classes.
      debugPrint('[SchoolDataSeeder] Seeding finished. Classes are empty (vide).');
    } catch (e) {
      debugPrint('[SchoolDataSeeder] Seeding exception: $e');
    }
  }
}
