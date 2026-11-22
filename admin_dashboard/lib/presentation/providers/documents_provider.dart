import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config/supabase_config.dart';

class AcademicDocumentType {
  static const Map<String, String> types = {
    'administrative': 'Administratif',
    'attestation': 'Attestation de scolarité',
    'releve_notes': 'Relevé de notes',
    'certificat': 'Certificat d\'inscription',
    'carte_etudiant': 'Carte d\'étudiant',
    'exams': 'Examens & Évaluations',
    'planning': 'Emploi du temps & Planning',
    'courses': 'Supports de cours & Syllabus',
    'stage_pfe': 'Convention de stage / PFE',
    'reglement': 'Règlement intérieur',
    'other': 'Autre document',
  };

  static String getLabel(String? category) {
    if (category == null || category.isEmpty || category == 'all') {
      return 'Tous les types';
    }
    return types[category] ?? (category[0].toUpperCase() + category.substring(1));
  }

  static String toDbCategory(String uiType) {
    switch (uiType) {
      case 'courses':
      case 'stage_pfe':
        return 'courses';
      case 'exams':
        return 'exams';
      case 'administrative':
      case 'attestation':
      case 'releve_notes':
      case 'certificat':
      case 'carte_etudiant':
      case 'reglement':
        return 'administrative';
      default:
        return 'other';
    }
  }
}

class Document {
  final String id;
  final String schoolId;
  final String? classId;
  final String title;
  final String? description;
  final String category;
  final int semester;
  final String fileUrl;
  final String? fileName;
  final int? fileSize;
  final String? mimeType;
  final String? fileType;
  final DateTime createdAt;
  final String? className;
  
  // Dedicated student metadata
  final String? studentId;
  final String? studentName;
  final String? studentCode;

  Document({
    required this.id,
    required this.schoolId,
    this.classId,
    required this.title,
    this.description,
    this.category = 'administrative',
    this.semester = 1,
    required this.fileUrl,
    this.fileName,
    this.fileSize,
    this.mimeType,
    this.fileType,
    required this.createdAt,
    this.className,
    this.studentId,
    this.studentName,
    this.studentCode,
  });

  Document copyWith({
    String? id,
    String? schoolId,
    String? classId,
    String? title,
    String? description,
    String? category,
    int? semester,
    String? fileUrl,
    String? fileName,
    int? fileSize,
    String? mimeType,
    String? fileType,
    DateTime? createdAt,
    String? className,
    String? studentId,
    String? studentName,
    String? studentCode,
  }) => Document(
    id: id ?? this.id,
    schoolId: schoolId ?? this.schoolId,
    classId: classId ?? this.classId,
    title: title ?? this.title,
    description: description ?? this.description,
    category: category ?? this.category,
    semester: semester ?? this.semester,
    fileUrl: fileUrl ?? this.fileUrl,
    fileName: fileName ?? this.fileName,
    fileSize: fileSize ?? this.fileSize,
    mimeType: mimeType ?? this.mimeType,
    fileType: fileType ?? this.fileType,
    createdAt: createdAt ?? this.createdAt,
    className: className ?? this.className,
    studentId: studentId ?? this.studentId,
    studentName: studentName ?? this.studentName,
    studentCode: studentCode ?? this.studentCode,
  );

  bool get isStudentDedicated => studentId != null && studentId!.isNotEmpty;

  String get cleanDescription {
    if (description == null) return '';
    var text = description!;
    text = text.replaceAll(RegExp(r'\[Semestre:\s*\d+\]'), '');
    text = text.replaceAll(RegExp(r'\[Student:\s*[^\]]+\]'), '');
    text = text.replaceAll(RegExp(r'\[Type:\s*[^\]]+\]'), '');
    return text.trim();
  }

