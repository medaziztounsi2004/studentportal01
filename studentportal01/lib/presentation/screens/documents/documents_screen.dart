import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/l10n/app_localizations.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/theme/arabic_typography.dart';
import '../../../core/theme/responsive.dart';
import '../../../core/router/app_router.dart';
import '../../../data/models/document_model.dart';
import '../../../data/services/offline_cache_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/student_context_provider.dart';
import '../../widgets/animated_search_header.dart';
import '../../widgets/bouncing_wrapper.dart';
import '../../widgets/bouncy_dropdown_selector.dart';
import '../../widgets/detail_modal_sheet.dart';
import '../../widgets/documents_skeleton.dart';
import '../../widgets/semester_navigator.dart';
import '../../widgets/locked_semester_card.dart';
import '../../widgets/empty_state_glass_card.dart';
import '../../providers/nav_bar_provider.dart';
import '../../../core/utils/file_download_helper.dart';
import '../../widgets/ios_photo_gallery_viewer.dart';

// Semester state provider for this screen
final docsSemesterProvider = StateProvider<int>((ref) => 1);

/// Set of document IDs that have been opened/read by the current user
final readDocumentsProvider =
    StateNotifierProvider<ReadDocumentsNotifier, Set<String>>((ref) {
  final authState = ref.watch(authProvider);
  final userId = authState.user?.id ?? 'default_user';
  return ReadDocumentsNotifier(userId);
});

class ReadDocumentsNotifier extends StateNotifier<Set<String>> {
  final String userId;
  static const _storagePrefix = 'read_documents_ids_';

  ReadDocumentsNotifier(this.userId) : super({}) {
    _loadFromCache();
  }

  void _loadFromCache() {
    try {
      final cachedList = OfflineCacheService.instance.getList('$_storagePrefix$userId');
      if (cachedList != null) {
        state = cachedList.map((e) => e.toString()).toSet();
      }
    } catch (e) {
      debugPrint('ReadDocumentsNotifier load error: $e');
    }
  }

  Future<void> markAsRead(String id) async {
    if (state.contains(id)) return;
    final updated = Set<String>.from(state)..add(id);
    state = updated;
    await OfflineCacheService.instance.setJson('$_storagePrefix$userId', updated.toList());
  }

  bool isRead(String id) => state.contains(id);
}

/// Parses raw `public.documents` rows, enforces per-student / per-class / school-wide
/// visibility, and sorts newest first.
List<DocumentModel> parseVisibleStudentDocuments(
  List<Map<String, dynamic>> rawRows, {
  String? userId,
  String? classId,
}) {
  final docs = <DocumentModel>[];
  for (final row in rawRows) {
    try {
      final doc = DocumentModel.fromJson(row);
      if (doc.isVisibleToStudent(userId: userId, classId: classId)) {
        docs.add(doc);
      }
    } catch (_) {}
  }
  docs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return docs;
}

