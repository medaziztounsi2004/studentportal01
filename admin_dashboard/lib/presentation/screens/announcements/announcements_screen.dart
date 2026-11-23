// ignore_for_file: deprecated_member_use, unused_element, unnecessary_underscores, avoid_web_libraries_in_flutter, unused_local_variable, unused_field, unnecessary_non_null_assertion, prefer_final_fields, unused_element_parameter
import 'dart:async';
import 'dart:ui';
import 'dart:html' as html;
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/error_messages.dart';
import '../../providers/announcements_provider.dart';
import '../../providers/building_provider.dart';
import '../../providers/subjects_management_provider.dart';
import '../../../data/models/building_models.dart';
import '../../widgets/admin_sidebar.dart';
import '../../widgets/admin_sort_dropdown.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/ios_loader.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/modern_animated_switch.dart';
import '../../widgets/undo_redo_toolbar_buttons.dart';
import '../../providers/undo_redo_provider.dart';
import '../../widgets/feedback_pill.dart';

/// Text formatter that capitalizes the first letter of each word
class CapitalizeWordsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;

    final String formatted = _capitalizeWords(newValue.text);

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  String _capitalizeWords(String text) {
    if (text.isEmpty) return text;

    final parts = <String>[];
    final buffer = StringBuffer();

    for (int i = 0; i < text.length; i++) {
      final char = text[i];

      if (char == ' ' || char == '-') {
        if (buffer.isNotEmpty) {
          parts.add(_capitalizeWord(buffer.toString()));
          buffer.clear();
        }
        parts.add(char);
      } else {
        buffer.write(char);
      }
    }

    if (buffer.isNotEmpty) {
      parts.add(_capitalizeWord(buffer.toString()));
    }

    return parts.join();
  }

  String _capitalizeWord(String word) {
    if (word.isEmpty) return word;
    return word[0].toUpperCase() + word.substring(1).toLowerCase();
  }
}

/// Normalize string for smart search (remove accents, lowercase)
String _normalizeForSearch(String text) {
  const accents = 'àáâãäåçèéêëìíîïñòóôõöùúûüýÿÀÁÂÃÄÅÇÈÉÊËÌÍÎÏÑÒÓÔÕÖÙÚÛÜÝŸ';
  const normalized = 'aaaaaaceeeeiiiinooooouuuuyyAAAAAAÇEEEEIIIINOOOOOUUUUYY';
  var result = text.toLowerCase();
  for (var i = 0; i < accents.length; i++) {
    result = result.replaceAll(accents[i], normalized[i].toLowerCase());
  }
  return result;
}

/// Get all searchable fields for an announcement (including formatted dates)
String _getSearchableFields(AnnouncementModel a) {
  final dateFormatter = DateFormat('dd/MM/yyyy HH:mm');
  final timeFormatter = DateFormat('HH:mm');

  // Type labels mapping
  String typeLabel;
  switch (a.announcementType) {
    case 'teacher_absent':
      typeLabel = 'absence prof enseignant';
      break;
    case 'room_change':
      typeLabel = 'changement salle';
      break;
    case 'reminder':
      typeLabel = 'rappel';
      break;
    case 'exam':
      typeLabel = 'examen controle test';
      break;
    case 'retenue':
      typeLabel = 'retenue detention punition sanction';
      break;
    case 'avertissement':
      typeLabel = 'avertissement warning sanction';
      break;
    case 'exclusion_classe':
      typeLabel = 'exclusion classe temporaire sanction';
      break;
    case 'exclusion_etablissement':
      typeLabel = 'exclusion établissement temporaire renvoi sanction';
      break;
    case 'convocation_parents':
      typeLabel = 'convocation parents famille sanction';
      break;
    case 'conseil_discipline':
      typeLabel = 'conseil discipline sanction conseil';
      break;
    case 'exclusion_definitive':
      typeLabel = 'exclusion définitive expulsion renvoi définitif sanction';
      break;
    case 'closure':
      typeLabel = 'fermeture fermé';
      break;
    case 'trip':
      typeLabel = 'sortie voyage excursion visite';
      break;
    case 'party':
      typeLabel = 'fête événement celebration soirée';
      break;
    case 'payment':
      typeLabel = 'paiement frais cotisation';
      break;
    default:
      typeLabel = 'général general';
  }

  // Scope labels
  final scopeLabel = a.scope == 'global'
      ? 'note info global publique'
      : a.scope == 'student'
      ? 'message élève étudiant individuel sanction'
      : 'message classe';

  // Build all searchable text
  final fields = [
    a.title,
    a.content,
    a.senderLabel ?? '',
    a.className ?? '',
    typeLabel,
    scopeLabel,
    dateFormatter.format(a.createdAt),
    timeFormatter.format(a.createdAt),
    a.isPinned ? 'épinglé pinned' : '',
    a.isImportant ? 'important urgent' : '',
    a.hasAttachment ? 'pièce jointe fichier attachment' : '',
  ];

  // Add payload fields if available
  a.payload.forEach((key, value) {
    if (value != null) fields.add(value.toString());
  });

  return fields.join(' ');
}

/// Smart search: token matching, accent-insensitive, multi-field
bool _smartMatch(AnnouncementModel a, String query) {
  if (query.isEmpty) return true;
  final tokens = _normalizeForSearch(query).split(RegExp(r'\s+'));
  final searchFields = _normalizeForSearch(_getSearchableFields(a));
  return tokens.every((token) => searchFields.contains(token));
}

