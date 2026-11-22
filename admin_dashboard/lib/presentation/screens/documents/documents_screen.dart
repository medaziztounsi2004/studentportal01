// ignore_for_file: avoid_web_libraries_in_flutter, unused_element, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:ui';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/error_messages.dart';
import '../../../data/models/class_model.dart';
import '../../../data/models/academic_models.dart';
import '../../../data/models/user_model.dart';
import '../../providers/classes_provider.dart';
import '../../providers/documents_provider.dart';
import '../../providers/grade_levels_provider.dart';
import '../../providers/semesters_provider.dart';
import '../../providers/users_provider.dart';
import '../../widgets/admin_sidebar.dart';
import '../../widgets/admin_sort_dropdown.dart';
import '../../widgets/ios_loader.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/user_avatar.dart';

class DocumentsScreen extends ConsumerStatefulWidget {
  const DocumentsScreen({super.key});

  @override
  ConsumerState<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends ConsumerState<DocumentsScreen> {
  // Search & Debounce
  final _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _debounce;

  // Selected category tab index (0: Tous, 1: Académiques, 2: Administratif, 3: Cours, 4: Examens, 5: Autre)
  int _selectedTabIndex = 0;

  // Selected semester pill (null = Tous, int = semester number from DB)
  int? _selectedSemesterPill;

  // Selection state for multi-action
  final Set<String> _selectedIds = {};
  String _sortKey = 'date_desc';

  // Pagination
  int _currentPage = 1;
  int _rowsPerPage = 10;

  // Drawers
  bool _showFilterDrawer = false;
  Document? _selectedDocForDetail;

  // Advanced Filters
  String? _filterType;
  String? _filterCategory;
  String? _filterNiveauId;
  String? _filterSectionId;
  String? _filterClassId;
  int? _filterSemester;
  String? _filterFileType;
  DateTime? _filterDateFrom;
  DateTime? _filterDateTo;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) {
        setState(() {
          _searchQuery = _searchController.text.trim();
          _currentPage = 1;
        });
      }
    });
  }

  bool get _hasActiveFilters =>
      _filterType != null ||
      _filterCategory != null ||
      _filterNiveauId != null ||
      _filterSectionId != null ||
      _filterClassId != null ||
      _filterSemester != null ||
      _filterFileType != null ||
      _filterDateFrom != null ||
      _filterDateTo != null;

  void _resetFilters() {
    setState(() {
      _filterType = null;
      _filterCategory = null;
      _filterNiveauId = null;
      _filterSectionId = null;
      _filterClassId = null;
      _filterSemester = null;
      _filterFileType = null;
      _filterDateFrom = null;
      _filterDateTo = null;
      _currentPage = 1;
    });
  }

  bool _matchesCategoryTab(Document d) {
    final dbCat = AcademicDocumentType.toDbCategory(d.category);
    switch (_selectedTabIndex) {
      case 1: // Académiques (everything except administrative)
        return dbCat != 'administrative';
      case 2: // Administratif
        return dbCat == 'administrative';
      case 3: // Cours
        return dbCat == 'courses';
      case 4: // Examens
        return dbCat == 'exams';
      case 5: // Autre
        return dbCat == 'other';
      default: // Tous (0)
        return true;
    }
  }

  List<Document> _applyFiltering(
    List<Document> docs,
    List<SemesterModel> semesters,
  ) {
    return docs.where((d) {
      // 1. Text Search
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchTitle = d.title.toLowerCase().contains(q);
        final matchDesc = d.cleanDescription.toLowerCase().contains(q);
        final matchClass = (d.className ?? '').toLowerCase().contains(q);
        final matchStudent = (d.studentName ?? '').toLowerCase().contains(q) ||
            (d.studentCode ?? '').toLowerCase().contains(q);
        final matchType =
            AcademicDocumentType.getLabel(d.category).toLowerCase().contains(q);
        if (!matchTitle &&
            !matchDesc &&
            !matchClass &&
            !matchStudent &&
            !matchType) {
          return false;
        }
      }

      // 2. Category Tab filter
      if (!_matchesCategoryTab(d)) return false;

      // 3. Semester Pill filter
      if (_selectedSemesterPill != null && d.semester != _selectedSemesterPill) {
        return false;
      }

      // 4. Advanced filters
      if (_filterType != null && d.category != _filterType) return false;
      if (_filterCategory != null) {
        final dbCat = AcademicDocumentType.toDbCategory(d.category);
        if (_filterCategory == 'administrative' && dbCat != 'administrative') {
          return false;
        }
        if (_filterCategory == 'academic' && dbCat == 'administrative') {
          return false;
        }
      }
      if (_filterSemester != null && d.semester != _filterSemester) return false;
      if (_filterClassId != null) {
        if (d.classId != _filterClassId) return false;
      } else if (_filterSectionId != null) {
        final classes = ref.read(classesProvider).value?.classes ?? <ClassModel>[];
        final sectionClassIds = classes.where((c) => c.sectionId == _filterSectionId).map((c) => c.id).toSet();
        if (d.classId == null || !sectionClassIds.contains(d.classId)) return false;
      } else if (_filterNiveauId != null) {
        final classes = ref.read(classesProvider).value?.classes ?? <ClassModel>[];
        final gradeClassIds = classes.where((c) => c.gradeLevelId == _filterNiveauId).map((c) => c.id).toSet();
        if (d.classId == null || !gradeClassIds.contains(d.classId)) return false;
      }
      if (_filterFileType != null) {
        final ext = (d.fileType ?? '').toUpperCase();
        if (_filterFileType == 'PDF' && !ext.contains('PDF')) return false;
        if (_filterFileType == 'Word' &&
            !ext.contains('DOC') &&
            !ext.contains('DOCX')) {
          return false;
        }
        if (_filterFileType == 'Excel' &&
            !ext.contains('XLS') &&
            !ext.contains('XLSX') &&
            !ext.contains('CSV')) {
          return false;
        }
        if (_filterFileType == 'Image' &&
            !ext.contains('PNG') &&
            !ext.contains('JPG') &&
            !ext.contains('JPEG')) {
          return false;
        }
      }
      if (_filterDateFrom != null && d.createdAt.isBefore(_filterDateFrom!)) {
        return false;
      }
      if (_filterDateTo != null &&
          d.createdAt.isAfter(
            _filterDateTo!.add(const Duration(days: 1)),
          )) {
        return false;
      }

      return true;
    }).toList();
  }

  void _exportCsv(List<Document> docs) {
    if (docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucun document à exporter')),
      );
      return;
    }
    final rows = <List<dynamic>>[];
    rows.add([
      'ID',
      'Titre',
      'Catégorie',
      'Semestre',
      'Classe',
      'Étudiant dédié',
      'Format',
      'Date de création',
      'Lien fichier',
    ]);
    final df = DateFormat("d MMM yyyy 'à' HH:mm", 'fr_FR');
    for (final d in docs) {
      rows.add([
        d.id,
        d.title,
        AcademicDocumentType.getLabel(d.category),
        'Semestre ${d.semester}',
        d.className ?? 'Général',
        d.isStudentDedicated ? '${d.studentName} (${d.studentCode})' : 'Tous',
        d.fileType ?? 'PDF',
        df.format(d.createdAt),
        d.fileUrl,
      ]);
    }
    final csvData = const ListToCsvConverter().convert(rows);
    final bytes = html.Blob([csvData], 'text/csv;charset=utf-8');
    final url = html.Url.createObjectUrlFromBlob(bytes);
    html.AnchorElement(href: url)
      ..setAttribute(
        'download',
        'documents_export_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.csv',
      )
      ..click();
    html.Url.revokeObjectUrl(url);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${docs.length} documents exportés en CSV avec succès'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  UserModel? _findStudent(String? studentId) {
    if (studentId == null || studentId.isEmpty) return null;
    final users = ref.watch(usersProvider).value?.users;
    if (users == null) return null;
    for (final u in users) {
      if (u.id == studentId) return u;
    }
    return null;
  }

  void _openFile(String url) {
    if (url.isEmpty) return;
    try {
      html.window.open(url, '_blank');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            UserFriendlyError.format(
              e,
              fallback: 'Unable to open this file right now. Please try again.',
            ),
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _confirmDeleteSingle(Document d) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.08),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.errorSoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: AppColors.error,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Supprimer document ?',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Voulez-vous vraiment supprimer "${d.title}" ? Cette action est irréversible.'),
            ],
          ),
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          actions: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SizedBox(
                  height: 40,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF6B7280),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Annuler',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 40,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      try {
                        await ref.read(documentsProvider.notifier).delete(d.id);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Document supprimé avec succès'),
                              backgroundColor: AppColors.success,
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                UserFriendlyError.format(
                                  e,
                                  fallback:
                                      'Unable to delete this document right now. Please try again.',
                                ),
                              ),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text(
                      'Supprimer',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteSelected() {
    if (_selectedIds.isEmpty) return;
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.08),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.errorSoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: AppColors.error,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Supprimer la sélection ?',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ],
          ),
          content: Text(
            'Voulez-vous supprimer les ${_selectedIds.length} documents sélectionnés ? Cette action est irréversible.',
          ),
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          actions: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SizedBox(
                  height: 40,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF6B7280),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Annuler',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 40,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      final count = _selectedIds.length;
                      try {
                        await ref
                            .read(documentsProvider.notifier)
                            .bulkDelete(_selectedIds.toList());
                        setState(() => _selectedIds.clear());
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '$count documents supprimés avec succès',
                              ),
                              backgroundColor: AppColors.success,
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                UserFriendlyError.format(
                                  e,
                                  fallback:
                                      'Unable to delete the selected documents right now. Please try again.',
                                ),
                              ),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text(
                      'Supprimer',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _bulkChangeSemester(
    List<Document> selectedDocs,
    List<SemesterModel> semesters,
  ) {
    if (selectedDocs.isEmpty || semesters.isEmpty) return;
    int targetSemester = semesters.first.number;
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.08),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            title: const Text(
              'Changer le semestre',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Appliquer un nouveau semestre aux ${selectedDocs.length} document${selectedDocs.length > 1 ? 's' : ''} sélectionné${selectedDocs.length > 1 ? 's' : ''} :',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.slate50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.borderLight),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: targetSemester,
                      isExpanded: true,
                      borderRadius: BorderRadius.circular(10),
                      dropdownColor: Colors.white,
                      items: semesters
                          .map(
                            (s) => DropdownMenuItem(
                              value: s.number,
                              child: Text(
                                s.name,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setModalState(() => targetSemester = v);
                      },
                    ),
                  ),
                ),
              ],
            ),
            actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            actions: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SizedBox(
                    height: 40,
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF6B7280),
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Annuler',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 40,
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        try {
                          final notifier = ref.read(documentsProvider.notifier);
                          for (final d in selectedDocs) {
                            await notifier.updateDocument(
                              id: d.id,
                              title: d.title,
                              description: d.cleanDescription,
                              fileUrl: d.fileUrl,
                              fileName: d.fileName,
                              fileSize: d.fileSize,
                              mimeType: d.mimeType,
                              classId: d.classId,
                              category: d.category,
                              semester: targetSemester,
                              studentId: d.studentId,
                              studentName: d.studentName,
                              studentCode: d.studentCode,
                            );
                          }
                          if (mounted) {
                            setState(() => _selectedIds.clear());
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '${selectedDocs.length} document${selectedDocs.length > 1 ? 's mis' : ' mis'} à jour',
                                ),
                                backgroundColor: AppColors.success,
                              ),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  UserFriendlyError.format(
                                    e,
                                    fallback:
                                        'Unable to update the selected documents right now. Please try again.',
                                  ),
                                ),
                                backgroundColor: AppColors.error,
                              ),
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6D4CF6),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Appliquer',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddOrEditModal({Document? editDoc}) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.08),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: _DocumentFormDialog(editDoc: editDoc),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final docsAsync = ref.watch(documentsProvider);
    final semestersAsync = ref.watch(semestersProvider);

    // Extract dynamic deduplicated semesters list from Period DB
    final rawSemesters = semestersAsync.value?.filteredSemesters.isNotEmpty == true
        ? semestersAsync.value!.filteredSemesters
        : (semestersAsync.value?.semesters ?? <SemesterModel>[]);
    final semesters = <SemesterModel>[];
    final seenSemNumbers = <int>{};
    for (final s in rawSemesters) {
      if (seenSemNumbers.add(s.number)) {
        semesters.add(s);
      }
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Row(
            children: [
              const AdminSidebar(currentRoute: '/documents'),
              Expanded(
                child: Stack(
                  children: [
                    Column(
                      children: [
                        // Header Bar
                        _buildHeader(),

                        // Main Content
                        Expanded(
                          child: docsAsync.when(
                            skipLoadingOnReload: true,
                            skipLoadingOnRefresh: true,
                            loading: () => const DocumentsSkeletonLoader(),
                            error: (err, _) => Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.error_outline_rounded,
                                      size: 48,
                                      color: AppColors.error,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      UserFriendlyError.format(
                                        err,
                                        fallback:
                                            'Unable to load documents right now. Please try again.',
                                      ),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(color: AppColors.error),
                                    ),
                                    const SizedBox(height: 12),
                                    ElevatedButton.icon(
                                      onPressed: () => ref
                                          .read(documentsProvider.notifier)
                                          .refresh(),
                                      icon: const Icon(Icons.refresh, size: 16),
                                      label: const Text('Réessayer'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            data: (state) =>
                                _buildBody(state.documents, semesters),
                          ),
                        ),
                      ],
                    ),

                    // Floating Black Selection Bar (EXACT CLONE OF USER PAGE)
                    if (_selectedIds.isNotEmpty)
                      Positioned(
                        bottom: 24,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: _buildFloatingSelectionBar(
                            docsAsync.value?.documents ?? [],
                            semesters,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),

          // Right Filter Drawer with Full-App Background Blur
          if (_showFilterDrawer) _buildRightFilterDrawer(semesters),

          // Right Document Detail Drawer with Full-App Background Blur
          if (_selectedDocForDetail != null)
            _buildRightDetailDrawer(_selectedDocForDetail!, semesters),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // HEADER BAR (EXACT CLONE OF USER PAGE)
  // ─────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE9EAF2))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Title + Subtitle
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Documents',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Gérez et organisez tous les documents pédagogiques et administratifs',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
            ],
          ),

          const Spacer(),

          // Exact Users page Search Bar (no blue highlight)
          SizedBox(
            width: 320,
            height: 40,
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() {
                _searchQuery = v.trim();
                _currentPage = 1;
              }),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Rechercher...',
                hintStyle: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 13,
                ),
                prefixIcon: const Icon(
                  Icons.search,
                  size: 18,
                  color: AppColors.textTertiary,
                ),
                suffixIcon: _searchController.text.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.slate50,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: const Text(
                            '⌘K',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.textTertiary,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                            _currentPage = 1;
                          });
                        },
                      ),
                filled: true,
                fillColor: AppColors.slate50,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: const Color(0xFF655DD5).withOpacity(0.4),
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          AdminSortDropdown<String>(
            value: _sortKey,
            tooltip: 'Trier les documents',
            onChanged: (v) => setState(() {
              _sortKey = v;
              _currentPage = 1;
            }),
            options: const [
              SortOption(value: 'date_desc', label: 'Date (Plus récent)', icon: Icons.calendar_today_outlined),
              SortOption(value: 'date_asc', label: 'Date (Plus ancien)', icon: Icons.calendar_today_outlined),
              SortOption(value: 'title_asc', label: 'Titre (A → Z)', icon: Icons.sort_by_alpha),
              SortOption(value: 'title_desc', label: 'Titre (Z → A)', icon: Icons.sort_by_alpha),
              SortOption(value: 'size_desc', label: 'Taille (Plus volumineux)', icon: Icons.arrow_upward),
              SortOption(value: 'size_asc', label: 'Taille (Moins volumineux)', icon: Icons.arrow_downward),
              SortOption(value: 'category_asc', label: 'Catégorie (A → Z)', icon: Icons.folder_outlined),
            ],
          ),
          const SizedBox(width: 8),

          // Filter Button
          _buildHeaderIconButton(
            icon: Icons.filter_list_rounded,
            tooltip: 'Filtres',
            isActive: _showFilterDrawer || _hasActiveFilters,
            onPressed: () {
              setState(() {
                _showFilterDrawer = !_showFilterDrawer;
                if (_showFilterDrawer) _selectedDocForDetail = null;
              });
            },
          ),
          const SizedBox(width: 16),

          // Primary Add Button
          SizedBox(
            height: 40,
            child: ElevatedButton.icon(
              onPressed: () => _showAddOrEditModal(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text(
                'Ajouter',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6D4CF6),
                foregroundColor: Colors.white,
                elevation: 2,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                shadowColor: const Color(0xFF6D4CF6).withOpacity(0.3),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderIconButton({
    required IconData icon,
    required String tooltip,
    VoidCallback? onPressed,
    bool isActive = false,
  }) {
    return IconButton(
      icon: Icon(icon, size: 20),
      tooltip: tooltip,
      onPressed: onPressed,
      color: isActive ? const Color(0xFF655DD5) : AppColors.textTertiary,
      style: IconButton.styleFrom(
        backgroundColor:
            isActive ? const Color(0xFFF5F3FF) : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: isActive
                ? const Color(0xFF655DD5).withOpacity(0.2)
                : Colors.transparent,
          ),
        ),
      ),
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // FLOATING SELECTION BAR (EXACT CLONE OF USER PAGE)
  // ─────────────────────────────────────────────────────────────
  Widget _buildFloatingSelectionBar(
    List<Document> allDocs,
    List<SemesterModel> semesters,
  ) {
    final count = _selectedIds.length;
    final selectedDocs =
        allDocs.where((d) => _selectedIds.contains(d.id)).toList();

    return Material(
      elevation: 12,
      borderRadius: BorderRadius.circular(10),
      color: const Color(0xFF111827),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Count badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(color: Colors.white.withOpacity(0.15)),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: const Color(0xFF655DD5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Center(
                      child: Text(
                        '$count',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    count > 1 ? 'Sélectionnés' : 'Sélectionné',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            // Actions
            _buildSelectionAction(
              Icons.delete_outline,
              'Supprimer',
              const Color(0xFFFCA5A5),
              _confirmDeleteSelected,
            ),
            // Close button
            Container(
              margin: const EdgeInsets.only(left: 4),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: Colors.white.withOpacity(0.15)),
                ),
              ),
              child: IconButton(
                icon: const Icon(Icons.close, size: 16, color: Colors.white60),
                onPressed: () => setState(() => _selectedIds.clear()),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionAction(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // MAIN BODY
  // ─────────────────────────────────────────────────────────────
  Widget _buildBody(List<Document> allDocs, List<SemesterModel> semesters) {
    final filtered = _applyFiltering(allDocs, semesters);
    switch (_sortKey) {
      case 'date_asc':
        filtered.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
      case 'title_asc':
        filtered.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case 'title_desc':
        filtered.sort((a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()));
        break;
      case 'size_desc':
        filtered.sort((a, b) => (b.fileSize ?? 0).compareTo(a.fileSize ?? 0));
        break;
      case 'size_asc':
        filtered.sort((a, b) => (a.fileSize ?? 0).compareTo(b.fileSize ?? 0));
        break;
      case 'category_asc':
        filtered.sort((a, b) => a.category.toLowerCase().compareTo(b.category.toLowerCase()));
        break;
      case 'date_desc':
      default:
        filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
    }

    // Header Category Tabs: Tous, Académiques, Administratif, Cours, Examens, Autre
    final totalCount = allDocs.length;
    final academicCount = allDocs
        .where((d) => AcademicDocumentType.toDbCategory(d.category) != 'administrative')
        .length;
    final adminCount = allDocs
        .where((d) => AcademicDocumentType.toDbCategory(d.category) == 'administrative')
        .length;
    final coursesCount = allDocs
        .where((d) => AcademicDocumentType.toDbCategory(d.category) == 'courses')
        .length;
    final examsCount = allDocs
        .where((d) => AcademicDocumentType.toDbCategory(d.category) == 'exams')
        .length;
    final otherCount = allDocs
        .where((d) => AcademicDocumentType.toDbCategory(d.category) == 'other')
        .length;

    final tabs = <_TabItem>[
      _TabItem(
        label: 'Tous',
        count: totalCount,
        icon: Icons.folder_outlined,
      ),
      _TabItem(
        label: 'Académiques',
        count: academicCount,
        icon: Icons.school_rounded,
      ),
      _TabItem(
        label: 'Administratif',
        count: adminCount,
        icon: Icons.description_outlined,
      ),
      _TabItem(
        label: 'Cours',
        count: coursesCount,
        icon: Icons.menu_book_rounded,
      ),
      _TabItem(
        label: 'Examens',
        count: examsCount,
        icon: Icons.assignment_outlined,
      ),
      _TabItem(
        label: 'Autre',
        count: otherCount,
        icon: Icons.more_horiz_rounded,
      ),
    ];

    // Pagination slice supporting _rowsPerPage == -1 ("All")
    final totalFiltered = filtered.length;
    final totalPages =
        _rowsPerPage == -1 ? 1 : (totalFiltered / _rowsPerPage).ceil();
    if (_currentPage > totalPages && totalPages > 0) _currentPage = totalPages;
    final startIndex =
        _rowsPerPage == -1 ? 0 : (_currentPage - 1) * _rowsPerPage;
    final endIndex = _rowsPerPage == -1
        ? totalFiltered
        : (startIndex + _rowsPerPage).clamp(0, totalFiltered);
    final paginatedDocs = (startIndex < totalFiltered)
        ? filtered.sublist(startIndex, endIndex)
        : <Document>[];

    return Column(
      children: [
        // Header Category Tabs (Users page design)
        _buildTabBar(tabs),

        // Semester Pills Bar (Users page segmented pills + dynamic Period DB semesters)
        _buildSemesterPillsBar(semesters),

        // Document Table Card
        Expanded(
          child: Container(
            color: const Color(0xFFF8FAFC),
            padding: const EdgeInsets.all(24),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border.withOpacity(0.5)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Column(
                  children: [
                    // Table Header Row
                    _buildTableHeaderRow(paginatedDocs),

                    // Table Body / Empty State
                    Expanded(
                      child: paginatedDocs.isEmpty
                          ? _buildEmptyState()
                          : ListView.separated(
                              itemCount: paginatedDocs.length,
                              separatorBuilder: (context, index) => Divider(
                                height: 1,
                                color: AppColors.border.withOpacity(0.4),
                              ),
                              itemBuilder: (context, index) {
                                final d = paginatedDocs[index];
                                final isSelected =
                                    _selectedIds.contains(d.id);
                                return _buildDocumentRow(d, isSelected);
                              },
                            ),
                    ),

                    // Pagination Footer
                    _buildPaginationFooter(totalFiltered),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // HEADER CATEGORY TABS BAR (EXACT CLONE OF USER PAGE)
  // ─────────────────────────────────────────────────────────────
  Widget _buildTabBar(List<_TabItem> tabs) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: AppColors.border.withOpacity(0.5)),
        ),
      ),
      padding: const EdgeInsets.only(left: 24, top: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(tabs.length, (index) {
            final t = tabs[index];
            final isActive = _selectedTabIndex == index;
            return Padding(
              padding: EdgeInsets.only(right: index == tabs.length - 1 ? 24 : 24),
              child: _buildTab(
                icon: t.icon,
                label: t.label,
                count: t.count,
                isActive: isActive,
                onTap: () {
                  setState(() {
                    _selectedTabIndex = index;
                    _currentPage = 1;
                  });
                },
                activeColor: const Color(0xFF655DD5),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildTab({
    required IconData icon,
    required String label,
    required int count,
    required bool isActive,
    required VoidCallback onTap,
    required Color activeColor,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.only(bottom: 12, top: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? activeColor : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: isActive ? activeColor : AppColors.textTertiary,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                color: isActive ? activeColor : AppColors.textTertiary,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isActive ? const Color(0xFFE0E7FF) : AppColors.slate100,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color:
                      isActive ? const Color(0xFF4338CA) : AppColors.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // SEMESTER PILLS BAR (EXACT CLONE OF USER PAGE PILLS BAR)
  // ─────────────────────────────────────────────────────────────
  Widget _buildSemesterPillsBar(List<SemesterModel> semesters) {
    final activeFilterChips = <Widget>[];
    if (_filterType != null) {
      activeFilterChips.add(_buildActiveFilterChip(
        label: 'Type: ${AcademicDocumentType.getLabel(_filterType)}',
        onRemove: () => setState(() {
          _filterType = null;
          _currentPage = 1;
        }),
      ));
    }
    if (_filterCategory != null) {
      activeFilterChips.add(_buildActiveFilterChip(
        label:
            'Catégorie: ${_filterCategory == 'administrative' ? 'Administratif' : 'Académique'}',
        onRemove: () => setState(() {
          _filterCategory = null;
          _currentPage = 1;
        }),
      ));
    }
    if (_filterSemester != null) {
      final semName = semesters
              .where((s) => s.number == _filterSemester)
              .map((s) => s.name)
              .firstOrNull ??
          'Semestre $_filterSemester';
      activeFilterChips.add(_buildActiveFilterChip(
        label: semName,
        onRemove: () => setState(() {
          _filterSemester = null;
          _currentPage = 1;
        }),
      ));
    }
    if (_filterNiveauId != null) {
      final gradeLevels = ref.read(gradeLevelsProvider).value?.gradeLevels ?? <GradeLevelModel>[];
      final gName = gradeLevels
              .where((g) => g.id == _filterNiveauId)
              .map((g) => g.name)
              .firstOrNull ??
          'Niveau';
      activeFilterChips.add(_buildActiveFilterChip(
        label: 'Niveau: $gName',
        onRemove: () => setState(() {
          _filterNiveauId = null;
          _filterSectionId = null;
          _filterClassId = null;
          _currentPage = 1;
        }),
      ));
    }
    if (_filterSectionId != null) {
      final gradeLevels = ref.read(gradeLevelsProvider).value?.gradeLevels ?? <GradeLevelModel>[];
      final currentGrade = gradeLevels.where((g) => g.id == _filterNiveauId).firstOrNull;
      final classes = ref.read(classesProvider).value?.classes ?? <ClassModel>[];
      final sFromClass = classes.where((c) => c.sectionId == _filterSectionId).map((c) => c.sectionName).firstOrNull;
      final sName = sFromClass ?? currentGrade?.sections
              .where((s) => s.id == _filterSectionId)
              .map((s) => s.name)
              .firstOrNull ??
          'Filière';
      activeFilterChips.add(_buildActiveFilterChip(
        label: 'Filière: $sName',
        onRemove: () => setState(() {
          _filterSectionId = null;
          _filterClassId = null;
          _currentPage = 1;
        }),
      ));
    }
    if (_filterClassId != null) {
      final classes = ref.read(classesProvider).value?.classes ?? <ClassModel>[];
      final clsName = classes
              .where((c) => c.id == _filterClassId)
              .map((c) => c.name)
              .firstOrNull ??
          'Classe';
      activeFilterChips.add(_buildActiveFilterChip(
        label: 'Classe: $clsName',
        onRemove: () => setState(() {
          _filterClassId = null;
          _currentPage = 1;
        }),
      ));
    }
    if (_filterFileType != null) {
      activeFilterChips.add(_buildActiveFilterChip(
        label: 'Format: $_filterFileType',
        onRemove: () => setState(() {
          _filterFileType = null;
          _currentPage = 1;
        }),
      ));
    }
    if (_filterDateFrom != null) {
      activeFilterChips.add(_buildActiveFilterChip(
        label: 'Du ${DateFormat('d MMM', 'fr_FR').format(_filterDateFrom!)}',
        onRemove: () => setState(() {
          _filterDateFrom = null;
          _currentPage = 1;
        }),
        color: AppColors.warning,
      ));
    }
    if (_filterDateTo != null) {
      activeFilterChips.add(_buildActiveFilterChip(
        label: 'Au ${DateFormat('d MMM', 'fr_FR').format(_filterDateTo!)}',
        onRemove: () => setState(() {
          _filterDateTo = null;
          _currentPage = 1;
        }),
        color: AppColors.warning,
      ));
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: AppColors.border.withOpacity(0.5)),
        ),
      ),
      child: Row(
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: AppColors.slate100.withOpacity(0.8),
                borderRadius: BorderRadius.circular(24),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildSemesterChip(
                      'Tous',
                      _selectedSemesterPill == null,
                      () => setState(() {
                        _selectedSemesterPill = null;
                        _currentPage = 1;
                      }),
                    ),
                    ...semesters.map((s) {
                      return _buildSemesterChip(
                        s.name,
                        _selectedSemesterPill == s.number,
                        () => setState(() {
                          _selectedSemesterPill = s.number;
                          _currentPage = 1;
                        }),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),
          if (activeFilterChips.isNotEmpty) ...[
            const SizedBox(width: 16),
            Container(width: 1, height: 24, color: AppColors.border),
            const SizedBox(width: 12),
            const Text(
              'Filtres actifs:',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 8),
            ...activeFilterChips,
          ],
        ],
      ),
    );
  }

  Widget _buildSemesterChip(
    String label,
    bool isActive,
    VoidCallback onTap,
  ) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
              color: isActive ? AppColors.textPrimary : AppColors.textTertiary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveFilterChip({
    required String label,
    required VoidCallback onRemove,
    Color? color,
  }) {
    final chipColor = color ?? const Color(0xFF655DD5);
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: chipColor.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: chipColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: onRemove,
            child: Icon(Icons.close, size: 14, color: chipColor),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // TABLE HEADER ROW
  // ─────────────────────────────────────────────────────────────
  Widget _buildTableHeaderRow(List<Document> pageDocs) {
    final allPageSelected =
        pageDocs.isNotEmpty && pageDocs.every((d) => _selectedIds.contains(d.id));

    return Container(
      height: 44,
      color: const Color(0xFFF9FAFB),
      padding: const EdgeInsets.fromLTRB(0, 0, 20, 0),
      child: Row(
        children: [
          // Select All Checkbox (EXACT CLONE OF USER PAGE)
          SizedBox(
            width: 44,
            child: Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: Checkbox(
                  value: allPageSelected && pageDocs.isNotEmpty,
                  tristate: false,
                  onChanged: (v) {
                    setState(() {
                      if (allPageSelected) {
                        for (final d in pageDocs) {
                          _selectedIds.remove(d.id);
                        }
                      } else {
                        for (final d in pageDocs) {
                          _selectedIds.add(d.id);
                        }
                      }
                    });
                  },
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(3),
                  ),
                  side: const BorderSide(color: AppColors.slate300, width: 1.5),
                  activeColor: const Color(0xFF655DD5),
                ),
              ),
            ),
          ),

          // Title / Document Header
          const Expanded(
            flex: 4,
            child: Text(
              'DOCUMENT / TITRE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textTertiary,
                letterSpacing: 0.5,
              ),
            ),
          ),

          // Type Header
          const Expanded(
            flex: 2,
            child: Text(
              'TYPE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textTertiary,
                letterSpacing: 0.5,
              ),
            ),
          ),

          // Target (Class or Dedicated Student)
          const Expanded(
            flex: 2,
            child: Text(
              'DESTINATAIRE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textTertiary,
                letterSpacing: 0.5,
              ),
            ),
          ),

          // Date Header
          const Expanded(
            flex: 2,
            child: Text(
              'DATE D\'AJOUT',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textTertiary,
                letterSpacing: 0.5,
              ),
            ),
          ),

          // Actions Header
          const SizedBox(
            width: 64,
            child: Text(
              'ACTIONS',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textTertiary,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // TABLE ROW
  // ─────────────────────────────────────────────────────────────
  Widget _buildDocumentRow(Document d, bool isSelected) {
    final df = DateFormat("d MMM yyyy 'à' HH:mm", 'fr_FR');
    final formattedDate = df.format(d.createdAt);
    final ext = (d.fileType ?? 'PDF').toUpperCase();

    return InkWell(
      onTap: () {
        setState(() {
          _selectedDocForDetail = d;
          _showFilterDrawer = false;
        });
      },
      hoverColor: const Color(0xFFF9FAFB),
      child: Container(
        padding: const EdgeInsets.fromLTRB(0, 12, 20, 12),
        color: isSelected
            ? const Color(0xFFF5F3FF).withOpacity(0.4)
            : Colors.transparent,
        child: Row(
          children: [
            // Checkbox (EXACT CLONE OF USER PAGE)
            SizedBox(
              width: 44,
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: Checkbox(
                    value: isSelected,
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _selectedIds.add(d.id);
                        } else {
                          _selectedIds.remove(d.id);
                        }
                      });
                    },
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(3),
                    ),
                    side:
                        const BorderSide(color: AppColors.slate300, width: 1.5),
                    activeColor: const Color(0xFF655DD5),
                  ),
                ),
              ),
            ),

            // File Icon + Title + Description preview
            Expanded(
              flex: 4,
              child: Row(
                children: [
                  _buildFileTypeIcon(ext),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          d.title,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (d.cleanDescription.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            d.cleanDescription,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textTertiary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Type Badge
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _getTypeColor(d.category).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    AcademicDocumentType.getLabel(d.category),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _getTypeColor(d.category),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),

            // Destinataire (Dedicated Student OR Class OR General)
            Expanded(
              flex: 2,
              child: d.isStudentDedicated
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Builder(
                          builder: (_) {
                            final student = _findStudent(d.studentId);
                            return UserAvatar(
                              name: d.studentName ??
                                  student?.fullName ??
                                  'Étudiant',
                              photoUrl: student?.photoUrl,
                              gender: student?.gender,
                              radius: 12,
                            );
                          },
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                d.studentName ?? 'Étudiant',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF6D4CF6),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (d.studentCode != null &&
                                  d.studentCode!.isNotEmpty)
                                Text(
                                  d.studentCode!,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: AppColors.textTertiary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : (d.className != null && d.className!.isNotEmpty)
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            d.className!,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF475569),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        )
                      : const Text(
                          'Tous (Général)',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textTertiary,
                          ),
                        ),
            ),

            // Date
            Expanded(
              flex: 2,
              child: Text(
                formattedDate,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),

            // Actions - Three Dots PopupMenuButton (like User page!)
            SizedBox(
              width: 64,
              child: Center(
                child: PopupMenuButton<String>(
                  icon: const Icon(
                    Icons.more_horiz,
                    size: 18,
                    color: AppColors.textTertiary,
                  ),
                  tooltip: 'Actions',
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 8,
                  offset: const Offset(-140, 36),
                  onSelected: (action) => _handleRowAction(action, d),
                  itemBuilder: (ctx) => [
                    _buildPopupItem(
                      'open',
                      Icons.open_in_new_rounded,
                      'Ouvrir / Télécharger',
                      const Color(0xFF6D4CF6),
                    ),
                    _buildPopupItem(
                      'view',
                      Icons.visibility_outlined,
                      'Détails',
                      AppColors.success,
                    ),
                    _buildPopupItem(
                      'edit',
                      Icons.edit_outlined,
                      'Modifier',
                      const Color(0xFF655DD5),
                    ),
                    const PopupMenuDivider(),
                    _buildPopupItem(
                      'delete',
                      Icons.delete_outline_rounded,
                      'Supprimer',
                      AppColors.error,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _buildPopupItem(
    String value,
    IconData icon,
    String label,
    Color color,
  ) {
    return PopupMenuItem(
      value: value,
      height: 40,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: value == 'delete' ? AppColors.error : AppColors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  void _handleRowAction(String action, Document d) {
    switch (action) {
      case 'open':
        _openFile(d.fileUrl);
        break;
      case 'view':
        setState(() {
          _selectedDocForDetail = d;
          _showFilterDrawer = false;
        });
        break;
      case 'edit':
        _showAddOrEditModal(editDoc: d);
        break;
      case 'delete':
        _confirmDeleteSingle(d);
        break;
    }
  }

  Widget _buildFileTypeIcon(String ext) {
    Color bg;
    IconData icon;
    if (ext.contains('PDF')) {
      bg = const Color(0xFFEF4444);
      icon = Icons.picture_as_pdf_rounded;
    } else if (ext.contains('DOC')) {
      bg = const Color(0xFF3B82F6);
      icon = Icons.description_rounded;
    } else if (ext.contains('XLS') || ext.contains('CSV')) {
      bg = const Color(0xFF10B981);
      icon = Icons.table_chart_rounded;
    } else if (ext.contains('PPT')) {
      bg = const Color(0xFFF59E0B);
      icon = Icons.slideshow_rounded;
    } else if (ext.contains('PNG') || ext.contains('JPG')) {
      bg = const Color(0xFF8B5CF6);
      icon = Icons.image_rounded;
    } else {
      bg = const Color(0xFF64748B);
      icon = Icons.insert_drive_file_rounded;
    }

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: bg.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: bg, size: 20),
    );
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'courses':
        return const Color(0xFF3B82F6);
      case 'exams':
        return const Color(0xFFEF4444);
      case 'administrative':
        return const Color(0xFF10B981);
      case 'attestation':
      case 'certificat':
        return const Color(0xFF8B5CF6);
      default:
        return const Color(0xFF64748B);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // EMPTY STATE
  // ─────────────────────────────────────────────────────────────
  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(32),
              ),
              child: const Icon(
                Icons.folder_open_rounded,
                size: 32,
                color: Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Aucun document trouvé',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Essayez de modifier votre recherche ou vos filtres.',
              style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
            ),
            if (_hasActiveFilters || _searchQuery.isNotEmpty) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () {
                  _searchController.clear();
                  _resetFilters();
                },
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Réinitialiser les filtres'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF6D4CF6),
                  side: const BorderSide(color: Color(0xFF6D4CF6)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // PAGINATION FOOTER (EXACT CLONE OF USER PAGE)
  // ─────────────────────────────────────────────────────────────
  Widget _buildPaginationFooter(int totalItems) {
    final totalPages =
        _rowsPerPage == -1 ? 1 : (totalItems / _rowsPerPage).ceil();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFB),
        border: Border(
          top: BorderSide(color: AppColors.border.withOpacity(0.3)),
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(8),
          bottomRight: Radius.circular(8),
        ),
      ),
      child: Row(
        children: [
          // Items per page
          const Text(
            'Afficher par ',
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _rowsPerPage,
                isDense: true,
                borderRadius: BorderRadius.circular(10),
                dropdownColor: Colors.white,
                elevation: 4,
                menuMaxHeight: 200,
                icon: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 14,
                  color: AppColors.textTertiary,
                ),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
                items: const [10, 20, 50, -1]
                    .map(
                      (v) => DropdownMenuItem(
                        value: v,
                        child: Text(
                          v == -1 ? 'All' : '$v',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() {
                      _rowsPerPage = v;
                      _currentPage = 1;
                    });
                  }
                },
              ),
            ),
          ),
          const Spacer(),
          // Page info
          Text(
            'Page $_currentPage sur ${totalPages == 0 ? 1 : totalPages}',
            style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
          const SizedBox(width: 12),
          // Prev/Next
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                InkWell(
                  onTap: _currentPage > 1
                      ? () => setState(() => _currentPage--)
                      : null,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(5),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.chevron_left,
                      size: 18,
                      color: _currentPage > 1
                          ? AppColors.textSecondary
                          : AppColors.textTertiary,
                    ),
                  ),
                ),
                Container(width: 1, height: 24, color: AppColors.border),
                InkWell(
                  onTap: _currentPage < totalPages
                      ? () => setState(() => _currentPage++)
                      : null,
                  borderRadius: const BorderRadius.horizontal(
                    right: Radius.circular(5),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: _currentPage < totalPages
                          ? AppColors.textSecondary
                          : AppColors.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // FILTER DRAWER (EXACT CLONE OF USER PAGE FILTER DRAWER)
  // ─────────────────────────────────────────────────────────────
  Widget _buildRightFilterDrawer(List<SemesterModel> semesters) {
    final classesState = ref.watch(classesProvider);
    final List<ClassModel> classes = classesState.value?.classes ?? <ClassModel>[];
    final gradeLevelsState = ref.watch(gradeLevelsProvider);
    final gradeLevels = gradeLevelsState.value?.gradeLevels ?? <GradeLevelModel>[];

    final currentGrade = gradeLevels.where((g) => g.id == _filterNiveauId).firstOrNull;
    final Map<String, String> sectionsForNiveau = {};
    if (currentGrade != null) {
      for (final c in classes) {
        final matchesNiveau = c.gradeLevelId == currentGrade.id ||
            c.gradeLevelName?.toLowerCase() == currentGrade.name.toLowerCase();
        if (matchesNiveau && c.sectionId != null && c.sectionName != null) {
          sectionsForNiveau[c.sectionId!] = c.sectionName!;
        }
      }
      for (final s in currentGrade.sections) {
        sectionsForNiveau[s.id] = s.name;
      }
    }
    final hasSections = currentGrade != null && (currentGrade.hasSections || sectionsForNiveau.isNotEmpty);

    List<ClassModel> filteredClasses;
    if (_filterSectionId != null) {
      filteredClasses = classes.where((c) {
        if (_filterNiveauId != null && c.gradeLevelId != _filterNiveauId) return false;
        return c.sectionId == _filterSectionId || c.sectionName == sectionsForNiveau[_filterSectionId];
      }).toList();
    } else if (_filterNiveauId != null) {
      filteredClasses = classes.where((c) => c.gradeLevelId == _filterNiveauId).toList();
    } else {
      filteredClasses = classes;
    }

    return Positioned.fill(
      child: Stack(
        children: [
          // Blurred Backdrop
          GestureDetector(
            onTap: () => setState(() => _showFilterDrawer = false),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: Container(color: Colors.black.withOpacity(0.2)),
            ),
          ),

          // Slide-over Drawer Panel
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              width: 380,
              height: double.infinity,
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x1F000000),
                    blurRadius: 24,
                    offset: Offset(-4, 0),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 18,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: AppColors.border.withOpacity(0.5),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Text(
                          'Filtres',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () =>
                              setState(() => _showFilterDrawer = false),
                          color: AppColors.textTertiary,
                        ),
                      ],
                    ),
                  ),

                  // Filter Fields
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Type de document
                          _buildFilterLabel('TYPE DE DOCUMENT'),
                          const SizedBox(height: 8),
                          _buildFilterDropdown<String?>(
                            value: _filterType,
                            hint: 'Tous les types',
                            items: [
                              const DropdownMenuItem(
                                value: null,
                                child: Text('Tous les types'),
                              ),
                              ...AcademicDocumentType.types.entries.map(
                                (e) => DropdownMenuItem(
                                  value: e.key,
                                  child: Text(e.value),
                                ),
                              ),
                            ],
                            onChanged: (v) => setState(() {
                              _filterType = v;
                              _currentPage = 1;
                            }),
                          ),
                          const SizedBox(height: 20),

                          // Catégorie
                          _buildFilterLabel('CATÉGORIE'),
                          const SizedBox(height: 8),
                          _buildFilterDropdown<String?>(
                            value: _filterCategory,
                            hint: 'Toutes les catégories',
                            items: const [
                              DropdownMenuItem(
                                value: null,
                                child: Text('Toutes les catégories'),
                              ),
                              DropdownMenuItem(
                                value: 'academic',
                                child: Text('Académique'),
                              ),
                              DropdownMenuItem(
                                value: 'administrative',
                                child: Text('Administratif'),
                              ),
                            ],
                            onChanged: (v) => setState(() {
                              _filterCategory = v;
                              _currentPage = 1;
                            }),
                          ),
                          const SizedBox(height: 20),

                          // Semestre (Dynamic from DB!)
                          _buildFilterLabel('SEMESTRE'),
                          const SizedBox(height: 8),
                          _buildFilterDropdown<int?>(
                            value: _filterSemester,
                            hint: 'Tous les semestres',
                            items: [
                              const DropdownMenuItem(
                                value: null,
                                child: Text('Tous les semestres'),
                              ),
                              ...semesters.map(
                                (s) => DropdownMenuItem(
                                  value: s.number,
                                  child: Text(s.name),
                                ),
                              ),
                            ],
                            onChanged: (v) => setState(() {
                              _filterSemester = v;
                              _currentPage = 1;
                            }),
                          ),
                          const SizedBox(height: 20),

                          // Niveau
                          _buildFilterLabel('NIVEAU'),
                          const SizedBox(height: 8),
                          _buildFilterDropdown<String?>(
                            value: _filterNiveauId,
                            hint: 'Tous les niveaux',
                            items: [
                              const DropdownMenuItem(
                                value: null,
                                child: Text('Tous les niveaux'),
                              ),
                              ...gradeLevels.map(
                                (g) => DropdownMenuItem(
                                  value: g.id,
                                  child: Text(g.name),
                                ),
                              ),
                            ],
                            onChanged: (v) => setState(() {
                              _filterNiveauId = v;
                              _filterSectionId = null;
                              _filterClassId = null;
                              _currentPage = 1;
                            }),
                          ),
                          const SizedBox(height: 20),

                          // Filière (conditional if niveau has sections)
                          if (hasSections && sectionsForNiveau.isNotEmpty) ...[
                            _buildFilterLabel('FILIÈRE'),
                            const SizedBox(height: 8),
                            _buildFilterDropdown<String?>(
                              value: _filterSectionId,
                              hint: 'Toutes les filières',
                              items: [
                                const DropdownMenuItem(
                                  value: null,
                                  child: Text('Toutes les filières'),
                                ),
                                ...sectionsForNiveau.entries.map(
                                  (s) => DropdownMenuItem(
                                    value: s.key,
                                    child: Text(s.value),
                                  ),
                                ),
                              ],
                              onChanged: (v) => setState(() {
                                _filterSectionId = v;
                                _filterClassId = null;
                                _currentPage = 1;
                              }),
                            ),
                            const SizedBox(height: 20),
                          ],

                          // Classe concernée
                          _buildFilterLabel('CLASSE CONCERNÉE'),
                          const SizedBox(height: 8),
                          _buildFilterDropdown<String?>(
                            value: _filterClassId,
                            hint: 'Toutes les classes',
                            items: [
                              const DropdownMenuItem(
                                value: null,
                                child: Text('Toutes les classes'),
                              ),
                              ...filteredClasses.map(
                                (c) => DropdownMenuItem(
                                  value: c.id,
                                  child: Text(c.name),
                                ),
                              ),
                            ],
                            onChanged: (v) => setState(() {
                              _filterClassId = v;
                              _currentPage = 1;
                            }),
                          ),
                          const SizedBox(height: 20),

                          // Format de fichier
                          _buildFilterLabel('FORMAT DE FICHIER'),
                          const SizedBox(height: 8),
                          _buildFilterDropdown<String?>(
                            value: _filterFileType,
                            hint: 'Tous les formats',
                            items: const [
                              DropdownMenuItem(
                                value: null,
                                child: Text('Tous les formats'),
                              ),
                              DropdownMenuItem(value: 'PDF', child: Text('PDF')),
                              DropdownMenuItem(
                                value: 'Word',
                                child: Text('Word (.docx)'),
                              ),
                              DropdownMenuItem(
                                value: 'Excel',
                                child: Text('Excel / CSV'),
                              ),
                              DropdownMenuItem(
                                value: 'Image',
                                child: Text('Image'),
                              ),
                            ],
                            onChanged: (v) => setState(() {
                              _filterFileType = v;
                              _currentPage = 1;
                            }),
                          ),
                          const SizedBox(height: 20),

                          // Période (Date début / Date fin)
                          _buildFilterLabel('PÉRIODE (DATE)'),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _buildDatePickerField(
                                  value: _filterDateFrom,
                                  hint: 'Date début',
                                  onTap: () async {
                                    final date = await showDatePicker(
                                      context: context,
                                      initialDate: _filterDateFrom ??
                                          DateTime.now().subtract(
                                            const Duration(days: 90),
                                          ),
                                      firstDate: DateTime(2020),
                                      lastDate: DateTime.now(),
                                    );
                                    if (date != null) {
                                      setState(() => _filterDateFrom = date);
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildDatePickerField(
                                  value: _filterDateTo,
                                  hint: 'Date fin',
                                  onTap: () async {
                                    final date = await showDatePicker(
                                      context: context,
                                      initialDate:
                                          _filterDateTo ?? DateTime.now(),
                                      firstDate: DateTime(2020),
                                      lastDate: DateTime.now(),
                                    );
                                    if (date != null) {
                                      setState(() => _filterDateTo = date);
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Bottom Buttons Container (Matching Image 5)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 20,
                    ),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFAFAFB),
                      border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: OutlinedButton(
                              onPressed: _resetFilters,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF374151),
                                backgroundColor: Colors.white,
                                side: const BorderSide(color: Color(0xFFD1D5DB)),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 0,
                              ),
                              child: const Text(
                                'Réinitialiser',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Container(
                            height: 48,
                            decoration: BoxDecoration(
                              color: const Color(0xFF6D4CF6),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      const Color(0xFF6D4CF6).withOpacity(0.3),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () {
                                  setState(() => _showFilterDrawer = false);
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: const Center(
                                  child: Text(
                                    'Appliquer',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppColors.textTertiary,
        letterSpacing: 1.0,
      ),
    );
  }

  Widget _buildFilterDropdown<T>({
    required T value,
    required String hint,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.slate50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          hint: Text(
            hint,
            style: const TextStyle(fontSize: 13, color: AppColors.textTertiary),
          ),
          isExpanded: true,
          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          items: items,
          onChanged: onChanged,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          borderRadius: BorderRadius.circular(8),
          dropdownColor: Colors.white,
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 20,
            color: AppColors.textTertiary,
          ),
        ),
      ),
    );
  }

  Widget _buildDatePickerField({
    DateTime? value,
    required String hint,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.slate50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value != null
                    ? DateFormat('d MMM yyyy', 'fr_FR').format(value)
                    : hint,
                style: TextStyle(
                  fontSize: 13,
                  color: value != null
                      ? AppColors.textPrimary
                      : AppColors.textTertiary,
                ),
              ),
            ),
            const Icon(
              Icons.calendar_today_outlined,
              size: 16,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // DETAIL DRAWER
  // ─────────────────────────────────────────────────────────────
  Widget _buildRightDetailDrawer(Document d, List<SemesterModel> semesters) {
    final df = DateFormat('dd MMMM yyyy à HH:mm', 'fr');
    final ext = (d.fileType ?? 'PDF').toUpperCase();
    final semLabel = semesters
            .where((s) => s.number == d.semester)
            .map((s) => s.name)
            .firstOrNull ??
        'Semestre ${d.semester}';

    return Positioned.fill(
      child: Stack(
        children: [
          // Blurred Backdrop
          GestureDetector(
            onTap: () => setState(() => _selectedDocForDetail = null),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: Container(color: Colors.black.withOpacity(0.2)),
            ),
          ),

          // Drawer Panel
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              width: 420,
              height: double.infinity,
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x1F000000),
                    blurRadius: 24,
                    offset: Offset(-4, 0),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 18,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: AppColors.border.withOpacity(0.5),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Text(
                          'Détails du document',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () =>
                              setState(() => _selectedDocForDetail = null),
                          color: AppColors.textTertiary,
                        ),
                      ],
                    ),
                  ),

                  // Detail Body
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: Column(
                              children: [
                                _buildFileTypeIcon(ext),
                                const SizedBox(height: 12),
                                Text(
                                  d.title,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _getTypeColor(d.category)
                                        .withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    AcademicDocumentType.getLabel(d.category),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: _getTypeColor(d.category),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Divider(color: Color(0xFFF1F5F9)),
                          const SizedBox(height: 16),

                          // Description
                          if (d.cleanDescription.isNotEmpty) ...[
                            const Text(
                              'DESCRIPTION',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textTertiary,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              d.cleanDescription,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF334155),
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],

                          // Dedicated Student Card (if applicable)
                          if (d.isStudentDedicated) ...[
                            const Text(
                              'ÉTUDIANT CONCERNÉ',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textTertiary,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF5F3FF),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color:
                                      const Color(0xFF6D4CF6).withOpacity(0.2),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Builder(
                                    builder: (_) {
                                      final student = _findStudent(d.studentId);
                                      return UserAvatar(
                                        name: d.studentName ??
                                            student?.fullName ??
                                            'Étudiant',
                                        photoUrl: student?.photoUrl,
                                        gender: student?.gender,
                                        radius: 17,
                                      );
                                    },
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          d.studentName ?? 'Étudiant',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF1E293B),
                                          ),
                                        ),
                                        if (d.studentCode != null &&
                                            d.studentCode!.isNotEmpty)
                                          Text(
                                            'Matricule: ${d.studentCode}',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: AppColors.textTertiary,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],

                          // Metadata Grid
                          _buildDetailRow(
                            'Semestre',
                            semLabel,
                            Icons.calendar_month_outlined,
                          ),
                          _buildDetailRow(
                            'Classe',
                            d.className ?? 'Toutes les classes (Général)',
                            Icons.groups_outlined,
                          ),
                          _buildDetailRow(
                            'Format',
                            ext,
                            Icons.extension_outlined,
                          ),
                          _buildDetailRow(
                            'Date d\'ajout',
                            df.format(d.createdAt),
                            Icons.access_time_rounded,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Bottom Action Buttons
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 20,
                    ),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFAFAFB),
                      border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                setState(() => _selectedDocForDetail = null);
                                _showAddOrEditModal(editDoc: d);
                              },
                              icon: const Icon(Icons.edit_outlined, size: 16),
                              label: const Text('Modifier'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF374151),
                                backgroundColor: Colors.white,
                                side: const BorderSide(color: Color(0xFFD1D5DB)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: ElevatedButton.icon(
                              onPressed: () => _openFile(d.fileUrl),
                              icon: const Icon(
                                Icons.open_in_new_rounded,
                                size: 16,
                              ),
                              label: const Text('Ouvrir'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF6D4CF6),
                                foregroundColor: Colors.white,
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Icon(icon, size: 16, color: const Color(0xFF94A3B8)),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _TabItem {
  final String label;
  final int count;
  final IconData icon;
  const _TabItem({
    required this.label,
    required this.count,
    required this.icon,
  });
}

// ─────────────────────────────────────────────────────────────
// ADD / EDIT DOCUMENT MODAL DIALOG
// ─────────────────────────────────────────────────────────────
class _UploadedDocItem {
  final String fileUrl;
  final String fileName;
  final int fileSize;
  final String mimeType;
  final Uint8List? bytes;

  const _UploadedDocItem({
    required this.fileUrl,
    required this.fileName,
    required this.fileSize,
    required this.mimeType,
    this.bytes,
  });

  bool get isImage =>
      mimeType.toLowerCase().startsWith('image/') ||
      ['.png', '.jpg', '.jpeg', '.webp', '.gif']
          .any((ext) => fileName.toLowerCase().endsWith(ext));
}

class _DocumentFormDialog extends ConsumerStatefulWidget {
  final Document? editDoc;
  const _DocumentFormDialog({this.editDoc});

  @override
  ConsumerState<_DocumentFormDialog> createState() =>
      _DocumentFormDialogState();
}

class _DocumentFormDialogState extends ConsumerState<_DocumentFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _descController;
  late TextEditingController _studentSearchController;

  String _selectedCategory = 'administrative';
  String? _selectedClassId;

  // Target mode: 'all' | 'class' | 'student'
  String _targetMode = 'all';

  // Selected Student
  UserModel? _selectedStudent;
  bool _clearedExistingStudent = false;
  bool _isUploading = false;
  bool _isSaving = false;
  int _uploadingImagesSkeletonCount = 0;
  int _uploadingDocsSkeletonCount = 0;
  final List<_UploadedDocItem> _uploadedFiles = [];
  String? _formError;

  bool get isEditing => widget.editDoc != null;

  @override
  void initState() {
    super.initState();
    final d = widget.editDoc;
    _titleController = TextEditingController(text: d?.title ?? '');
    _descController = TextEditingController(text: d?.cleanDescription ?? '');
    _studentSearchController = TextEditingController();

    if (d != null) {
      _selectedCategory = d.category;
      _selectedClassId = d.classId;
      if (d.fileUrl.isNotEmpty) {
        _uploadedFiles.add(
          _UploadedDocItem(
            fileUrl: d.fileUrl,
            fileName: d.fileName ?? d.title,
            fileSize: d.fileSize ?? 0,
            mimeType: d.mimeType ?? 'application/pdf',
          ),
        );
      }

      if (d.isStudentDedicated) {
        _targetMode = 'student';
      } else if (d.classId != null && d.classId!.isNotEmpty) {
        _targetMode = 'class';
      } else {
        _targetMode = 'all';
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _studentSearchController.dispose();
    super.dispose();
  }

  String _formatBytes(int? bytes) {
    if (bytes == null || bytes <= 0) return '';
    if (bytes < 1024) return '$bytes o';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} Ko';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} Mo';
  }

  int _resolveCurrentSemesterNumber(SemestersState? semState) {
    if (semState == null) return 1;
    final list = semState.filteredSemesters.isNotEmpty
        ? semState.filteredSemesters
        : semState.semesters;
    final currentFlagged =
        list.where((s) => s.isCurrent).firstOrNull ?? semState.current;
    if (currentFlagged != null) return currentFlagged.number;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final byDate = list.where((s) {
      final start = DateTime(s.startDate.year, s.startDate.month, s.startDate.day);
      final end = DateTime(s.endDate.year, s.endDate.month, s.endDate.day);
      return !today.isBefore(start) && !today.isAfter(end);
    }).firstOrNull;
    if (byDate != null) return byDate.number;

    return list.isNotEmpty ? list.first.number : 1;
  }

  String _getMimeType(String extension) {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'ppt':
        return 'application/vnd.ms-powerpoint';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      default:
        return 'application/octet-stream';
    }
  }

  IconData _getDocTypeIcon(String name, String mime) {
    final lowerName = name.toLowerCase();
    final lowerMime = mime.toLowerCase();
    if (lowerName.endsWith('.pdf') || lowerMime.contains('pdf')) {
      return Icons.picture_as_pdf_rounded;
    }
    if (lowerName.endsWith('.doc') ||
        lowerName.endsWith('.docx') ||
        lowerMime.contains('word')) {
      return Icons.description_rounded;
    }
    if (lowerName.endsWith('.xls') ||
        lowerName.endsWith('.xlsx') ||
        lowerName.endsWith('.csv') ||
        lowerMime.contains('excel') ||
        lowerMime.contains('sheet')) {
      return Icons.table_chart_rounded;
    }
    if (lowerName.endsWith('.ppt') ||
        lowerName.endsWith('.pptx') ||
        lowerMime.contains('presentation')) {
      return Icons.slideshow_rounded;
    }
    return Icons.insert_drive_file_rounded;
  }

  Future<void> _pickAndUploadFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const [
          'pdf',
          'doc',
          'docx',
          'xls',
          'xlsx',
          'ppt',
          'pptx',
          'png',
          'jpg',
          'jpeg',
          'webp',
        ],
        allowMultiple: true,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final imgExts = {'png', 'jpg', 'jpeg', 'webp', 'gif'};
      int imgCount = 0;
      int docCount = 0;
      for (final f in result.files) {
        final ext = (f.extension ?? '').toLowerCase();
        if (imgExts.contains(ext)) {
          imgCount++;
        } else {
          docCount++;
        }
      }

      setState(() {
        _isUploading = true;
        _uploadingImagesSkeletonCount += imgCount;
        _uploadingDocsSkeletonCount += docCount;
        _formError = null;
      });

      final supabase = SupabaseConfig.client;
      final user = supabase.auth.currentUser;
      String schoolPrefix = 'shared';
      if (user != null) {
        try {
          final profile = await supabase
              .from('users')
              .select('school_id')
              .eq('id', user.id)
              .maybeSingle();
          final sid = profile?['school_id']?.toString();
          if (sid != null && sid.isNotEmpty) {
            schoolPrefix = sid;
          }
        } catch (_) {}
      }

      final candidateBuckets = <String>[
        'documents',
        SupabaseConfig.attachmentsBucket,
        SupabaseConfig.suggestionAttachmentsBucket,
        'suggestions',
        'profiles',
      ];

      final total = result.files.length;
      for (int i = 0; i < total; i++) {
        final file = result.files[i];
        final bytes = file.bytes;
        if (bytes == null) {
          final ext = (file.extension ?? '').toLowerCase();
          if (imgExts.contains(ext)) {
            _uploadingImagesSkeletonCount = (_uploadingImagesSkeletonCount - 1).clamp(0, 999);
          } else {
            _uploadingDocsSkeletonCount = (_uploadingDocsSkeletonCount - 1).clamp(0, 999);
          }
          continue;
        }

        final extension = (file.extension ?? 'pdf').toLowerCase();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final safeName = file.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
        final mimeType = _getMimeType(extension);

        String? uploadedUrl;
        Object? lastError;

        for (final bucket in candidateBuckets) {
          final storagePath = bucket == 'documents'
              ? 'uploads/${timestamp}_$safeName'
              : '$schoolPrefix/documents/${timestamp}_$safeName';
          try {
            await supabase.storage.from(bucket).uploadBinary(
                  storagePath,
                  bytes,
                  fileOptions: FileOptions(contentType: mimeType),
                );
            uploadedUrl = supabase.storage.from(bucket).getPublicUrl(storagePath);
            break;
          } on StorageException catch (e) {
            lastError = e;
            final msg = e.message.toLowerCase();
            final isRetryable = e.statusCode == '404' ||
                e.statusCode == '403' ||
                e.statusCode == '400' ||
                e.statusCode == '415' ||
                msg.contains('bucket') ||
                msg.contains('mime') ||
                msg.contains('policy') ||
                msg.contains('not found');
            if (!isRetryable) rethrow;
          }
        }

        if (uploadedUrl == null) {
          final ext = extension.toLowerCase();
          if (imgExts.contains(ext)) {
            _uploadingImagesSkeletonCount = (_uploadingImagesSkeletonCount - 1).clamp(0, 999);
          } else {
            _uploadingDocsSkeletonCount = (_uploadingDocsSkeletonCount - 1).clamp(0, 999);
          }
          throw lastError ??
              Exception('Aucun espace de stockage disponible pour ${file.name}.');
        }

        final isImg = imgExts.contains(extension);
        _uploadedFiles.add(_UploadedDocItem(
          fileUrl: uploadedUrl,
          fileName: file.name,
          fileSize: file.size,
          mimeType: mimeType,
          bytes: bytes,
        ));

        if (isImg) {
          _uploadingImagesSkeletonCount = (_uploadingImagesSkeletonCount - 1).clamp(0, 999);
        } else {
          _uploadingDocsSkeletonCount = (_uploadingDocsSkeletonCount - 1).clamp(0, 999);
        }

        if (_titleController.text.trim().isEmpty) {
          _titleController.text = file.name
              .replaceAll(RegExp(r'\.[^.]+$'), '')
              .replaceAll('_', ' ');
        }
      }

      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadingImagesSkeletonCount = 0;
          _uploadingDocsSkeletonCount = 0;
          _formError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadingImagesSkeletonCount = 0;
          _uploadingDocsSkeletonCount = 0;
          _formError = UserFriendlyError.format(
            e,
            fallback: 'Unable to upload file(s). Please try again.',
          );
        });
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final baseTitle = _titleController.text.trim();
    final description = _descController.text.trim();

    if (_uploadedFiles.isEmpty) {
      setState(() {
        _formError = 'Veuillez téléverser au moins un fichier avant d\'enregistrer.';
      });
      return;
    }

    if (_targetMode == 'class' &&
        (_selectedClassId == null || _selectedClassId!.isEmpty)) {
      setState(() {
        _formError = 'Veuillez sélectionner une classe destinataire.';
      });
      return;
    }

    String? targetStudentId;
    String? targetStudentName;
    String? targetStudentCode;

    if (_targetMode == 'student') {
      if (_selectedStudent != null) {
        targetStudentId = _selectedStudent!.id;
        targetStudentName = _selectedStudent!.fullName;
        targetStudentCode = _selectedStudent!.studentCode;
      } else if (!_clearedExistingStudent &&
          widget.editDoc != null &&
          widget.editDoc!.isStudentDedicated) {
        targetStudentId = widget.editDoc!.studentId;
        targetStudentName = widget.editDoc!.studentName;
        targetStudentCode = widget.editDoc!.studentCode;
      }
      if (targetStudentId == null || targetStudentId.isEmpty) {
        setState(() {
          _formError = 'Veuillez rechercher et sélectionner un étudiant.';
        });
        return;
      }
    }

    final targetSemester = isEditing
        ? widget.editDoc!.semester
        : _resolveCurrentSemesterNumber(ref.read(semestersProvider).value);

    setState(() {
      _isSaving = true;
      _formError = null;
    });

    try {
      final notifier = ref.read(documentsProvider.notifier);
      final targetClassId = _targetMode == 'class' ? _selectedClassId : null;

      if (isEditing) {
        final first = _uploadedFiles.first;
        await notifier.updateDocument(
          id: widget.editDoc!.id,
          title: baseTitle,
          description: description,
          fileUrl: first.fileUrl,
          fileName: first.fileName,
          fileSize: first.fileSize,
          mimeType: first.mimeType,
          classId: targetClassId,
          category: _selectedCategory,
          semester: targetSemester,
          studentId: targetStudentId,
          studentName: targetStudentName,
          studentCode: targetStudentCode,
        );
      } else {
        if (_uploadedFiles.length == 1) {
          final first = _uploadedFiles.first;
          await notifier.create(
            title: baseTitle,
            description: description,
            fileUrl: first.fileUrl,
            fileName: first.fileName,
            fileSize: first.fileSize,
            mimeType: first.mimeType,
            classId: targetClassId,
            category: _selectedCategory,
            semester: targetSemester,
            studentId: targetStudentId,
            studentName: targetStudentName,
            studentCode: targetStudentCode,
          );
        } else {
          final filesToInsert = <({
            String title,
            String fileUrl,
            String? fileName,
            int? fileSize,
            String? mimeType,
          })>[];

          for (int i = 0; i < _uploadedFiles.length; i++) {
            final f = _uploadedFiles[i];
            final docTitle = _uploadedFiles.length > 1
                ? '$baseTitle (${i + 1}/${_uploadedFiles.length})'
                : baseTitle;

            filesToInsert.add((
              title: docTitle,
              fileUrl: f.fileUrl,
              fileName: f.fileName,
              fileSize: f.fileSize,
              mimeType: f.mimeType,
            ));
          }

          await notifier.createMultiple(
            files: filesToInsert,
            description: description,
            classId: targetClassId,
            category: _selectedCategory,
            semester: targetSemester,
            studentId: targetStudentId,
            studentName: targetStudentName,
            studentCode: targetStudentCode,
          );
        }
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isEditing
                  ? 'Document mis à jour avec succès'
                  : (_uploadedFiles.length > 1
                      ? '${_uploadedFiles.length} documents ajoutés avec succès'
                      : 'Document ajouté avec succès'),
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _formError = UserFriendlyError.format(
            e,
            fallback: 'Unable to save document(s). Please try again.',
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final classesState = ref.watch(classesProvider);
    final List<ClassModel> classes = classesState.value?.classes ?? <ClassModel>[];
    final effectiveClassId = (_selectedClassId != null &&
            classes.any((c) => c.id == _selectedClassId))
        ? _selectedClassId
        : null;

    // Students from usersProvider
    final usersState = ref.watch(usersProvider);
    final allStudents = (usersState.value?.users ?? [])
        .where((u) => u.role == 'student')
        .toList();
    final chosenStudent = _selectedStudent ??
        (!_clearedExistingStudent && widget.editDoc?.studentId != null
            ? allStudents
                .where((u) => u.id == widget.editDoc!.studentId)
                .firstOrNull
            : null);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        width: 580,
        constraints: const BoxConstraints(maxHeight: 780),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Modal Header (matching UserFormDialog)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF6D4CF6).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.post_add_rounded,
                      color: Color(0xFF6D4CF6),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    isEditing ? 'Modifier le document' : 'Ajouter un document',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.pop(context),
                    color: AppColors.textTertiary,
                  ),
                ],
              ),
            ),

            // Modal Body Form
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Inline error notice (always visible above backdrop)
                      if (_formError != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.errorSoft,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppColors.error.withOpacity(0.25),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline_rounded,
                                size: 18,
                                color: AppColors.error,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _formError!,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.error,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.close_rounded,
                                  size: 16,
                                  color: AppColors.error,
                                ),
                                onPressed: () =>
                                    setState(() => _formError = null),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 24,
                                  minHeight: 24,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Titre du document
                      _buildFieldLabel('TITRE DU DOCUMENT *'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _titleController,
                        style: const TextStyle(fontSize: 14),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Le titre est obligatoire'
                            : null,
                        decoration: _inputDecoration(
                          'Ex: Attestation de scolarité 2026/2027',
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Type de document
                      _buildFieldLabel('TYPE DE DOCUMENT'),
                      const SizedBox(height: 8),
                      _buildStyledDropdown<String>(
                        value: AcademicDocumentType.types
                                .containsKey(_selectedCategory)
                            ? _selectedCategory
                            : 'administrative',
                        items: AcademicDocumentType.types.entries
                            .map((e) => DropdownMenuItem(
                                  value: e.key,
                                  child: Text(e.value),
                                ))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedCategory = val);
                          }
                        },
                      ),
                      const SizedBox(height: 18),

                      // Destinataire du document (Semestre auto-assigné au semestre courant)
                      _buildFieldLabel('DESTINATAIRE DU DOCUMENT'),
                      const SizedBox(height: 8),
                      _buildStyledDropdown<String>(
                        value: _targetMode,
                        items: const [
                          DropdownMenuItem(
                            value: 'all',
                            child: Text('Général (Toutes les classes)'),
                          ),
                          DropdownMenuItem(
                            value: 'class',
                            child: Text('Une classe spécifique'),
                          ),
                          DropdownMenuItem(
                            value: 'student',
                            child: Text('Un étudiant spécifique'),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _targetMode = val;
                              _formError = null;
                              if (val != 'class') _selectedClassId = null;
                              if (val != 'student') _selectedStudent = null;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 18),

                      // When target is Class: show class dropdown
                      if (_targetMode == 'class') ...[
                        _buildFieldLabel('CHOISIR LA CLASSE'),
                        const SizedBox(height: 8),
                        _buildStyledDropdown<String?>(
                          value: effectiveClassId,
                          items: [
                            const DropdownMenuItem(
                              value: null,
                              child: Text('Sélectionner une classe'),
                            ),
                            ...classes.map((c) => DropdownMenuItem(
                                  value: c.id,
                                  child: Text(c.name),
                                )),
                          ],
                          onChanged: (val) => setState(() {
                            _selectedClassId = val;
                            _formError = null;
                          }),
                        ),
                        const SizedBox(height: 18),
                      ],

                      // When target is Single Student: Search & Select Student by Name / Code / Email
                      if (_targetMode == 'student') ...[
                        _buildFieldLabel('RECHERCHER L\'ÉTUDIANT (NOM, MATRICULE OU EMAIL)'),
                        const SizedBox(height: 8),
                        if (chosenStudent != null ||
                            (!_clearedExistingStudent &&
                                widget.editDoc != null &&
                                widget.editDoc!.isStudentDedicated)) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5F3FF),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFF6D4CF6).withOpacity(0.3)),
                            ),
                            child: Row(
                              children: [
                                UserAvatar(
                                  name: chosenStudent?.fullName ??
                                      widget.editDoc?.studentName ??
                                      'Étudiant',
                                  photoUrl: chosenStudent?.photoUrl,
                                  gender: chosenStudent?.gender,
                                  radius: 17,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        chosenStudent?.fullName ??
                                            widget.editDoc?.studentName ??
                                            'Étudiant',
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                                      ),
                                      if ((chosenStudent?.studentCode ??
                                              widget.editDoc?.studentCode ??
                                              chosenStudent?.email ??
                                              '')
                                          .isNotEmpty)
                                        Text(
                                          chosenStudent?.studentCode ??
                                              widget.editDoc?.studentCode ??
                                              chosenStudent?.email ??
                                              '',
                                          style: const TextStyle(fontSize: 11, color: AppColors.textTertiary),
                                        ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textTertiary),
                                  onPressed: () {
                                    setState(() {
                                      _selectedStudent = null;
                                      _clearedExistingStudent = true;
                                      _studentSearchController.clear();
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                        ] else ...[
                          TextFormField(
                            controller: _studentSearchController,
                            style: const TextStyle(fontSize: 14),
                            onChanged: (_) => setState(() {}),
                            decoration: _inputDecoration('Taper pour rechercher un étudiant...').copyWith(
                              prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF94A3B8)),
                            ),
                          ),
                          if (_studentSearchController.text.trim().isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Container(
                              constraints: const BoxConstraints(maxHeight: 180),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppColors.borderLight),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.04),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: ListView(
                                shrinkWrap: true,
                                children: allStudents.where((u) {
                                  final q = _studentSearchController.text.trim().toLowerCase();
                                  return u.fullName.toLowerCase().contains(q) ||
                                      u.email.toLowerCase().contains(q) ||
                                      (u.studentCode?.toLowerCase().contains(q) ?? false);
                                }).take(6).map((student) {
                                  return ListTile(
                                    dense: true,
                                    leading: UserAvatar(
                                      name: student.fullName,
                                      photoUrl: student.photoUrl,
                                      gender: student.gender,
                                      radius: 14,
                                    ),
                                    title: Text(student.fullName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                    subtitle: Text(
                                      '${student.studentCode ?? student.email} • ${student.className ?? ''}',
                                      style: const TextStyle(fontSize: 11, color: AppColors.textTertiary),
                                    ),
                                    onTap: () {
                                      setState(() {
                                        _selectedStudent = student;
                                        _clearedExistingStudent = false;
                                        _formError = null;
                                        _studentSearchController.clear();
                                      });
                                    },
                                  );
                                }).toList(),
                              ),
                            ),
                          ],
                          const SizedBox(height: 18),
                        ],
                      ],

                      // Fichiers du document (Sélection multiple, prévisualisation carrée 100x100 pour photos, cartes documents, aucun bouton remplacer)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildFieldLabel('FICHIER(S) DU DOCUMENT *'),
                          if (_uploadedFiles.isNotEmpty)
                            Text(
                              '${_uploadedFiles.length} fichier${_uploadedFiles.length > 1 ? "s" : ""}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF6D4CF6),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      if (_uploadedFiles.isEmpty && !_isUploading && _uploadingImagesSkeletonCount == 0 && _uploadingDocsSkeletonCount == 0)
                        InkWell(
                          onTap: _pickAndUploadFiles,
                          mouseCursor: SystemMouseCursors.click,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              vertical: 24,
                              horizontal: 16,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.slate50.withOpacity(0.7),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppColors.slate300,
                                width: 1.5,
                              ),
                            ),
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF6D4CF6).withOpacity(0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.cloud_upload_outlined,
                                    size: 24,
                                    color: Color(0xFF6D4CF6),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                const Text(
                                  'Cliquez pour ajouter des fichiers',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF6D4CF6),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'PDF, DOC, DOCX, XLS, XLSX, PPT, PNG, JPG (Multi-sélection possible)',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textTertiary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Images section (square 100x100 preview + skeletons)
                            Builder(
                              builder: (context) {
                                final images = _uploadedFiles.where((f) => f.isImage).toList();
                                if (images.isEmpty && _uploadingImagesSkeletonCount == 0) return const SizedBox.shrink();

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Images & Photos',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 10,
                                      runSpacing: 10,
                                      children: [
                                        ...images.map((item) {
                                          return Stack(
                                            children: [
                                              ClipRRect(
                                                borderRadius: BorderRadius.circular(8),
                                                child: item.bytes != null
                                                    ? Image.memory(
                                                        item.bytes!,
                                                        width: 100,
                                                        height: 100,
                                                        fit: BoxFit.cover,
                                                      )
                                                    : Image.network(
                                                        item.fileUrl,
                                                        width: 100,
                                                        height: 100,
                                                        fit: BoxFit.cover,
                                                        errorBuilder: (context, error, stackTrace) => Container(
                                                          width: 100,
                                                          height: 100,
                                                          color: AppColors.slate100,
                                                          child: const Icon(
                                                            Icons.image_outlined,
                                                            color: Color(0xFF6D4CF6),
                                                            size: 32,
                                                          ),
                                                        ),
                                                      ),
                                              ),
                                              Positioned(
                                                top: 4,
                                                right: 4,
                                                child: MouseRegion(
                                                  cursor: SystemMouseCursors.click,
                                                  child: GestureDetector(
                                                    onTap: _isUploading
                                                        ? null
                                                        : () => setState(() {
                                                              _uploadedFiles.remove(item);
                                                              _formError = null;
                                                            }),
                                                    child: Container(
                                                      padding: const EdgeInsets.all(4),
                                                      decoration: const BoxDecoration(
                                                        color: AppColors.error,
                                                        shape: BoxShape.circle,
                                                      ),
                                                      child: const Icon(
                                                        Icons.close,
                                                        size: 14,
                                                        color: AppColors.surface,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          );
                                        }),
                                        ...List.generate(
                                          _uploadingImagesSkeletonCount,
                                          (_) => const _SkeletonBox(
                                            width: 100,
                                            height: 100,
                                            borderRadius: 8,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                );
                              },
                            ),

                            // Documents section (non-images + skeletons)
                            Builder(
                              builder: (context) {
                                final docs = _uploadedFiles.where((f) => !f.isImage).toList();
                                if (docs.isEmpty && _uploadingDocsSkeletonCount == 0) return const SizedBox.shrink();

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Documents & Fichiers',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    ...docs.map((item) {
                                      return Container(
                                        margin: const EdgeInsets.only(bottom: 8),
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                        decoration: BoxDecoration(
                                          color: AppColors.slate50,
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: AppColors.border),
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 38,
                                              height: 38,
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF6D4CF6).withOpacity(0.1),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Icon(
                                                _getDocTypeIcon(item.fileName, item.mimeType),
                                                color: const Color(0xFF6D4CF6),
                                                size: 20,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    item.fileName,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.w600,
                                                      color: AppColors.textPrimary,
                                                    ),
                                                  ),
                                                  if (_formatBytes(item.fileSize).isNotEmpty) ...[
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      _formatBytes(item.fileSize),
                                                      style: const TextStyle(
                                                        fontSize: 11,
                                                        color: AppColors.textTertiary,
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            MouseRegion(
                                              cursor: SystemMouseCursors.click,
                                              child: IconButton(
                                                icon: const Icon(
                                                  Icons.close_rounded,
                                                  size: 18,
                                                  color: AppColors.error,
                                                ),
                                                tooltip: 'Supprimer ce fichier',
                                                onPressed: _isUploading
                                                    ? null
                                                    : () => setState(() {
                                                          _uploadedFiles.remove(item);
                                                          _formError = null;
                                                        }),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }),
                                    ...List.generate(
                                      _uploadingDocsSkeletonCount,
                                      (_) => const _SkeletonDocCard(),
                                    ),
                                  ],
                                );
                              },
                            ),

                            // "Ajouter d'autres fichiers" button (borderless!)
                            const SizedBox(height: 4),
                            MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: InkWell(
                                onTap: _isUploading ? null : _pickAndUploadFiles,
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    color: const Color(0xFF6D4CF6).withOpacity(0.06),
                                  ),
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.add_circle_outline_rounded,
                                        size: 16,
                                        color: Color(0xFF6D4CF6),
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'Ajouter d\'autres fichiers (images, pdf, documents...)',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF6D4CF6),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 18),

                      // Description
                      _buildFieldLabel('DESCRIPTION (OPTIONNEL)'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _descController,
                        maxLines: 3,
                        style: const TextStyle(fontSize: 14),
                        decoration: _inputDecoration('Précisions supplémentaires sur le document...'),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Modal Footer Buttons (matching UserFormDialog exactly!)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              decoration: const BoxDecoration(
                color: Color(0xFFFAFAFB),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SizedBox(
                    height: 40,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF6B7280),
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        enabledMouseCursor: SystemMouseCursors.click,
                      ),
                      child: const Text(
                        'Annuler',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 40,
                    child: ElevatedButton.icon(
                      onPressed: (_isSaving || _isUploading) ? null : _submit,
                      icon: _isSaving
                          ? const IosLoader.small(color: Colors.white)
                          : const Icon(Icons.check_rounded, size: 16),
                      label: Text(
                        isEditing
                            ? 'Enregistrer'
                            : (_uploadedFiles.length > 1
                                ? 'Ajouter les ${_uploadedFiles.length} documents'
                                : 'Ajouter le document'),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6D4CF6),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 2,
                        enabledMouseCursor: SystemMouseCursors.click,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: AppColors.textSecondary,
        letterSpacing: 0.5,
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
      filled: true,
      fillColor: AppColors.slate50,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.borderLight),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.borderLight),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF6D4CF6), width: 1.5),
      ),
    );
  }

  Widget _buildStyledDropdown<T>({
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.slate50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButtonFormField<T>(
          value: value,
          items: items,
          onChanged: onChanged,
          style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
          decoration: const InputDecoration(
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
          dropdownColor: Colors.white,
          isExpanded: true,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}

class _SkeletonBox extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;
  const _SkeletonBox({
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  State<_SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<_SkeletonBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.35, end: 0.85).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: AppColors.slate200.withOpacity(_animation.value),
            borderRadius: BorderRadius.circular(widget.borderRadius),
          ),
        );
      },
    );
  }
}

class _SkeletonDocCard extends StatefulWidget {
  const _SkeletonDocCard();

  @override
  State<_SkeletonDocCard> createState() => _SkeletonDocCardState();
}

class _SkeletonDocCardState extends State<_SkeletonDocCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.35, end: 0.85).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.slate50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.slate200.withOpacity(_animation.value),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 140,
                      height: 14,
                      decoration: BoxDecoration(
                        color: AppColors.slate200.withOpacity(_animation.value),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 60,
                      height: 10,
                      decoration: BoxDecoration(
                        color: AppColors.slate200.withOpacity(_animation.value),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