  factory Document.fromJson(Map<String, dynamic> json) {
    final rawDesc = json['description']?.toString() ?? '';
    
    // Parse semester from description or title or fallback to 1
    int sem = 1;
    final semMatch = RegExp(r'\[Semestre:\s*(\d+)\]').firstMatch(rawDesc);
    if (semMatch != null) {
      sem = int.tryParse(semMatch.group(1) ?? '1') ?? 1;
    } else {
      final titleMatch = RegExp(r'\b(?:S|Semestre\s*)(\d+)\b', caseSensitive: false).firstMatch(json['title']?.toString() ?? '');
      if (titleMatch != null) {
        sem = int.tryParse(titleMatch.group(1) ?? '1') ?? 1;
      }
    }

    // Parse student metadata: [Student: id | name | code]
    String? sId;
    String? sName;
    String? sCode;
    final studMatch = RegExp(r'\[Student:\s*([^\|\]]+)\|?([^\|\]]*)\|?([^\]]*)\]').firstMatch(rawDesc);
    if (studMatch != null) {
      sId = studMatch.group(1)?.trim();
      sName = studMatch.group(2)?.trim();
      sCode = studMatch.group(3)?.trim();
      if (sName != null && sName.isEmpty) sName = null;
      if (sCode != null && sCode.isEmpty) sCode = null;
    }

    // Parse custom UI type tag: [Type: specific_type]
    String? parsedUiType;
    final typeMatch = RegExp(r'\[Type:\s*([^\]]+)\]').firstMatch(rawDesc);
    if (typeMatch != null) {
      parsedUiType = typeMatch.group(1)?.trim();
    }

    final rawFileName = json['file_name']?.toString() ?? json['file_url']?.toString().split('/').last ?? '';
    String? ext;
    if (rawFileName.contains('.')) {
      ext = rawFileName.split('.').last.toUpperCase();
    }

    return Document(
      id: json['id']?.toString() ?? '',
      schoolId: json['school_id']?.toString() ?? '',
      classId: json['class_id']?.toString(),
      title: json['title']?.toString() ?? '',
      description: rawDesc,
      category: parsedUiType ?? json['category']?.toString() ?? 'administrative',
      semester: sem,
      fileUrl: json['file_url']?.toString() ?? '',
      fileName: rawFileName,
      fileSize: json['file_size'] is int ? json['file_size'] as int : int.tryParse(json['file_size']?.toString() ?? ''),
      mimeType: json['mime_type']?.toString(),
      fileType: ext ?? 'PDF',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
      className: json['classes']?['name']?.toString(),
      studentId: sId,
      studentName: sName,
      studentCode: sCode,
    );
  }
}

class DocumentsState {
  final List<Document> documents;
  DocumentsState({this.documents = const []});

  DocumentsState copyWith({List<Document>? documents}) =>
    DocumentsState(documents: documents ?? this.documents);
}

class DocumentsNotifier extends AsyncNotifier<DocumentsState> {
  @override
  Future<DocumentsState> build() async => _load();