/// All documents from Supabase visible to the signed-in student (with Realtime + offline cache).
final allStudentDocumentsProvider = FutureProvider<List<DocumentModel>>((ref) async {
  final studentCtx = await ref.watch(studentContextProvider.future);
  final authState = ref.watch(authProvider);
  final supabase = Supabase.instance.client;

  final schoolId = studentCtx?.schoolId 
      ?? authState.user?.schoolId 
      ?? (OfflineCacheService.instance.getMap('cached_user')?['school_id']?.toString());
  final userId = studentCtx?.userId 
      ?? authState.user?.id 
      ?? (OfflineCacheService.instance.getMap('cached_user')?['id']?.toString());
  final classId = studentCtx?.classId 
      ?? authState.enrollment?.classId 
      ?? (OfflineCacheService.instance.getMap('cached_enrollment')?['class_id']?.toString());

  final primaryCacheKey =
      'documents_school_${schoolId ?? 'none'}_user_${userId ?? 'anon'}';
  const latestCacheKey = 'documents_latest';

  List<DocumentModel> readCachedDocuments() {
    for (final key in [primaryCacheKey, latestCacheKey]) {
      final cached = OfflineCacheService.instance.getListOfMaps(key);
      if (cached != null && cached.isNotEmpty) {
        final parsed = parseVisibleStudentDocuments(
          cached,
          userId: userId,
          classId: classId,
        );
        if (parsed.isNotEmpty) return parsed;
        // Safety net: if filtering by userId/classId filtered out all documents offline, return all valid docs from cache
        final fallback = cached.map((r) {
          try {
            return DocumentModel.fromJson(r);
          } catch (_) {
            return null;
          }
        }).whereType<DocumentModel>().toList();
        if (fallback.isNotEmpty) return fallback;
      }
    }
    return [];
  }

  // 0. Fast return when offline
  if (ConnectivityService.instance.isOffline) {
    return readCachedDocuments();
  }

  // Listen for new/updated/deleted admin documents in real time when enabled.
  RealtimeChannel? channel;
  try {
    channel = supabase
        .channel('student_documents_${schoolId ?? 'global'}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'documents',
          callback: (_) => ref.invalidateSelf(),
        )
        .subscribe();
    ref.onDispose(() {
      if (channel != null) {
        try {
          supabase.removeChannel(channel);
        } catch (_) {}
      }
    });
  } catch (_) {}

  if (schoolId == null || schoolId.isEmpty) {
    return readCachedDocuments();
  }

  try {
    final response = await supabase
        .from('documents')
        .select(
          'id, school_id, class_id, title, description, category, file_url, file_name, file_size, mime_type, uploaded_by, created_at',
        )
        .eq('school_id', schoolId)
        .order('created_at', ascending: false)
        .timeout(const Duration(seconds: 4));

    final rawRows = List<Map<String, dynamic>>.from(response as List);
    final visibleRows = <Map<String, dynamic>>[];
    final visibleDocs = <DocumentModel>[];

    for (final row in rawRows) {
      try {
        final doc = DocumentModel.fromJson(row);
        if (doc.isVisibleToStudent(userId: userId, classId: classId)) {
          visibleRows.add(row);
          visibleDocs.add(doc);
        }
      } catch (_) {}
    }

    visibleDocs.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    OfflineCacheService.instance.setJson(primaryCacheKey, visibleRows);
    OfflineCacheService.instance.setJson(latestCacheKey, visibleRows);
    ConnectivityService.instance.reportNetworkSuccess();

    return visibleDocs;
  } catch (e) {
    ConnectivityService.instance.reportNetworkError(e);
    return readCachedDocuments();
  }
});

/// Documents filtered for the currently selected period/semester.
final documentsProvider =
    FutureProvider.family<List<DocumentModel>, int>((ref, semester) async {
  try {
    final allSemesters = await ref.watch(semestersProvider.future);
    if (isSemesterLocked(semester, allSemesters)) {
      return [];
    }
  } catch (_) {}
  final docs = await ref.watch(allStudentDocumentsProvider.future);
  return docs.where((doc) => doc.effectiveSemester == semester).toList();
});

/// Unread documents counter provider for the current student
final unreadDocumentsCountProvider = Provider<int>((ref) {
  final docsAsync = ref.watch(allStudentDocumentsProvider);
  final readIds = ref.watch(readDocumentsProvider);
  return docsAsync.when(
    data: (docs) => docs.where((d) => !readIds.contains(d.id)).length,
    loading: () => 0,
    error: (_, _) => 0,
  );
});

class DocumentsScreen extends ConsumerStatefulWidget {
  final String? initialDocumentId;

  const DocumentsScreen({
    super.key,
    this.initialDocumentId,
  });

  @override
  ConsumerState<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends ConsumerState<DocumentsScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _searchAnimController;
  String? _selectedCategory;
  bool _hasUserPickedSemester = false;
  DateTime? _lastResumeRefresh;
  bool _hasHandledInitialDocument = false;

  // Search state
  bool _isSearching = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  // iOS 26 gradient colors
  static const _gradientColors = [
    Color(0xFFF8F0FC),
    Color(0xFFF0E6F8),
    Color(0xFFEAF0FA),
    Color(0xFFF4F8FC),
    Color(0xFFFAFCFD),
  ];