/// Highlight matching text in a string
Widget _highlightText(String text, String query, TextStyle? baseStyle) {
  if (query.isEmpty) {
    return Text(
      text,
      style: baseStyle,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  final normalizedText = _normalizeForSearch(text);
  final normalizedQuery = _normalizeForSearch(query);
  final tokens = normalizedQuery
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .toList();

  if (tokens.isEmpty) {
    return Text(
      text,
      style: baseStyle,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  // Find all match positions
  List<_MatchRange> matches = [];
  for (final token in tokens) {
    int start = 0;
    while (true) {
      final index = normalizedText.indexOf(token, start);
      if (index == -1) break;
      matches.add(_MatchRange(index, index + token.length));
      start = index + 1;
    }
  }

  if (matches.isEmpty) {
    return Text(
      text,
      style: baseStyle,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  // Sort and merge overlapping ranges
  matches.sort((a, b) => a.start.compareTo(b.start));
  List<_MatchRange> merged = [];
  for (final m in matches) {
    if (merged.isEmpty || merged.last.end < m.start) {
      merged.add(m);
    } else {
      merged.last = _MatchRange(
        merged.last.start,
        m.end > merged.last.end ? m.end : merged.last.end,
      );
    }
  }

  // Build text spans
  List<TextSpan> spans = [];
  int lastEnd = 0;
  for (final m in merged) {
    if (m.start > lastEnd) {
      spans.add(
        TextSpan(text: text.substring(lastEnd, m.start), style: baseStyle),
      );
    }
    spans.add(
      TextSpan(
        text: text.substring(m.start, m.end),
        style:
            baseStyle?.copyWith(
              backgroundColor: AppColors.warningSoft,
              fontWeight: FontWeight.bold,
            ) ??
            TextStyle(
              backgroundColor: AppColors.warningSoft,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
    lastEnd = m.end;
  }
  if (lastEnd < text.length) {
    spans.add(TextSpan(text: text.substring(lastEnd), style: baseStyle));
  }

  return RichText(
    text: TextSpan(children: spans),
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
  );
}

class _MatchRange {
  int start;
  int end;
  _MatchRange(this.start, this.end);
}

class AnnouncementsScreen extends ConsumerStatefulWidget {
  final String? initialScope;
  final String? preSelectedStudentId;

  const AnnouncementsScreen({
    super.key,
    this.initialScope,
    this.preSelectedStudentId,
  });

  @override
  ConsumerState<AnnouncementsScreen> createState() =>
      _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends ConsumerState<AnnouncementsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _debounce;
  String _sortKey = 'pinned_first';

  // Filter state
  String? _filterType; // null = all types
  DateTime? _filterDateFrom;
  DateTime? _filterDateTo;
  bool _showFilters = false;

  // Academic hierarchy filters
  String? _filterNiveauId;
  String? _filterSectionId;
  String? _filterClassId;

  List<Map<String, dynamic>> _filterNiveaux = [];
  List<Map<String, dynamic>> _filterSections = [];
  List<Map<String, dynamic>> _filterNiveauSections = [];
  List<Map<String, dynamic>> _filterClasses = [];
  final Map<String, Map<String, dynamic>> _classById = {};
  final Map<String, Map<String, dynamic>> _classByName = {};
  final Map<String, Set<String>> _studentClassIds = {};

  List<Map<String, dynamic>> get _availableFilterSections {
    if (_filterNiveauId == null) {
      return _filterSections;
    }
    final mappedSectionIds = _filterNiveauSections
        .where((ns) => ns['niveau_id']?.toString() == _filterNiveauId)
        .map((ns) => ns['section_id']?.toString())
        .whereType<String>()
        .toSet();

    for (final c in _filterClasses) {
      if (c['niveau_id']?.toString() == _filterNiveauId && c['section_id'] != null) {
        mappedSectionIds.add(c['section_id'].toString());
      }
    }

    return _filterSections
        .where((s) => mappedSectionIds.contains(s['id']?.toString()))
        .toList();
  }

  List<Map<String, dynamic>> get _availableFilterClasses {
    return _filterClasses.where((c) {
      if (_filterNiveauId != null && c['niveau_id']?.toString() != _filterNiveauId) {
        return false;
      }
      if (_filterSectionId != null && c['section_id']?.toString() != _filterSectionId) {
        return false;
      }
      return true;
    }).toList();
  }

  Set<String> _getAnnouncementClassIds(AnnouncementModel a) {
    final classIds = <String>{};

    if (a.targetClassId != null && a.targetClassId!.isNotEmpty) {
      classIds.add(a.targetClassId!);
    }
    if (a.payload['class_id'] != null) {
      classIds.add(a.payload['class_id'].toString());
    }
    if (a.payload['target_class_id'] != null) {
      classIds.add(a.payload['target_class_id'].toString());
    }
    if (a.payload['target_classes'] is List) {
      for (final item in a.payload['target_classes']) {
        if (item != null) {
          final str = item.toString();
          if (_classById.containsKey(str)) {
            classIds.add(str);
          } else if (_classByName.containsKey(str.toLowerCase().trim())) {
            classIds.add(_classByName[str.toLowerCase().trim()]!['id'].toString());
          }
        }
      }
    }
    if (a.payload['classes'] is List) {
      for (final item in a.payload['classes']) {
        if (item != null) {
          final str = item.toString();
          if (_classById.containsKey(str)) {
            classIds.add(str);
          } else if (_classByName.containsKey(str.toLowerCase().trim())) {
            classIds.add(_classByName[str.toLowerCase().trim()]!['id'].toString());
          }
        }
      }
    }
    if (a.className != null && a.className!.isNotEmpty) {
      final lower = a.className!.toLowerCase().trim();
      if (_classByName.containsKey(lower)) {
        classIds.add(_classByName[lower]!['id'].toString());
      }
    }

    final sId = a.targetStudentId;
    if (sId != null && _studentClassIds.containsKey(sId)) {
      classIds.addAll(_studentClassIds[sId]!);
    }

    return classIds;
  }

  bool _matchesAcademicFilters(AnnouncementModel a) {
    if (_filterNiveauId == null && _filterSectionId == null && _filterClassId == null) {
      return true;
    }

    final classIds = _getAnnouncementClassIds(a);

    // 1. Classe filter
    if (_filterClassId != null) {
      return classIds.contains(_filterClassId);
    }

    // 2. Filière (section) filter
    if (_filterSectionId != null) {
      if (a.payload['section_id']?.toString() == _filterSectionId ||
          a.payload['target_section_id']?.toString() == _filterSectionId) {
        if (_filterNiveauId == null) return true;
        if (a.payload['niveau_id']?.toString() == _filterNiveauId ||
            a.payload['target_niveau_id']?.toString() == _filterNiveauId) {
          return true;
        }
      }
      for (final cid in classIds) {
        final c = _classById[cid];
        if (c != null && c['section_id']?.toString() == _filterSectionId) {
          if (_filterNiveauId == null || c['niveau_id']?.toString() == _filterNiveauId) {
            return true;
          }
        }
      }
      return false;
    }

    // 3. Niveau filter
    if (_filterNiveauId != null) {
      if (a.payload['niveau_id']?.toString() == _filterNiveauId ||
          a.payload['target_niveau_id']?.toString() == _filterNiveauId) {
        return true;
      }
      for (final cid in classIds) {
        final c = _classById[cid];
        if (c != null && c['niveau_id']?.toString() == _filterNiveauId) {
          return true;
        }
      }
      return false;
    }

    return true;
  }

  // Multi-select state
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

  // Pagination
  int _currentPage = 0;
  int _pageSize = 10;

  // Filter status
  String _filterStatus = 'all'; // 'all', 'pinned', 'important'

  final Map<String, Map<String, dynamic>> _studentLookupByName = {};
  final Map<String, Map<String, dynamic>> _studentLookupById = {};

  Future<void> _loadStudentLookup() async {
    try {
      final res = await Supabase.instance.client
          .from('users')
          .select('id, full_name, phone, student_code, photo_url, gender')
          .eq('role', 'student');
      for (final s in res) {
        final id = s['id']?.toString();
        final name = (s['full_name']?.toString() ?? '').toLowerCase().trim();
        if (id != null) _studentLookupById[id] = s;
        if (name.isNotEmpty) _studentLookupByName[name] = s;
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _loadFilterMetadata() async {
    final supabase = Supabase.instance.client;
    try {
      final futures = await Future.wait([
        supabase.from('niveaux').select('id, name, code, cycle, display_order').order('display_order').catchError((_) => []),
        supabase.from('sections').select('id, name, code').order('name').catchError((_) => []),
        supabase.from('niveau_sections').select('niveau_id, section_id').catchError((_) => []),
        supabase.from('classes').select('id, name, niveau_id, section_id').order('name').catchError((_) => []),
        supabase.from('enrollments').select('user_id, class_id').catchError((_) => []),
      ]);

      if (!mounted) return;

      final niveaux = List<Map<String, dynamic>>.from(futures[0] as List);
      final sections = List<Map<String, dynamic>>.from(futures[1] as List);
      final niveauSections = List<Map<String, dynamic>>.from(futures[2] as List);
      final classes = List<Map<String, dynamic>>.from(futures[3] as List);
      final enrollments = List<Map<String, dynamic>>.from(futures[4] as List);

      _classById.clear();
      _classByName.clear();
      for (final c in classes) {
        final id = c['id']?.toString();
        final name = c['name']?.toString().toLowerCase().trim();
        if (id != null) _classById[id] = c;
        if (name != null && name.isNotEmpty) _classByName[name] = c;
      }

      _studentClassIds.clear();
      for (final e in enrollments) {
        final uid = e['user_id']?.toString();
        final cid = e['class_id']?.toString();
        if (uid != null && cid != null) {
          _studentClassIds.putIfAbsent(uid, () => {}).add(cid);
        }
      }

      setState(() {
        _filterNiveaux = niveaux;
        _filterSections = sections;
        _filterNiveauSections = niveauSections;
        _filterClasses = classes;
      });
    } catch (e) {
      debugPrint('Error loading filter metadata: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _loadStudentLookup();
    _loadFilterMetadata();
    _tabController = TabController(length: 4, vsync: this);

    // Handle navigation with pre-selected student
    if (widget.initialScope != null || widget.preSelectedStudentId != null) {
      debugPrint(
        'AnnouncementsScreen: Received navigation params - scope: ${widget.initialScope}, studentId: ${widget.preSelectedStudentId}',
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        debugPrint('AnnouncementsScreen: Opening dialog with params');
        _openCreateDialog(
          initialScope: widget.initialScope,
          preSelectedStudentId: widget.preSelectedStudentId,
        );
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      setState(() => _searchQuery = value);
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _selectionMode = false;
      } else {
        _selectedIds.add(id);
        _selectionMode = true;
      }
    });
  }

  void _selectAll(List<AnnouncementModel> list) {
    setState(() {
      if (_selectedIds.length == list.length) {
        _selectedIds.clear();
        _selectionMode = false;
      } else {
        _selectedIds.addAll(list.map((a) => a.id));
        _selectionMode = true;
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  Future<void> _handleUndo() async {
    final notifier = ref.read(undoRedoProvider.notifier);
    if (!ref.read(undoRedoProvider).canUndo('announcements')) return;
    try {
      final desc = await notifier.undo('announcements');
      if (mounted && desc != null) {
        FeedbackPill.showUndo(context, message: 'Action annulée : $desc');
      }
    } catch (e) {
      if (mounted) FeedbackPill.showError(context, 'Impossible d\'annuler : $e');
    }
  }

  Future<void> _handleRedo() async {
    final notifier = ref.read(undoRedoProvider.notifier);
    if (!ref.read(undoRedoProvider).canRedo('announcements')) return;
    try {
      final desc = await notifier.redo('announcements');
      if (mounted && desc != null) {
        FeedbackPill.showSuccess(context, 'Action rétablie : $desc');
      }
    } catch (e) {
      if (mounted) FeedbackPill.showError(context, 'Impossible de rétablir : $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final announcementsAsync = ref.watch(announcementsProvider);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () => _handleUndo(),
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): () => _handleUndo(),
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): () => _handleRedo(),
        const SingleActivator(LogicalKeyboardKey.keyY, meta: true): () => _handleRedo(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Row(
            children: [
              const AdminSidebar(currentRoute: '/announcements'),
              Expanded(
                child: Column(
                  children: [
                    _buildHeader(announcementsAsync),
                    _buildTabBar(announcementsAsync),
                    Expanded(
                      child: announcementsAsync.when(
                        loading: () => const AnnouncementsSkeletonLoader(),
                        error: (e, _) => Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.error_outline,
                                  size: 48, color: AppColors.error),
                              const SizedBox(height: 16),
                              Text(
                                UserFriendlyError.format(
                                  e,
                                  fallback: 'Unable to load announcements right now. Please try again.',
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: () => ref
                                    .read(announcementsProvider.notifier)
                                    .refresh(),
                                child: const Text('Réessayer'),
                              ),
                            ],
                          ),
                        ),
                        data: (state) => _buildTabContent(context, state),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_showFilters) _buildFilterPanel(),
          if (_selectedIds.isNotEmpty)
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Center(
                child: _buildFloatingSelectionBar(context, announcementsAsync),
              ),
            ),
        ],
      ),
    ),
    ),
    );
  }

  Widget _buildFilterPanel() {
    return Positioned.fill(
      child: GestureDetector(
        onTap: () => setState(() => _showFilters = false),
        child: Stack(
          children: [
            // Full-app purple backdrop
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(color: Colors.black.withOpacity(0.30)),
            ),
            // Panel from right
            Positioned(
              top: 0,
              bottom: 0,
              right: 0,
              child: GestureDetector(
                onTap: () {},
                child: Container(
                  width: 360,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.12),
                        blurRadius: 24,
                        offset: const Offset(-4, 0),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Header
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 20),
                        decoration: const BoxDecoration(
                          border: Border(
                              bottom: BorderSide(
                                  color: AppColors.border)),
                        ),
                        child: Row(
                          children: [
                            const Text('Filtres',
                                style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary)),
                            const Spacer(),
                            InkWell(
                              onTap: () => setState(
                                  () => _showFilters = false),
                              borderRadius:
                                  BorderRadius.circular(8),
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(Icons.close,
                                    size: 22,
                                    color:
                                        AppColors.textSecondary),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Content
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              // Niveau
                              const Text('NIVEAU',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.0,
                                      color: AppColors.slate400)),
                              const SizedBox(height: 12),
                              _buildStyledDropdown<String?>(
                                value: _filterNiveaux.any((n) => n['id']?.toString() == _filterNiveauId) ? _filterNiveauId : null,
                                defaultValue: null,
                                items: [
                                  const DropdownMenuItem(value: null, child: Text('Tous les niveaux')),
                                  ..._filterNiveaux.map((n) => DropdownMenuItem(
                                    value: n['id']?.toString(),
                                    child: Text(n['name']?.toString() ?? n['code']?.toString() ?? 'Niveau'),
                                  )),
                                ],
                                onChanged: (v) => setState(() {
                                  _filterNiveauId = v;
                                  if (_filterSectionId != null &&
                                      !_availableFilterSections.any((s) => s['id']?.toString() == _filterSectionId)) {
                                    _filterSectionId = null;
                                  }
                                  if (_filterClassId != null &&
                                      !_availableFilterClasses.any((c) => c['id']?.toString() == _filterClassId)) {
                                    _filterClassId = null;
                                  }
                                  _currentPage = 0;
                                }),
                              ),
                              const SizedBox(height: 28),

                              // Filière
                              const Text('FILIÈRE',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.0,
                                      color: AppColors.slate400)),
                              const SizedBox(height: 12),
                              _buildStyledDropdown<String?>(
                                value: _availableFilterSections.any((s) => s['id']?.toString() == _filterSectionId) ? _filterSectionId : null,
                                defaultValue: null,
                                items: [
                                  const DropdownMenuItem(value: null, child: Text('Toutes les filières')),
                                  ..._availableFilterSections.map((s) => DropdownMenuItem(
                                    value: s['id']?.toString(),
                                    child: Text(s['name']?.toString() ?? s['code']?.toString() ?? 'Filière'),
                                  )),
                                ],
                                onChanged: (v) => setState(() {
                                  _filterSectionId = v;
                                  if (_filterClassId != null &&
                                      !_availableFilterClasses.any((c) => c['id']?.toString() == _filterClassId)) {
                                    _filterClassId = null;
                                  }
                                  _currentPage = 0;
                                }),
                              ),
                              const SizedBox(height: 28),

                              // Classe
                              const Text('CLASSE',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.0,
                                      color: AppColors.slate400)),
                              const SizedBox(height: 12),
                              _buildStyledDropdown<String?>(
                                value: _availableFilterClasses.any((c) => c['id']?.toString() == _filterClassId) ? _filterClassId : null,
                                defaultValue: null,
                                items: [
                                  const DropdownMenuItem(value: null, child: Text('Toutes les classes')),
                                  ..._availableFilterClasses.map((c) => DropdownMenuItem(
                                    value: c['id']?.toString(),
                                    child: Text(c['name']?.toString() ?? 'Classe'),
                                  )),
                                ],
                                onChanged: (v) => setState(() {
                                  _filterClassId = v;
                                  _currentPage = 0;
                                }),
                              ),
                              const SizedBox(height: 28),

                              // Type
                              const Text('TYPE D\'ANNONCE',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.0,
                                      color: AppColors.slate400)),
                              const SizedBox(height: 12),
                              _buildStyledDropdown<String?>(
                                value: _filterType,
                                defaultValue: null,
                                items: const [
                                  DropdownMenuItem(value: null, child: Text('Tous les types')),
                                  DropdownMenuItem(value: 'general', child: Text('Général')),
                                  DropdownMenuItem(value: 'teacher_absent', child: Text('Absence prof')),
                                  DropdownMenuItem(value: 'room_change', child: Text('Changement salle')),
                                  DropdownMenuItem(value: 'exam', child: Text('Examen')),
                                  DropdownMenuItem(value: 'reminder', child: Text('Rappel')),
                                  DropdownMenuItem(value: 'retenue', child: Text('Retenue')),
                                  DropdownMenuItem(value: 'avertissement', child: Text('Avertissement')),
                                  DropdownMenuItem(value: 'exclusion_classe', child: Text('Exclusion classe')),
                                  DropdownMenuItem(value: 'exclusion_etablissement', child: Text('Exclusion établissement')),
                                  DropdownMenuItem(value: 'convocation_parents', child: Text('Convocation parents')),
                                  DropdownMenuItem(value: 'conseil_discipline', child: Text('Conseil discipline')),
                                  DropdownMenuItem(value: 'exclusion_definitive', child: Text('Exclusion définitive')),
                                  DropdownMenuItem(value: 'closure', child: Text('Fermeture')),
                                  DropdownMenuItem(value: 'trip', child: Text('Sortie/Voyage')),
                                  DropdownMenuItem(value: 'party', child: Text('Événement')),
                                  DropdownMenuItem(value: 'payment', child: Text('Paiement')),
                                ],
                                onChanged: (v) => setState(() {
                                  _filterType = v;
                                  _currentPage = 0;
                                }),
                              ),
                              const SizedBox(height: 28),
                              // Date range
                              const Text('PÉRIODE (DATE)',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.0,
                                      color: AppColors.slate400)),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text('DU',
                                            style: TextStyle(
                                                fontSize: 10,
                                                fontWeight:
                                                    FontWeight.w700,
                                                color: AppColors
                                                    .slate500)),
                                        const SizedBox(height: 6),
                                        _buildFilterDateField(
                                            'Du',
                                            _filterDateFrom,
                                            (d) => setState(() {
                                                  _filterDateFrom =
                                                      d;
                                                  _currentPage = 0;
                                                })),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text('AU',
                                            style: TextStyle(
                                                fontSize: 10,
                                                fontWeight:
                                                    FontWeight.w700,
                                                color: AppColors
                                                    .slate500)),
                                        const SizedBox(height: 6),
                                        _buildFilterDateField(
                                            'Au',
                                            _filterDateTo,
                                            (d) => setState(() {
                                                  _filterDateTo = d;
                                                  _currentPage = 0;
                                                })),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 28),
                              // Status
                              const Text('STATUT',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.0,
                                      color: AppColors.slate400)),
                              const SizedBox(height: 12),
                              _buildStyledDropdown<String>(
                                value: _filterStatus,
                                defaultValue: 'all',
                                items: const [
                                  DropdownMenuItem(value: 'all', child: Text('Tous les statuts')),
                                  DropdownMenuItem(value: 'pinned', child: Text('Épinglé')),
                                  DropdownMenuItem(value: 'important', child: Text('Important')),
                                ],
                                onChanged: (v) => setState(() {
                                  _filterStatus = v ?? 'all';
                                  _currentPage = 0;
                                }),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Actions
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 20),
                        decoration: const BoxDecoration(
                           color: Color(0xFFFAFAFB),
                          border: Border(
                              top: BorderSide(
                                  color: Color(0xFFE5E7EB))),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 48,
                                child: OutlinedButton(
                                  onPressed: () => setState(() {
                                    _filterNiveauId = null;
                                    _filterSectionId = null;
                                    _filterClassId = null;
                                    _filterType = null;
                                    _filterDateFrom = null;
                                    _filterDateTo = null;
                                    _filterStatus = 'all';
                                    _currentPage = 0;
                                  }),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor:
                                        const Color(0xFF374151),
                                    backgroundColor: Colors.white,
                                    side: const BorderSide(
                                        color: Color(0xFFD1D5DB)),
                                    padding:
                                        const EdgeInsets.symmetric(
                                            vertical: 12),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(
                                                12)),
                                    elevation: 0,
                                  ),
                                  child: const Text(
                                      'Réinitialiser',
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontWeight:
                                              FontWeight.w600)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Container(
                                height: 48,
                                decoration: BoxDecoration(
                                  color:
                                      const Color(0xFF6D4CF6),
                                  borderRadius:
                                      BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(
                                              0xFF6D4CF6)
                                          .withOpacity(0.3),
                                      blurRadius: 10,
                                      offset:
                                          const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () => setState(() =>
                                        _showFilters = false),
                                    borderRadius:
                                        BorderRadius.circular(
                                            12),
                                    child: const Center(
                                      child: Text(
                                          'Appliquer',
                                          style: TextStyle(
                                              color:
                                                  Colors.white,
                                              fontSize: 14,
                                              fontWeight:
                                                  FontWeight
                                                      .w600)),
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStyledDropdown<T>({
    required T value,
    required T defaultValue,
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
          isExpanded: true,
          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          items: items,
          onChanged: onChanged,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          borderRadius: BorderRadius.circular(8),
          dropdownColor: Colors.white,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: AppColors.textTertiary),
        ),
      ),
    );
  }

  Widget _buildFilterDateField(
      String label, DateTime? value, ValueChanged<DateTime?> onChanged) {
    final dateFormat = DateFormat('d MMM yyyy', 'fr_FR');
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (picked != null) onChanged(picked);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.slate50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value != null ? dateFormat.format(value) : label,
                style: TextStyle(
                  fontSize: 13,
                  color: value != null
                      ? AppColors.textPrimary
                      : AppColors.textTertiary,
                ),
              ),
            ),
            const Icon(Icons.calendar_today_rounded,
                size: 14, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(String label, String status) {
    final isSelected = _filterStatus == status;
    return InkWell(
      onTap: () => setState(() {
        _filterStatus = status;
        _currentPage = 0;
      }),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary
              : AppColors.slate100,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isSelected
                ? Colors.white
                : AppColors.slate600,
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(AsyncValue<AnnouncementsState> announcementsAsync) {
    final totalCount = announcementsAsync.whenOrNull(data: (s) => s.announcements.length) ?? 0;
    final globalCount = announcementsAsync.whenOrNull(data: (s) => s.announcements.where((a) => a.scope == 'global').length) ?? 0;
    final classCount = announcementsAsync.whenOrNull(data: (s) => s.announcements.where((a) => a.scope == 'class').length) ?? 0;
    final studentCount = announcementsAsync.whenOrNull(data: (s) => s.announcements.where((a) => a.scope == 'student').length) ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE9EAF2))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Title — no icon
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Annonces',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$totalCount utilisateurs • $globalCount globales • $classCount classe • $studentCount étudiants',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
            ],
          ),
          const Spacer(),
          // ── Toolbar: pinned far right matching absences header ──
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 320,
                height: 40,
                child: TextField(
                        controller: _searchController,
                        onChanged: _onSearchChanged,
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Rechercher...',
                          hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 13),
                          prefixIcon: Icon(Icons.search, size: 18, color: AppColors.textTertiary),
                          suffixIcon: _searchQuery.isEmpty
                              ? Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.slate50,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: AppColors.border),
                                    ),
                                    child: Text('⌘K', style: TextStyle(fontSize: 10, color: AppColors.textTertiary, fontFamily: 'monospace')),
                                  ),
                                )
                              : IconButton(
                                  icon: const Icon(Icons.clear, size: 16),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {
                                      _searchQuery = '';
                                      _currentPage = 0;
                                    });
                                  },
                                ),
                          filled: true,
                          fillColor: AppColors.slate50,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
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
                            borderSide: BorderSide(color: const Color(0xFF655DD5).withOpacity(0.4), width: 1.5),
                          ),
                        ),
                      ),
                    ),
                const SizedBox(width: 8),
                AdminSortDropdown<String>(
                  value: _sortKey,
                  tooltip: 'Trier les annonces',
                  onChanged: (v) => setState(() {
                    _sortKey = v;
                    _currentPage = 0;
                  }),
                  options: const [
                    SortOption(value: 'pinned_first', label: 'Épinglés d’abord', icon: Icons.push_pin_outlined),
                    SortOption(value: 'date_desc', label: 'Date (Plus récent)', icon: Icons.calendar_today_outlined),
                    SortOption(value: 'date_asc', label: 'Date (Plus ancien)', icon: Icons.calendar_today_outlined),
                    SortOption(value: 'title_asc', label: 'Titre (A → Z)', icon: Icons.sort_by_alpha),
                    SortOption(value: 'title_desc', label: 'Titre (Z → A)', icon: Icons.sort_by_alpha),
                    SortOption(value: 'type_asc', label: 'Type d’annonce', icon: Icons.category_outlined),
                  ],
                ),
                const SizedBox(width: 8),
                _buildHeaderIconButton(
                  icon: Icons.filter_list_rounded,
                  tooltip: 'Filtres',
                  isActive: _filterType != null ||
                      _filterDateFrom != null ||
                      _filterDateTo != null ||
                      _filterStatus != 'all' ||
                      _filterNiveauId != null ||
                      _filterSectionId != null ||
                      _filterClassId != null ||
                      _showFilters,
                  onPressed: () => setState(() => _showFilters = !_showFilters),
                ),
                const SizedBox(width: 8),
                _buildHeaderIconButton(
                  icon: Icons.file_download_outlined,
                  tooltip: 'Télécharger CSV',
                  onPressed: _downloadCSV,
                ),
                const SizedBox(width: 8),
                _buildHeaderIconButton(
                  icon: Icons.print_outlined,
                  tooltip: 'Imprimer',
                  onPressed: _printPage,
                ),
                const SizedBox(width: 8),
                UndoRedoToolbarButtons(
                  scope: 'announcements',
                  onUndo: _handleUndo,
                  onRedo: _handleRedo,
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 40,
                  child: ElevatedButton.icon(
                    onPressed: () => _showComposerDialog(context),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Ajouter', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6D4CF6),
                      foregroundColor: Colors.white,
                      elevation: 2,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      shadowColor: const Color(0xFF6D4CF6).withOpacity(0.3),
                    ),
                  ),
                ),
              ],
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
        backgroundColor: isActive ? const Color(0xFFF5F3FF) : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: isActive ? const Color(0xFF655DD5).withOpacity(0.2) : Colors.transparent),
        ),
      ),
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
    );
  }

  void _downloadCSV() {
    final state = ref
        .read(announcementsProvider)
        .whenOrNull(data: (s) => s);
    final list = state?.announcements ?? [];
    final rows = [
      ['ID', 'Titre', 'Type', 'Contenu', 'Portée', 'Classe', 'Auteur', 'Date'],
      ...list.map((a) => [
            a.id,
            a.title,
            a.announcementType,
            a.content.replaceAll('\n', ' '),
            a.scope,
            a.className ?? '',
            a.authorName ?? '',
            '${a.createdAt.day.toString().padLeft(2, '0')}/${a.createdAt.month.toString().padLeft(2, '0')}/${a.createdAt.year}',
          ]),
    ];
    final csv = const ListToCsvConverter().convert(rows);
    final bytes = csv.codeUnits;
    final blob = html.Blob([bytes], 'text/csv;charset=utf-8');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.document.createElement('a') as html.AnchorElement
      ..href = url
      ..style.display = 'none'
      ..download =
          'annonces_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv';
    html.document.body!.children.add(anchor);
    anchor.click();
    html.document.body!.children.remove(anchor);
    html.Url.revokeObjectUrl(url);
  }

  void _printPage() {
    html.window.print();
  }

  Widget _buildFloatingSelectionBar(
    BuildContext context,
    AsyncValue<AnnouncementsState> announcementsAsync,
  ) {
    final count = _selectedIds.length;
    final selectedAnnouncements = announcementsAsync.value?.announcements
        .where((a) => _selectedIds.contains(a.id))
        .toList() ?? [];
    final allPinned = selectedAnnouncements.isNotEmpty &&
        selectedAnnouncements.every((a) => a.isPinned);
    final allImportant = selectedAnnouncements.isNotEmpty &&
        selectedAnnouncements.every((a) => a.isImportant);

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
                border: Border(right: BorderSide(color: Colors.white.withOpacity(0.15))),
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
                  const Text(
                    'Sélectionnés',
                    style: TextStyle(
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
              allPinned ? Icons.push_pin_outlined : Icons.push_pin,
              allPinned ? 'Désépingler' : 'Épingler',
              Colors.white70,
              () => _bulkPin(!allPinned),
            ),
            _buildSelectionAction(
              Icons.priority_high,
              allImportant ? 'Normal' : 'Important',
              Colors.white70,
              () => _bulkImportant(!allImportant),
            ),
            _buildSelectionAction(
              Icons.delete_outline,
              'Supprimer',
              const Color(0xFFFCA5A5),
              _bulkDeleteConfirm,
            ),
            // Close button
            Container(
              margin: const EdgeInsets.only(left: 4),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: Colors.white.withOpacity(0.15))),
              ),
              child: IconButton(
                icon: const Icon(Icons.close, size: 16, color: Colors.white60),
                onPressed: _exitSelectionMode,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionAction(IconData icon, String label, Color color, VoidCallback onTap) {
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
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: color)),
          ],
        ),
      ),
    );
  }

  void _bulkPin(bool pinned) async {
    final state = ref.read(announcementsProvider).value;
    if (state == null) return;
    final selected = state.announcements
        .where((a) => _selectedIds.contains(a.id))
        .toList();
    await ref
        .read(announcementsProvider.notifier)
        .bulkTogglePin(selected, pinned);
  }

  void _bulkImportant(bool important) async {
    final state = ref.read(announcementsProvider).value;
    if (state == null) return;
    final selected = state.announcements
        .where((a) => _selectedIds.contains(a.id))
        .toList();
    await ref
        .read(announcementsProvider.notifier)
        .bulkToggleImportant(selected, important);
  }

  void _bulkDeleteConfirm() {
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
                child: const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 18),
              ),
              const SizedBox(width: 12),
              const Text('Supprimer les annonces ?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Êtes-vous sûr de vouloir supprimer ${_selectedIds.length} annonce(s) ?'),
              const SizedBox(height: 6),
              const Text(
                'Cette action est irréversible.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          actions: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF6B7280),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  child: const Text('Annuler', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final state = ref.read(announcementsProvider).value;
                    if (state == null) return;
                    final selected = state.announcements.where((a) => _selectedIds.contains(a.id)).toList();
                    await ref.read(announcementsProvider.notifier).bulkDelete(selected);
                    _exitSelectionMode();
                  },
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Supprimer', style: TextStyle(fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar(AsyncValue<AnnouncementsState> announcementsAsync) {
    final state = announcementsAsync.whenOrNull(data: (s) => s);
    final all = state?.announcements ?? [];
    final filtered =
        all.where((a) => _smartMatch(a, _searchQuery)).toList();

    final totalCount = filtered.length;
    final notifCount =
        filtered.where((a) => a.scope == 'global').length;
    final msgCount =
        filtered.where((a) => a.scope == 'class').length;
    final studentCount =
        filtered.where((a) => a.scope == 'student').length;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border:
            Border(bottom: BorderSide(color: AppColors.border.withOpacity(0.5))),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 24, top: 4),
          child: TabBar(
            controller: _tabController,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textTertiary,
            indicatorColor: AppColors.primary,
            indicatorWeight: 2,
            labelStyle: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 13),
            unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w500, fontSize: 13),
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorSize: TabBarIndicatorSize.tab,
            dividerHeight: 0,
            labelPadding: const EdgeInsets.symmetric(horizontal: 12),
            onTap: (_) => setState(() => _currentPage = 0),
        tabs: [
          Tab(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12, top: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.format_list_bulleted, size: 18),
                  const SizedBox(width: 8),
                  const Text('Toutes'),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('$totalCount',
                        style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ),
          Tab(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12, top: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.notifications_none, size: 18),
                  const SizedBox(width: 8),
                  const Text('Notifications'),
                ],
              ),
            ),
          ),
          Tab(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12, top: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.groups_outlined, size: 18),
                  const SizedBox(width: 8),
                  const Text('Messages'),
                ],
              ),
            ),
          ),
          Tab(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12, top: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.person_outline, size: 18),
                  const SizedBox(width: 8),
                  const Text('Messages Élèves'),
                ],
              ),
            ),
          ),
        ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabContent(BuildContext context, AnnouncementsState state) {
    var filtered = state.announcements
        .where((a) => _smartMatch(a, _searchQuery))
        .toList();

    // Apply type filter
    if (_filterType != null) {
      filtered = filtered
          .where((a) => a.announcementType == _filterType)
          .toList();
    }

    // Apply date filters
    if (_filterDateFrom != null) {
      filtered = filtered
          .where((a) => a.createdAt.isAfter(
                _filterDateFrom!.subtract(const Duration(days: 1))))
          .toList();
    }
    if (_filterDateTo != null) {
      filtered = filtered
          .where((a) => a.createdAt.isBefore(
                _filterDateTo!.add(const Duration(days: 1))))
          .toList();
    }

    // Apply status filter
    if (_filterStatus == 'pinned') {
      filtered = filtered.where((a) => a.isPinned).toList();
    } else if (_filterStatus == 'important') {
      filtered = filtered.where((a) => a.isImportant).toList();
    }

    // Apply academic filters (Niveau -> Filière -> Classe)
    if (_filterNiveauId != null || _filterSectionId != null || _filterClassId != null) {
      filtered = filtered.where(_matchesAcademicFilters).toList();
    }

    return TabBarView(
      controller: _tabController,
      children: [
        _buildAnnouncementsList(filtered),
        _buildAnnouncementsList(
          filtered.where((a) => a.scope == 'global').toList()),
        _buildAnnouncementsList(
          filtered.where((a) => a.scope == 'class').toList()),
        _buildAnnouncementsList(
          filtered.where((a) => a.scope == 'student').toList()),
      ],
    );
  }

  Widget _buildAnnouncementsList(List<AnnouncementModel> list) {
    final hasFilters = _searchQuery.isNotEmpty ||
        _filterType != null ||
        _filterDateFrom != null ||
        _filterDateTo != null ||
        _filterStatus != 'all' ||
        _filterNiveauId != null ||
        _filterSectionId != null ||
        _filterClassId != null;

    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.slate100,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.campaign_outlined,
                  size: 40, color: AppColors.slate300),
            ),
            const SizedBox(height: 20),
            Text(
              hasFilters
                  ? 'Aucun résultat avec ces filtres'
                  : 'Aucune annonce',
              style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 16,
                  fontWeight: FontWeight.w500),
            ),
            if (hasFilters) ...[
              const SizedBox(height: 8),
              Text('Essayez de modifier vos critères de recherche',
                  style: TextStyle(
                      color: AppColors.slate400, fontSize: 13)),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () => setState(() {
                  _searchController.clear();
                  _searchQuery = '';
                  _filterNiveauId = null;
                  _filterSectionId = null;
                  _filterClassId = null;
                  _filterType = null;
                  _filterDateFrom = null;
                  _filterDateTo = null;
                  _filterStatus = 'all';
                  _currentPage = 0;
                }),
                icon: const Icon(Icons.clear_all, size: 18),
                label: const Text('Effacer les filtres'),
              ),
            ],
          ],
        ),
      );
    }

    // Sort
    list.sort((a, b) {
      int cmp;
      switch (_sortKey) {
        case 'date_desc':
          cmp = b.createdAt.compareTo(a.createdAt);
          break;
        case 'date_asc':
          cmp = a.createdAt.compareTo(b.createdAt);
          break;
        case 'title_asc':
          cmp = a.title.toLowerCase().compareTo(b.title.toLowerCase());
          break;
        case 'title_desc':
          cmp = b.title.toLowerCase().compareTo(a.title.toLowerCase());
          break;
        case 'type_asc':
          cmp = a.announcementType.compareTo(b.announcementType);
          break;
        case 'pinned_first':
        default:
          if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
          cmp = b.createdAt.compareTo(a.createdAt);
          break;
      }
      if (cmp != 0) return cmp;
      final dCmp = b.createdAt.compareTo(a.createdAt);
      if (dCmp != 0) return dCmp;
      return a.id.compareTo(b.id);
    });

    // Paginate
    final totalPages = (list.length / _pageSize).ceil().clamp(1, 999999);
    final safePage = _currentPage.clamp(0, totalPages - 1);
    final startIdx = safePage * _pageSize;
    final endIdx = (startIdx + _pageSize).clamp(0, list.length);
    final pageItems = list.sublist(startIdx, endIdx);

    return Container(
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
              _buildSelectAllBar(list),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: pageItems.length,
                  itemBuilder: (ctx, i) =>
                      _buildAnnouncementCard(pageItems[i]),
                ),
              ),
              _buildPaginationBar(list.length, totalPages),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaginationBar(int total, int totalPages) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFB),
        border: Border(top: BorderSide(color: AppColors.border.withOpacity(0.3))),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(8),
          bottomRight: Radius.circular(8),
        ),
      ),
      child: Row(
        children: [
          Text('Afficher par',
              style: TextStyle(
                  fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _pageSize,
                isDense: true,
                borderRadius: BorderRadius.circular(10),
                dropdownColor: Colors.white,
                elevation: 4,
                menuMaxHeight: 200,
                items: [10, 20, 50]
                    .map((s) => DropdownMenuItem(
                        value: s,
                        child: Text('$s',
                            style:
                                const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))))
                    .toList(),
                onChanged: (v) => setState(() {
                  _pageSize = v!;
                  _currentPage = 0;
                }),
              ),
            ),
          ),
          const Spacer(),
          Text(
            'Page ${_currentPage + 1} sur $totalPages',
            style: TextStyle(
                fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 20),
            onPressed: _currentPage > 0
                ? () => setState(() => _currentPage--)
                : null,
            style: IconButton.styleFrom(
              backgroundColor: AppColors.slate50,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              side: const BorderSide(color: AppColors.border),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 20),
            onPressed: _currentPage < totalPages - 1
                ? () => setState(() => _currentPage++)
                : null,
            style: IconButton.styleFrom(
              backgroundColor: AppColors.slate50,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              side: const BorderSide(color: AppColors.border),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectAllBar(List<AnnouncementModel> list) {
    final allSelected =
        _selectedIds.length == list.length && list.isNotEmpty;
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 32, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.slate50,
        border: Border(
            bottom: BorderSide(color: AppColors.border.withOpacity(0.5))),
      ),
      child: Row(
        children: [
          Checkbox(
            value: allSelected,
            tristate:
                _selectedIds.isNotEmpty && !allSelected,
            onChanged: (_) => _selectAll(list),
            activeColor: const Color(0xFF655DD5),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4)),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: () => _selectAll(list),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                allSelected
                    ? 'Tout désélectionner'
                    : 'Tout sélectionner',
                style: const TextStyle(
                    color: AppColors.slate700, fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
          ),
          const Spacer(),
          Text(
            '${list.length} annonce(s)',
            style: const TextStyle(
                color: AppColors.slate500, fontSize: 12),
          ),
        ],
      ),
    );
  }

  String _formatTimeAgo(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.isNegative || diff.inSeconds < 45) {
      return "À l'instant";
    }
    if (diff.inMinutes < 60) {
      return 'Il y a ${diff.inMinutes} min';
    }
    if (diff.inHours < 24) {
      return 'Il y a ${diff.inHours}h';
    }
    if (diff.inDays == 1) {
      final hour = dt.hour.toString().padLeft(2, '0');
      final minute = dt.minute.toString().padLeft(2, '0');
      return 'Hier à $hour:$minute';
    }
    if (diff.inDays < 7) {
      return 'Il y a ${diff.inDays}j';
    }
    if (diff.inDays < 30) {
      final weeks = (diff.inDays / 7).floor();
      return 'Il y a $weeks sem.';
    }
    return DateFormat('d MMM yyyy', 'fr_FR').format(dt);
  }

  Widget _buildAnnouncementCard(AnnouncementModel a) {
    final typeInfo = _getTypeInfo(a.announcementType);
    final isSelected = _selectedIds.contains(a.id);
    final dateStr = DateFormat('d MMM yyyy', 'fr_FR').format(a.createdAt);
    final timeAgoStr = _formatTimeAgo(a.createdAt);

    String? studentTarget;
    final payloadName = a.payload['student_name']?.toString() ??
        a.payload['target_student_name']?.toString() ??
        a.payload['student']?['full_name']?.toString() ??
        a.payload['student']?['name']?.toString();
    if (payloadName != null && payloadName.trim().isNotEmpty) {
      studentTarget = payloadName.trim();
    } else {
      final match = RegExp(r'\*\*@([^*]+)\*\*').firstMatch(a.content);
      if (match != null && match.group(1)?.trim().isNotEmpty == true) {
        studentTarget = match.group(1)!.trim();
      } else {
        final match2 = RegExp(r'@([A-Za-zÀ-ÿ\s\-]+)').firstMatch(a.content);
        if (match2 != null && match2.group(1)?.trim().isNotEmpty == true) {
          studentTarget = match2.group(1)!.trim();
        }
      }
    }
    final isStudentMsg = a.scope == 'student' || studentTarget != null || (_tabController.index == 3);
    final targetStudentId = a.payload['target_student_id']?.toString() ?? a.payload['student_id']?.toString();
    final studentInfo = (studentTarget != null ? _studentLookupByName[studentTarget.toLowerCase().trim()] : null) ??
        (targetStudentId != null ? _studentLookupById[targetStudentId] : null);
    final studentPhotoUrl = studentInfo?['photo_url']?.toString() ??
        a.payload['student_photo_url']?.toString() ??
        a.payload['photo_url']?.toString() ??
        a.payload['student']?['photo_url']?.toString();
    final studentGender = studentInfo?['gender']?.toString() ??
        a.payload['student_gender']?.toString() ??
        a.payload['gender']?.toString() ??
        a.payload['student']?['gender']?.toString();

    final bool hasAttachments = a.hasAttachment ||
        (a.payload['attachments'] is List && (a.payload['attachments'] as List).isNotEmpty) ||
        (a.payload['files'] is List && (a.payload['files'] as List).isNotEmpty) ||
        (a.payload['attachment_url'] != null && a.payload['attachment_url'].toString().trim().isNotEmpty) ||
        (a.payload['file_url'] != null && a.payload['file_url'].toString().trim().isNotEmpty);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isSelected
            ? const Color(0xFFF5F3FF)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? const Color(0xFFDDD6FE)
              : AppColors.border,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _selectionMode
            ? () => _toggleSelection(a.id)
            : () =>
                _showComposerDialog(context, announcement: a),
        onLongPress: () {
          if (!_selectionMode) {
            setState(() => _selectionMode = true);
            _toggleSelection(a.id);
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: Checkbox(
                    value: isSelected,
                    onChanged: (_) => _toggleSelection(a.id),
                    activeColor: const Color(0xFF655DD5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4)),
                  ),
                ),
                const SizedBox(width: 8),
                // Type icon rounded square
                Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: typeInfo.color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(typeInfo.icon,
                        color: typeInfo.color, size: 15),
                  ),
                ),
                const SizedBox(width: 14),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title row + class badge + type label
                    Row(
                      children: [
                        Flexible(
                          child: _searchQuery.isNotEmpty
                              ? _highlightText(
                                  a.title.isNotEmpty
                                      ? a.title
                                      : typeInfo.label,
                                  _searchQuery,
                                  const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color:
                                          AppColors.textPrimary),
                                )
                              : Text(
                                  a.title.isNotEmpty
                                      ? a.title
                                      : typeInfo.label,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color:
                                          AppColors.textPrimary),
                                  maxLines: 1,
                                  overflow:
                                      TextOverflow.ellipsis,
                                ),
                        ),
                        if (isStudentMsg && studentTarget != null) ...[
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                UserAvatar(
                                  name: studentTarget,
                                  photoUrl: studentPhotoUrl,
                                  gender: studentGender,
                                  radius: 9,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  studentTarget,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else if (a.className != null) ...[
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFECFDF5),
                              borderRadius:
                                  BorderRadius.circular(8),
                            ),
                            child: Text(
                              a.className!,
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF15803D)),
                            ),
                          ),
                        ],
                        if (a.isPinned) ...[  
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF655DD5).withOpacity(0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.push_pin, size: 12, color: const Color(0xFF655DD5)),
                                const SizedBox(width: 4),
                                Text('Épinglé', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF655DD5))),
                              ],
                            ),
                          ),
                        ],
                        if (a.isImportant) ...[
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.priority_high_rounded, size: 12, color: Color(0xFFDC2626)),
                                SizedBox(width: 4),
                                Text(
                                  'Important',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFDC2626),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Description
                    _searchQuery.isNotEmpty
                        ? _highlightText(
                            a.content,
                            _searchQuery,
                            TextStyle(
                                fontSize: 13,
                                color: AppColors.slate500,
                                height: 1.5),
                          )
                        : Text(
                            a.content,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 13,
                                color: AppColors.slate500,
                                height: 1.5),
                          ),
                    if (hasAttachments) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3E8FF),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.attach_file_rounded,
                                    size: 12, color: Color(0xFF9333EA)),
                                SizedBox(width: 4),
                                Text(
                                  'Pièce jointe',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF9333EA),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 24),
              // Right side: 3-dot menu top, date bottom
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (!_selectionMode)
                    PopupMenuButton<String>(
                      onSelected: (v) => _handleAction(v, a),
                      icon: Icon(Icons.more_horiz,
                          size: 18, color: AppColors.slate400),
                      padding: EdgeInsets.zero,
                      tooltip: 'Actions',
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      elevation: 8,
                      offset: const Offset(-160, 40),
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'pin',
                          height: 40,
                          child: Row(children: [
                            Icon(
                                a.isPinned
                                    ? Icons.push_pin_outlined
                                    : Icons.push_pin,
                                size: 18,
                                color: AppColors.slate600),
                            const SizedBox(width: 12),
                            Text(a.isPinned
                                ? 'Désépingler'
                                : 'Épingler',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.slate600)),
                          ]),
                        ),
                        PopupMenuItem(
                          value: 'edit',
                          height: 40,
                          child: Row(children: [
                            Icon(Icons.edit_outlined, size: 18, color: AppColors.slate600),
                            const SizedBox(width: 12),
                            Text('Modifier', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.slate600)),
                          ]),
                        ),
                        const PopupMenuDivider(),
                        PopupMenuItem(
                          value: 'delete',
                          height: 40,
                          child: Row(children: [
                            Icon(Icons.delete_outline_rounded,
                                size: 18,
                                color: AppColors.error),
                            const SizedBox(width: 12),
                            Text('Supprimer',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.error)),
                          ]),
                        ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.access_time_rounded,
                          size: 13, color: AppColors.slate400),
                      const SizedBox(width: 4),
                      Text(
                        timeAgoStr,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.slate600,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '($dateStr)',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.slate400,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
          ),
      ),
    );
  }

  // Badges are now inline icons in the card header

  _TypeInfo _getTypeInfo(String type) {
    switch (type) {
      case 'teacher_absent':
        return _TypeInfo('Absence prof', Icons.person_off, AppColors.warning);
      case 'room_change':
        return _TypeInfo('Changement salle', Icons.meeting_room, AppColors.secondary);
      case 'reminder':
        return _TypeInfo('Rappel', Icons.alarm, AppColors.primary);
      case 'exam':
        return _TypeInfo('Examen', Icons.assignment, AppColors.error);
      case 'retenue':
        return _TypeInfo('Retenue', Icons.access_time, const Color(0xFFDC2626));
      case 'avertissement':
        return _TypeInfo('Avertissement', Icons.warning_amber, AppColors.warning);
      case 'exclusion_classe':
        return _TypeInfo(
          'Exclusion classe',
          Icons.no_meeting_room,
          AppColors.accent,
        );
      case 'exclusion_etablissement':
        return _TypeInfo('Exclusion établissement', Icons.block, AppColors.error);
      case 'convocation_parents':
        return _TypeInfo(
          'Convocation parents',
          Icons.family_restroom,
          AppColors.chart5,
        );
      case 'conseil_discipline':
        return _TypeInfo('Conseil discipline', Icons.gavel, AppColors.secondary);
      case 'exclusion_definitive':
        return _TypeInfo('Exclusion définitive', Icons.cancel, AppColors.textPrimary);
      case 'closure':
        return _TypeInfo('Fermeture', Icons.lock, AppColors.slate300);
      case 'trip':
        return _TypeInfo('Sortie/Voyage', Icons.directions_bus, AppColors.success);
      case 'party':
        return _TypeInfo('Événement', Icons.celebration, AppColors.chart4);
      case 'payment':
        return _TypeInfo('Paiement', Icons.payment, AppColors.chart5);
      default:
        return _TypeInfo('Général', Icons.campaign, AppColors.chart6);
    }
  }

  String _formatDate(DateTime dt) {
    return DateFormat('d MMM yyyy', 'fr_FR').format(dt);
  }

  void _handleAction(String action, AnnouncementModel a) {
    switch (action) {
      case 'pin':
        ref
            .read(announcementsProvider.notifier)
            .togglePin(a.id, a.isPinned, scope: a.scope);
        break;
      case 'edit':
        _showComposerDialog(context, announcement: a);
        break;
      case 'delete':
        _confirmDelete(context, a);
        break;
    }
  }

  void _confirmDelete(BuildContext context, AnnouncementModel a) {
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
                child: const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 18),
              ),
              const SizedBox(width: 12),
              const Text('Supprimer l\'annonce ?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Êtes-vous sûr de vouloir supprimer "${a.title}" ?'),
              const SizedBox(height: 6),
              const Text(
                'Cette action est irréversible.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          actions: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF6B7280),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  child: const Text('Annuler', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () {
                    final aTitle = a.title.isNotEmpty ? a.title : 'Annonce';
                    ref.read(announcementsProvider.notifier).delete(a.id, scope: a.scope);
                    Navigator.pop(ctx);
                    if (mounted) {
                      FeedbackPill.showSuccess(context, 'Annonce "$aTitle" supprimée');
                    }
                  },
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Supprimer', style: TextStyle(fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openCreateDialog({String? initialScope, String? preSelectedStudentId}) {
    _showComposerDialog(
      context,
      initialScope: initialScope,
      preSelectedStudentId: preSelectedStudentId,
    );
  }

  void _showComposerDialog(
    BuildContext context, {
    AnnouncementModel? announcement,
    String? initialScope,
    String? preSelectedStudentId,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.08),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: _AnnouncementComposerDialog(
          announcement: announcement,
          initialScope: initialScope,
          preSelectedStudentId: preSelectedStudentId,
          onSave: () {
            ref.invalidate(announcementsProvider);
            Navigator.pop(ctx);
          },
        ),
      ),
    );
  }
}