  Future<DocumentsState> _load() async {
    final supabase = SupabaseConfig.client;
    final user = supabase.auth.currentUser;
    if (user == null) throw Exception('Non connecte');

    final profile = await supabase.from('users').select('school_id').eq('id', user.id).single();
    final data = await supabase.from('documents').select('*, classes(name)').eq('school_id', profile['school_id']).order('created_at', ascending: false);

    return DocumentsState(documents: (data as List).map((e) => Document.fromJson(e)).toList());
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  static String formatDescription({
    String? userDescription,
    required int semester,
    String? uiType,
    String? studentId,
    String? studentName,
    String? studentCode,
  }) {
    final buffer = StringBuffer(userDescription?.trim() ?? '');
    buffer.write('\n[Semestre: $semester]');
    if (uiType != null && uiType.isNotEmpty) {
      buffer.write(' [Type: $uiType]');
    }
    if (studentId != null && studentId.isNotEmpty) {
      buffer.write(' [Student: $studentId|${studentName ?? ''}|${studentCode ?? ''}]');
    }
    return buffer.toString().trim();
  }

  Future<void> create({
    required String title,
    String? description,
    required String fileUrl,
    String? fileName,
    int? fileSize,
    String? mimeType,
    String? classId,
    String category = 'administrative',
    int semester = 1,
    String? studentId,
    String? studentName,
    String? studentCode,
  }) async {
    final supabase = SupabaseConfig.client;
    final user = supabase.auth.currentUser;
    if (user == null) throw Exception('Non connecté');

    final profile = await supabase
        .from('users')
        .select('school_id')
        .eq('id', user.id)
        .single();
    final dbCategory = AcademicDocumentType.toDbCategory(category);
    final formattedDesc = formatDescription(
      userDescription: description,
      semester: semester,
      uiType: category,
      studentId: studentId,
      studentName: studentName,
      studentCode: studentCode,
    );

    final inserted = await supabase
        .from('documents')
        .insert({
          'school_id': profile['school_id'],
          'class_id': classId,
          'title': title,
          'description': formattedDesc,
          'file_url': fileUrl,
          'file_name': fileName ?? title,
          'file_size': fileSize,
          'mime_type': mimeType ?? 'application/pdf',
          'category': dbCategory,
          'uploaded_by': user.id,
        })
        .select('id');

    if ((inserted as List).isEmpty) {
      throw Exception('You do not have permission to create this document.');
    }
    state = AsyncData(await _load());
  }

  Future<void> createMultiple({
    required List<({
      String title,
      String fileUrl,
      String? fileName,
      int? fileSize,
      String? mimeType,
    })> files,
    String? description,
    String? classId,
    String category = 'administrative',
    int semester = 1,
    String? studentId,
    String? studentName,
    String? studentCode,
  }) async {
    if (files.isEmpty) return;
    final supabase = SupabaseConfig.client;
    final user = supabase.auth.currentUser;
    if (user == null) throw Exception('Non connecté');

    final profile = await supabase
        .from('users')
        .select('school_id')
        .eq('id', user.id)
        .single();
    final dbCategory = AcademicDocumentType.toDbCategory(category);
    final formattedDesc = formatDescription(
      userDescription: description,
      semester: semester,
      uiType: category,
      studentId: studentId,
      studentName: studentName,
      studentCode: studentCode,
    );

    final rows = files.map((f) => {
      'school_id': profile['school_id'],
      'class_id': classId,
      'title': f.title,
      'description': formattedDesc,
      'file_url': f.fileUrl,
      'file_name': f.fileName ?? f.title,
      'file_size': f.fileSize,
      'mime_type': f.mimeType ?? 'application/pdf',
      'category': dbCategory,
      'uploaded_by': user.id,
    }).toList();

    final inserted = await supabase
        .from('documents')
        .insert(rows)
        .select('id');

    if ((inserted as List).isEmpty) {
      throw Exception('You do not have permission to create this document.');
    }
    state = AsyncData(await _load());
  }

  Future<void> updateDocument({
    required String id,
    required String title,
    String? description,
    required String fileUrl,
    String? fileName,
    int? fileSize,
    String? mimeType,
    String? classId,
    String category = 'administrative',
    int semester = 1,
    String? studentId,
    String? studentName,
    String? studentCode,
  }) async {
    final supabase = SupabaseConfig.client;
    final dbCategory = AcademicDocumentType.toDbCategory(category);
    final formattedDesc = formatDescription(
      userDescription: description,
      semester: semester,
      uiType: category,
      studentId: studentId,
      studentName: studentName,
      studentCode: studentCode,
    );

    final previous = state.value;
    state.whenData((s) {
      final updatedList = s.documents.map((doc) {
        if (doc.id == id) {
          return doc.copyWith(
            title: title,
            description: formattedDesc,
            fileUrl: fileUrl,
            fileName: fileName,
            fileSize: fileSize,
            mimeType: mimeType,
            classId: classId,
            category: category,
            semester: semester,
            studentId: studentId,
            studentName: studentName,
            studentCode: studentCode,
          );
        }
        return doc;
      }).toList();
      state = AsyncData(s.copyWith(documents: updatedList));
    });

    try {
      final updated = await supabase
          .from('documents')
          .update({
            'class_id': classId,
            'title': title,
            'description': formattedDesc,
            'file_url': fileUrl,
            'category': dbCategory,
            if (fileName != null && fileName.isNotEmpty) 'file_name': fileName,
            'file_size': fileSize,
            'mime_type': mimeType,
          })
          .eq('id', id)
          .select('id');

      if ((updated as List).isEmpty) {
        throw Exception(
          'You do not have permission to modify this document, or it no longer exists.',
        );
      }
    } catch (e) {
      if (previous != null) state = AsyncData(previous);
      rethrow;
    }
  }

  Future<void> delete(String id) async {
    final previous = state.value;
    state.whenData((s) {
      final updated = s.documents.where((doc) => doc.id != id).toList();
      state = AsyncData(s.copyWith(documents: updated));
    });

    try {
      await SupabaseConfig.client.from('documents').delete().eq('id', id);
    } catch (e) {
      if (previous != null) state = AsyncData(previous);
      rethrow;
    }
  }

  Future<void> bulkDelete(List<String> ids) async {
    if (ids.isEmpty) return;
    final previous = state.value;
    final idSet = ids.toSet();
    state.whenData((s) {
      final updated = s.documents.where((doc) => !idSet.contains(doc.id)).toList();
      state = AsyncData(s.copyWith(documents: updated));
    });

    try {
      await SupabaseConfig.client.from('documents').delete().filter('id', 'in', ids);
    } catch (e) {
      if (previous != null) state = AsyncData(previous);
      rethrow;
    }
  }
}

final documentsProvider = AsyncNotifierProvider<DocumentsNotifier, DocumentsState>(DocumentsNotifier.new);