  void _checkAutoOpenInitial(List<DocumentModel> list) {
    if (_hasHandledInitialDocument || widget.initialDocumentId == null) return;
    final match = list.where((d) => d.id == widget.initialDocumentId).firstOrNull;
    if (match != null) {
      _hasHandledInitialDocument = true;
      ref.read(readDocumentsProvider.notifier).markAsRead(match.id);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _DocumentCard._showDocumentDetails(context, match, list, ref);
        }
      });
    }
  }

  @override
  void didUpdateWidget(DocumentsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialDocumentId != oldWidget.initialDocumentId &&
        widget.initialDocumentId != null) {
      _hasHandledInitialDocument = false;
      ref.read(allStudentDocumentsProvider).whenData((list) {
        _checkAutoOpenInitial(list);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _searchAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _searchController.addListener(() {
      if (_searchQuery != _searchController.text) {
        setState(() {
          _searchQuery = _searchController.text;
        });
      }
    });

    // Ensure visiting the Documents screen checks for newly admin-sent documents.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!ref.read(allStudentDocumentsProvider).isLoading) {
        ref.invalidate(allStudentDocumentsProvider);
      }
      final currentSemesters = ref.read(semestersProvider).valueOrNull;
      if (currentSemesters != null &&
          currentSemesters.isNotEmpty &&
          !_hasUserPickedSemester) {
        final activeNum = resolveCurrentSemesterNumber(currentSemesters);
        if (ref.read(docsSemesterProvider) != activeNum) {
          ref.read(docsSemesterProvider.notifier).state = activeNum;
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final now = DateTime.now();
      if (_lastResumeRefresh == null ||
          now.difference(_lastResumeRefresh!) > const Duration(seconds: 3)) {
        _lastResumeRefresh = now;
        ref.invalidate(semestersProvider);
        ref.invalidate(allStudentDocumentsProvider);
      }
    }
  }

  @override
  void deactivate() {
    dismissAllOverlaysAndPopups();
    super.deactivate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_isSearching) {
      ref.read(backSwipeInterceptorProvider.notifier).state = null;
    }
    _searchAnimController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (_isSearching) {
        _searchAnimController.forward();
        ref.read(backSwipeInterceptorProvider.notifier).state = () {
          _toggleSearch();
          return true;
        };
        Future.delayed(const Duration(milliseconds: 150), () {
          _searchFocusNode.requestFocus();
        });
      } else {
        ref.read(backSwipeInterceptorProvider.notifier).state = null;
        _searchAnimController.reverse();
        _searchController.clear();
        _searchQuery = '';
        _searchFocusNode.unfocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final selectedSemester = ref.watch(docsSemesterProvider);
    final documentsAsync = ref.watch(documentsProvider(selectedSemester));
    final semesters = ref.watch(semestersProvider).valueOrNull ?? [];
    final isLocked = isSemesterLocked(selectedSemester, semesters);

    ref.watch(allStudentDocumentsProvider).whenData((list) {
      _checkAutoOpenInitial(list);
    });

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: _gradientColors,
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _buildHeader(l10n),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: context.horizontalPadding),
                child: DynamicSemesterNav(
                  selectedSemesterNumber: selectedSemester,
                  accentColor: const Color(0xFF10B981),
                  secondaryColor: const Color(0xFF059669),
                  onChanged: (v) {
                    _hasUserPickedSemester = true;
                    ref.read(docsSemesterProvider.notifier).state = v;
                    setState(() {
                      _selectedCategory = null;
                    });
                  },
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: isLocked
                    ? LockedSemesterCard(
                        startDate: semesters
                            .where((s) => s.number == selectedSemester)
                            .firstOrNull
                            ?.startDate,
                        moduleType: LockedModuleType.documents,
                      )
                    : documentsAsync.when(
                        data: (documents) => _buildContent(documents, l10n, selectedSemester),
                        loading: () => _buildLoadingState(l10n),
                        error: (error, stack) {
                          final allDocs = ref.watch(allStudentDocumentsProvider).valueOrNull ?? [];
                          final semDocs = allDocs.where((d) => d.effectiveSemester == selectedSemester).toList();
                          if (semDocs.isNotEmpty) {
                            return _buildContent(semDocs, l10n, selectedSemester);
                          }
                          return _buildErrorState(l10n);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(AppLocalizations l10n) {
    return Padding(
      padding: EdgeInsets.fromLTRB(context.horizontalPadding, 12, context.horizontalPadding, 8),
      child: AnimatedSearchHeader(
        animationController: _searchAnimController,
        searchController: _searchController,
        searchFocusNode: _searchFocusNode,
        onToggleSearch: _toggleSearch,
        title: l10n.documents,
        subtitle: l10n.homeSubtitleDocuments,
        icon: Icons.folder_rounded,
        gradientColors: const [Color(0xFF10B981), Color(0xFF059669)],
        isSearching: _isSearching,
      ),
    );
  }

  Widget _buildContent(List<DocumentModel> documents, AppLocalizations l10n, int selectedSemester) {
    // 1. Strictly filter documents for the selected semester
    // All document types including courses are supported in the document page
    final semesterDocs = documents.where((doc) {
      return doc.effectiveSemester == selectedSemester;
    }).toList();

    // 2. Sort documents by post date descending (most recent first)
    semesterDocs.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // 3. Extract unique categories present in this semester
    final availableCategories = semesterDocs.map((d) => d.category).toSet().toList();

    // 4. Apply category filter if one is selected
    var filteredDocs = semesterDocs;
    if (_selectedCategory != null) {
      filteredDocs = filteredDocs.where((doc) => doc.category == _selectedCategory).toList();
    }

    // 5. Apply search filter
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filteredDocs = filteredDocs.where((doc) {
        return doc.title.toLowerCase().contains(query) ||
            (doc.description?.toLowerCase().contains(query) ?? false) ||
            doc.fileName.toLowerCase().contains(query) ||
            doc.displayCategory(l10n).toLowerCase().contains(query);
      }).toList();
    }

    if (semesterDocs.isEmpty) {
      return _buildEmptySemesterState(selectedSemester, l10n);
    }

    final isRtl = Directionality.of(context) == TextDirection.rtl;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        if (_isSearching) _toggleSearch();
      },
      onHorizontalDragUpdate: (details) {
        if (_isSearching) {
          if (isRtl) {
            if ((details.primaryDelta ?? 0) > 8) _toggleSearch();
          } else {
            if ((details.primaryDelta ?? 0) < -8) _toggleSearch();
          }
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // "Trier par" label and dropdown button aligned to max right - fixed at top
          Padding(
            padding: EdgeInsets.symmetric(horizontal: context.horizontalPadding),
            child: _buildSortAndFilterBar(availableCategories, l10n),
          ),
          const SizedBox(height: 10),

          // Scrollable document cards that pass cleanly under the "Trier par" row
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(allStudentDocumentsProvider);
                ref.invalidate(documentsProvider(selectedSemester));
                await ref.read(documentsProvider(selectedSemester).future);
              },
              color: const Color(0xFF10B981),
              backgroundColor: Colors.white,
              child: filteredDocs.isEmpty
                  ? SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                      child: _buildEmptyFilterState(l10n),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.fromLTRB(context.horizontalPadding, 4, context.horizontalPadding, 140),
                      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                      itemCount: filteredDocs.length,
                      itemBuilder: (context, index) => _DocumentCard(document: filteredDocs[index], allDocuments: filteredDocs),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSortAndFilterBar(List<String> availableCategories, AppLocalizations l10n) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    const allCategoriesKey = '__ALL__';
    final currentLabel = DocumentTypeHelper.getLabel(_selectedCategory, l10n);

    final allCategoryKeys = <String>{
      ...DocumentTypeHelper.types.keys,
      ...availableCategories,
    };

    final sortOptions = <MapEntry<String, String>>[
      MapEntry(allCategoriesKey, l10n.allTypes),
      ...allCategoryKeys.map((cat) => MapEntry(cat, DocumentTypeHelper.getLabel(cat, l10n))),
    ];

    final items = sortOptions.map((entry) {
      final catKey = entry.key;
      final isAll = catKey == allCategoriesKey;
      return BouncyDropdownItem<String>(
        value: catKey,
        label: entry.value,
        icon: isAll ? Icons.dashboard_rounded : getCategoryIcon(catKey),
        color: isAll ? const Color(0xFF10B981) : getCategoryColor(catKey),
      );
    }).toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          // "Trier par" label on left
          Text(
            l10n.sortBy,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
              letterSpacing: -0.2,
            ),
          ),
          const Spacer(), // Pushes the pill to the maximum right

          // Bouncy dropdown selector matching suggestion type exactly
          BouncyDropdownSelector<String>(
            items: items,
            selectedValue: _selectedCategory ?? allCategoriesKey,
            onSelected: (String categoryKey) {
              setState(() {
                _selectedCategory = (categoryKey == allCategoriesKey) ? null : categoryKey;
              });
            },
            menuWidth: 260.0,
            menuAlignment: isRtl ? Alignment.bottomLeft : Alignment.bottomRight,
            borderRadius: 22.0,
            customTrigger: (context, isOpen, toggle, selectedItem) {
              return GestureDetector(
                onTap: toggle,
                child: AnimatedScale(
                  scale: isOpen ? 0.95 : 1.0,
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutBack,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.8),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF10B981).withValues(alpha: 0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _selectedCategory != null
                              ? getCategoryIcon(_selectedCategory!)
                              : Icons.dashboard_rounded,
                          size: 15,
                          color: _selectedCategory != null
                              ? getCategoryColor(_selectedCategory!)
                              : const Color(0xFF10B981),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          currentLabel,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _selectedCategory != null
                                ? const Color(0xFF10B981)
                                : const Color(0xFF1F2937),
                          ),
                        ),
                        const SizedBox(width: 6),
                        AnimatedRotation(
                          turns: isOpen ? 0.5 : 0.0,
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeInOut,
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 18,
                            color: _selectedCategory != null
                                ? const Color(0xFF10B981)
                                : Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  static IconData getCategoryIcon(String category) {
    switch (category) {
      case 'releve_notes':
        return Icons.grade_rounded;
      case 'exams':
        return Icons.quiz_rounded;
      case 'carte_etudiant':
        return Icons.badge_rounded;
      case 'attestation':
        return Icons.verified_rounded;
      case 'planning':
        return Icons.calendar_month_rounded;
      case 'certificat':
        return Icons.workspace_premium_rounded;
      case 'stage_pfe':
        return Icons.work_rounded;
      case 'reglement':
        return Icons.gavel_rounded;
      case 'administrative':
        return Icons.description_rounded;
      case 'courses':
        return Icons.menu_book_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  static Color getCategoryColor(String category) {
    switch (category) {
      case 'releve_notes':
        return const Color(0xFF8B5CF6);
      case 'exams':
        return const Color(0xFFF43F5E);
      case 'carte_etudiant':
        return const Color(0xFF3B82F6);
      case 'attestation':
        return const Color(0xFF6B5CE7);
      case 'planning':
        return const Color(0xFF10B981);
      case 'certificat':
        return const Color(0xFF06B6D4);
      case 'stage_pfe':
        return const Color(0xFFF59E0B);
      case 'reglement':
        return const Color(0xFF64748B);
      case 'administrative':
        return const Color(0xFF6366F1);
      case 'courses':
        return const Color(0xFF4ECDC4);
      default:
        return const Color(0xFF9CA3AF);
    }
  }




  static String formatRelativeTime(BuildContext context, DateTime time) {
    final localTime = time.toLocal();
    final now = DateTime.now();
    final difference = now.difference(localTime);
    String lang = 'fr';
    try {
      lang = Localizations.localeOf(context).languageCode;
    } catch (_) {}

    if (difference.isNegative || difference.inSeconds < 60) {
      if (lang == 'ar') return 'الآن';
      if (lang == 'en') return 'Just now';
      return "À l'instant";
    }

    if (lang == 'ar') {
      if (difference.inMinutes < 60) {
        return 'منذ ${difference.inMinutes} د';
      } else if (difference.inHours < 24) {
        return 'منذ ${difference.inHours} س';
      } else if (difference.inDays < 7) {
        return 'منذ ${difference.inDays} ي';
      } else if (difference.inDays < 30) {
        final weeks = (difference.inDays / 7).floor();
        return 'منذ $weeks أس';
      } else {
        return DateFormat('d MMM', 'ar').format(localTime);
      }
    } else if (lang == 'en') {
      if (difference.inMinutes < 60) {
        return '${difference.inMinutes}m ago';
      } else if (difference.inHours < 24) {
        return '${difference.inHours}h ago';
      } else if (difference.inDays < 7) {
        return '${difference.inDays}d ago';
      } else if (difference.inDays < 30) {
        final weeks = (difference.inDays / 7).floor();
        return '${weeks}w ago';
      } else {
        return DateFormat('d MMM', 'en').format(localTime);
      }
    } else {
      if (difference.inMinutes < 60) {
        return 'Il y a ${difference.inMinutes} min';
      } else if (difference.inHours < 24) {
        return 'Il y a ${difference.inHours} h';
      } else if (difference.inDays < 7) {
        return 'Il y a ${difference.inDays} j';
      } else if (difference.inDays < 30) {
        final weeks = (difference.inDays / 7).floor();
        return 'Il y a $weeks sem.';
      } else {
        return DateFormat('d MMM', 'fr_FR').format(localTime);
      }
    }
  }

  Widget _buildEmptySemesterState(int semester, AppLocalizations l10n) {
    return EmptyStateGlassCard(
      alignment: const Alignment(0, -0.45),
      icon: Icons.folder_open_rounded,
      gradientColors: const [Color(0xFF10B981), Color(0xFF059669)],
      title: l10n.noData,
      subtitle: l10n.noDocsForSemester(semester),
    );
  }

  Widget _buildEmptyFilterState(AppLocalizations l10n) {
    return EmptyStateGlassCard(
      alignment: const Alignment(0, -0.2),
      icon: Icons.filter_list_off_rounded,
      gradientColors: const [Color(0xFF10B981), Color(0xFF059669)],
      title: l10n.noMatchingDocuments,
      subtitle: l10n.trySelectAnotherType,
    );
  }

  Widget _buildLoadingState(AppLocalizations l10n) {
    final currentLabel = _selectedCategory != null
        ? DocumentTypeHelper.getLabel(_selectedCategory, l10n)
        : null;
    return DocumentsCardsSkeleton(selectedCategoryLabel: currentLabel);
  }

  Widget _buildErrorState(AppLocalizations l10n) {
    final selectedSemester = ref.watch(docsSemesterProvider);
    return Center(
      child: Container(
        margin: const EdgeInsets.all(40),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 20,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                size: 28,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.error,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF2D3142),
              ),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => ref.refresh(documentsProvider(selectedSemester)),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  l10n.retry,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Document card widget - iOS 26 premium style without entry hover animation
class _DocumentCard extends ConsumerWidget {
  final DocumentModel document;
  final List<DocumentModel>? allDocuments;

  const _DocumentCard({
    required this.document,
    this.allDocuments,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isRead = ref.watch(readDocumentsProvider).contains(document.id);
    final categoryColor = _DocumentsScreenState.getCategoryColor(document.category);
    final categoryIcon = _DocumentsScreenState.getCategoryIcon(document.category);

    final iconBoxSize = (52 * context.responsiveScale).clamp(42.0, 52.0);
    final iconInnerSize = (26 * context.responsiveScale).clamp(20.0, 26.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: BouncingWrapper(
        shrinkScale: 0.93,
        overshootScale: 1.055,
        delayNavigation: false,
        onTap: () {
          ref.read(readDocumentsProvider.notifier).markAsRead(document.id);
          _showDocumentDetails(context, document, allDocuments, ref);
        },
        child: Container(
          padding: EdgeInsets.all(AppResponsive.cardPadding(context, base: 16.0)),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.6),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
              children: [
                // Category icon with soft gradient matching document type
                Container(
                  width: iconBoxSize,
                  height: iconBoxSize,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [categoryColor, categoryColor.withValues(alpha: 0.75)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: categoryColor.withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    categoryIcon,
                    color: Colors.white,
                    size: iconInnerSize,
                  ),
                ),
                const SizedBox(width: 14),
                
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Category type as pure colored text
                      Text(
                        DocumentTypeHelper.getLabel(document.category, l10n),
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: categoryColor,
                          letterSpacing: 0.1,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      // Document Title
                      Text(
                        document.title,
                        style: ArabicTypography.subtitleStyle(
                          context,
                          fontSize: 15,
                          fontWeight: isRead ? FontWeight.w600 : FontWeight.w900,
                          color: isRead ? const Color(0xFF1F2937) : const Color(0xFF111827),
                          letterSpacing: -0.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (document.cleanDescription != null &&
                          document.cleanDescription!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          document.cleanDescription!,
                          style: ArabicTypography.bodyStyle(
                            context,
                            fontSize: 12,
                            fontWeight: isRead ? FontWeight.w400 : FontWeight.w700,
                            color: isRead ? Colors.grey[600] : const Color(0xFF374151),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 8),
                      // Bottom row: files count and size on left, since when received on right
                      Row(
                        children: [
                          if (document.batchInfo != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6D4CF6).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${document.batchInfo!['index']}/${document.batchInfo!['total']}',
                                style: ArabicTypography.bodyStyle(
                                  context,
                                  fontSize: 10.5,
                                  color: const Color(0xFF6D4CF6),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (document.fileSize != null) const SizedBox(width: 6),
                          ],
                          if (document.fileSize != null)
                            Text(
                              document.displayFileSize,
                              style: ArabicTypography.bodyStyle(
                                context,
                                fontSize: 11,
                                color: isRead ? Colors.grey[500] : const Color(0xFF6B7280),
                                fontWeight: isRead ? FontWeight.w400 : FontWeight.w600,
                              ),
                            ),
                          const Spacer(),
                          // Since when received time at bottom right (like announcement page)
                          Icon(
                            Icons.access_time_rounded,
                            size: 11,
                            color: isRead ? Colors.grey[400] : const Color(0xFF6B7280),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _DocumentsScreenState.formatRelativeTime(context, document.createdAt),
                            style: ArabicTypography.bodyStyle(
                              context,
                              fontSize: 10.5,
                              color: isRead ? Colors.grey[500] : const Color(0xFF6B7280),
                              fontWeight: isRead ? FontWeight.w400 : FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(width: 8),
                // Normal grey arrow pointing left in Arabic, right in Latin
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Icon(
                    ArabicTypography.isArabic(context)
                        ? Icons.chevron_left_rounded
                        : Icons.chevron_right_rounded,
                    size: 18,
                    color: Colors.grey[400],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
  }

  static void _showImageViewer(BuildContext context, String imageUrl, String fileName) {
    IosPhotoGalleryViewer.show(
      context: context,
      imageUrls: [imageUrl],
      initialIndex: 0,
    );
  }

  static Widget _buildImageDocCard(BuildContext context, DocumentModel doc) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.purple.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          // Small image thumbnail with bounce
          BouncingWrapper(
            shrinkScale: 0.90,
            overshootScale: 1.08,
            onTap: () => _showImageViewer(context, doc.fileUrl, doc.fileName),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 52,
                height: 52,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      doc.fileUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: Colors.grey[200],
                        child: const Icon(Icons.broken_image, size: 22, color: Colors.grey),
                      ),
                    ),
                    Container(
                      color: Colors.black.withValues(alpha: 0.15),
                      child: const Center(
                        child: Icon(Icons.zoom_in_rounded, size: 20, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: BouncingWrapper(
              behavior: HitTestBehavior.opaque,
              shrinkScale: 0.96,
              overshootScale: 1.04,
              onTap: () => _showImageViewer(context, doc.fileUrl, doc.fileName),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    doc.fileName.isNotEmpty ? doc.fileName : doc.displayTitle,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.purple[800],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    doc.fileSize != null ? '${doc.fileExtension} • ${doc.displayFileSize}' : doc.fileExtension,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.purple[600],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          BouncingWrapper(
            shrinkScale: 0.82,
            overshootScale: 1.18,
            onTap: () {
              Navigator.of(context, rootNavigator: true).pop();
              FileDownloadHelper.downloadFile(
                context: context,
                url: doc.fileUrl,
                fileName: doc.fileName,
              );
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.purple.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.download_rounded,
                size: 20,
                color: Colors.purple[700],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildFileDocCard(BuildContext context, DocumentModel doc) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.purple.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: BouncingWrapper(
              behavior: HitTestBehavior.opaque,
              shrinkScale: 0.96,
              overshootScale: 1.04,
              onTap: () => FileDownloadHelper.viewFile(
                context: context,
                url: doc.fileUrl,
                fileName: doc.fileName,
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.purple.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      doc.isPdf ? Icons.picture_as_pdf_rounded : Icons.description_rounded,
                      size: 22,
                      color: Colors.purple[700],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          doc.fileName.isNotEmpty ? doc.fileName : doc.displayTitle,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.purple[800],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          doc.fileSize != null ? '${doc.fileExtension} • ${doc.displayFileSize}' : doc.fileExtension,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.purple[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          BouncingWrapper(
            shrinkScale: 0.82,
            overshootScale: 1.18,
            onTap: () {
              Navigator.of(context, rootNavigator: true).pop();
              FileDownloadHelper.downloadFile(
                context: context,
                url: doc.fileUrl,
                fileName: doc.fileName,
              );
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.purple.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.download_rounded,
                size: 20,
                color: Colors.purple[700],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static void _showDocumentDetails(
    BuildContext context,
    DocumentModel document, [
    List<DocumentModel>? allDocs,
    WidgetRef? ref,
  ]) {
    if (ref != null) {
      ref.read(readDocumentsProvider.notifier).markAsRead(document.id);
    }
    final l10n = AppLocalizations.of(context);
    final categoryColor = _DocumentsScreenState.getCategoryColor(document.category);
    final categoryIcon = _DocumentsScreenState.getCategoryIcon(document.category);

    final batch = document.batchInfo;
    final displayTitle = document.displayTitle;
    final double titleFontSize = displayTitle.length > 40
        ? 14.0
        : (displayTitle.length > 24 ? 15.5 : 18.0);

    List<DocumentModel> batchFiles = [];
    if (batch != null && allDocs != null) {
      batchFiles = allDocs.where((d) =>
        d.displayTitle == document.displayTitle &&
        d.category == document.category
      ).toList();
      batchFiles.sort((a, b) => (a.batchInfo?['index'] ?? 0).compareTo(b.batchInfo?['index'] ?? 0));
    }
    if (batchFiles.isEmpty) {
      batchFiles = [document];
    }
    final bool isMultiFile = batchFiles.length > 1;

    DetailModalSheet.show(
      context: context,
      initialChildSize: 0.65,
      bottomAction: isMultiFile
          ? null
          : BouncingWrapper(
              behavior: HitTestBehavior.opaque,
              shrinkScale: 0.94,
              overshootScale: 1.05,
              delayNavigation: true,
              onTap: () async {
                Navigator.of(context, rootNavigator: true).pop();
                FileDownloadHelper.downloadFile(
                  context: context,
                  url: document.fileUrl,
                  fileName: document.fileName,
                );
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [categoryColor, categoryColor.withValues(alpha: 0.85)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: categoryColor.withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.download_rounded, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      l10n.translate('download'),
                      style: ArabicTypography.buttonStyle(
                        context,
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with icon, category pill, and date sent like an announcement
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [categoryColor, categoryColor.withValues(alpha: 0.75)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: categoryColor.withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(categoryIcon, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: categoryColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            document.displayCategory(l10n),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: categoryColor,
                            ),
                          ),
                        ),
                        if (isMultiFile)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6D4CF6).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.layers_outlined,
                                  size: 12,
                                  color: Color(0xFF6D4CF6),
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  '${batchFiles.length} fichiers',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF6D4CF6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.formatAnnouncementDateTime(document.createdAt),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          // Content area starting with title
          const SizedBox(height: 18),
          Text(
            displayTitle,
            style: ArabicTypography.headerStyle(
              context,
              fontSize: titleFontSize,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1F2937),
            ),
          ),
          
          if ((document.cleanDescription ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              document.cleanDescription!.trim(),
              style: ArabicTypography.bodyStyle(
                context,
                fontSize: 13.5,
                fontWeight: FontWeight.w400,
                color: Colors.grey[700],
                height: 1.45,
              ),
            ),
          ],
          
          const SizedBox(height: 16),
          
          // Files list matching announcement attachment design
          ...batchFiles.map((doc) => doc.isImage
              ? _buildImageDocCard(context, doc)
              : _buildFileDocCard(context, doc)),
        ],
      ),
    );
  }
}