class _TypeInfo {
  final String label;
  final IconData icon;
  final Color color;
  _TypeInfo(this.label, this.icon, this.color);
}

// =============================================================================
// COMPOSER DIALOG
// =============================================================================

class _AnnouncementComposerDialog extends ConsumerStatefulWidget {
  final AnnouncementModel? announcement;
  final VoidCallback onSave;
  final String? initialScope;
  final String? preSelectedStudentId;

  const _AnnouncementComposerDialog({
    this.announcement,
    required this.onSave,
    this.initialScope,
    this.preSelectedStudentId,
  });

  @override
  ConsumerState<_AnnouncementComposerDialog> createState() =>
      _AnnouncementComposerDialogState();
}

class _AnnouncementComposerDialogState
    extends ConsumerState<_AnnouncementComposerDialog> {
  final _formKey = GlobalKey<FormState>();
  final ScrollController _dialogScrollCtrl = ScrollController();
  late final Listenable _previewListenable;
  late TextEditingController _titleCtrl;
  late TextEditingController _contentCtrl;
  late TextEditingController _senderLabelCtrl;

  // Payload controllers for type-specific fields
  late TextEditingController _teacherNameCtrl;
  late TextEditingController _startDateCtrl;
  late TextEditingController _startTimeCtrl; // Separate time controller
  late TextEditingController _endDateCtrl;
  late TextEditingController _endTimeCtrl; // Separate time controller
  late TextEditingController _replacementNoteCtrl;
  late TextEditingController _subjectCtrl;
  late TextEditingController _oldRoomCtrl;
  late TextEditingController _newRoomCtrl;
  late TextEditingController _examDateCtrl; // Separate date for exam
  late TextEditingController _examTimeCtrl; // Separate time for exam
  late TextEditingController _changeDateCtrl; // Separate date for room change
  late TextEditingController _changeTimeCtrl; // Separate time for room change
  String? _selectedBuildingId; // For building selection in room forms (new room)
  String? _selectedFloorId; // For floor selection in room forms (new room)
  String? _selectedRoomId; // For room selection in room forms (new room)
  String? _selectedOldBuildingId; // For old room building selection in room_change
  String? _selectedOldFloorId; // For old room floor selection in room_change
  String? _selectedOldRoomId; // For old room selection in room_change
  late TextEditingController _instructionsCtrl;
  late TextEditingController _reasonCtrl;
  late TextEditingController _closedFromCtrl;
  late TextEditingController _closedToCtrl;
  late TextEditingController _reopenDateCtrl;
  late TextEditingController _dueDateCtrl;
  late TextEditingController _actionRequiredCtrl;
  // Trip controllers
  late TextEditingController _destinationCtrl;
  late TextEditingController _departureDateCtrl;
  late TextEditingController _departureTimeCtrl;
  late TextEditingController _returnDateCtrl;
  late TextEditingController _returnTimeCtrl;
  late TextEditingController _meetingPointCtrl;
  late TextEditingController _tripCostCtrl;
  late TextEditingController _tripNotesCtrl;
  // Party/Event controllers
  late TextEditingController _eventNameCtrl;
  late TextEditingController _eventDateCtrl;
  late TextEditingController _eventTimeCtrl;
  late TextEditingController _eventLocationCtrl;
  late TextEditingController _dressCodeCtrl;
  late TextEditingController _eventNotesCtrl;
  // Payment controllers
  late TextEditingController _paymentTypeCtrl;
  late TextEditingController _paymentAmountCtrl;
  late TextEditingController _paymentDueDateCtrl;
  late TextEditingController _paymentMethodCtrl;
  late TextEditingController _paymentNotesCtrl;
  // Sanction controllers (for student messages)
  late TextEditingController _sanctionReasonCtrl;
  late TextEditingController _sanctionDateCtrl;
  late TextEditingController _sanctionDurationCtrl;
  late TextEditingController _sanctionNotesCtrl;
  late TextEditingController _meetingDateCtrl;
  late TextEditingController _meetingTimeCtrl;
  late TextEditingController _disciplineSubjectCtrl;
  String _durationUnit = 'jour'; // Unit for sanction duration

  String _scope = 'global';
  String? _selectedClassId;
  String? _selectedStudentId;
  String _searchStudentQuery = '';
  late TextEditingController _searchStudentCtrl;
  String? _selectedSubjectName; // For subject dropdown
  String _teacherSearchQuery = ''; // For fuzzy teacher search
  String? _selectedTeacherName; // For teacher search selection
  String? _selectedTeacherSpeciality;
  String? _selectedTeacherPhotoUrl;
  String _announcementType = 'general';
  String _senderType = 'administration';
  bool _isPinned = false;
  bool _isImportant = false;
  bool _isLoading = false;

  final List<_PendingFile> _pendingFiles = [];
  int _loadingImagesSkeletonCount = 0;
  int _loadingDocsSkeletonCount = 0;
  List<Map<String, dynamic>> _existingAttachments =
      []; // Existing attachments from DB
  final List<String> _attachmentsToDelete = []; // IDs to delete on save
  List<Map<String, dynamic>> _classes = [];
  bool _classesLoading = true;

  Map<String, dynamic>? _loadedStudentInfo;

  Future<void> _loadStudentInfo(AnnouncementModel? a) async {
    if (a == null) return;
    try {
      final targetId = a.targetStudentId ??
          a.payload['target_student_id']?.toString() ??
          a.payload['student_id']?.toString();
      if (targetId != null && targetId.isNotEmpty) {
        final res = await SupabaseConfig.client
            .from('users')
            .select('id, full_name, photo_url, gender, student_code, enrollments:enrollments(class_id, classes:classes(name, niveau_id, niveaux:niveaux(name)))')
            .eq('id', targetId)
            .maybeSingle();
        if (res != null && mounted) {
          setState(() => _loadedStudentInfo = res);
          return;
        }
      }
      final name = a.payload['student_name']?.toString() ??
          a.payload['target_student_name']?.toString() ??
          a.payload['student']?['full_name']?.toString();
      if (name != null && name.trim().isNotEmpty) {
        final res = await SupabaseConfig.client
            .from('users')
            .select('id, full_name, photo_url, gender, student_code, enrollments:enrollments(class_id, classes:classes(name, niveau_id, niveaux:niveaux(name)))')
            .ilike('full_name', '%${name.trim()}%')
            .maybeSingle();
        if (res != null && mounted) {
          setState(() => _loadedStudentInfo = res);
        }
      }
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    final a = widget.announcement;
    _titleCtrl = TextEditingController(text: a?.title ?? '');
    _contentCtrl = TextEditingController(text: a?.content ?? '');
    _senderLabelCtrl = TextEditingController(text: a?.senderLabel ?? '');
    _searchStudentCtrl = TextEditingController();

    // Initialize payload controllers
    final payload = a?.payload ?? {};
    _teacherNameCtrl = TextEditingController(
      text: payload['teacher_name'] ?? '',
    );
    _startDateCtrl = TextEditingController(text: payload['start_date'] ?? '');
    _startTimeCtrl = TextEditingController(text: payload['start_time'] ?? '');
    _endDateCtrl = TextEditingController(text: payload['end_date'] ?? '');
    _endTimeCtrl = TextEditingController(text: payload['end_time'] ?? '');
    _replacementNoteCtrl = TextEditingController(
      text: payload['replacement_note'] ?? '',
    );
    _subjectCtrl = TextEditingController(text: payload['subject'] ?? '');
    _selectedSubjectName = payload['subject'] as String?;
    _selectedTeacherName = payload['teacher_name'] as String?;
    _selectedTeacherSpeciality = payload['teacher_speciality'] as String? ?? payload['subject'] as String?;
    _selectedTeacherPhotoUrl = payload['teacher_photo_url'] as String?;
    if (_selectedTeacherName != null && _selectedTeacherName!.isEmpty) {
      _selectedTeacherName = null;
      _selectedTeacherSpeciality = null;
      _selectedTeacherPhotoUrl = null;
    }
    if (_selectedSubjectName != null && _selectedSubjectName!.isEmpty) _selectedSubjectName = null;
    _oldRoomCtrl = TextEditingController(text: payload['old_room'] ?? '');
    _newRoomCtrl = TextEditingController(text: payload['new_room'] ?? '');
    _examDateCtrl = TextEditingController(text: payload['exam_date'] ?? '');
    _examTimeCtrl = TextEditingController(text: payload['exam_time'] ?? '');
    _changeDateCtrl = TextEditingController(text: payload['change_date'] ?? '');
    _changeTimeCtrl = TextEditingController(text: payload['change_time'] ?? '');
    // Room restoration when editing
    final roomName = payload['room'] as String?;
    final newRoomId = payload['new_room_id'] as String?;
    final oldRoomId = payload['old_room_id'] as String?;
    final oldRoomName = payload['old_room'] as String?;
    if ((roomName != null && roomName.isNotEmpty) ||
        (newRoomId != null && newRoomId.isNotEmpty) ||
        (oldRoomId != null && oldRoomId.isNotEmpty) ||
        (oldRoomName != null && oldRoomName.isNotEmpty)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final buildingAsync = ref.read(buildingProvider);
        if (!buildingAsync.hasValue) return;
        final buildingState = buildingAsync.value!;

        // Restore new room
        RoomModel? foundRoom;
        if (newRoomId != null && newRoomId.isNotEmpty) {
          foundRoom = buildingState.availableRooms.firstWhere(
            (r) => r.id == newRoomId,
            orElse: () => RoomModel(id: '', floorId: '', name: ''),
          );
        }
        if ((foundRoom == null || foundRoom.id.isEmpty) && roomName != null && roomName.isNotEmpty) {
          foundRoom = buildingState.availableRooms.firstWhere(
            (r) => r.name == roomName,
            orElse: () => RoomModel(id: '', floorId: '', name: ''),
          );
        }
        if (foundRoom != null && foundRoom.id.isNotEmpty) {
          for (final b in buildingState.buildings) {
            for (final f in b.floors) {
              if (f.id == foundRoom.floorId || f.rooms.any((r) => r.id == foundRoom!.id)) {
                _selectedBuildingId = b.id;
                _selectedFloorId = f.id;
                _selectedRoomId = foundRoom.id;
                break;
              }
            }
          }
        }

        // Restore old room if present (e.g. room_change)
        RoomModel? foundOldRoom;
        if (oldRoomId != null && oldRoomId.isNotEmpty) {
          foundOldRoom = buildingState.availableRooms.firstWhere(
            (r) => r.id == oldRoomId,
            orElse: () => RoomModel(id: '', floorId: '', name: ''),
          );
        }
        if ((foundOldRoom == null || foundOldRoom.id.isEmpty) && oldRoomName != null && oldRoomName.isNotEmpty) {
          foundOldRoom = buildingState.availableRooms.firstWhere(
            (r) => r.name == oldRoomName,
            orElse: () => RoomModel(id: '', floorId: '', name: ''),
          );
        }
        if (foundOldRoom != null && foundOldRoom.id.isNotEmpty) {
          for (final b in buildingState.buildings) {
            for (final f in b.floors) {
              if (f.id == foundOldRoom.floorId || f.rooms.any((r) => r.id == foundOldRoom!.id)) {
                _selectedOldBuildingId = b.id;
                _selectedOldFloorId = f.id;
                _selectedOldRoomId = foundOldRoom.id;
                break;
              }
            }
          }
        }

        if (mounted) setState(() {});
      });
    }
    _instructionsCtrl = TextEditingController(
      text: payload['instructions'] ?? '',
    );
    _reasonCtrl = TextEditingController(text: payload['reason'] ?? '');
    _closedFromCtrl = TextEditingController(text: payload['closed_from'] ?? '');
    _closedToCtrl = TextEditingController(text: payload['closed_to'] ?? '');
    _reopenDateCtrl = TextEditingController(text: payload['reopen_date'] ?? '');
    _dueDateCtrl = TextEditingController(text: payload['due_date'] ?? '');
    _actionRequiredCtrl = TextEditingController(
      text: payload['action_required'] ?? '',
    );
    // Trip controllers
    _destinationCtrl = TextEditingController(
      text: payload['destination'] ?? '',
    );
    _departureDateCtrl = TextEditingController(
      text: payload['departure_date'] ?? '',
    );
    _departureTimeCtrl = TextEditingController(
      text: payload['departure_time'] ?? '',
    );
    _returnDateCtrl = TextEditingController(text: payload['return_date'] ?? '');
    _returnTimeCtrl = TextEditingController(text: payload['return_time'] ?? '');
    _meetingPointCtrl = TextEditingController(
      text: payload['meeting_point'] ?? '',
    );
    _tripCostCtrl = TextEditingController(text: payload['cost'] ?? '');
    _tripNotesCtrl = TextEditingController(text: payload['notes'] ?? '');
    // Party controllers
    _eventNameCtrl = TextEditingController(text: payload['event_name'] ?? '');
    _eventDateCtrl = TextEditingController(text: payload['event_date'] ?? '');
    _eventTimeCtrl = TextEditingController(text: payload['event_time'] ?? '');
    _eventLocationCtrl = TextEditingController(text: payload['location'] ?? '');
    _dressCodeCtrl = TextEditingController(text: payload['dress_code'] ?? '');
    _eventNotesCtrl = TextEditingController(text: payload['notes'] ?? '');
    // Payment controllers
    _paymentTypeCtrl = TextEditingController(
      text: payload['payment_type'] ?? '',
    );
    _paymentAmountCtrl = TextEditingController(text: payload['amount'] ?? '');
    _paymentDueDateCtrl = TextEditingController(
      text: payload['due_date'] ?? '',
    );
    _paymentMethodCtrl = TextEditingController(
      text: payload['payment_method'] ?? '',
    );
    _paymentNotesCtrl = TextEditingController(text: payload['notes'] ?? '');
    // Sanction controllers
    _sanctionReasonCtrl = TextEditingController(
      text: payload['sanction_reason'] ?? '',
    );
    _sanctionDateCtrl = TextEditingController(
      text: payload['sanction_date'] ?? '',
    );
    _sanctionDurationCtrl = TextEditingController(
      text: payload['sanction_duration'] ?? '',
    );
    _sanctionNotesCtrl = TextEditingController(
      text: payload['sanction_notes'] ?? '',
    );
    _meetingDateCtrl = TextEditingController(
      text: payload['meeting_date'] ?? '',
    );
    _meetingTimeCtrl = TextEditingController(
      text: payload['meeting_time'] ?? '',
    );
    _disciplineSubjectCtrl = TextEditingController(
      text: payload['discipline_subject'] ?? '',
    );

    // Real-time preview listenable - only rebuilds the preview card, keeping the form stable
    _previewListenable = Listenable.merge([
      _titleCtrl,
      _contentCtrl,
      _senderLabelCtrl,
      _teacherNameCtrl,
      _startDateCtrl,
      _startTimeCtrl,
      _endDateCtrl,
      _endTimeCtrl,
      _replacementNoteCtrl,
      _subjectCtrl,
      _oldRoomCtrl,
      _newRoomCtrl,
      _examDateCtrl,
      _examTimeCtrl,
      _changeDateCtrl,
      _changeTimeCtrl,
      _instructionsCtrl,
      _reasonCtrl,
      _closedFromCtrl,
      _closedToCtrl,
      _reopenDateCtrl,
      _dueDateCtrl,
      _actionRequiredCtrl,
      _destinationCtrl,
      _departureDateCtrl,
      _departureTimeCtrl,
      _returnDateCtrl,
      _returnTimeCtrl,
      _meetingPointCtrl,
      _tripCostCtrl,
      _tripNotesCtrl,
      _eventNameCtrl,
      _eventDateCtrl,
      _eventTimeCtrl,
      _eventLocationCtrl,
      _dressCodeCtrl,
      _eventNotesCtrl,
      _paymentTypeCtrl,
      _paymentAmountCtrl,
      _paymentDueDateCtrl,
      _paymentMethodCtrl,
      _paymentNotesCtrl,
      _sanctionReasonCtrl,
      _sanctionDateCtrl,
      _sanctionDurationCtrl,
      _sanctionNotesCtrl,
      _meetingDateCtrl,
      _meetingTimeCtrl,
      _disciplineSubjectCtrl,
    ]);

    if (a != null) {
      _scope = a.scope;
      _selectedClassId = a.targetClassId;
      _selectedStudentId = a.targetStudentId ??
          a.payload['target_student_id']?.toString() ??
          a.payload['student_id']?.toString();
      _announcementType = a.announcementType;
      _senderType = a.senderType;
      _isPinned = a.isPinned;
      _isImportant = a.isImportant;
      _loadStudentInfo(a);
      // Load existing attachments unconditionally
      _loadExistingAttachments(a.id);
    } else {
      // Handle initial parameters from navigation
      if (widget.initialScope != null) {
        _scope = widget.initialScope!;
      }
      if (widget.preSelectedStudentId != null) {
        _selectedStudentId = widget.preSelectedStudentId;
        // Set default announcement type for student messages
        if (_scope == 'student') {
          _announcementType = 'avertissement';
        }
      }
    }
    _loadClasses();
  }

  Future<void> _loadExistingAttachments(String announcementId) async {
    try {
      final supabase = Supabase.instance.client;
      final data = await supabase
          .from('announcement_attachments')
          .select()
          .eq('announcement_id', announcementId);
      if (mounted) {
        setState(() {
          _existingAttachments = List<Map<String, dynamic>>.from(data);
        });
      }
    } catch (e) {
      debugPrint('Error loading attachments: $e');
    }
  }

  void _onTextChanged() {
    setState(() {}); // Trigger rebuild to update preview
  }

  /// Generate human-readable content from type-specific fields
  String _generateContent() {
    final extra = _contentCtrl.text.trim();
    String generated = '';

    switch (_announcementType) {
      case 'teacher_absent':
        final teacher = _teacherNameCtrl.text.trim();
        final startDate = _startDateCtrl.text.trim();
        final startTime = _startTimeCtrl.text.trim();
        final endDate = _endDateCtrl.text.trim();
        final endTime = _endTimeCtrl.text.trim();
        final replacement = _replacementNoteCtrl.text.trim();

        if (teacher.isNotEmpty) {
          generated = '$teacher sera absent';
          if (startDate.isNotEmpty) {
            if (endDate.isNotEmpty && startDate != endDate) {
              generated += ' du $startDate';
              if (startTime.isNotEmpty) generated += ' à $startTime';
              generated += ' au $endDate';
              if (endTime.isNotEmpty) generated += ' à $endTime';
            } else {
              generated += ' le $startDate';
              if (startTime.isNotEmpty && endTime.isNotEmpty) {
                generated += ' de $startTime à $endTime';
              } else if (startTime.isNotEmpty) {
                generated += ' à partir de $startTime';
              }
            }
          }
          generated += '.';
          if (replacement.isNotEmpty) generated += ' $replacement.';
        }
        break;

      case 'room_change':
        final subject = _subjectCtrl.text.trim();
        final date = _changeDateCtrl.text.trim();
        final time = _changeTimeCtrl.text.trim();

        // Get old and new room names
        String? oldRoomName;
        String? newRoomName;
        if (_selectedOldRoomId != null || _selectedRoomId != null) {
          final buildingAsync = ref.read(buildingProvider);
          if (buildingAsync.hasValue) {
            final buildingState = buildingAsync.value!;

            // Get old room name
            if (_selectedOldRoomId != null) {
              final oldRoom = buildingState.availableRooms.firstWhere(
                (r) => r.id == _selectedOldRoomId,
                orElse: () => RoomModel(id: '', floorId: '', name: ''),
              );
              if (oldRoom.name.isNotEmpty) oldRoomName = oldRoom.name;
            }

            // Get new room name
            if (_selectedRoomId != null) {
              final newRoom = buildingState.availableRooms.firstWhere(
                (r) => r.id == _selectedRoomId,
                orElse: () => RoomModel(id: '', floorId: '', name: ''),
              );
              if (newRoom.name.isNotEmpty) newRoomName = newRoom.name;
            }
          }
        }

        if (oldRoomName != null && newRoomName != null) {
          generated = 'Le cours';
          if (subject.isNotEmpty) generated += ' de $subject';
          generated +=
              ' est déplacé de la salle $oldRoomName vers la salle $newRoomName';
          if (date.isNotEmpty) {
            generated += ' le $date';
            if (time.isNotEmpty) generated += ' à $time';
          }
          generated += '.';
        }
        break;

      case 'exam':
        final subject = _subjectCtrl.text.trim();
        final date = _examDateCtrl.text.trim();
        final time = _examTimeCtrl.text.trim();
        final instructions = _instructionsCtrl.text.trim();

        // Get room name
        String? roomName;
        if (_selectedRoomId != null) {
          final buildingAsync = ref.read(buildingProvider);
          if (buildingAsync.hasValue) {
            final buildingState = buildingAsync.value!;
            final room = buildingState.availableRooms.firstWhere(
              (r) => r.id == _selectedRoomId,
              orElse: () => RoomModel(id: '', floorId: '', name: ''),
            );
            if (room.name.isNotEmpty) roomName = room.name;
          }
        }

        if (subject.isNotEmpty) {
          generated = 'Un examen de $subject';
          if (date.isNotEmpty) {
            generated += ' aura lieu le $date';
            if (time.isNotEmpty) generated += ' à $time';
          }
          if (roomName != null && roomName.isNotEmpty) {
            generated += ' en salle $roomName';
          }
          generated += '.';
          if (instructions.isNotEmpty) generated += ' $instructions.';
        }
        break;

      case 'retenue':
        final date = _examDateCtrl.text.trim();
        final time = _examTimeCtrl.text.trim();
        final instructions = _instructionsCtrl.text.trim();

        // Get room name
        String? roomName;
        if (_selectedRoomId != null) {
          final buildingAsync = ref.read(buildingProvider);
          if (buildingAsync.hasValue) {
            final buildingState = buildingAsync.value!;
            final room = buildingState.availableRooms.firstWhere(
              (r) => r.id == _selectedRoomId,
              orElse: () => RoomModel(id: '', floorId: '', name: ''),
            );
            if (room.name.isNotEmpty) roomName = room.name;
          }
        }

        generated = 'Une retenue est prévue';
        if (date.isNotEmpty) {
          generated += ' le $date';
          if (time.isNotEmpty) generated += ' à $time';
        }
        if (roomName != null && roomName.isNotEmpty) {
          generated += ' en salle $roomName';
        }
        generated += '.';
        if (instructions.isNotEmpty) generated += ' $instructions.';
        break;

      case 'closure':
        final reason = _reasonCtrl.text.trim();
        final from = _closedFromCtrl.text.trim();
        final to = _closedToCtrl.text.trim();
        final reopen = _reopenDateCtrl.text.trim();

        generated = 'L\'établissement sera fermé';
        if (reason.isNotEmpty) generated += ' pour $reason';
        if (from.isNotEmpty) {
          if (to.isNotEmpty) {
            generated += ' du $from au $to';
          } else {
            generated += ' le $from';
          }
        }
        generated += '.';
        if (reopen.isNotEmpty) generated += ' Réouverture prévue le $reopen.';
        break;

      case 'reminder':
        final dueDate = _dueDateCtrl.text.trim();
        final action = _actionRequiredCtrl.text.trim();

        if (action.isNotEmpty) {
          generated = 'Rappel: $action';
          if (dueDate.isNotEmpty) generated += '. Date limite: $dueDate';
          generated += '.';
        } else if (dueDate.isNotEmpty) {
          generated = 'Date limite: $dueDate.';
        }
        break;

      case 'trip':
        final destination = _destinationCtrl.text.trim();
        final departDate = _departureDateCtrl.text.trim();
        final departTime = _departureTimeCtrl.text.trim();
        final returnDate = _returnDateCtrl.text.trim();
        final returnTime = _returnTimeCtrl.text.trim();
        final meetingPoint = _meetingPointCtrl.text.trim();
        final cost = _tripCostCtrl.text.trim();
        final notes = _tripNotesCtrl.text.trim();

        if (destination.isNotEmpty) {
          generated = 'Une sortie à $destination est organisée';
          if (departDate.isNotEmpty) {
            generated += ' le $departDate';
            if (departTime.isNotEmpty) generated += ' à $departTime';
          }
          generated += '.';
          if (returnDate.isNotEmpty) {
            generated += ' Retour prévu le $returnDate';
            if (returnTime.isNotEmpty) generated += ' à $returnTime';
            generated += '.';
          }
          if (meetingPoint.isNotEmpty) {
            generated += ' Rendez-vous: $meetingPoint.';
          }
          if (cost.isNotEmpty) generated += ' Coût: $cost.';
          if (notes.isNotEmpty) generated += ' $notes';
        }
        break;

      case 'party':
        final eventName = _eventNameCtrl.text.trim();
        final eventDate = _eventDateCtrl.text.trim();
        final eventTime = _eventTimeCtrl.text.trim();
        final location = _eventLocationCtrl.text.trim();
        final dressCode = _dressCodeCtrl.text.trim();
        final notes = _eventNotesCtrl.text.trim();

        if (eventName.isNotEmpty) {
          generated = eventName;
          if (eventDate.isNotEmpty) {
            generated += ' aura lieu le $eventDate';
            if (eventTime.isNotEmpty) generated += ' à $eventTime';
          }
          generated += '.';
          if (location.isNotEmpty) generated += ' Lieu: $location.';
          if (dressCode.isNotEmpty) generated += ' Tenue: $dressCode.';
          if (notes.isNotEmpty) generated += ' $notes';
        }
        break;

      case 'payment':
        final paymentType = _paymentTypeCtrl.text.trim();
        final amount = _paymentAmountCtrl.text.trim();
        final dueDate = _paymentDueDateCtrl.text.trim();
        final method = _paymentMethodCtrl.text.trim();
        final notes = _paymentNotesCtrl.text.trim();

        final typeLabels = {
          'frais_scolarite': 'Frais de scolarité',
          'frais_inscription': 'Frais d\'inscription',
          'frais_sortie': 'Frais de sortie',
          'frais_materiel': 'Frais de matériel',
          'cotisation': 'Cotisation',
          'autre': 'Paiement',
        };
        final typeLabel = typeLabels[paymentType] ?? 'Paiement';

        generated = typeLabel;
        if (amount.isNotEmpty) generated += ' de $amount';
        generated += ' à régler';
        if (dueDate.isNotEmpty) generated += ' avant le $dueDate';
        generated += '.';
        if (method.isNotEmpty) generated += ' Mode de paiement: $method.';
        if (notes.isNotEmpty) generated += ' $notes';
        break;

      // ========== SANCTION TYPES (STUDENT MESSAGES) ==========
      case 'avertissement':
        final reason = _sanctionReasonCtrl.text.trim();
        final date = _sanctionDateCtrl.text.trim();
        final notes = _sanctionNotesCtrl.text.trim();

        generated = 'Un avertissement vous a été adressé';
        if (date.isNotEmpty) generated += ' le $date';
        if (reason.isNotEmpty) {
          generated += ' en raison de : $reason.';
        } else {
          generated += '.';
        }
        if (notes.isNotEmpty) generated += ' $notes';
        break;

      case 'exclusion_classe':
        final reason = _sanctionReasonCtrl.text.trim();
        final date = _sanctionDateCtrl.text.trim();
        final duration = _sanctionDurationCtrl.text.trim();
        final notes = _sanctionNotesCtrl.text.trim();

        generated = 'Une mesure d\'exclusion temporaire de cours a été prononcée';
        if (duration.isNotEmpty) {
          final plural =
              int.tryParse(duration) != null && int.parse(duration) > 1;
          final unitText = plural && _durationUnit == 'jour'
              ? 'jours'
              : _durationUnit;
          generated += ' pour une durée de $duration $unitText';
        }
        if (date.isNotEmpty) generated += ' à compter du $date';
        if (reason.isNotEmpty) {
          generated += ', suite aux faits suivants : $reason.';
        } else {
          generated += '.';
        }
        if (notes.isNotEmpty) generated += ' Travail à effectuer : $notes';
        break;

      case 'exclusion_etablissement':
        final reason = _sanctionReasonCtrl.text.trim();
        final date = _sanctionDateCtrl.text.trim();
        final duration = _sanctionDurationCtrl.text.trim();
        final notes = _sanctionNotesCtrl.text.trim();

        generated = 'Une exclusion temporaire de l\'établissement a été prononcée';
        if (duration.isNotEmpty) {
          final plural =
              int.tryParse(duration) != null && int.parse(duration) > 1;
          final unitText = plural && _durationUnit == 'jour'
              ? 'jours'
              : _durationUnit;
          generated += ' pour une durée de $duration $unitText';
        }
        if (date.isNotEmpty) generated += ' à compter du $date';
        if (reason.isNotEmpty) {
          generated += ' en raison de : $reason.';
        } else {
          generated += '.';
        }
        generated +=
            ' L\'accès à l\'établissement vous est strictement interdit durant cette période.';
        if (notes.isNotEmpty) generated += ' $notes';
        break;

      case 'convocation_parents':
        final reason = _sanctionReasonCtrl.text.trim();
        final meetingDate = _meetingDateCtrl.text.trim();
        final meetingTime = _meetingTimeCtrl.text.trim();
        final notes = _sanctionNotesCtrl.text.trim();

        generated = 'Vos parents ou votre représentant légal sont convoqués au sein de l\'établissement';
        if (meetingDate.isNotEmpty) {
          generated += ' le $meetingDate';
          if (meetingTime.isNotEmpty) generated += ' à $meetingTime';
        }
        if (reason.isNotEmpty) {
          generated += ' concernant : $reason.';
        } else {
          generated += '.';
        }
        generated += ' La présence d\'au moins un responsable légal est obligatoire.';
        if (notes.isNotEmpty) generated += ' Lieu : $notes';
        break;

      case 'conseil_discipline':
        final subject = _disciplineSubjectCtrl.text.trim();
        final meetingDate = _meetingDateCtrl.text.trim();
        final meetingTime = _meetingTimeCtrl.text.trim();
        final notes = _sanctionNotesCtrl.text.trim();

        generated = 'Vous êtes convoqué(e) à une séance du conseil de discipline';
        if (meetingDate.isNotEmpty) {
          generated += ' le $meetingDate';
          if (meetingTime.isNotEmpty) generated += ' à $meetingTime';
        }
        if (subject.isNotEmpty) {
          generated += ' concernant les faits suivants : $subject.';
        } else {
          generated += '.';
        }
        generated +=
            ' La présence de vos parents ou de votre représentant légal est obligatoire.';
        if (notes.isNotEmpty) generated += ' $notes';
        break;

      case 'exclusion_definitive':
        final reason = _sanctionReasonCtrl.text.trim();
        final date = _sanctionDateCtrl.text.trim();
        final notes = _sanctionNotesCtrl.text.trim();

        generated = 'Une exclusion définitive de l\'établissement a été prononcée à votre encontre';
        if (date.isNotEmpty) generated += ' à compter du $date';
        if (reason.isNotEmpty) {
          generated += ' en raison de : $reason.';
        } else {
          generated += '.';
        }
        generated +=
            ' Cette décision met fin à votre scolarité au sein de l\'établissement.';
        if (notes.isNotEmpty) generated += ' Modalités : $notes';
        break;
    }

    // Add extra remarks if provided
    if (extra.isNotEmpty) {
      generated = generated.isNotEmpty ? '$generated $extra' : extra;
    }

    return generated;
  }

  // Date picker helper
  Future<void> _pickDate(
    TextEditingController ctrl, {
    DateTime? initialDate,
  }) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 2)),
      locale: const Locale('fr', 'FR'),
      helpText: 'Sélectionner une date',
      cancelText: 'Annuler',
      confirmText: 'OK',
    );
    if (picked != null) {
      ctrl.text = DateFormat('d MMM yyyy', 'fr_FR').format(picked);
      setState(() {});
    }
  }

  // Time picker helper
  Future<void> _pickTime(
    TextEditingController ctrl, {
    TimeOfDay? initialTime,
  }) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime ?? TimeOfDay.now(),
      helpText: 'Sélectionner une heure',
      cancelText: 'Annuler',
      confirmText: 'OK',
    );
    if (picked != null) {
      ctrl.text =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      setState(() {});
    }
  }

  // Build a date field with picker
  // ========== REDESIGNED FORM HELPERS ==========

  InputDecoration _styledInputDecoration({
    required String hint,
    IconData? prefixIcon,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF6D4CF6), width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      prefixIcon: prefixIcon != null
          ? Icon(prefixIcon, size: 18, color: const Color(0xFF94A3B8))
          : null,
      suffixIcon: suffix,
    );
  }

  Widget _formFieldLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 6),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.slate400,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _formCardWrapper({required String title, required List<Widget> children}) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    );
  }

  Widget _buildDateField(
    TextEditingController ctrl,
    String label, {
    Color? iconColor,
    bool required = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _formFieldLabel(required ? '$label *' : label),
        TextFormField(
          controller: ctrl,
          readOnly: true,
          mouseCursor: SystemMouseCursors.click,
          style: const TextStyle(fontSize: 13),
          decoration: _styledInputDecoration(
            hint: 'Date',
            prefixIcon: Icons.calendar_today,
            suffix: ctrl.text.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.clear, size: 16, color: AppColors.slate400),
                    mouseCursor: SystemMouseCursors.click,
                    onPressed: () => setState(() => ctrl.clear()),
                  )
                : null,
          ),
          onTap: () => _pickDate(ctrl),
        ),
      ],
    );
  }

  Widget _buildTimeField(
    TextEditingController ctrl,
    String label, {
    Color? iconColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _formFieldLabel(label),
        TextFormField(
          controller: ctrl,
          readOnly: true,
          mouseCursor: SystemMouseCursors.click,
          style: const TextStyle(fontSize: 13),
          decoration: _styledInputDecoration(
            hint: 'Heure',
            prefixIcon: Icons.schedule,
            suffix: ctrl.text.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.clear, size: 16, color: AppColors.slate400),
                    mouseCursor: SystemMouseCursors.click,
                    onPressed: () => setState(() => ctrl.clear()),
                  )
                : null,
          ),
          onTap: () => _pickTime(ctrl),
        ),
      ],
    );
  }

  Widget _styledTextFormField({
    required TextEditingController controller,
    required String label,
    required String hint,
    IconData? prefixIcon,
    int maxLines = 1,
    List<TextInputFormatter>? inputFormatters,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    VoidCallback? onChanged,
  }) {
    final effectivePrefix = maxLines > 1 ? null : prefixIcon;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _formFieldLabel(label),
        TextFormField(
          controller: controller,
          style: const TextStyle(fontSize: 13),
          maxLines: maxLines,
          inputFormatters: inputFormatters,
          keyboardType: keyboardType,
          decoration: _styledInputDecoration(hint: hint, prefixIcon: effectivePrefix),
          validator: validator,
          onChanged: onChanged != null ? (_) => onChanged() : null,
        ),
      ],
    );
  }

  /// Premium subject dropdown that fetches from subjects provider
  Widget _buildSubjectDropdown({required String label, bool isRequired = true}) {
    final subjectsAsync = ref.watch(subjectsManagementProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _formFieldLabel(label),
        subjectsAsync.when(
          loading: () => Container(
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.slate50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.slate200),
            ),
            child: const Center(
              child: IosLoader.small(color: AppColors.secondary),
            ),
          ),
          error: (e, _) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.error.withOpacity(0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.error.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, size: 16, color: AppColors.error.withOpacity(0.7)),
                const SizedBox(width: 8),
                const Text('Unable to load subjects', style: TextStyle(fontSize: 12, color: AppColors.error)),
              ],
            ),
          ),
          data: (state) {
            final subjects = state.subjects;
            // If editing and the saved name isn't in the list, still show it
            final currentValue = _selectedSubjectName;
            final validValue = subjects.any((s) => s.name == currentValue) ? currentValue : null;
            return DropdownButtonFormField<String>(
              value: validValue,
              isExpanded: true,
              decoration: _styledInputDecoration(
                hint: 'Sélectionner une matière',
                prefixIcon: Icons.menu_book_rounded,
              ),
              style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
              borderRadius: BorderRadius.circular(10),
              items: subjects.map((s) => DropdownMenuItem<String>(
                value: s.name,
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: s.color != null
                          ? Color(int.parse(s.color!.replaceFirst('#', '0xFF')))
                          : AppColors.secondary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        s.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    if (s.code != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.slate100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          s.code!,
                          style: const TextStyle(fontSize: 10, color: AppColors.slate500, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ],
                ),
              )).toList(),
              onChanged: (v) {
                setState(() {
                  _selectedSubjectName = v;
                  _subjectCtrl.text = v ?? '';
                });
              },
              validator: isRequired ? (v) => v == null ? 'Matière requise' : null : null,
            );
          },
        ),
      ],
    );
  }

  /// Fuzzy string matching — normalizes text and checks for subsequence/contains
  double _fuzzyScore(String query, String target) {
    String normalize(String s) => s
        .toLowerCase()
        .replaceAll(RegExp(r'[àáâãäå]'), 'a')
        .replaceAll(RegExp(r'[èéêë]'), 'e')
        .replaceAll(RegExp(r'[ìíîï]'), 'i')
        .replaceAll(RegExp(r'[òóôõö]'), 'o')
        .replaceAll(RegExp(r'[ùúûü]'), 'u')
        .replaceAll(RegExp(r'[ç]'), 'c')
        .replaceAll(RegExp(r'[^a-z0-9 ]'), '')
        .trim();
    final q = normalize(query);
    final t = normalize(target);
    if (q.isEmpty) return 0;
    // Exact contains
    if (t.contains(q)) return 1.0;
    // Word prefix matching
    final qWords = q.split(' ').where((w) => w.isNotEmpty).toList();
    final tWords = t.split(' ').where((w) => w.isNotEmpty).toList();
    int matchedWords = 0;
    for (final qw in qWords) {
      if (tWords.any((tw) => tw.startsWith(qw) || tw.contains(qw))) {
        matchedWords++;
      }
    }
    if (matchedWords == qWords.length) return 0.9;
    if (matchedWords > 0) return 0.5 + (0.3 * matchedWords / qWords.length);
    // Subsequence check
    int qi = 0;
    for (int ti = 0; ti < t.length && qi < q.length; ti++) {
      if (t[ti] == q[qi]) qi++;
    }
    if (qi == q.length) return 0.4;
    // Levenshtein-like: short edit distance
    if ((q.length - matchedWords).abs() <= 2) return 0.3;
    return 0;
  }

  /// Smart teacher search widget with fuzzy matching
  Widget _buildTeacherSearchField() {
    final subjectsAsync = ref.watch(subjectsManagementProvider);
    final subjectsState = subjectsAsync.asData?.value;
    String? currentSpeciality = _selectedTeacherSpeciality;
    String? currentPhotoUrl = _selectedTeacherPhotoUrl;
    if (_selectedTeacherName != null && subjectsState != null) {
      final foundTeacher = subjectsState.teachers
          .where((t) => t.fullName.toLowerCase() == _selectedTeacherName!.toLowerCase())
          .firstOrNull;
      if (foundTeacher != null) {
        currentPhotoUrl ??= foundTeacher.photoUrl;
        if (currentSpeciality == null) {
          final assignment = subjectsState.teacherAssignments
              .where((a) => a.teacherId == foundTeacher.id)
              .firstOrNull;
          if (assignment != null) {
            final subj = subjectsState.subjects
                .where((s) => s.id == assignment.subjectId)
                .firstOrNull;
            currentSpeciality = subj?.name;
          }
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _formFieldLabel('ENSEIGNANT CONCERNÉ *'),
        // Selected teacher pill
        if (_selectedTeacherName != null) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
            ),
            child: Row(
              children: [
                UserAvatar(
                  name: _selectedTeacherName!,
                  photoUrl: currentPhotoUrl,
                  radius: 18,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _selectedTeacherName!,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        currentSpeciality ?? 'Enseignant',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: AppColors.slate500,
                        ),
                      ),
                    ],
                  ),
                ),
                InkWell(
                  onTap: () => setState(() {
                    _selectedTeacherName = null;
                    _selectedTeacherSpeciality = null;
                    _selectedTeacherPhotoUrl = null;
                    _teacherNameCtrl.clear();
                    _teacherSearchQuery = '';
                  }),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.slate100,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, size: 14, color: AppColors.slate500),
                  ),
                ),
              ],
            ),
          ),
        ],
        // Search field
        if (_selectedTeacherName == null) ...[
          TextFormField(
            controller: _teacherNameCtrl,
            style: const TextStyle(fontSize: 13),
            decoration: _styledInputDecoration(
              hint: 'Rechercher un enseignant...',
              prefixIcon: Icons.search_rounded,
            ).copyWith(
              suffixIcon: _teacherSearchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 16, color: AppColors.slate400),
                    onPressed: () => setState(() {
                      _teacherNameCtrl.clear();
                      _teacherSearchQuery = '';
                    }),
                  )
                : null,
            ),
            onChanged: (v) => setState(() => _teacherSearchQuery = v),
            validator: (v) => (v == null || v.isEmpty) && _selectedTeacherName == null ? 'Enseignant requis' : null,
          ),
          // Results dropdown
          if (_teacherSearchQuery.length >= 2)
            subjectsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Center(child: IosLoader.small()),
              ),
              error: (_, __) => const SizedBox.shrink(),
              data: (state) {
                final teachers = state.teachers.where((t) => t.isActive).toList();
                // Score and filter
                final scored = teachers
                    .map((t) {
                      final name = t.fullName;
                      final score = _fuzzyScore(_teacherSearchQuery, name);
                      return (teacher: t, name: name, score: score);
                    })
                    .where((e) => e.score > 0.2)
                    .toList()
                  ..sort((a, b) => b.score.compareTo(a.score));
                final results = scored.take(8).toList();
                if (results.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.slate50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.slate200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.search_off, size: 16, color: AppColors.slate400),
                          const SizedBox(width: 8),
                          const Text('Aucun enseignant trouvé', style: TextStyle(fontSize: 12, color: AppColors.slate400)),
                        ],
                      ),
                    ),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.slate200),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 4))],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Result count badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.slate50,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.secondary,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${results.length}',
                                  style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'résultat${results.length > 1 ? 's' : ''}',
                                style: const TextStyle(fontSize: 11, color: AppColors.slate500),
                              ),
                            ],
                          ),
                        ),
                        Flexible(
                          child: ListView.separated(
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount: results.length,
                            separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.slate100),
                            itemBuilder: (_, i) {
                              final r = results[i];
                              final assignment = state.teacherAssignments
                                  .where((a) => a.teacherId == r.teacher.id)
                                  .firstOrNull;
                              final subj = assignment != null
                                  ? state.subjects
                                      .where((s) => s.id == assignment.subjectId)
                                      .firstOrNull
                                  : null;
                              final teacherSpeciality = subj?.name ?? 'Enseignant';
                              return InkWell(
                                onTap: () {
                                  setState(() {
                                    _selectedTeacherName = r.name;
                                    _selectedTeacherSpeciality = teacherSpeciality;
                                    _selectedTeacherPhotoUrl = r.teacher.photoUrl;
                                    _teacherNameCtrl.text = r.name;
                                    _teacherSearchQuery = '';
                                  });
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  child: Row(
                                    children: [
                                      UserAvatar(
                                        name: r.name,
                                        photoUrl: r.teacher.photoUrl,
                                        radius: 15,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          r.name,
                                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      // Fuzzy confidence indicator
                                      Container(
                                        width: 6,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: r.score >= 0.8 ? AppColors.success : r.score >= 0.5 ? AppColors.accent : AppColors.slate300,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ],
    );
  }

  Widget _styledDropdown<T>({
    required String label,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
    IconData? prefixIcon,
    String? Function(T?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _formFieldLabel(label),
        DropdownButtonFormField<T>(
          value: value,
          decoration: _styledInputDecoration(
            hint: 'Sélectionner',
            prefixIcon: prefixIcon,
          ),
          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          borderRadius: BorderRadius.circular(10),
          items: items,
          onChanged: onChanged,
          validator: validator,
        ),
      ],
    );
  }

  @override
  void dispose() {
    _dialogScrollCtrl.dispose();
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    _senderLabelCtrl.dispose();
    _searchStudentCtrl.dispose();
    // Dispose payload controllers
    _teacherNameCtrl.dispose();
    _startDateCtrl.dispose();
    _startTimeCtrl.dispose();
    _endDateCtrl.dispose();
    _endTimeCtrl.dispose();
    _replacementNoteCtrl.dispose();
    _subjectCtrl.dispose();
    _oldRoomCtrl.dispose();
    _newRoomCtrl.dispose();
    _examDateCtrl.dispose();
    _examTimeCtrl.dispose();
    _changeDateCtrl.dispose();
    _changeTimeCtrl.dispose();
    _instructionsCtrl.dispose();
    _reasonCtrl.dispose();
    _closedFromCtrl.dispose();
    _closedToCtrl.dispose();
    _reopenDateCtrl.dispose();
    _dueDateCtrl.dispose();
    _actionRequiredCtrl.dispose();
    // Dispose new controllers
    _destinationCtrl.dispose();
    _departureDateCtrl.dispose();
    _departureTimeCtrl.dispose();
    _returnDateCtrl.dispose();
    _returnTimeCtrl.dispose();
    _meetingPointCtrl.dispose();
    _tripCostCtrl.dispose();
    _tripNotesCtrl.dispose();
    _eventNameCtrl.dispose();
    _eventDateCtrl.dispose();
    _eventTimeCtrl.dispose();
    _eventLocationCtrl.dispose();
    _dressCodeCtrl.dispose();
    _eventNotesCtrl.dispose();
    _paymentTypeCtrl.dispose();
    _paymentAmountCtrl.dispose();
    _paymentDueDateCtrl.dispose();
    _paymentMethodCtrl.dispose();
    _paymentNotesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadClasses() async {
    try {
      final notifier = ref.read(announcementsProvider.notifier);
      final data = await notifier.fetchClasses();
      setState(() {
        _classes = data;
        _classesLoading = false;
      });
    } catch (e) {
      setState(() => _classesLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.announcement != null;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        width: 720,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(isEditing),
              Flexible(
                child: SingleChildScrollView(
                  controller: _dialogScrollCtrl,
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. Type de publication
                      if (!isEditing) ...[
                        const Text(
                          '1. TYPE DE PUBLICATION',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: Color(0xFF4B5563),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildScopeSelector(),
                      ] else
                        _buildScopeBadge(),
                      const SizedBox(height: 32),
                      // 2. Détails de l'annonce
                      const Text(
                        '2. DÉTAILS DE L\'ANNONCE',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: Color(0xFF4B5563),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_scope == 'class' && !isEditing) ...[
                        _buildClassSelector(),
                        const SizedBox(height: 12),
                        _buildSenderSelector(),
                        const SizedBox(height: 16),
                      ],
                      if (_scope == 'student' && !isEditing)
                        _buildStudentSelector(),
                      _buildTypeSelector(),
                      const SizedBox(height: 8),
                      _buildTypeSpecificFields(),
                      const SizedBox(height: 24),
                      const SizedBox(height: 24),
                      if (_announcementType == 'general') ...[
                        _buildStyledField(
                          label: 'Titre de l\'annonce',
                          child: TextFormField(
                            controller: _titleCtrl,
                            style: const TextStyle(fontSize: 14),
                            decoration: InputDecoration(
                              hintText: 'Réunion de parents d\'élèves...',
                              hintStyle: TextStyle(color: AppColors.slate400, fontSize: 14),
                              filled: true,
                              fillColor: AppColors.slate50,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: AppColors.border),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: AppColors.border),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: AppColors.secondary, width: 2),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            ),
                            inputFormatters: [CapitalizeWordsFormatter()],
                            validator: (v) => v == null || v.trim().isEmpty ? 'Le titre est requis' : null,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildStyledField(
                          label: 'Message',
                          child: TextFormField(
                            controller: _contentCtrl,
                            style: const TextStyle(fontSize: 14),
                            decoration: InputDecoration(
                              hintText: 'Saisir le contenu détaillé de l\'annonce ici...',
                              hintStyle: TextStyle(color: AppColors.slate400, fontSize: 14),
                              filled: true,
                              fillColor: AppColors.slate50,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: AppColors.border),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: AppColors.border),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: AppColors.secondary, width: 2),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              alignLabelWithHint: true,
                            ),
                            maxLines: 4,
                            validator: (v) => v == null || v.trim().isEmpty ? 'Le contenu est requis' : null,
                          ),
                        ),
                      ],
                      if (_announcementType != 'general') ...[
                        _buildStyledField(
                          label: 'Remarques supplémentaires (optionnel)',
                          child: TextFormField(
                            controller: _contentCtrl,
                            style: const TextStyle(fontSize: 14),
                            decoration: InputDecoration(
                              hintText: 'Ajouter des détails si nécessaire...',
                              hintStyle: TextStyle(color: AppColors.slate400, fontSize: 14),
                              filled: true,
                              fillColor: AppColors.slate50,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: AppColors.border),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: AppColors.border),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: AppColors.secondary, width: 2),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              alignLabelWithHint: true,
                            ),
                            maxLines: 3,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      _buildOptions(),
                      const SizedBox(height: 24),
                      // 3. Pièces jointes
                      Text('3. PIÈCES JOINTES',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                              color: AppColors.slate400)),
                      const SizedBox(height: 16),
                      _buildAttachmentsSection(),
                      const SizedBox(height: 24),
                      _buildPreview(),
                    ],
                  ),
                ),
              ),
              _buildActions(isEditing),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStyledField({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        child,
      ],
    );
  }

  Widget _buildHeader(bool isEditing) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.slate100)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.secondary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.campaign, color: AppColors.secondary, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEditing ? 'Modifier l\'annonce' : 'Nouvelle annonce',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  'Créez une publication pour votre établissement',
                  style: TextStyle(fontSize: 13, color: AppColors.slate500),
                ),
              ],
            ),
          ),
          InkWell(
            mouseCursor: SystemMouseCursors.click,
            onTap: () => Navigator.pop(context),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.transparent,
              ),
              child: Icon(Icons.close, size: 22, color: AppColors.slate400),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScopeSelector() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.slate100.withOpacity(0.8),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildScopeTab('global', 'Notification'),
          _buildScopeTab('class', 'Message classe'),
          _buildScopeTab('student', 'Message élève'),
        ],
      ),
    );
  }

  Widget _buildScopeTab(String value, String label) {
    final selected = _scope == value;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => setState(() {
          _scope = value;
          _selectedClassId = null;
          _selectedStudentId = null;
          if (_scope == 'global') _senderType = 'administration';
          if (_scope == 'student') {
            if (!const ['avertissement', 'retenue', 'exclusion_classe', 'exclusion_etablissement', 'convocation_parents', 'conseil_discipline', 'exclusion_definitive'].contains(_announcementType)) {
              _announcementType = 'avertissement';
            }
          } else {
            if (!const ['general', 'teacher_absent', 'room_change', 'exam', 'retenue', 'reminder', 'trip', 'party', 'payment', 'closure'].contains(_announcementType)) {
              _announcementType = 'general';
            }
          }
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            boxShadow: selected
                ? [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 1))]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? AppColors.textPrimary : AppColors.textTertiary,
            ),
          ),
        ),
      ),
    );
  }

  String _getFullNiveauName(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '';
    final lower = s.toLowerCase();
    if (lower.startsWith('1ère') || lower.startsWith('1ere') || lower == '1') {
      return '1ère année secondaire';
    } else if (lower.startsWith('2ème') || lower.startsWith('2eme') || lower == '2') {
      return '2ème année secondaire';
    } else if (lower.startsWith('3ème') || lower.startsWith('3eme') || lower == '3') {
      return '3ème année secondaire';
    } else if (lower.startsWith('4ème') || lower.startsWith('4eme') || lower.contains('bac') || lower == '4') {
      return 'Baccalauréat';
    } else if (lower.startsWith('7')) {
      return '7ème année de base';
    } else if (lower.startsWith('8')) {
      return '8ème année de base';
    } else if (lower.startsWith('9')) {
      return '9ème année de base';
    }
    return s;
  }

  Widget _buildScopeBadge() {
    if (_scope == 'student') {
      final a = widget.announcement;
      String studentName = 'Élève';
      final payloadName = a?.payload['student_name']?.toString() ??
          a?.payload['target_student_name']?.toString() ??
          a?.payload['student']?['full_name']?.toString() ??
          a?.payload['student']?['name']?.toString();
      if (payloadName != null && payloadName.trim().isNotEmpty) {
        studentName = payloadName.trim();
      } else if (a != null) {
        final match = RegExp(r'\*\*@([^*]+)\*\*').firstMatch(a.content);
        if (match != null && match.group(1)?.trim().isNotEmpty == true) {
          studentName = match.group(1)!.trim();
        } else {
          final match2 = RegExp(r'@([A-Za-zÀ-ÿ\s\-]+)').firstMatch(a.content);
          if (match2 != null && match2.group(1)?.trim().isNotEmpty == true) {
            studentName = match2.group(1)!.trim();
          }
        }
      }

      final studentPhoto = _loadedStudentInfo?['photo_url']?.toString() ??
          a?.payload['student_photo_url']?.toString() ??
          a?.payload['photo_url']?.toString() ??
          a?.payload['student']?['photo_url']?.toString();
      final studentGender = _loadedStudentInfo?['gender']?.toString() ??
          a?.payload['student_gender']?.toString() ??
          a?.payload['gender']?.toString() ??
          a?.payload['student']?['gender']?.toString();

      String? className = a?.className;
      String? rawLevel = a?.payload['student_level']?.toString() ??
          a?.payload['level']?.toString() ??
          a?.payload['niveau']?.toString();

      final enrollments = _loadedStudentInfo?['enrollments'] as List?;
      if (enrollments != null && enrollments.isNotEmpty) {
        final classInfo = enrollments.first['classes'] as Map<String, dynamic>?;
        if (classInfo != null) {
          if (className == null || className.isEmpty) {
            className = classInfo['name']?.toString();
          }
          final nivInfo = classInfo['niveaux'] as Map<String, dynamic>?;
          if (nivInfo != null && nivInfo['name'] != null) {
            rawLevel = nivInfo['name'].toString();
          }
        }
      }

      if ((rawLevel == null || rawLevel.isEmpty) && className != null && className.isNotEmpty) {
        final matchedClass = _classes.firstWhere(
          (c) => c['name']?.toString() == className,
          orElse: () => {},
        );
        if (matchedClass.isNotEmpty) {
          final niv = matchedClass['niveaux'] as Map<String, dynamic>?;
          if (niv != null && niv['name'] != null) {
            rawLevel = niv['name'].toString();
          } else if (matchedClass['niveau_name'] != null) {
            rawLevel = matchedClass['niveau_name'].toString();
          }
        }
      }

      if ((rawLevel == null || rawLevel.isEmpty) && className != null && className.isNotEmpty) {
        rawLevel = className;
      }

      final niveauName = (rawLevel != null && rawLevel.isNotEmpty) ? _getFullNiveauName(rawLevel) : '';

      final classAndNiveau = [
        if (className != null && className.isNotEmpty) className,
        if (niveauName.isNotEmpty) niveauName,
      ].join(' • ');

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            UserAvatar(
              name: studentName,
              photoUrl: studentPhoto,
              gender: studentGender,
              radius: 18,
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  studentName,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (classAndNiveau.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    classAndNiveau,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      );
    }

    final Color color;
    final IconData icon;
    final String label;
    final String? extra;

    switch (_scope) {
      case 'class':
        color = const Color(0xFF0EA5E9);
        icon = Icons.groups_outlined;
        label = 'Message de classe';
        extra = widget.announcement?.className;
        break;
      default:
        color = const Color(0xFF655DD5);
        icon = Icons.notifications_none_rounded;
        label = 'Notification';
        extra = null;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.08), color.withOpacity(0.03)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 17),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
          if (extra != null) ...[
            Container(
              width: 1, height: 16,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              color: color.withOpacity(0.2),
            ),
            Text(
              extra,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildClassSelector() {
    // Group classes by niveau
    final Map<String, List<Map<String, dynamic>>> groupedClasses = {};
    final Map<String, int> niveauOrder = {};

    for (final c in _classes) {
      final niveau = c['niveaux'] as Map<String, dynamic>?;
      final niveauName =
          niveau?['name'] as String? ?? c['level'] as String? ?? 'Sans niveau';
      final displayOrder = niveau?['display_order'] as int? ?? 999;
      groupedClasses.putIfAbsent(niveauName, () => []).add(c);
      niveauOrder[niveauName] = displayOrder;
    }

    // Sort niveaux by display order
    final sortedNiveaux = groupedClasses.keys.toList()
      ..sort(
        (a, b) => (niveauOrder[a] ?? 999).compareTo(niveauOrder[b] ?? 999),
      );

    // Build dropdown items with headers showing student count per niveau
    final List<DropdownMenuItem<String>> items = [];
    for (final niveauName in sortedNiveaux) {
      final classes = groupedClasses[niveauName]!;
      final totalStudents = classes.fold<int>(
        0,
        (sum, c) => sum + (c['student_count'] as int? ?? 0),
      );

      // Add a disabled header item for the niveau
      items.add(
        DropdownMenuItem<String>(
          enabled: false,
          value: 'header_$niveauName',
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border.withOpacity(0.5))),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(Icons.school, size: 14, color: AppColors.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    niveauName.toUpperCase(),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                      fontSize: 11,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.primary.withOpacity(0.1), AppColors.primary.withOpacity(0.05)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.people_alt_outlined, size: 12, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text(
                        '$totalStudents',
                        style: TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      // Add class items under this niveau
      for (final c in classes) {
        final studentCount = c['student_count'] as int? ?? 0;
        items.add(
          DropdownMenuItem<String>(
            value: c['id'] as String,
            child: Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: AppColors.secondary.withOpacity(0.5),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      c['name'] as String? ?? '',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.slate100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.person_outline, size: 12, color: AppColors.slate500),
                        const SizedBox(width: 3),
                        Text(
                          '$studentCount',
                          style: TextStyle(fontSize: 11, color: AppColors.slate600, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    }

    // Find selected class name for the chip display
    String? selectedClassName;
    int? selectedStudentCount;
    if (_selectedClassId != null) {
      for (final c in _classes) {
        if (c['id'] == _selectedClassId) {
          selectedClassName = c['name'] as String?;
          selectedStudentCount = c['student_count'] as int?;
          break;
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _formFieldLabel('CLASSE DESTINATAIRE *'),
        const SizedBox(height: 2),
        _classesLoading
            ? Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  children: [
                    IosLoader.small(color: AppColors.secondary),
                    const SizedBox(width: 12),
                    Text('Chargement des classes...', style: TextStyle(fontSize: 13, color: AppColors.slate400)),
                  ],
                ),
              )
            : _classes.isEmpty
            ? Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.warningSoft,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.warning.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Aucune classe disponible',
                            style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.warning, fontSize: 13),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Créez des classes dans la section "Classes".',
                            style: TextStyle(color: AppColors.warning.withOpacity(0.8), fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Selected class chip
                  if (_selectedClassId != null && selectedClassName != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [AppColors.secondary.withOpacity(0.08), AppColors.secondary.withOpacity(0.03)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppColors.secondary.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.check_circle, color: AppColors.secondary, size: 18),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  selectedClassName!,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.secondary,
                                    fontSize: 14,
                                  ),
                                ),
                                if (selectedStudentCount != null)
                                  Text(
                                    '$selectedStudentCount élève(s) dans cette classe',
                                    style: TextStyle(fontSize: 11, color: AppColors.secondary.withOpacity(0.7)),
                                  ),
                              ],
                            ),
                          ),
                          InkWell(
                            onTap: () => setState(() => _selectedClassId = null),
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: AppColors.secondary.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.close, size: 16, color: AppColors.secondary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  DropdownButtonFormField<String>(
                    value: _selectedClassId,
                    decoration: _styledInputDecoration(
                      hint: 'Rechercher et sélectionner une classe...',
                      prefixIcon: Icons.class_outlined,
                    ),
                    style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                    borderRadius: BorderRadius.circular(10),
                    isExpanded: true,
                    menuMaxHeight: 450,
                    items: items,
                    onChanged: (v) {
                      if (v != null && !v.startsWith('header_')) {
                        setState(() => _selectedClassId = v);
                      }
                    },
                    validator: (v) =>
                        _scope == 'class' && (v == null || v.startsWith('header_'))
                        ? 'Sélectionnez une classe'
                        : null,
                  ),
                ],
              ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildStudentSelector() {
    return Consumer(
      builder: (context, ref, child) {
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: SupabaseConfig.client
              .from('users')
              .select('id, full_name, phone, student_code, photo_url, gender, enrollments:enrollments(class_id, classes:classes(name, niveau_id, niveaux:niveaux(name)))')
              .eq('role', 'student')
              .order('full_name'),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  children: [
                    IosLoader.small(color: AppColors.secondary),
                    const SizedBox(width: 12),
                    Text('Chargement des élèves...', style: TextStyle(fontSize: 13, color: AppColors.slate400)),
                  ],
                ),
              );
            }

            if (snapshot.hasError || !snapshot.hasData) {
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.errorSoft,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.error.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.error.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.error_outline, color: AppColors.error, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Unable to load students',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          if (snapshot.hasError)
                            Text(
                              UserFriendlyError.format(
                                snapshot.error,
                                fallback: 'Please try refreshing the page.',
                              ),
                              style: TextStyle(fontSize: 11, color: AppColors.error.withOpacity(0.7)),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }

            final allStudents = snapshot.data!;
            if (allStudents.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.warningSoft,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.warning.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text('Aucun élève disponible', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                    ),
                  ],
                ),
              );
            }

            return StatefulBuilder(
              builder: (context, setLocalState) {
                final query = _searchStudentCtrl.text.toLowerCase();
                final filteredStudents = query.isEmpty
                    ? allStudents
                    : allStudents.where((student) {
                        final fullName = (student['full_name'] ?? '').toLowerCase();
                        final phone = (student['phone'] ?? '').toLowerCase();
                        final studentCode = (student['student_code'] ?? '').toLowerCase();
                        return fullName.contains(query) ||
                            phone.contains(query) ||
                            studentCode.contains(query);
                      }).toList();

                // Get selected student info
                Map<String, dynamic>? selectedStudent;
                if (_selectedStudentId != null) {
                  for (final s in allStudents) {
                    if (s['id'] == _selectedStudentId) {
                      selectedStudent = s;
                      break;
                    }
                  }
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Selected student card
                    if (selectedStudent != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
                        ),
                        child: Row(
                          children: [
                            UserAvatar(
                              name: selectedStudent['full_name'] ?? '?',
                              photoUrl: selectedStudent['photo_url'] as String?,
                              gender: selectedStudent['gender'] as String?,
                              radius: 18,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    selectedStudent['full_name'] ?? 'Élève sélectionné',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF111827),
                                      fontSize: 14,
                                    ),
                                  ),
                                  Builder(
                                    builder: (_) {
                                      final enrollments = selectedStudent?['enrollments'] as List?;
                                      String? sClassName;
                                      String? sNiveauName;
                                      if (enrollments != null && enrollments.isNotEmpty) {
                                        final classInfo = enrollments.first['classes'] as Map<String, dynamic>?;
                                        sClassName = classInfo?['name'] as String?;
                                        final nivInfo = classInfo?['niveaux'] as Map<String, dynamic>?;
                                        sNiveauName = nivInfo?['name'] as String?;
                                      }
                                      if ((sNiveauName == null || sNiveauName.isEmpty) && sClassName != null && sClassName.isNotEmpty) {
                                        sNiveauName = _getFullNiveauName(sClassName);
                                      } else if (sNiveauName != null && sNiveauName.isNotEmpty) {
                                        sNiveauName = _getFullNiveauName(sNiveauName);
                                      }
                                      final parts = [
                                        if (sClassName != null && sClassName.isNotEmpty) sClassName,
                                        if (sNiveauName != null && sNiveauName.isNotEmpty) sNiveauName,
                                      ];
                                      final subtext = parts.isNotEmpty
                                          ? parts.join(' • ')
                                          : (selectedStudent?['student_code'] ?? '').toString();

                                      if (subtext.isEmpty) return const SizedBox.shrink();
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          subtext,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF64748B),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                            InkWell(
                              mouseCursor: SystemMouseCursors.click,
                              onTap: () => setState(() => _selectedStudentId = null),
                              borderRadius: BorderRadius.circular(20),
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 18,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Search field
                    TextField(
                      controller: _searchStudentCtrl,
                      onChanged: (v) => setLocalState(() {}),
                      style: const TextStyle(fontSize: 13),
                      decoration: _styledInputDecoration(
                        hint: 'Rechercher par nom, téléphone, code...',
                        prefixIcon: Icons.search,
                        suffix: _searchStudentCtrl.text.isNotEmpty
                            ? IconButton(
                                mouseCursor: SystemMouseCursors.click,
                                icon: Icon(Icons.clear, size: 16, color: AppColors.slate400),
                                onPressed: () {
                                  _searchStudentCtrl.clear();
                                  setLocalState(() {});
                                },
                              )
                            : null,
                      ),
                    ),

                    // Result count badge
                    if (_searchStudentCtrl.text.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: filteredStudents.isNotEmpty
                                  ? AppColors.secondary.withOpacity(0.1)
                                  : AppColors.slate100,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              filteredStudents.isEmpty
                                  ? 'Aucun résultat'
                                  : '${filteredStudents.length} résultat(s)',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: filteredStudents.isNotEmpty ? AppColors.secondary : AppColors.slate400,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Student results list
                      Container(
                        constraints: const BoxConstraints(maxHeight: 300),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: filteredStudents.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.search_off, size: 36, color: AppColors.slate300),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Aucun élève trouvé pour "$query"',
                                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              )
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: ListView.separated(
                                  shrinkWrap: true,
                                  itemCount: filteredStudents.length,
                                  separatorBuilder: (_, __) => Divider(
                                    height: 1,
                                    color: AppColors.border.withOpacity(0.5),
                                  ),
                                  itemBuilder: (context, index) {
                                    final student = filteredStudents[index];
                                    final studentId = student['id'] as String;
                                    final name = student['full_name'] ?? '';
                                    final studentCode = student['student_code'] ?? '';
                                    final phone = student['phone'] ?? '';
                                    final isSelected = _selectedStudentId == studentId;

                                    return Material(
                                      color: isSelected
                                          ? AppColors.secondary.withOpacity(0.06)
                                          : Colors.transparent,
                                      child: InkWell(
                                        mouseCursor: SystemMouseCursors.click,
                                        onTap: () {
                                          setState(() {
                                            _selectedStudentId = isSelected ? null : studentId;
                                          });
                                          if (!isSelected) {
                                            _searchStudentCtrl.clear();
                                            setLocalState(() {});
                                          }
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                          child: Row(
                                            children: [
                                              // Avatar
                                              UserAvatar(
                                                name: name,
                                                photoUrl: student['photo_url'] as String?,
                                                gender: student['gender'] as String?,
                                                radius: 19,
                                              ),
                                              const SizedBox(width: 12),
                                              // Info
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      name,
                                                      style: TextStyle(
                                                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                                        fontSize: 13,
                                                        color: isSelected ? AppColors.secondary : AppColors.textPrimary,
                                                      ),
                                                    ),
                                                    if (studentCode.isNotEmpty || phone.isNotEmpty) ...[
                                                      const SizedBox(height: 2),
                                                      Row(
                                                        children: [
                                                          if (studentCode.isNotEmpty) ...[
                                                            Icon(Icons.badge_outlined, size: 11, color: AppColors.slate400),
                                                            const SizedBox(width: 3),
                                                            Text(
                                                              studentCode,
                                                              style: TextStyle(fontSize: 11, color: AppColors.slate500),
                                                            ),
                                                          ],
                                                          if (studentCode.isNotEmpty && phone.isNotEmpty)
                                                            Padding(
                                                              padding: const EdgeInsets.symmetric(horizontal: 6),
                                                              child: Text('·', style: TextStyle(color: AppColors.slate300)),
                                                            ),
                                                          if (phone.isNotEmpty) ...[
                                                            Icon(Icons.phone_outlined, size: 11, color: AppColors.slate400),
                                                            const SizedBox(width: 3),
                                                            Text(
                                                              phone,
                                                              style: TextStyle(fontSize: 11, color: AppColors.slate500),
                                                            ),
                                                          ],
                                                        ],
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                              // Check icon
                                              if (isSelected)
                                                Container(
                                                  padding: const EdgeInsets.all(4),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.secondary.withOpacity(0.15),
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: Icon(Icons.check, size: 16, color: AppColors.secondary),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                      ),
                    ],

                    if (_scope == 'student' && _selectedStudentId == null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, size: 14, color: AppColors.error.withOpacity(0.7)),
                            const SizedBox(width: 6),
                            Text(
                              'Veuillez sélectionner un élève',
                              style: TextStyle(
                                color: AppColors.error,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 20),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildTypeSelector() {
    final types = _scope == 'student'
        ? [
            ('avertissement', 'Avertissement', Icons.warning_amber, AppColors.warning),
            ('retenue', 'Retenue', Icons.access_time, const Color(0xFFDC2626)),
            ('exclusion_classe', 'Exclusion classe', Icons.no_meeting_room, AppColors.accent),
            ('exclusion_etablissement', 'Exclusion étab.', Icons.block, AppColors.error),
            ('convocation_parents', 'Convocation', Icons.family_restroom, AppColors.chart5),
            ('conseil_discipline', 'Conseil disc.', Icons.gavel, AppColors.secondary),
            ('exclusion_definitive', 'Exclusion déf.', Icons.cancel, AppColors.textPrimary),
          ]
        : [
            ('general', 'Général', Icons.campaign, AppColors.chart6),
            ('teacher_absent', 'Absence prof', Icons.person_off, AppColors.warning),
            ('room_change', 'Changement salle', Icons.meeting_room, AppColors.secondary),
            ('exam', 'Examen', Icons.assignment, AppColors.error),
            ('retenue', 'Retenue', Icons.access_time, const Color(0xFFDC2626)),
            ('reminder', 'Rappel', Icons.alarm, AppColors.primary),
            ('trip', 'Sortie', Icons.directions_bus, AppColors.success),
            ('party', 'Événement', Icons.celebration, AppColors.chart4),
            ('payment', 'Paiement', Icons.payment, AppColors.chart5),
            ('closure', 'Fermeture', Icons.lock, AppColors.slate300),
          ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GridView.count(
          crossAxisCount: 5,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.0,
          children: types.map((t) {
            final selected = _announcementType == t.$1;
            return InkWell(
              mouseCursor: SystemMouseCursors.click,
              onTap: () => setState(() => _announcementType = t.$1),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected ? AppColors.secondary : AppColors.border,
                    width: selected ? 2 : 1,
                  ),
                  color: selected ? AppColors.secondary.withOpacity(0.05) : Colors.white,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(t.$3, size: 16, color: selected ? AppColors.secondary : t.$4),
                    const SizedBox(height: 4),
                    Text(
                      t.$2,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: selected ? AppColors.secondary : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildTypeChip(
    String value,
    String label,
    IconData icon,
    Color color,
  ) {
    final selected = _announcementType == value;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: FilterChip(
        selected: selected,
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: selected ? AppColors.textOnPrimary : color),
            const SizedBox(width: 6),
            Text(label),
          ],
        ),
        onSelected: (_) {
          setState(() => _announcementType = value);
        },
        selectedColor: color,
        checkmarkColor: AppColors.textOnPrimary,
        labelStyle: TextStyle(color: selected ? AppColors.textOnPrimary : AppColors.textPrimary),
      ),
    );
  }

  /// Type-specific form fields based on announcement type
  Widget _buildTypeSpecificFields() {
    switch (_announcementType) {
      case 'teacher_absent':
        return _buildTeacherAbsentForm();
      case 'room_change':
        return _buildRoomChangeForm();
      case 'exam':
        return _buildExamForm();
      case 'retenue':
        return _buildRetenueForm();
      case 'closure':
        return _buildClosureForm();
      case 'reminder':
        return _buildReminderForm();
      case 'trip':
        return _buildTripForm();
      case 'party':
        return _buildPartyForm();
      case 'payment':
        return _buildPaymentForm();
      case 'avertissement':
        return _buildAvertissementForm();
      case 'exclusion_classe':
        return _buildExclusionClasseForm();
      case 'exclusion_etablissement':
        return _buildExclusionEtablissementForm();
      case 'convocation_parents':
        return _buildConvocationParentsForm();
      case 'conseil_discipline':
        return _buildConseilDisciplineForm();
      case 'exclusion_definitive':
        return _buildExclusionDefinitiveForm();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildTeacherAbsentForm() {
    return _formCardWrapper(
      title: 'Détails de l\'absence',
      children: [
        _buildTeacherSearchField(),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _formFieldLabel('DÉBUT DE L\'ABSENCE'),
                  Row(
                    children: [
                      Expanded(child: _buildDateField(_startDateCtrl, '')),
                      const SizedBox(width: 8),
                      Expanded(child: _buildTimeField(_startTimeCtrl, '')),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _formFieldLabel('FIN DE L\'ABSENCE'),
                  Row(
                    children: [
                      Expanded(child: _buildDateField(_endDateCtrl, '')),
                      const SizedBox(width: 8),
                      Expanded(child: _buildTimeField(_endTimeCtrl, '')),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _styledTextFormField(
          controller: _replacementNoteCtrl,
          label: 'INFORMATIONS COMPLÉMENTAIRES',
          hint: 'Note de remplacement ou détails supplémentaires...',
          maxLines: 3,
        ),
      ],
    );
  }

  Widget _buildRoomChangeForm() {
    return _formCardWrapper(
      title: 'Détails du changement',
      children: [
        // Subject dropdown from data
        _buildSubjectDropdown(label: 'MATIÈRE', isRequired: false),
        const SizedBox(height: 16),
        _formFieldLabel('ANCIENNE SALLE'),
        _buildRoomSelectorForType(isOldRoom: true),
        const SizedBox(height: 12),
        Center(child: Icon(Icons.arrow_downward_rounded, color: AppColors.secondary, size: 22)),
        const SizedBox(height: 12),
        _formFieldLabel('NOUVELLE SALLE'),
        _buildRoomSelectorForType(isOldRoom: false),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _buildDateField(_changeDateCtrl, 'DATE')),
            const SizedBox(width: 12),
            Expanded(child: _buildTimeField(_changeTimeCtrl, 'HEURE')),
          ],
        ),
      ],
    );
  }

  Widget _buildExamForm() {
    return _formCardWrapper(
      title: 'Détails de l\'examen',
      children: [
        _buildSubjectDropdown(label: 'MATIÈRE *', isRequired: true),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _buildDateField(_examDateCtrl, 'DATE')),
            const SizedBox(width: 12),
            Expanded(child: _buildTimeField(_examTimeCtrl, 'HEURE')),
          ],
        ),
        const SizedBox(height: 16),
        _buildRoomSelector(),
        const SizedBox(height: 16),
        _styledTextFormField(
          controller: _instructionsCtrl,
          label: 'INSTRUCTIONS',
          hint: 'Ex: Apporter calculatrice',
          prefixIcon: Icons.info_outline,
        ),
      ],
    );
  }

  Widget _buildRetenueForm() {
    return _formCardWrapper(
      title: 'Détails de la retenue',
      children: [
        Row(
          children: [
            Expanded(child: _buildDateField(_examDateCtrl, 'DATE DE LA RETENUE')),
            const SizedBox(width: 12),
            Expanded(child: _buildTimeField(_examTimeCtrl, 'HEURE')),
          ],
        ),
        const SizedBox(height: 16),
        _buildRoomSelector(),
        const SizedBox(height: 16),
        _styledTextFormField(
          controller: _instructionsCtrl,
          label: 'TRAVAIL ACADÉMIQUE / TÂCHE DISCIPLINAIRE',
          hint: 'Ex: Rédiger un devoir, Copier le règlement',
          prefixIcon: Icons.assignment,
          maxLines: 3,
        ),
      ],
    );
  }

  Widget _buildClosureForm() {
    return _formCardWrapper(
      title: 'Détails de la fermeture',
      children: [
        _styledTextFormField(
          controller: _reasonCtrl,
          label: 'RAISON DE LA FERMETURE',
          hint: 'Ex: Travaux, Journée pédagogique',
          prefixIcon: Icons.help_outline,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _buildDateField(_closedFromCtrl, 'FERMÉ DU')),
            const SizedBox(width: 12),
            Expanded(child: _buildDateField(_closedToCtrl, 'AU')),
          ],
        ),
        const SizedBox(height: 16),
        _buildDateField(_reopenDateCtrl, 'DATE DE RÉOUVERTURE'),
      ],
    );
  }

  Widget _buildReminderForm() {
    return _formCardWrapper(
      title: 'Détails du rappel',
      children: [
        _buildDateField(_dueDateCtrl, 'DATE LIMITE', required: true),
        const SizedBox(height: 16),
        _styledTextFormField(
          controller: _actionRequiredCtrl,
          label: 'ACTION REQUISE',
          hint: 'Ex: Inscription aux examens',
        ),
      ],
    );
  }

  Widget _buildTripForm() {
    return _formCardWrapper(
      title: 'Détails de la sortie/voyage',
      children: [
        _styledTextFormField(
          controller: _destinationCtrl,
          label: 'DESTINATION',
          hint: 'Destination *',
          prefixIcon: Icons.place,
          inputFormatters: [CapitalizeWordsFormatter()],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _formFieldLabel('DÉPART'),
                  Row(
                    children: [
                      Expanded(child: _buildDateField(_departureDateCtrl, '')),
                      const SizedBox(width: 8),
                      Expanded(child: _buildTimeField(_departureTimeCtrl, '')),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _formFieldLabel('RETOUR'),
                  Row(
                    children: [
                      Expanded(child: _buildDateField(_returnDateCtrl, '')),
                      const SizedBox(width: 8),
                      Expanded(child: _buildTimeField(_returnTimeCtrl, '')),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _styledTextFormField(
          controller: _meetingPointCtrl,
          label: 'POINT DE RENDEZ-VOUS',
          hint: 'Ex: Devant l\'entrée principale',
          prefixIcon: Icons.location_on,
          inputFormatters: [CapitalizeWordsFormatter()],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _styledTextFormField(
                controller: _tripCostCtrl,
                label: 'COÛT (OPTIONNEL)',
                hint: 'Ex: 150 DH',
                prefixIcon: Icons.attach_money,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _styledTextFormField(
          controller: _tripNotesCtrl,
          label: 'NOTES',
          hint: 'Informations supplémentaires...',
          maxLines: 2,
        ),
      ],
    );
  }

  Widget _buildPartyForm() {
    return _formCardWrapper(
      title: 'Détails de l\'événement',
      children: [
        _styledTextFormField(
          controller: _eventNameCtrl,
          label: 'NOM DE L\'ÉVÉNEMENT',
          hint: 'Ex: Fête de fin d\'année *',
          prefixIcon: Icons.event,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _buildDateField(_eventDateCtrl, 'DATE')),
            const SizedBox(width: 12),
            Expanded(child: _buildTimeField(_eventTimeCtrl, 'HEURE')),
          ],
        ),
        const SizedBox(height: 16),
        _styledTextFormField(
          controller: _eventLocationCtrl,
          label: 'LIEU',
          hint: 'Ex: Salle des fêtes',
          prefixIcon: Icons.location_on,
          inputFormatters: [CapitalizeWordsFormatter()],
        ),
        const SizedBox(height: 16),
        _styledTextFormField(
          controller: _dressCodeCtrl,
          label: 'CODE VESTIMENTAIRE (OPTIONNEL)',
          hint: 'Ex: Tenue de soirée',
          prefixIcon: Icons.checkroom,
        ),
        const SizedBox(height: 16),
        _styledTextFormField(
          controller: _eventNotesCtrl,
          label: 'NOTES',
          hint: 'Informations supplémentaires...',
          maxLines: 2,
        ),
      ],
    );
  }

  Widget _buildPaymentForm() {
    return _formCardWrapper(
      title: 'Détails du paiement',
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: _styledDropdown<String>(
                label: 'TYPE DE PAIEMENT',
                value: _paymentTypeCtrl.text.isEmpty ? null : _paymentTypeCtrl.text,
                prefixIcon: Icons.category,
                items: const [
                  DropdownMenuItem(value: 'frais_scolarite', child: Text('Frais de scolarité')),
                  DropdownMenuItem(value: 'frais_inscription', child: Text('Frais d\'inscription')),
                  DropdownMenuItem(value: 'frais_sortie', child: Text('Frais de sortie/voyage')),
                  DropdownMenuItem(value: 'frais_materiel', child: Text('Frais de matériel')),
                  DropdownMenuItem(value: 'cotisation', child: Text('Cotisation')),
                  DropdownMenuItem(value: 'autre', child: Text('Autre')),
                ],
                onChanged: (v) => setState(() => _paymentTypeCtrl.text = v ?? ''),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: _styledTextFormField(
                controller: _paymentAmountCtrl,
                label: 'MONTANT',
                hint: 'Ex: 500 DH *',
                prefixIcon: Icons.attach_money,
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildDateField(_paymentDueDateCtrl, 'DATE LIMITE DE PAIEMENT', required: true),
        const SizedBox(height: 16),
        _styledTextFormField(
          controller: _paymentMethodCtrl,
          label: 'MODE DE PAIEMENT (OPTIONNEL)',
          hint: 'Ex: Espèces, virement, chèque',
          prefixIcon: Icons.credit_card,
        ),
        const SizedBox(height: 16),
        _styledTextFormField(
          controller: _paymentNotesCtrl,
          label: 'NOTES',
          hint: 'Informations supplémentaires...',
          maxLines: 2,
        ),
      ],
    );
  }

  /// Build payload JSON from type-specific fields
  Map<String, dynamic> _buildPayload() {
    // Helper to get room name from ID
    String? getRoomName() {
      if (_selectedRoomId == null) return null;
      final buildingAsync = ref.read(buildingProvider);
      if (!buildingAsync.hasValue) return null;
      final buildingState = buildingAsync.value!;
      final room = buildingState.availableRooms.firstWhere(
        (r) => r.id == _selectedRoomId,
        orElse: () => RoomModel(id: '', floorId: '', name: ''),
      );
      return room.name.isNotEmpty ? room.name : null;
    }

    // Helper to get old room name from ID (for room_change)
    String? getOldRoomName() {
      if (_selectedOldRoomId == null) return null;
      final buildingAsync = ref.read(buildingProvider);
      if (!buildingAsync.hasValue) return null;
      final buildingState = buildingAsync.value!;
      final room = buildingState.availableRooms.firstWhere(
        (r) => r.id == _selectedOldRoomId,
        orElse: () => RoomModel(id: '', floorId: '', name: ''),
      );
      return room.name.isNotEmpty ? room.name : null;
    }

    switch (_announcementType) {
      case 'teacher_absent':
        return {
          'teacher_name': _teacherNameCtrl.text.trim(),
          'start_date': _startDateCtrl.text.trim(),
          'start_time': _startTimeCtrl.text.trim(),
          'end_date': _endDateCtrl.text.trim(),
          'end_time': _endTimeCtrl.text.trim(),
          'replacement_note': _replacementNoteCtrl.text.trim(),
        };
      case 'room_change':
        return {
          'subject': _subjectCtrl.text.trim(),
          'old_room': getOldRoomName() ?? '',
          'old_room_id': _selectedOldRoomId ?? '',
          'new_room': getRoomName() ?? '',
          'new_room_id': _selectedRoomId ?? '',
          'change_date': _changeDateCtrl.text.trim(),
          'change_time': _changeTimeCtrl.text.trim(),
        };
      case 'exam':
        return {
          'subject': _subjectCtrl.text.trim(),
          'exam_date': _examDateCtrl.text.trim(),
          'exam_time': _examTimeCtrl.text.trim(),
          'room': getRoomName() ?? '',
          'instructions': _instructionsCtrl.text.trim(),
        };
      case 'retenue':
        return {
          'exam_date': _examDateCtrl.text.trim(),
          'exam_time': _examTimeCtrl.text.trim(),
          'room': getRoomName() ?? '',
          'instructions': _instructionsCtrl.text.trim(),
        };
      case 'closure':
        return {
          'reason': _reasonCtrl.text.trim(),
          'closed_from': _closedFromCtrl.text.trim(),
          'closed_to': _closedToCtrl.text.trim(),
          'reopen_date': _reopenDateCtrl.text.trim(),
        };
      case 'reminder':
        return {
          'due_date': _dueDateCtrl.text.trim(),
          'action_required': _actionRequiredCtrl.text.trim(),
        };
      case 'trip':
        return {
          'destination': _destinationCtrl.text.trim(),
          'departure_date': _departureDateCtrl.text.trim(),
          'departure_time': _departureTimeCtrl.text.trim(),
          'return_date': _returnDateCtrl.text.trim(),
          'return_time': _returnTimeCtrl.text.trim(),
          'meeting_point': _meetingPointCtrl.text.trim(),
          'cost': _tripCostCtrl.text.trim(),
          'notes': _tripNotesCtrl.text.trim(),
        };
      case 'party':
        return {
          'event_name': _eventNameCtrl.text.trim(),
          'event_date': _eventDateCtrl.text.trim(),
          'event_time': _eventTimeCtrl.text.trim(),
          'location': _eventLocationCtrl.text.trim(),
          'dress_code': _dressCodeCtrl.text.trim(),
          'notes': _eventNotesCtrl.text.trim(),
        };
      case 'payment':
        return {
          'payment_type': _paymentTypeCtrl.text.trim(),
          'amount': _paymentAmountCtrl.text.trim(),
          'due_date': _paymentDueDateCtrl.text.trim(),
          'payment_method': _paymentMethodCtrl.text.trim(),
          'notes': _paymentNotesCtrl.text.trim(),
        };
      // ========== SANCTION TYPES PAYLOAD ==========
      case 'avertissement':
        return {
          'sanction_reason': _sanctionReasonCtrl.text.trim(),
          'sanction_date': _sanctionDateCtrl.text.trim(),
          'sanction_notes': _sanctionNotesCtrl.text.trim(),
        };
      case 'exclusion_classe':
        return {
          'sanction_reason': _sanctionReasonCtrl.text.trim(),
          'sanction_date': _sanctionDateCtrl.text.trim(),
          'sanction_duration': _sanctionDurationCtrl.text.trim(),
          'duration_unit': _durationUnit,
          'sanction_notes': _sanctionNotesCtrl.text.trim(),
        };
      case 'exclusion_etablissement':
        return {
          'sanction_reason': _sanctionReasonCtrl.text.trim(),
          'sanction_date': _sanctionDateCtrl.text.trim(),
          'sanction_duration': _sanctionDurationCtrl.text.trim(),
          'duration_unit': _durationUnit,
          'sanction_notes': _sanctionNotesCtrl.text.trim(),
        };
      case 'convocation_parents':
        return {
          'sanction_reason': _sanctionReasonCtrl.text.trim(),
          'meeting_date': _meetingDateCtrl.text.trim(),
          'meeting_time': _meetingTimeCtrl.text.trim(),
          'sanction_notes': _sanctionNotesCtrl.text.trim(),
        };
      case 'conseil_discipline':
        return {
          'discipline_subject': _disciplineSubjectCtrl.text.trim(),
          'meeting_date': _meetingDateCtrl.text.trim(),
          'meeting_time': _meetingTimeCtrl.text.trim(),
          'sanction_notes': _sanctionNotesCtrl.text.trim(),
        };
      case 'exclusion_definitive':
        return {
          'sanction_reason': _sanctionReasonCtrl.text.trim(),
          'sanction_date': _sanctionDateCtrl.text.trim(),
          'sanction_notes': _sanctionNotesCtrl.text.trim(),
        };
      default:
        return {};
    }
  }

  // ========== SANCTION FORMS FOR STUDENT MESSAGES ==========

  Widget _buildAvertissementForm() {
    return _formCardWrapper(
      title: 'Détails de l\'avertissement',
      children: [
        _styledTextFormField(
          controller: _sanctionReasonCtrl,
          label: 'MOTIF DE L\'AVERTISSEMENT',
          hint: 'Ex: Absence non justifiée, Comportement inapproprié *',
          prefixIcon: Icons.help_outline,
          maxLines: 3,
          validator: (v) => v == null || v.trim().isEmpty ? 'Le motif est requis' : null,
        ),
        const SizedBox(height: 16),
        _buildDateField(_sanctionDateCtrl, 'DATE DE L\'AVERTISSEMENT'),
        const SizedBox(height: 16),
        _styledTextFormField(
          controller: _sanctionNotesCtrl,
          label: 'OBSERVATIONS COMPLÉMENTAIRES (OPTIONNEL)',
          hint: 'Remarques additionnelles',
          prefixIcon: Icons.notes,
          maxLines: 2,
        ),
      ],
    );
  }

  Widget _buildExclusionClasseForm() {
    return _formCardWrapper(
      title: 'Détails de l\'exclusion de classe',
      children: [
        _styledTextFormField(
          controller: _sanctionReasonCtrl,
          label: 'MOTIF DE L\'EXCLUSION',
          hint: 'Ex: Comportement perturbateur, Manque de respect *',
          prefixIcon: Icons.help_outline,
          maxLines: 3,
          validator: (v) => v == null || v.trim().isEmpty ? 'Le motif est requis' : null,
        ),
        const SizedBox(height: 16),
        _buildDateField(_sanctionDateCtrl, 'DATE DE L\'EXCLUSION'),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _styledTextFormField(
                controller: _sanctionDurationCtrl,
                label: 'DURÉE',
                hint: 'Ex: 1, 2, 3 *',
                prefixIcon: Icons.schedule,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) => v == null || v.trim().isEmpty ? 'La durée est requise' : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _styledDropdown<String>(
                label: 'UNITÉ',
                value: _durationUnit,
                items: const [
                  DropdownMenuItem(value: 'jour', child: Text('Jour(s)')),
                  DropdownMenuItem(value: 'séance', child: Text('Séance(s)')),
                  DropdownMenuItem(value: 'heure', child: Text('Heure(s)')),
                  DropdownMenuItem(value: 'semaine', child: Text('Semaine(s)')),
                ],
                onChanged: (value) => setState(() => _durationUnit = value!),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _styledTextFormField(
          controller: _sanctionNotesCtrl,
          label: 'TRAVAIL À FAIRE PENDANT L\'EXCLUSION (OPTIONNEL)',
          hint: 'Devoirs ou révisions à effectuer',
          prefixIcon: Icons.assignment,
          maxLines: 2,
        ),
      ],
    );
  }

  Widget _buildExclusionEtablissementForm() {
    return _formCardWrapper(
      title: 'Détails de l\'exclusion de l\'établissement',
      children: [
        _styledTextFormField(
          controller: _sanctionReasonCtrl,
          label: 'MOTIF DE L\'EXCLUSION',
          hint: 'Ex: Faute grave, Violence, Fraude *',
          prefixIcon: Icons.help_outline,
          maxLines: 3,
          validator: (v) => v == null || v.trim().isEmpty ? 'Le motif est requis' : null,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _buildDateField(_sanctionDateCtrl, 'DATE DE DÉBUT')),
            const SizedBox(width: 12),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: _styledTextFormField(
                      controller: _sanctionDurationCtrl,
                      label: 'DURÉE',
                      hint: 'Ex: 3 *',
                      prefixIcon: Icons.schedule,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (v) => v == null || v.trim().isEmpty ? 'Requis' : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: _styledDropdown<String>(
                      label: 'UNITÉ',
                      value: _durationUnit,
                      items: const [
                        DropdownMenuItem(value: 'jour', child: Text('jour')),
                        DropdownMenuItem(value: 'séance', child: Text('séance')),
                        DropdownMenuItem(value: 'heure', child: Text('heure')),
                        DropdownMenuItem(value: 'semaine', child: Text('semaine')),
                      ],
                      onChanged: (value) => setState(() => _durationUnit = value ?? 'jour'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.error.withOpacity(0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.error.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              Icon(Icons.info_rounded, color: AppColors.error, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'L\'élève ne peut pas accéder à l\'établissement pendant la période d\'exclusion.',
                  style: TextStyle(fontSize: 12, color: AppColors.error),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _styledTextFormField(
          controller: _sanctionNotesCtrl,
          label: 'OBSERVATIONS (OPTIONNEL)',
          hint: 'Informations complémentaires',
          prefixIcon: Icons.notes,
          maxLines: 2,
        ),
      ],
    );
  }

  Widget _buildConvocationParentsForm() {
    return _formCardWrapper(
      title: 'Détails de la convocation des parents',
      children: [
        _styledTextFormField(
          controller: _sanctionReasonCtrl,
          label: 'OBJET DE LA CONVOCATION',
          hint: 'Ex: Problème de comportement, Résultats scolaires *',
          prefixIcon: Icons.help_outline,
          maxLines: 3,
          validator: (v) => v == null || v.trim().isEmpty ? 'L\'objet est requis' : null,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _buildDateField(_meetingDateCtrl, 'DATE DU RENDEZ-VOUS', required: true)),
            const SizedBox(width: 12),
            Expanded(child: _buildTimeField(_meetingTimeCtrl, 'HEURE')),
          ],
        ),
        const SizedBox(height: 16),
        _styledTextFormField(
          controller: _sanctionNotesCtrl,
          label: 'LIEU ET INFORMATIONS COMPLÉMENTAIRES (OPTIONNEL)',
          hint: 'Ex: Bureau du directeur, Salle des professeurs',
          prefixIcon: Icons.location_on,
          maxLines: 2,
        ),
      ],
    );
  }

  Widget _buildConseilDisciplineForm() {
    return _formCardWrapper(
      title: 'Détails du conseil de discipline',
      children: [
        _styledTextFormField(
          controller: _disciplineSubjectCtrl,
          label: 'SUJET DU CONSEIL',
          hint: 'Ex: Faute grave, Comportement récurrent *',
          prefixIcon: Icons.help_outline,
          maxLines: 3,
          validator: (v) => v == null || v.trim().isEmpty ? 'Le sujet est requis' : null,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _buildDateField(_meetingDateCtrl, 'DATE DU CONSEIL', required: true)),
            const SizedBox(width: 12),
            Expanded(child: _buildTimeField(_meetingTimeCtrl, 'HEURE')),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.secondary.withOpacity(0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.secondary.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              Icon(Icons.info_rounded, color: AppColors.secondary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'La présence des parents ou du représentant légal est obligatoire.',
                  style: TextStyle(fontSize: 12, color: AppColors.secondary),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _styledTextFormField(
          controller: _sanctionNotesCtrl,
          label: 'LIEU ET INFORMATIONS (OPTIONNEL)',
          hint: 'Ex: Salle de réunion, Documents à apporter',
          prefixIcon: Icons.location_on,
          maxLines: 2,
        ),
      ],
    );
  }

  Widget _buildExclusionDefinitiveForm() {
    return _formCardWrapper(
      title: 'Détails de l\'exclusion définitive',
      children: [
        _styledTextFormField(
          controller: _sanctionReasonCtrl,
          label: 'MOTIF DE L\'EXCLUSION DÉFINITIVE',
          hint: 'Ex: Décision du conseil de discipline *',
          prefixIcon: Icons.help_outline,
          maxLines: 3,
          validator: (v) => v == null || v.trim().isEmpty ? 'Le motif est requis' : null,
        ),
        const SizedBox(height: 16),
        _buildDateField(_sanctionDateCtrl, 'DATE D\'EFFET', required: true),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.error.withOpacity(0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.error.withOpacity(0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.warning_rounded, color: AppColors.error, size: 18),
                  const SizedBox(width: 8),
                  const Text(
                    'Sanction grave',
                    style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.error, fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Cette décision met fin définitivement à la scolarité de l\'élève dans cet établissement.',
                style: TextStyle(fontSize: 12, color: AppColors.error),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _styledTextFormField(
          controller: _sanctionNotesCtrl,
          label: 'MODALITÉS ADMINISTRATIVES (OPTIONNEL)',
          hint: 'Ex: Démarches à effectuer, Documents à récupérer',
          prefixIcon: Icons.description,
          maxLines: 2,
        ),
      ],
    );
  }

  Widget _buildRoomSelector() {
    return Consumer(
      builder: (context, ref, child) {
        final buildingAsync = ref.watch(buildingProvider);
        return buildingAsync.when(
          loading: () => const Center(child: IosLoader()),
          error: (e, _) => Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.errorSoft,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.error.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: AppColors.error, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Unable to load rooms',
                    style: TextStyle(color: AppColors.error, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          data: (buildingState) {
            final buildings = buildingState.buildings;

            if (buildings.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.slate100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.slate300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: AppColors.textSecondary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Aucun bloc configuré. Allez dans Structure pour ajouter des blocs.',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              );
            }

            final selectedBuilding = _selectedBuildingId != null
                ? buildings.cast<BuildingModel?>().firstWhere(
                    (b) => b?.id == _selectedBuildingId,
                    orElse: () => null,
                  )
                : null;

            final floors = selectedBuilding != null
                ? selectedBuilding.floors.where((f) => f.isActive).toList()
                : <FloorModel>[];

            final selectedFloor = _selectedFloorId != null
                ? floors.cast<FloorModel?>().firstWhere(
                    (f) => f?.id == _selectedFloorId,
                    orElse: () => null,
                  )
                : null;

            final rooms = selectedFloor != null
                ? selectedFloor.rooms.where((r) => r.isActive).toList()
                : <RoomModel>[];

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Bloc dropdown
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _formFieldLabel('BLOC'),
                      DropdownButtonFormField<String>(
                        value: _selectedBuildingId,
                        decoration: _styledInputDecoration(
                          hint: 'Sélectionner un bloc',
                          prefixIcon: Icons.apartment,
                        ),
                        style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                        borderRadius: BorderRadius.circular(10),
                        isExpanded: true,
                        items: [
                          const DropdownMenuItem<String>(
                            value: null,
                            child: Text('Sélectionner un bloc'),
                          ),
                          ...buildings.map(
                            (b) => DropdownMenuItem<String>(
                              value: b.id,
                              child: Row(
                                children: [
                                  if (b.code != null) ...[
                                    Text(
                                      '[${b.code}] ',
                                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                    ),
                                  ],
                                  Flexible(child: Text(b.name, overflow: TextOverflow.ellipsis)),
                                ],
                              ),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedBuildingId = value;
                            _selectedFloorId = null;
                            _selectedRoomId = null;
                          });
                        },
                      ),
                    ],
                  ),
                ),

                // 2. Étage dropdown (appears when bloc is selected)
                if (_selectedBuildingId != null) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _formFieldLabel('ÉTAGE'),
                        DropdownButtonFormField<String>(
                          value: _selectedFloorId,
                          decoration: _styledInputDecoration(
                            hint: 'Sélectionner un étage',
                            prefixIcon: Icons.layers_outlined,
                          ),
                          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                          borderRadius: BorderRadius.circular(10),
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text('Sélectionner un étage'),
                            ),
                            ...floors.map(
                              (f) => DropdownMenuItem<String>(
                                value: f.id,
                                child: Text(f.name, overflow: TextOverflow.ellipsis),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _selectedFloorId = value;
                              _selectedRoomId = null;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ],

                // 3. Salle dropdown (appears when étage is selected)
                if (_selectedFloorId != null) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _formFieldLabel('SALLE'),
                        DropdownButtonFormField<String>(
                          value: _selectedRoomId,
                          decoration: _styledInputDecoration(
                            hint: 'Sélectionner une salle',
                            prefixIcon: Icons.meeting_room_outlined,
                          ),
                          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                          borderRadius: BorderRadius.circular(10),
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text('Sélectionner une salle'),
                            ),
                            ...rooms.map(
                              (r) => DropdownMenuItem<String>(
                                value: r.id,
                                child: Row(
                                  children: [
                                    Icon(
                                      r.roomType == 'lab' ? Icons.science
                                          : r.roomType == 'office' ? Icons.work
                                          : Icons.meeting_room,
                                      size: 16,
                                      color: AppColors.textSecondary,
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(child: Text(r.name, overflow: TextOverflow.ellipsis)),
                                    const SizedBox(width: 4),
                                    Text('(${r.capacity})', style: TextStyle(fontSize: 11, color: AppColors.slate500)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() => _selectedRoomId = value);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  /// Room selector for room_change type (supports old and new rooms) — bloc, étage & salle hierarchical cascade
  Widget _buildRoomSelectorForType({required bool isOldRoom}) {
    return Consumer(
      builder: (context, ref, _) {
        final buildingState = ref.watch(buildingProvider);

        return buildingState.when(
          data: (state) {
            final buildings = state.buildings;
            final selectedBuildingId = isOldRoom
                ? _selectedOldBuildingId
                : _selectedBuildingId;
            final selectedFloorId = isOldRoom
                ? _selectedOldFloorId
                : _selectedFloorId;
            final selectedRoomId = isOldRoom
                ? _selectedOldRoomId
                : _selectedRoomId;

            final selectedBuilding = selectedBuildingId != null
                ? buildings.cast<BuildingModel?>().firstWhere(
                    (b) => b?.id == selectedBuildingId,
                    orElse: () => null,
                  )
                : null;

            final floors = selectedBuilding != null
                ? selectedBuilding.floors.where((f) => f.isActive).toList()
                : <FloorModel>[];

            final selectedFloor = selectedFloorId != null
                ? floors.cast<FloorModel?>().firstWhere(
                    (f) => f?.id == selectedFloorId,
                    orElse: () => null,
                  )
                : null;

            final rooms = selectedFloor != null
                ? selectedFloor.rooms.where((r) => r.isActive).toList()
                : <RoomModel>[];

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Bloc dropdown
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: selectedBuildingId,
                    decoration: _styledInputDecoration(
                      hint: 'Sélectionner un bloc',
                      prefixIcon: Icons.apartment,
                    ),
                    style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                    borderRadius: BorderRadius.circular(10),
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('Sélectionner un bloc'),
                      ),
                      ...buildings.map(
                        (b) => DropdownMenuItem<String>(
                          value: b.id,
                          child: Row(
                            children: [
                              if (b.code != null) ...[
                                Text(
                                  '[${b.code}] ',
                                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                ),
                              ],
                              Flexible(child: Text(b.name, overflow: TextOverflow.ellipsis)),
                            ],
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        if (isOldRoom) {
                          _selectedOldBuildingId = value;
                          _selectedOldFloorId = null;
                          _selectedOldRoomId = null;
                        } else {
                          _selectedBuildingId = value;
                          _selectedFloorId = null;
                          _selectedRoomId = null;
                        }
                      });
                    },
                  ),
                ),

                // 2. Étage dropdown (appears when bloc is selected)
                if (selectedBuildingId != null) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: selectedFloorId,
                      decoration: _styledInputDecoration(
                        hint: 'Sélectionner un étage',
                        prefixIcon: Icons.layers_outlined,
                      ),
                      style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                      borderRadius: BorderRadius.circular(10),
                      isExpanded: true,
                      items: [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text('Sélectionner un étage'),
                        ),
                        ...floors.map(
                          (f) => DropdownMenuItem<String>(
                            value: f.id,
                            child: Text(f.name, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          if (isOldRoom) {
                            _selectedOldFloorId = value;
                            _selectedOldRoomId = null;
                          } else {
                            _selectedFloorId = value;
                            _selectedRoomId = null;
                          }
                        });
                      },
                    ),
                  ),
                ],

                // 3. Salle dropdown (appears when étage is selected)
                if (selectedFloorId != null) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: selectedRoomId,
                      decoration: _styledInputDecoration(
                        hint: 'Sélectionner une salle',
                        prefixIcon: Icons.meeting_room_outlined,
                      ),
                      style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                      borderRadius: BorderRadius.circular(10),
                      isExpanded: true,
                      items: [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text('Sélectionner une salle'),
                        ),
                        ...rooms.map(
                          (r) => DropdownMenuItem<String>(
                            value: r.id,
                            child: Row(
                              children: [
                                Icon(
                                  r.roomType == 'lab' ? Icons.science
                                      : r.roomType == 'office' ? Icons.work
                                      : Icons.meeting_room,
                                  size: 16,
                                  color: AppColors.textSecondary,
                                ),
                                const SizedBox(width: 8),
                                Flexible(child: Text(r.name, overflow: TextOverflow.ellipsis)),
                                const SizedBox(width: 4),
                                Text('(${r.capacity})', style: TextStyle(fontSize: 11, color: AppColors.slate500)),
                              ],
                            ),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          if (isOldRoom) {
                            _selectedOldRoomId = value;
                          } else {
                            _selectedRoomId = value;
                          }
                        });
                      },
                    ),
                  ),
                ],
              ],
            );
          },
          loading: () => const Center(child: IosLoader()),
          error: (e, s) => Text(
            UserFriendlyError.format(
              e,
              fallback: 'Unable to load rooms right now.',
            ),
          ),
        );
      },
    );
  }

  Widget _buildSenderSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _formFieldLabel('EXPÉDITEUR'),
        Row(
          children: [
            Expanded(
              child: RadioListTile<String>(
                value: 'administration',
                groupValue: _senderType,
                title: const Text('Administration'),
                onChanged: (v) => setState(() => _senderType = v!),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            Expanded(
              child: RadioListTile<String>(
                value: 'teacher',
                groupValue: _senderType,
                title: const Text('Professeur'),
                onChanged: (v) => setState(() => _senderType = v!),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
        if (_senderType == 'teacher') ...[
          const SizedBox(height: 8),
          TextFormField(
            controller: _senderLabelCtrl,
            style: const TextStyle(fontSize: 13),
            decoration: _styledInputDecoration(
              hint: 'Ex: Prof. Benali',
              prefixIcon: Icons.person,
            ),
            inputFormatters: [CapitalizeWordsFormatter()],
          ),
        ],
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildOptions() {
    return Row(
      children: [
        Expanded(
          child: _buildToggleCard(
            icon: Icons.push_pin_rounded,
            title: 'Épingler l\'annonce',
            subtitle: 'Afficher en haut de la liste',
            value: _isPinned,
            activeColor: const Color(0xFF655DD5),
            onChanged: (v) => setState(() => _isPinned = v),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildToggleCard(
            icon: Icons.flag_rounded,
            title: 'Marquer important',
            subtitle: 'Badge priorité haute',
            value: _isImportant,
            activeColor: const Color(0xFFD97706),
            onChanged: (v) => setState(() => _isImportant = v),
          ),
        ),
      ],
    );
  }

  Widget _buildToggleCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required Color activeColor,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: value ? activeColor.withOpacity(0.4) : AppColors.border),
        color: value ? activeColor.withOpacity(0.05) : AppColors.slate50.withOpacity(0.5),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: value ? activeColor : AppColors.slate400),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: value ? activeColor : AppColors.textPrimary)),
                Text(subtitle, style: TextStyle(fontSize: 11, color: AppColors.slate400)),
              ],
            ),
          ),
          ModernAnimatedSwitch(
            value: value,
            onChanged: onChanged,
            activeColor: activeColor,
          ),
        ],
      ),
    );
  }

  Widget _buildAttachmentsSection() {
    final imageFiles = _pendingFiles
        .where((f) => f.mimeType.startsWith('image/'))
        .toList();
    final otherFiles = _pendingFiles
        .where((f) => !f.mimeType.startsWith('image/'))
        .toList();

    // Filter existing attachments (exclude those marked for deletion)
    final existingImages = _existingAttachments
        .where(
          (a) {
            if (_attachmentsToDelete.contains(a['id'])) return false;
            final type = (a['file_type'] ?? a['mime_type'] ?? '').toString().toLowerCase();
            final name = (a['file_name'] ?? a['display_name'] ?? a['file_url'] ?? '').toString().toLowerCase();
            return type.startsWith('image/') ||
                ['.png', '.jpg', '.jpeg', '.webp', '.gif'].any((ext) => name.endsWith(ext));
          },
        )
        .toList();
    final existingFiles = _existingAttachments
        .where(
          (a) {
            if (_attachmentsToDelete.contains(a['id'])) return false;
            final type = (a['file_type'] ?? a['mime_type'] ?? '').toString().toLowerCase();
            final name = (a['file_name'] ?? a['display_name'] ?? a['file_url'] ?? '').toString().toLowerCase();
            final isImg = type.startsWith('image/') ||
                ['.png', '.jpg', '.jpeg', '.webp', '.gif'].any((ext) => name.endsWith(ext));
            return !isImg;
          },
        )
        .toList();

    final hasContent =
        _pendingFiles.isNotEmpty ||
        existingImages.isNotEmpty ||
        existingFiles.isNotEmpty ||
        _loadingImagesSkeletonCount > 0 ||
        _loadingDocsSkeletonCount > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Dropzone
        InkWell(
          mouseCursor: SystemMouseCursors.click,
          onTap: _pickFiles,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.slate300,
                width: 1.5,
                strokeAlign: BorderSide.strokeAlignInside,
              ),
              color: AppColors.slate50.withOpacity(0.5),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.cloud_upload_outlined, size: 24, color: AppColors.secondary),
                ),
                const SizedBox(height: 12),
                RichText(
                  text: TextSpan(
                    style: TextStyle(fontSize: 13, color: AppColors.slate500),
                    children: [
                      TextSpan(
                        text: 'Cliquez pour ajouter',
                        style: TextStyle(color: AppColors.secondary, fontWeight: FontWeight.w600),
                      ),
                      const TextSpan(text: ' des fichiers'),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'PNG, JPG, PDF, DOC jusqu\'à 10MB',
                  style: TextStyle(fontSize: 11, color: AppColors.slate400),
                ),
              ],
            ),
          ),
        ),
        if (hasContent) ...[
          const SizedBox(height: 16),
          // Existing images from database
          if (existingImages.isNotEmpty) ...[
            const Text(
              'Images existantes',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: existingImages.map((att) {
                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        att['file_url'],
                        width: 100,
                        height: 100,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 100,
                          height: 100,
                          color: AppColors.slate200,
                          child: const Icon(Icons.broken_image),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () =>
                              setState(() => _attachmentsToDelete.add(att['id'])),
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
              }).toList(),
            ),
            const SizedBox(height: 12),
          ],
          // New images to upload
          if (imageFiles.isNotEmpty || _loadingImagesSkeletonCount > 0) ...[
            const Text(
              'Nouvelles images',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ...imageFiles.map((f) {
                  final index = _pendingFiles.indexOf(f);
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(
                          f.bytes,
                          width: 100,
                          height: 100,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: () =>
                                setState(() => _pendingFiles.removeAt(index)),
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
                  _loadingImagesSkeletonCount,
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
          // Existing files from database
          if (existingFiles.isNotEmpty) ...[
            const Text(
              'Documents existants',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Column(
              children: existingFiles.map((att) {
                final fileName = att['display_name'] ?? att['file_name'] ?? 'Document';
                final fileSize = att['size_bytes'] ?? att['file_size'] ?? 0;
                final fileType = (att['file_type'] ?? att['mime_type'] ?? '').toString();

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
                          _getFileIcon(fileType),
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
                              fileName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            if (_formatBytes(fileSize).isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                _formatBytes(fileSize),
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
                          mouseCursor: SystemMouseCursors.click,
                          icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.slate500),
                          onPressed: () => _editExistingFileName(att),
                          tooltip: 'Modifier le nom',
                        ),
                      ),
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: IconButton(
                          mouseCursor: SystemMouseCursors.click,
                          icon: const Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: AppColors.error,
                          ),
                          tooltip: 'Supprimer ce fichier',
                          onPressed: () =>
                              setState(() => _attachmentsToDelete.add(att['id'])),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
          ],
          // New files to upload
          if (otherFiles.isNotEmpty || _loadingDocsSkeletonCount > 0) ...[
            const Text(
              'Nouveaux documents',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Column(
              children: [
                ...otherFiles.map((f) {
                  final index = _pendingFiles.indexOf(f);
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
                            _getFileIcon(f.mimeType),
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
                                f.customDisplayName ?? f.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              if (_formatBytes(f.bytes.length).isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  _formatBytes(f.bytes.length),
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
                            mouseCursor: SystemMouseCursors.click,
                            icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.slate500),
                            onPressed: () => _editFileName(f),
                            tooltip: 'Modifier le nom',
                          ),
                        ),
                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: IconButton(
                            mouseCursor: SystemMouseCursors.click,
                            icon: const Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: AppColors.error,
                            ),
                            tooltip: 'Supprimer ce fichier',
                            onPressed: () =>
                                setState(() => _pendingFiles.removeAt(index)),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                ...List.generate(
                  _loadingDocsSkeletonCount,
                  (_) => const _SkeletonDocCard(),
                ),
              ],
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildPreview() {
    return ListenableBuilder(
      listenable: _previewListenable,
      builder: (context, _) {
        final typeInfo = _getPreviewTypeInfo(_announcementType);
        // For typed announcements, show type label as title and generate content preview
        final previewTitle = _announcementType == 'general'
            ? (_titleCtrl.text.isEmpty ? 'Titre de l\'annonce...' : _titleCtrl.text)
            : typeInfo.label;
        final previewContent = _announcementType == 'general'
            ? (_contentCtrl.text.isEmpty
                  ? 'Le contenu de votre annonce apparaîtra ici...'
                  : _contentCtrl.text)
            : (_generateContent().isEmpty
                  ? 'Remplissez les champs ci-dessus...'
                  : _generateContent());

        return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Aperçu en temps réel',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(width: 8),
            Icon(Icons.visibility, size: 16, color: AppColors.slate400),
          ],
        ),
        const SizedBox(height: 8),
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide.none,
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with type icon and badges
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: typeInfo.color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        typeInfo.icon,
                        color: typeInfo.color,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        previewTitle,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_isPinned)
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.warningSoft,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.push_pin,
                              size: 12,
                              color: AppColors.warning,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Épinglé',
                              style: TextStyle(
                                fontSize: 10,
                                color: AppColors.warning,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_isImportant)
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.errorSoft,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.priority_high,
                              size: 12,
                              color: AppColors.error,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Important',
                              style: TextStyle(fontSize: 10, color: AppColors.error),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                // Content
                Text(
                  previewContent,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.slate700,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                // Footer with scope, type and sender
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _scope == 'global'
                            ? AppColors.primarySoft
                            : AppColors.successSoft,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _scope == 'global' ? Icons.public : Icons.group,
                            size: 12,
                            color: _scope == 'global'
                                ? AppColors.primary
                                : AppColors.success,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _scope == 'global' ? 'Notification' : 'Message',
                            style: TextStyle(
                              fontSize: 11,
                              color: _scope == 'global'
                                  ? AppColors.primary
                                  : AppColors.success,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: typeInfo.color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        typeInfo.label,
                        style: TextStyle(fontSize: 11, color: typeInfo.color),
                      ),
                    ),
                    if (_senderType == 'teacher' &&
                        _senderLabelCtrl.text.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Builder(builder: (context) {
                        final subjectsState = ref.watch(subjectsManagementProvider).asData?.value;
                        final tUser = subjectsState?.teachers.where((t) => t.fullName.toLowerCase() == _senderLabelCtrl.text.trim().toLowerCase()).firstOrNull;
                        return UserAvatar(
                          name: _senderLabelCtrl.text,
                          photoUrl: tUser?.photoUrl,
                          radius: 10,
                        );
                      }),
                      const SizedBox(width: 4),
                      Text(
                        _senderLabelCtrl.text,
                        style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      ),
                    ],
                    const Spacer(),
                    Icon(Icons.access_time, size: 12, color: AppColors.slate400),
                    const SizedBox(width: 4),
                    Text(
                      'À l\'instant',
                      style: TextStyle(fontSize: 11, color: AppColors.slate500),
                    ),
                  ],
                ),
                if (_pendingFiles.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildPreviewImageGallery(),
                ],
              ],
            ),
          ),
        ),
            ],
          );
      },
    );
  }

  Widget _buildPreviewImageGallery() {
    final imageFiles = _pendingFiles
        .where((f) => f.mimeType.startsWith('image/'))
        .toList();
    final otherFiles = _pendingFiles
        .where((f) => !f.mimeType.startsWith('image/'))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Show images in Facebook-style grid
        if (imageFiles.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 150,
              child: imageFiles.length == 1
                  ? Image.memory(
                      imageFiles[0].bytes,
                      fit: BoxFit.cover,
                      width: double.infinity,
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: Image.memory(
                            imageFiles[0].bytes,
                            fit: BoxFit.cover,
                            height: 150,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Column(
                            children: [
                              if (imageFiles.length > 1)
                                Expanded(
                                  child: Image.memory(
                                    imageFiles[1].bytes,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                  ),
                                ),
                              if (imageFiles.length > 2) ...[
                                const SizedBox(height: 2),
                                Expanded(
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      Image.memory(
                                        imageFiles[2].bytes,
                                        fit: BoxFit.cover,
                                      ),
                                      if (imageFiles.length > 3)
                                        Container(
                                          color: AppColors.textPrimary.withOpacity(0.45),
                                          child: Center(
                                            child: Text(
                                              '+${imageFiles.length - 3}',
                                              style: const TextStyle(
                                                color: AppColors.surface,
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        // Show file attachments count
        if (otherFiles.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.attach_file, size: 14, color: AppColors.secondaryLight),
              const SizedBox(width: 4),
              Text(
                '${otherFiles.length} document(s)',
                style: TextStyle(fontSize: 11, color: AppColors.secondary),
              ),
            ],
          ),
        ],
      ],
    );
  }

  _TypeInfo _getPreviewTypeInfo(String type) {
    switch (type) {
      case 'teacher_absent':
        return _TypeInfo('Absence prof', Icons.person_off, AppColors.warning);
      case 'room_change':
        return _TypeInfo('Changement salle', Icons.meeting_room, AppColors.secondary);
      case 'reminder':
        return _TypeInfo('Rappel', Icons.alarm, AppColors.primary);
      case 'exam':
        return _TypeInfo('Examen', Icons.assignment, AppColors.error);
      case 'retenue':
        return _TypeInfo('Retenue', Icons.access_time, const Color(0xFFDC2626));
      case 'trip':
        return _TypeInfo('Sortie', Icons.directions_bus, AppColors.success);
      case 'party':
        return _TypeInfo('Événement', Icons.celebration, AppColors.chart4);
      case 'payment':
        return _TypeInfo('Paiement', Icons.payment, AppColors.chart5);
      case 'closure':
        return _TypeInfo('Fermeture', Icons.lock, AppColors.slate300);
      case 'avertissement':
        return _TypeInfo('Avertissement', Icons.warning_amber, AppColors.warning);
      case 'exclusion_classe':
        return _TypeInfo('Exclusion classe', Icons.no_meeting_room, AppColors.accent);
      case 'exclusion_etablissement':
        return _TypeInfo('Exclusion étab.', Icons.block, AppColors.error);
      case 'convocation_parents':
        return _TypeInfo('Convocation', Icons.family_restroom, AppColors.chart5);
      case 'conseil_discipline':
        return _TypeInfo('Conseil disc.', Icons.gavel, AppColors.secondary);
      case 'exclusion_definitive':
        return _TypeInfo('Exclusion déf.', Icons.cancel, AppColors.textPrimary);
      case 'general':
      default:
        return _TypeInfo('Général', Icons.campaign, AppColors.chart6);
    }
  }

  Widget _buildActions(bool isEditing) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.slate100)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          SizedBox(
            height: 40,
            child: TextButton(
              onPressed: _isLoading ? null : () => Navigator.pop(context),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.slate500,
                enabledMouseCursor: SystemMouseCursors.click,
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              child: const Text('Annuler', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: 40,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _save,
              icon: _isLoading
                  ? const IosLoader.small(color: Colors.white)
                  : Icon(isEditing ? Icons.save_rounded : Icons.send_rounded, size: 16),
              label: Text(
                isEditing ? 'Enregistrer' : 'Publier l\'annonce',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6D4CF6),
                foregroundColor: Colors.white,
                enabledMouseCursor: SystemMouseCursors.click,
                elevation: 2,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: [
          'jpg',
          'jpeg',
          'png',
          'gif',
          'pdf',
          'doc',
          'docx',
          'xls',
          'xlsx',
        ],
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        if (mounted) {
          setState(() {
            for (final f in result.files) {
              if (f.bytes == null) continue;
              final mimeType = _getMimeType(f.extension ?? '');
              _pendingFiles.add(
                _PendingFile(
                  name: f.name,
                  bytes: f.bytes!,
                  mimeType: mimeType,
                ),
              );
            }
            _loadingImagesSkeletonCount = 0;
            _loadingDocsSkeletonCount = 0;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFriendlyError.format(
                e,
                fallback: 'Unable to attach this file right now. Please try again.',
              ),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  String _getMimeType(String ext) {
    switch (ext.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
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
      default:
        return 'application/octet-stream';
    }
  }

  IconData _getFileIcon(String mimeType) {
    if (mimeType.startsWith('image/')) return Icons.image;
    if (mimeType.contains('pdf')) return Icons.picture_as_pdf;
    if (mimeType.contains('word') || mimeType.contains('document')) {
      return Icons.description;
    }
    if (mimeType.contains('excel') || mimeType.contains('spreadsheet')) {
      return Icons.table_chart;
    }
    return Icons.attach_file;
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _editFileName(_PendingFile file) async {
    final controller = TextEditingController(
      text: file.customDisplayName ?? file.name,
    );
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Modifier le nom du fichier'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Nom du fichier',
            hintText: 'Ex: Document important',
          ),
          autofocus: true,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        actions: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFE8EAF0)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Annuler', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF6B7280))),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context, controller.text.trim()),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('OK', style: TextStyle(fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      setState(() {
        file.customDisplayName = result;
      });
    }
  }

  Future<void> _editExistingFileName(Map<String, dynamic> att) async {
    final controller = TextEditingController(
      text: att['display_name'] ?? att['file_name'],
    );
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Modifier le nom du fichier'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Nom du fichier',
            hintText: 'Ex: Document important',
          ),
          autofocus: true,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        actions: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFE8EAF0)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Annuler', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF6B7280))),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context, controller.text.trim()),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('OK', style: TextStyle(fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      setState(() {
        att['display_name'] = result;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_scope == 'class' &&
        _selectedClassId == null &&
        widget.announcement == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez sélectionner une classe'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }
    if (_scope == 'student' &&
        _selectedStudentId == null &&
        widget.announcement == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez sélectionner un élève'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      final notifier = ref.read(announcementsProvider.notifier);
      final payload = _buildPayload();

      // For typed announcements, generate content automatically
      // Title stays empty for typed announcements (type label will be shown)
      final title = _announcementType == 'general'
          ? _titleCtrl.text.trim()
          : '';
      final content = _announcementType == 'general'
          ? _contentCtrl.text.trim()
          : _generateContent();

      if (widget.announcement != null) {
        // Editing existing announcement
        await notifier.updateAnnouncement(
          id: widget.announcement!.id,
          title: title,
          content: content,
          targetClassId: _scope == 'student' ? null : _selectedClassId,
          isPinned: _isPinned,
          isImportant: _isImportant,
          scope: _scope,
          announcementType: _announcementType,
          senderType: _senderType,
          senderLabel: _senderType == 'teacher'
              ? _senderLabelCtrl.text.trim()
              : null,
          payload: payload,
        );

        // Delete marked attachments
        for (final attId in _attachmentsToDelete) {
          try {
            await notifier.deleteAttachment(attId);
            debugPrint('Deleted attachment: $attId');
          } catch (e) {
            debugPrint('Delete attachment error: $e');
          }
        }

        // Upload new attachments
        if (_pendingFiles.isNotEmpty) {
          for (final file in _pendingFiles) {
            try {
              await notifier.uploadAttachment(
                announcementId: widget.announcement!.id,
                scope: _scope,
                fileName: file.name,
                fileBytes: file.bytes,
                mimeType: file.mimeType,
                displayName: file.customDisplayName,
              );
              debugPrint('Upload success: ${file.name}');
            } catch (uploadError) {
              debugPrint('Upload error: $uploadError');
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      UserFriendlyError.format(
                        uploadError,
                        fallback: 'Unable to upload attachment "${file.name}". Please try again.',
                      ),
                    ),
                    backgroundColor: AppColors.error,
                    duration: const Duration(seconds: 5),
                  ),
                );
              }
            }
          }
        }
      } else {
        // Creating new announcement
        final announcementId = await notifier.create(
          title: title,
          content: content,
          targetClassId: _scope == 'student' ? null : _selectedClassId,
          targetStudentId: _scope == 'student' ? _selectedStudentId : null,
          isPinned: _isPinned,
          isImportant: _isImportant,
          scope: _scope,
          announcementType: _announcementType,
          senderType: _senderType,
          senderLabel: _senderType == 'teacher'
              ? _senderLabelCtrl.text.trim()
              : null,
          payload: payload,
        );
        debugPrint(
          'Created announcement: $announcementId, pending files: ${_pendingFiles.length}',
        );
        if (_pendingFiles.isNotEmpty && announcementId != null) {
          for (final file in _pendingFiles) {
            debugPrint('Uploading: ${file.name} (${file.bytes.length} bytes)');
            try {
              await notifier.uploadAttachment(
                announcementId: announcementId,
                scope: _scope,
                fileName: file.name,
                fileBytes: file.bytes,
                mimeType: file.mimeType,
                displayName: file.customDisplayName,
              );
              debugPrint('Upload success: ${file.name}');
            } catch (uploadError) {
              debugPrint('Upload error: $uploadError');
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      UserFriendlyError.format(
                        uploadError,
                        fallback: 'Unable to upload attachment "${file.name}". Please try again.',
                      ),
                    ),
                    backgroundColor: AppColors.error,
                    duration: const Duration(seconds: 5),
                  ),
                );
              }
            }
          }
        }
      }
      widget.onSave();
    } catch (e) {
      debugPrint('Save error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFriendlyError.format(
                e,
                fallback: 'Unable to save this announcement right now. Please try again.',
              ),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}

class _PendingFile {
  final String name;
  final Uint8List bytes;
  final String mimeType;
  String? customDisplayName; // For custom file names (non-images)
  _PendingFile({
    required this.name,
    required this.bytes,
    required this.mimeType,
  });
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
