// ignore_for_file: unused_element, unused_local_variable, depend_on_referenced_packages, deprecated_member_use, unnecessary_underscores

import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/error_messages.dart';
import '../../providers/suggestions_provider.dart';
import '../../providers/classes_provider.dart';
import '../../providers/grade_levels_provider.dart';
import '../../../data/models/class_model.dart';
import '../../widgets/admin_sidebar.dart';
import '../../widgets/admin_sort_dropdown.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/user_avatar.dart';
import '../users/user_profile_screen.dart';

// =====================================================
// SMART SEARCH HELPERS (same as announcements)
// =====================================================

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

/// Get all searchable fields for a suggestion (including formatted dates)
String _getSearchableFields(Suggestion s) {
  final dateFormatter = DateFormat('dd/MM/yyyy HH:mm EEEE MMMM', 'fr_FR');

  // Type labels mapping for Tunisian students
  String typeLabel;
  switch (s.suggestionType) {
    case 'reclamation_note':
      typeLabel = 'réclamation note grade examen';
      break;
    case 'absence':
      typeLabel = 'absence justification manque cours';
      break;
    case 'emploi_temps':
      typeLabel = 'emploi temps horaire planning seance';
      break;
    case 'inscription':
      typeLabel = 'inscription réinscription dossier';
      break;
    case 'paiement':
      typeLabel = 'paiement frais scolarité cotisation argent';
      break;
    case 'orientation':
      typeLabel = 'orientation filière changement spécialité';
      break;
    case 'bourse':
      typeLabel = 'bourse aide sociale financière';
      break;
    case 'transport':
      typeLabel = 'transport hébergement foyer bus';
      break;
    case 'restauration':
      typeLabel = 'restauration resto universitaire cantine';
      break;
    case 'bibliotheque':
      typeLabel = 'bibliothèque ressources livres';
      break;
    case 'vie_universitaire':
      typeLabel = 'vie universitaire activités club';
      break;
    case 'infrastructure':
      typeLabel = 'infrastructure équipements salle';
      break;
    case 'securite':
      typeLabel = 'sécurité hygiène';
      break;
    case 'autre':
      typeLabel = 'autre divers';
      break;
    default:
      typeLabel = 'général general';
  }

  // Status labels
  String statusLabel;
  switch (s.status) {
    case 'pending':
      statusLabel = 'en attente pending';
      break;
    case 'in_review':
      statusLabel = 'en cours review examen';
      break;
    case 'replied':
      statusLabel = 'répondu reply';
      break;
    case 'closed':
      statusLabel = 'fermé closed';
      break;
    default:
      statusLabel = s.status;
  }

  // Build all searchable text
  final fields = [
    s.subject,
    s.content,
    s.studentName ?? '',
    s.studentCode ?? '',
    s.className ?? '',
    typeLabel,
    statusLabel,
    dateFormatter.format(s.createdAt),
    s.isRead ? 'lu read' : 'non lu unread nouveau',
    s.hasAttachment ? 'pièce jointe fichier attachment' : '',
  ];

  return fields.join(' ');
}

/// Format relative time for suggestions (e.g. "Reçu il y a 5 min")
String _getRelativeTime(DateTime dt) {
  final now = DateTime.now();
  final diff = now.difference(dt);
  if (diff.inSeconds < 60) return "Reçu à l'instant";
  if (diff.inMinutes < 60) return "Reçu il y a ${diff.inMinutes} min";
  if (diff.inHours < 24) return "Reçu il y a ${diff.inHours}h";
  if (diff.inDays == 1) return "Reçu hier";
  if (diff.inDays < 7) return "Reçu il y a ${diff.inDays} j";
  if (diff.inDays < 30) return "Reçu il y a ${(diff.inDays / 7).floor()} sem";
  return "Reçu le ${DateFormat('d MMM yyyy', 'fr_FR').format(dt)}";
}

/// Convert abbreviated level code (e.g. 9B, 7B) to full French name
String _getFullNiveauName(String raw) {
  final clean = raw.trim();
  if (clean.isEmpty) return '';
  final upper = clean.toUpperCase();
  if (upper == '7B' || upper == '7' || upper.startsWith('7EME') || upper.startsWith('7È') || upper.startsWith('7E')) {
    return '7ème année de base';
  }
  if (upper == '8B' || upper == '8' || upper.startsWith('8EME') || upper.startsWith('8È') || upper.startsWith('8E')) {
    return '8ème année de base';
  }
  if (upper == '9B' || upper == '9' || upper.startsWith('9EME') || upper.startsWith('9È') || upper.startsWith('9E')) {
    return '9ème année de base';
  }
  if (upper == '1S' || upper.startsWith('1ERE') || upper.startsWith('1È') || upper.startsWith('1ER')) {
    return '1ère année secondaire';
  }
  if (upper == '2S' || upper.startsWith('2EME') || upper.startsWith('2È') || upper.startsWith('2E')) {
    return '2ème année secondaire';
  }
  if (upper == '3S' || upper.startsWith('3EME') || upper.startsWith('3È') || upper.startsWith('3E')) {
    return '3ème année secondaire';
  }
  if (upper == '4S' || upper == 'BAC' || upper.startsWith('4EME') || upper.startsWith('4È') || upper.startsWith('4E')) {
    return '4ème année (Bac)';
  }
  return clean;
}

/// Highlight matching text in a string
Widget _highlightText(
  String text,
  String query,
  TextStyle? baseStyle, {
  int maxLines = 2,
}) {
  if (query.isEmpty) {
    return Text(
      text,
      style: baseStyle,
      maxLines: maxLines,
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
      maxLines: maxLines,
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
      maxLines: maxLines,
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
              fontWeight: FontWeight.w700,
            ) ??
            TextStyle(
              backgroundColor: AppColors.warningSoft,
              fontWeight: FontWeight.w700,
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
    maxLines: maxLines,
    overflow: TextOverflow.ellipsis,
  );
}

class _MatchRange {
  int start;
  int end;
  _MatchRange(this.start, this.end);
}

class SuggestionsScreen extends ConsumerStatefulWidget {
  const SuggestionsScreen({super.key});

  @override
  ConsumerState<SuggestionsScreen> createState() => _SuggestionsScreenState();
}

class _SuggestionsScreenState extends ConsumerState<SuggestionsScreen> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  bool _showFilters = false;
  String _sortKey = 'date_desc';
  final Set<String> _selectedIds = {};
  bool _selectionMode = false;
  bool _isPerformingAction = false;

  // Pagination state
  int _currentPage = 1;
  int _itemsPerPage = 10;
  static const List<int> _perPageOptions = [10, 20, 50, 100, -1];


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(suggestionsProvider.notifier).clearFilters();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
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

  void _selectAll(List<Suggestion> suggestions) {
    setState(() {
      if (_selectedIds.length == suggestions.length) {
        _selectedIds.clear();
        _selectionMode = false;
      } else {
        _selectedIds.addAll(suggestions.map((s) => s.id));
        _selectionMode = true;
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedIds.clear();
      _selectionMode = false;
    });
  }

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;
    final count = _selectedIds.length;

    final confirm = await showDialog<bool>(
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
                decoration: BoxDecoration(color: AppColors.errorSoft, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 18),
              ),
              const SizedBox(width: 12),
              const Text('Supprimer en masse ?', style: TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Voulez-vous vraiment supprimer $count suggestion(s) ?'),
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
                SizedBox(
                  height: 40,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF6B7280),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Annuler', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 40,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(ctx, true),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Supprimer', style: TextStyle(fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                      foregroundColor: Colors.white,
                      elevation: 2,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (confirm == true) {
      setState(() => _isPerformingAction = true);
      try {
        await ref.read(suggestionsProvider.notifier).deleteMultiple(_selectedIds.toList());
        _clearSelection();
      } finally {
        if (mounted) setState(() => _isPerformingAction = false);
      }
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(suggestionsProvider.notifier).setSearchQuery(value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final suggestionsAsync = ref.watch(suggestionsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Row(
            children: [
              const AdminSidebar(currentRoute: '/suggestions'),
              Expanded(
                child: Column(
                  children: [
                    _buildTopBar(context, suggestionsAsync),
                    Expanded(
                      child: _isPerformingAction
                          ? const SuggestionsSkeletonLoader()
                          : suggestionsAsync.when(
                              loading: () => const SuggestionsSkeletonLoader(),
                        error: (e, _) => Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error),
                              const SizedBox(height: 16),
                              Text(
                                UserFriendlyError.format(
                                  e,
                                  fallback: 'Unable to load suggestions right now. Please try again.',
                                ),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: () => ref
                                    .read(suggestionsProvider.notifier)
                                    .refresh(),
                                child: const Text('Réessayer'),
                              ),
                            ],
                          ),
                        ),
                        data: (state) => _buildContent(context, ref, state),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_showFilters) _buildFilterPanel(suggestionsAsync),
          if (_selectedIds.isNotEmpty)
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Center(child: _buildFloatingSelectionBar(context)),
            ),
        ],
      ),
    );
  }

  Widget _buildTopBar(
    BuildContext context,
    AsyncValue<SuggestionsState> suggestionsAsync,
  ) {
    final unreadCount = suggestionsAsync.whenOrNull(data: (s) => s.unreadCount) ?? 0;
    final pendingCount = suggestionsAsync.whenOrNull(data: (s) => s.pendingCount) ?? 0;
    final totalCount = suggestionsAsync.whenOrNull(data: (s) => s.suggestions.length) ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE9EAF2))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Suggestions',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$totalCount suggestions • $unreadCount non lu(s) • $pendingCount en attente',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
            ],
          ),
          const Spacer(),
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
                suffixIcon: _searchController.text.isEmpty
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
                          ref.read(suggestionsProvider.notifier).setSearchQuery('');
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
          const SizedBox(width: 12),
          AdminSortDropdown<String>(
            value: _sortKey,
            tooltip: 'Trier les suggestions',
            onChanged: (v) => setState(() {
              _sortKey = v;
              _currentPage = 1;
            }),
            options: const [
              SortOption(value: 'date_desc', label: 'Date (Plus récent)', icon: Icons.calendar_today_outlined),
              SortOption(value: 'date_asc', label: 'Date (Plus ancien)', icon: Icons.calendar_today_outlined),
              SortOption(value: 'pending_first', label: 'En attente d’abord', icon: Icons.hourglass_top),
              SortOption(value: 'unread_first', label: 'Non lues d’abord', icon: Icons.mark_email_unread_outlined),
              SortOption(value: 'subject_asc', label: 'Sujet (A → Z)', icon: Icons.sort_by_alpha),
              SortOption(value: 'subject_desc', label: 'Sujet (Z → A)', icon: Icons.sort_by_alpha),
              SortOption(value: 'student_asc', label: 'Étudiant (A → Z)', icon: Icons.person_outline),
            ],
          ),
          const SizedBox(width: 8),
          _buildHeaderIconButton(
            icon: Icons.filter_list_rounded,
            tooltip: 'Filtres',
            isActive: _showFilters || _hasActiveFilters(suggestionsAsync),
            onPressed: () => setState(() => _showFilters = !_showFilters),
          ),
          const SizedBox(width: 8),
          _buildHeaderIconButton(
            icon: Icons.refresh,
            tooltip: 'Actualiser',
            onPressed: () => ref.read(suggestionsProvider.notifier).refresh(),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingSelectionBar(BuildContext context) {
    final count = _selectedIds.length;
    final state = ref.watch(suggestionsProvider).value;
    final selectedSuggestions = state?.suggestions
        .where((s) => _selectedIds.contains(s.id))
        .toList() ?? [];
    final allRead = selectedSuggestions.isNotEmpty &&
        selectedSuggestions.every((s) => s.isRead);

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
              allRead ? Icons.mark_email_unread_outlined : Icons.mark_email_read_outlined,
              allRead ? 'Marquer non lu' : 'Marquer lu',
              Colors.white70,
              () async {
                setState(() => _isPerformingAction = true);
                try {
                  for (final id in _selectedIds.toList()) {
                    if (allRead) {
                      await ref.read(suggestionsProvider.notifier).markAsUnread(id);
                    } else {
                      await ref.read(suggestionsProvider.notifier).markAsRead(id);
                    }
                  }
                  _clearSelection();
                } finally {
                  if (mounted) setState(() => _isPerformingAction = false);
                }
              },
            ),
            _buildSelectionAction(
              Icons.delete_outline,
              'Supprimer',
              const Color(0xFFFCA5A5),
              () => _deleteSelected(),
            ),
            // Close button
            Container(
              margin: const EdgeInsets.only(left: 4),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: Colors.white.withOpacity(0.15))),
              ),
              child: IconButton(
                icon: const Icon(Icons.close, size: 16, color: Colors.white60),
                onPressed: _clearSelection,
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

  bool _hasActiveFilters(AsyncValue<SuggestionsState> suggestionsAsync) {
    return suggestionsAsync.whenOrNull(
          data: (state) =>
              state.statusFilter != 'all' ||
              state.typeFilter != 'all' ||
              state.niveauFilter != 'all' ||
              state.fieldFilter != 'all' ||
              state.classFilter != 'all' ||
              state.dateFrom != null ||
              state.dateTo != null,
        ) ??
        false;
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

  Widget _buildFilterPanel(AsyncValue<SuggestionsState> suggestionsAsync) {
    return Positioned.fill(
      child: GestureDetector(
        onTap: () => setState(() => _showFilters = false),
        child: Stack(
          children: [
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(color: Colors.black.withValues(alpha: 0.30)),
            ),
            Positioned(
              top: 0,
              bottom: 0,
              right: 0,
              child: GestureDetector(
                onTap: () {}, // Prevent tap from closing panel
                child: Container(
                  width: 360,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 24,
                        offset: const Offset(-4, 0),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
                        child: Row(
                          children: [
                            const Text('Filtres', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                            const Spacer(),
                            InkWell(
                              onTap: () => setState(() => _showFilters = false),
                              borderRadius: BorderRadius.circular(8),
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(Icons.close, size: 22, color: AppColors.textSecondary),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: suggestionsAsync.whenOrNull(
                            data: (state) => Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('STATUT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.0, color: AppColors.slate400)),
                                const SizedBox(height: 12),
                                _buildStyledDropdown<String>(
                                  value: state.statusFilter,
                                  defaultValue: 'all',
                                  items: const [
                                    DropdownMenuItem(value: 'all', child: Text('Tous les statuts')),
                                    DropdownMenuItem(value: 'unread', child: Text('Non lus')),
                                    DropdownMenuItem(value: 'read', child: Text('Lus')),
                                    DropdownMenuItem(value: 'sent', child: Text('Envoyé')),
                                    DropdownMenuItem(value: 'replied', child: Text('Répondu')),
                                  ],
                                  onChanged: (v) => ref.read(suggestionsProvider.notifier).setStatusFilter(v!),
                                ),
                                const SizedBox(height: 28),
                                const Text('TYPE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.0, color: AppColors.slate400)),
                                const SizedBox(height: 12),
                                _buildStyledDropdown<String>(
                                  value: state.typeFilter,
                                  defaultValue: 'all',
                                  items: const [
                                    DropdownMenuItem(value: 'all', child: Text('Tous les types')),
                                    DropdownMenuItem(value: 'general', child: Text('Général')),
                                    DropdownMenuItem(value: 'reclamation_note', child: Text('Réclamation note')),
                                    DropdownMenuItem(value: 'absence', child: Text('Absence')),
                                    DropdownMenuItem(value: 'emploi_temps', child: Text('Emploi du temps')),
                                    DropdownMenuItem(value: 'inscription', child: Text('Inscription')),
                                    DropdownMenuItem(value: 'paiement', child: Text('Paiement')),
                                    DropdownMenuItem(value: 'stage', child: Text('Stage / PFE')),
                                    DropdownMenuItem(value: 'orientation', child: Text('Orientation')),
                                    DropdownMenuItem(value: 'bourse', child: Text('Bourse')),
                                    DropdownMenuItem(value: 'transport', child: Text('Transport')),
                                    DropdownMenuItem(value: 'restauration', child: Text('Restauration')),
                                    DropdownMenuItem(value: 'bibliotheque', child: Text('Bibliothèque')),
                                    DropdownMenuItem(value: 'vie_universitaire', child: Text('Vie universitaire')),
                                    DropdownMenuItem(value: 'infrastructure', child: Text('Infrastructure')),
                                    DropdownMenuItem(value: 'securite', child: Text('Sécurité')),
                                    DropdownMenuItem(value: 'autre', child: Text('Autre')),
                                  ],
                                  onChanged: (v) => ref.read(suggestionsProvider.notifier).setTypeFilter(v!),
                                ),
                                const SizedBox(height: 28),
                                Builder(
                                  builder: (context) {
                                    final classesState = ref.watch(classesProvider).value;
                                    final gradeLevelsState = ref.watch(gradeLevelsProvider).value;
                                    final allClasses = classesState?.classes ?? [];
                                    final allGradeLevels = gradeLevelsState?.gradeLevels ?? [];

                                    // 1. Available Niveaux
                                    final niveauSet = <String>{};
                                    for (final gl in allGradeLevels) {
                                      if (gl.name.trim().isNotEmpty) niveauSet.add(gl.name.trim());
                                    }
                                    for (final c in allClasses) {
                                      final lvl = c.level ?? c.gradeLevelName;
                                      if (lvl != null && lvl.trim().isNotEmpty) niveauSet.add(lvl.trim());
                                    }
                                    for (final s in state.suggestions) {
                                      if (s.studentLevel != null && s.studentLevel!.trim().isNotEmpty) {
                                        niveauSet.add(s.studentLevel!.trim());
                                      }
                                    }
                                    final availableNiveaux = niveauSet.toList()..sort();

                                    // 2. Check if selected niveau has filières
                                    final selectedNiveau = state.niveauFilter;
                                    List<String> availableFields = [];
                                    if (selectedNiveau != 'all') {
                                      final selLevelLower = selectedNiveau.toLowerCase().trim();
                                      final niveauClasses = allClasses.where((c) {
                                        final cLevel = (c.level ?? c.gradeLevelName ?? '').toLowerCase().trim();
                                        return cLevel == selLevelLower || cLevel.contains(selLevelLower) || selLevelLower.contains(cLevel);
                                      }).toList();

                                      final fieldSet = <String>{};
                                      for (final c in niveauClasses) {
                                        final sec = c.section ?? c.sectionName;
                                        if (sec != null && sec.trim().isNotEmpty && sec.trim().toLowerCase() != 'commun' && sec.trim().toLowerCase() != 'tronc commun') {
                                          fieldSet.add(sec.trim());
                                        }
                                      }
                                      for (final s in state.suggestions) {
                                        final sLevel = (s.studentLevel ?? s.className ?? '').toLowerCase().trim();
                                        if (sLevel.contains(selLevelLower) || selLevelLower.contains(sLevel)) {
                                          if (s.studentField != null && s.studentField!.trim().isNotEmpty) {
                                            fieldSet.add(s.studentField!.trim());
                                          }
                                        }
                                      }
                                      availableFields = fieldSet.toList()..sort();
                                    }

                                    // 3. Selectable classes
                                    var filteredClasses = allClasses;
                                    if (selectedNiveau != 'all') {
                                      final selLevelLower = selectedNiveau.toLowerCase().trim();
                                      filteredClasses = filteredClasses.where((c) {
                                        final cLevel = (c.level ?? c.gradeLevelName ?? '').toLowerCase().trim();
                                        return cLevel == selLevelLower || cLevel.contains(selLevelLower) || selLevelLower.contains(cLevel);
                                      }).toList();
                                    }
                                    if (state.fieldFilter != 'all') {
                                      final selFieldLower = state.fieldFilter.toLowerCase().trim();
                                      filteredClasses = filteredClasses.where((c) {
                                        final cField = (c.section ?? c.sectionName ?? '').toLowerCase().trim();
                                        return cField == selFieldLower || cField.contains(selFieldLower);
                                      }).toList();
                                    }

                                    final classItems = <String, String>{};
                                    for (final c in filteredClasses) {
                                      classItems[c.id] = c.name;
                                    }
                                    for (final s in state.suggestions) {
                                      if (s.classId != null && s.className != null) {
                                        bool matches = true;
                                        if (selectedNiveau != 'all') {
                                          final sLevel = (s.studentLevel ?? s.className ?? '').toLowerCase().trim();
                                          matches = sLevel.contains(selectedNiveau.toLowerCase().trim());
                                        }
                                        if (matches && state.fieldFilter != 'all') {
                                          final sField = (s.studentField ?? s.className ?? '').toLowerCase().trim();
                                          matches = sField.contains(state.fieldFilter.toLowerCase().trim());
                                        }
                                        if (matches) {
                                          classItems.putIfAbsent(s.classId!, () => s.className!);
                                        }
                                      }
                                    }

                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // NIVEAU
                                        const Text('NIVEAU', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.0, color: AppColors.slate400)),
                                        const SizedBox(height: 12),
                                        _buildStyledDropdown<String>(
                                          value: availableNiveaux.contains(state.niveauFilter) ? state.niveauFilter : 'all',
                                          defaultValue: 'all',
                                          items: [
                                            const DropdownMenuItem(value: 'all', child: Text('Tous les niveaux')),
                                            ...availableNiveaux.map((n) => DropdownMenuItem(value: n, child: Text(n))),
                                          ],
                                          onChanged: (v) => ref.read(suggestionsProvider.notifier).setNiveauFilter(v!),
                                        ),
                                        const SizedBox(height: 28),

                                        // FILIÈRE (only shown if filières exist for that niveau)
                                        if (availableFields.isNotEmpty) ...[
                                          const Text('FILIÈRE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.0, color: AppColors.slate400)),
                                          const SizedBox(height: 12),
                                          _buildStyledDropdown<String>(
                                            value: availableFields.contains(state.fieldFilter) ? state.fieldFilter : 'all',
                                            defaultValue: 'all',
                                            items: [
                                              const DropdownMenuItem(value: 'all', child: Text('Toutes les filières')),
                                              ...availableFields.map((f) => DropdownMenuItem(value: f, child: Text(f))),
                                            ],
                                            onChanged: (v) => ref.read(suggestionsProvider.notifier).setFieldFilter(v!),
                                          ),
                                          const SizedBox(height: 28),
                                        ],

                                        // CLASSE
                                        const Text('CLASSE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.0, color: AppColors.slate400)),
                                        const SizedBox(height: 12),
                                        _buildStyledDropdown<String>(
                                          value: classItems.containsKey(state.classFilter) ? state.classFilter : 'all',
                                          defaultValue: 'all',
                                          items: [
                                            const DropdownMenuItem(value: 'all', child: Text('Toutes les classes')),
                                            ...classItems.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))),
                                          ],
                                          onChanged: (v) => ref.read(suggestionsProvider.notifier).setClassFilter(v!),
                                        ),
                                        const SizedBox(height: 28),
                                      ],
                                    );
                                  },
                                ),
                                const Text('PÉRIODE (DATE)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.0, color: AppColors.slate400)),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text('DU', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.slate500)),
                                          const SizedBox(height: 6),
                                          _buildFilterDateField('Du', state.dateFrom, (d) {
                                            ref.read(suggestionsProvider.notifier).setDateRange(d, state.dateTo);
                                          }),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text('AU', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.slate500)),
                                          const SizedBox(height: 6),
                                          _buildFilterDateField('Au', state.dateTo, (d) {
                                            ref.read(suggestionsProvider.notifier).setDateRange(state.dateFrom, d);
                                          }),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
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
                                  onPressed: () => ref.read(suggestionsProvider.notifier).clearFilters(),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF374151),
                                    backgroundColor: Colors.white,
                                    side: const BorderSide(color: Color(0xFFD1D5DB)),
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    elevation: 0,
                                  ),
                                  child: const Text('Réinitialiser', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
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
                                      color: const Color(0xFF6D4CF6).withValues(alpha: 0.3),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () => setState(() => _showFilters = false),
                                    borderRadius: BorderRadius.circular(12),
                                    child: const Center(
                                      child: Text('Appliquer', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
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

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    SuggestionsState state,
  ) {
    final searchQuery = state.searchQuery;
    final rawList = state.filtered;
    final list = List<Suggestion>.from(rawList);
    switch (_sortKey) {
      case 'date_asc':
        list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
      case 'pending_first':
        list.sort((a, b) {
          final aPending = a.status == 'pending' ? 0 : 1;
          final bPending = b.status == 'pending' ? 0 : 1;
          if (aPending != bPending) return aPending.compareTo(bPending);
          return b.createdAt.compareTo(a.createdAt);
        });
        break;
      case 'unread_first':
        list.sort((a, b) {
          final aUnread = !a.isRead ? 0 : 1;
          final bUnread = !b.isRead ? 0 : 1;
          if (aUnread != bUnread) return aUnread.compareTo(bUnread);
          return b.createdAt.compareTo(a.createdAt);
        });
        break;
      case 'subject_asc':
        list.sort((a, b) => a.subject.toLowerCase().compareTo(b.subject.toLowerCase()));
        break;
      case 'subject_desc':
        list.sort((a, b) => b.subject.toLowerCase().compareTo(a.subject.toLowerCase()));
        break;
      case 'student_asc':
        list.sort((a, b) => (a.studentName ?? '').toLowerCase().compareTo((b.studentName ?? '').toLowerCase()));
        break;
      case 'date_desc':
      default:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
    }
    
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox_outlined, size: 64, color: AppColors.slate200),
            const SizedBox(height: 16),
            const Text(
              'Aucune suggestion',
              style: TextStyle(color: AppColors.textTertiary),
            ),
            if (state.suggestions.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Essayez de modifier les filtres',
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    final totalPages = _itemsPerPage == -1 ? 1 : (list.length / _itemsPerPage).ceil();
    if (_currentPage > totalPages && totalPages > 0) _currentPage = totalPages;
    final startIndex = _itemsPerPage == -1 ? 0 : (_currentPage - 1) * _itemsPerPage;
    final endIndex = _itemsPerPage == -1 ? list.length : (startIndex + _itemsPerPage).clamp(0, list.length);
    final pageSuggestions = list.sublist(startIndex, endIndex);

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
                  itemCount: pageSuggestions.length,
                  itemBuilder: (context, index) {
                    final s = pageSuggestions[index];
                    return _SuggestionCard(
                      suggestion: s,
                      searchQuery: searchQuery,
                      isSelected: _selectedIds.contains(s.id),
                      selectionMode: _selectionMode,
                      onSelect: () => _toggleSelection(s.id),
                      onAction: (action) => _handleAction(action, s),
                    );
                  },
                ),
              ),
              _buildPagination(list.length),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectAllBar(List<Suggestion> list) {
    final allSelected =
        _selectedIds.length == list.length && list.isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.slate50,
        border: Border(
          bottom: BorderSide(color: AppColors.border.withOpacity(0.5)),
        ),
      ),
      child: Row(
        children: [
          Checkbox(
            value: allSelected,
            tristate: _selectedIds.isNotEmpty && !allSelected,
            onChanged: (_) => _selectAll(list),
            activeColor: const Color(0xFF655DD5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: () => _selectAll(list),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                allSelected ? 'Tout désélectionner' : 'Tout sélectionner',
                style: const TextStyle(
                  color: AppColors.slate700,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          const Spacer(),
          Text(
            '${list.length} suggestion(s)',
            style: const TextStyle(
              color: AppColors.slate500,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPagination(int totalItems) {
    final totalPages = _itemsPerPage == -1 ? 1 : (totalItems / _itemsPerPage).ceil();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
          // Items per page
          Text('Afficher par ', style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _itemsPerPage,
                isDense: true,
                borderRadius: BorderRadius.circular(10),
                dropdownColor: Colors.white,
                elevation: 4,
                menuMaxHeight: 200,
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: AppColors.textTertiary),
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                items: _perPageOptions.map((v) => DropdownMenuItem(
                  value: v,
                  child: Text(v == -1 ? 'All' : '$v', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
                )).toList(),
                onChanged: (v) => setState(() {
                  _itemsPerPage = v!;
                  _currentPage = 1;
                }),
              ),
            ),
          ),
          const Spacer(),
          // Page info
          Text(
            'Page $_currentPage sur ${totalPages == 0 ? 1 : totalPages}',
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
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
                  onTap: _currentPage > 1 ? () => setState(() => _currentPage--) : null,
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(5)),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.chevron_left, size: 18, color: _currentPage > 1 ? AppColors.textSecondary : AppColors.textTertiary),
                  ),
                ),
                Container(width: 1, height: 24, color: AppColors.border),
                InkWell(
                  onTap: _currentPage < totalPages ? () => setState(() => _currentPage++) : null,
                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(5)),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.chevron_right, size: 18, color: _currentPage < totalPages ? AppColors.textSecondary : AppColors.textTertiary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _handleAction(String action, Suggestion s) {
    switch (action) {
      case 'reply':
        _showReplyDialog(context, ref, s);
        break;
      case 'read':
        setState(() => _isPerformingAction = true);
        ref.read(suggestionsProvider.notifier).markAsRead(s.id).whenComplete(() {
          if (mounted) setState(() => _isPerformingAction = false);
        });
        break;
      case 'unread':
        setState(() => _isPerformingAction = true);
        ref.read(suggestionsProvider.notifier).markAsUnread(s.id).whenComplete(() {
          if (mounted) setState(() => _isPerformingAction = false);
        });
        break;
      case 'view':
        _showDetailDialog(context, s);
        break;
      case 'delete':
        _confirmDelete(s);
        break;
      case 'viewStudent':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                UserProfileScreen(userId: s.studentId, userName: s.studentName),
          ),
        );
        break;
    }
  }

  Future<void> _confirmDelete(Suggestion s) async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.08),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: AppColors.errorSoft, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 18),
              ),
              const SizedBox(width: 12),
              const Text('Supprimer la suggestion ?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Voulez-vous vraiment supprimer "${s.subject}" ?'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: AppColors.slate50, borderRadius: BorderRadius.circular(6)),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 16, color: AppColors.textTertiary),
                    const SizedBox(width: 8),
                    Text('De: ${s.studentName ?? 'Étudiant inconnu'}', style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
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
                SizedBox(
                  height: 40,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF6B7280),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Annuler', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 40,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(ctx, true),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Supprimer', style: TextStyle(fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                      foregroundColor: Colors.white,
                      elevation: 2,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (confirm == true) {
      setState(() => _isPerformingAction = true);
      try {
        await ref.read(suggestionsProvider.notifier).delete(s.id);
      } finally {
        if (mounted) setState(() => _isPerformingAction = false);
      }
    }
  }

  void _showReplyDialog(BuildContext context, WidgetRef ref, Suggestion s) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Répondre à: ${s.subject}'),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Original message preview
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.slate100,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          s.studentName ?? 'Anonyme',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        if (s.className != null) ...[
                          const Text(' • '),
                          Text(
                            s.className!,
                            style: TextStyle(color: AppColors.textTertiary),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      s.content,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Votre réponse',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                maxLines: 4,
              ),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        actions: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
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
                    onPressed: () {
                      if (controller.text.isEmpty) return;
                      ref.read(suggestionsProvider.notifier).reply(s.id, controller.text);
                      Navigator.pop(ctx);
                    },
                    icon: const Icon(Icons.send, size: 16),
                    label: const Text('Envoyer', style: TextStyle(fontWeight: FontWeight.w700)),
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
  }

  void _showEditReplyDialog(BuildContext context, WidgetRef ref, Suggestion s, SuggestionReply reply) {
    final controller = TextEditingController(text: reply.message);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Modifier la réponse'),
        content: SizedBox(
          width: 500,
          child: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Votre réponse',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
            maxLines: 4,
            autofocus: true,
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        actions: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
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
                    onPressed: () {
                      if (controller.text.isEmpty) return;
                      ref.read(suggestionsProvider.notifier).updateReply(reply.id, controller.text);
                      Navigator.pop(ctx);
                    },
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Modifier', style: TextStyle(fontWeight: FontWeight.w700)),
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
  }

  void _showDetailDialog(BuildContext context, Suggestion s) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.08),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        child: Container(
          width: 700,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.slate100)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.speaker_notes, color: Color(0xFF6D4CF6), size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Détails de la suggestion',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Consultez et gérez cette demande.',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.slate500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    InkWell(
                      onTap: () => Navigator.pop(ctx),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(shape: BoxShape.circle),
                        child: const Icon(Icons.close, size: 22, color: AppColors.slate400),
                      ),
                    ),
                  ],
                ),
              ),
              
              // Body
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Student Header: Avatar, Name, Combined Pill & plain category text (click to view profile)
                      Builder(
                        builder: (context) {
                          final classesList = ref.read(classesProvider).value?.classes ?? [];
                          ClassModel? matchedClass;
                          try {
                            matchedClass = classesList.firstWhere(
                              (c) => (s.classId != null && c.id == s.classId) || (s.className != null && c.name.toLowerCase() == s.className!.toLowerCase()),
                            );
                          } catch (_) {}

                          final effectiveClass = (s.className?.isNotEmpty == true) ? s.className! : (matchedClass?.name ?? '');
                          final rawLevel = (s.studentLevel?.isNotEmpty == true) ? s.studentLevel! : (matchedClass?.gradeLevelName ?? matchedClass?.level ?? '');
                          final effectiveLevel = _getFullNiveauName(rawLevel);
                          final effectiveField = (s.studentField?.isNotEmpty == true) ? s.studentField! : (matchedClass?.sectionName ?? matchedClass?.section ?? '');

                          final combinedPill = [
                            if (effectiveClass.isNotEmpty) effectiveClass,
                            if (effectiveLevel.isNotEmpty) effectiveLevel,
                            if (effectiveField.isNotEmpty) effectiveField,
                          ].join(' • ');

                          return MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: GestureDetector(
                              onTap: () {
                                Navigator.pop(ctx);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => UserProfileScreen(
                                      userId: s.studentId,
                                      userName: s.studentName,
                                    ),
                                  ),
                                );
                              },
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  UserAvatar(
                                    name: (s.studentName?.isNotEmpty == true)
                                        ? s.studentName!
                                        : 'Étudiant',
                                    photoUrl: s.studentPhotoUrl,
                                    gender: s.studentGender,
                                    radius: 22,
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          s.studentName ?? 'Étudiant inconnu',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                        if (combinedPill.isNotEmpty) ...[
                                          const SizedBox(height: 3),
                                          Text(
                                            combinedPill,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                              color: Color(0xFF64748B),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      
                      const SizedBox(height: 20),
                      const Divider(color: AppColors.slate100, height: 1),
                      const SizedBox(height: 20),
                      
                      // Message Content: Subject & Body
                      if (s.subject.isNotEmpty && s.subject.trim().toLowerCase() != s.typeLabel.trim().toLowerCase()) ...[
                        Text(
                          s.subject,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      SelectableText(
                        s.content.isNotEmpty ? s.content : '(Aucun contenu)',
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.6,
                          color: Color(0xFF334155),
                        ),
                      ),
                      
                      if (s.attachments.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        _AttachmentsGrid(attachments: s.attachments),
                      ],

                      // Bottom Sent Date (Neutral color, aligned right, no line above)
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          const Icon(Icons.schedule, size: 14, color: AppColors.slate400),
                          const SizedBox(width: 6),
                          Text(
                            'Envoyé ${_getRelativeTime(s.createdAt).replaceFirst('Reçu ', '')} • ${DateFormat('dd MMM yyyy à HH:mm', 'fr_FR').format(s.createdAt)}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppColors.slate500,
                            ),
                          ),
                        ],
                      ),
                      
                      // Replies Section
                      if (s.replies.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        const Divider(color: AppColors.slate100, height: 1),
                        const SizedBox(height: 16),
                        Text(
                          'RÉPONSES (${s.replies.length})',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF64748B),
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 14),
                        ...s.replies.map((reply) => Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.slate200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEEF2FF),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Icon(Icons.admin_panel_settings, size: 14, color: Color(0xFF6D4CF6)),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Administration',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    DateFormat("d MMM yyyy 'à' HH:mm", 'fr_FR').format(reply.createdAt),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.slate500,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined, size: 16),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                    color: AppColors.slate400,
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      _showEditReplyDialog(context, ref, s, reply);
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 16),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                    color: AppColors.error,
                                    onPressed: () {
                                      showDialog(
                                        context: ctx,
                                        builder: (dialogCtx) => AlertDialog(
                                          title: const Text('Supprimer la réponse'),
                                          content: const Text('Êtes-vous sûr de vouloir supprimer cette réponse ?'),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(dialogCtx),
                                              child: const Text('Annuler'),
                                            ),
                                            TextButton(
                                              onPressed: () {
                                                ref.read(suggestionsProvider.notifier).deleteReply(reply.id);
                                                Navigator.pop(dialogCtx);
                                                Navigator.pop(ctx);
                                              },
                                              child: const Text('Supprimer', style: TextStyle(color: AppColors.error)),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                reply.message,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: AppColors.textSecondary,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        )),
                      ],
                    ],
                  ),
                ),
              ),
              
              // Bottom Actions
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                  border: Border(top: BorderSide(color: AppColors.slate100)),
                ),
                child: Row(
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: const Text(
                        'Supprimer',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.error,
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _confirmDelete(s);
                      },
                    ),
                    const Spacer(),
                    if (!s.isRead) ...[
                      SizedBox(
                        height: 40,
                        child: OutlinedButton(
                          onPressed: () {
                            ref.read(suggestionsProvider.notifier).markAsRead(s.id);
                            Navigator.pop(ctx);
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF6D4CF6),
                            side: const BorderSide(color: Color(0xFF6D4CF6)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Marquer lu', style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    SizedBox(
                      height: 40,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.reply, size: 18),
                        label: const Text('Répondre', style: TextStyle(fontWeight: FontWeight.w600)),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showReplyDialog(context, ref, s);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6D4CF6),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  final Suggestion suggestion;
  final String searchQuery;
  final bool isSelected;
  final bool selectionMode;
  final VoidCallback onSelect;
  final Function(String) onAction;

  const _SuggestionCard({
    required this.suggestion,
    required this.searchQuery,
    required this.isSelected,
    required this.selectionMode,
    required this.onSelect,
    required this.onAction,
  });

  /// Get color for suggestion type
  Color _getTypeColor(String type) {
    switch (type) {
      case 'reclamation_note':
        return const Color(0xFFEF4444);
      case 'absence':
        return const Color(0xFFF59E0B);
      case 'emploi_temps':
        return const Color(0xFF3B82F6);
      case 'inscription':
        return const Color(0xFF8B5CF6);
      case 'paiement':
        return const Color(0xFF10B981);
      case 'orientation':
        return const Color(0xFFEC4899);
      case 'bourse':
        return const Color(0xFF14B8A6);
      case 'transport':
        return const Color(0xFF78716C);
      case 'restauration':
        return const Color(0xFFEAB308);
      case 'bibliotheque':
        return const Color(0xFF0EA5E9);
      case 'vie_universitaire':
        return const Color(0xFFA855F7);
      case 'infrastructure':
        return const Color(0xFF64748B);
      case 'securite':
        return const Color(0xFFDC2626);
      case 'autre':
        return const Color(0xFF6B7280);
      default:
        return const Color(0xFF9CA3AF);
    }
  }

  /// Get icon for suggestion type
  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'reclamation_note':
        return Icons.grade_outlined;
      case 'absence':
        return Icons.event_busy_outlined;
      case 'emploi_temps':
        return Icons.calendar_month_outlined;
      case 'inscription':
        return Icons.app_registration_outlined;
      case 'paiement':
        return Icons.payments_outlined;
      case 'orientation':
        return Icons.explore_outlined;
      case 'bourse':
        return Icons.school_outlined;
      case 'transport':
        return Icons.directions_bus_outlined;
      case 'restauration':
        return Icons.restaurant_outlined;
      case 'bibliotheque':
        return Icons.local_library_outlined;
      case 'vie_universitaire':
        return Icons.groups_outlined;
      case 'infrastructure':
        return Icons.business_outlined;
      case 'securite':
        return Icons.security_outlined;
      case 'autre':
        return Icons.help_outline;
      default:
        return Icons.mail_outline;
    }
  }

  /// Get type label
  String _getTypeLabel(String type) {
    switch (type) {
      case 'reclamation_note':
        return 'Réclamation note';
      case 'absence':
        return 'Absence';
      case 'emploi_temps':
        return 'Emploi du temps';
      case 'inscription':
        return 'Inscription';
      case 'paiement':
        return 'Paiement';
      case 'orientation':
        return 'Orientation';
      case 'bourse':
        return 'Bourse';
      case 'transport':
        return 'Transport';
      case 'restauration':
        return 'Restauration';
      case 'bibliotheque':
        return 'Bibliothèque';
      case 'vie_universitaire':
        return 'Vie universitaire';
      case 'infrastructure':
        return 'Infrastructure';
      case 'securite':
        return 'Sécurité';
      case 'autre':
        return 'Autre';
      default:
        return 'Général';
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat("d MMM yyyy 'à' HH:mm", 'fr_FR');
    final s = suggestion;
    final typeColor = _getTypeColor(s.suggestionType);
    final typeLabel = _getTypeLabel(s.suggestionType);

    final dateStr = dateFormat.format(s.createdAt);

    final effectiveClass = (s.className != null && s.className!.isNotEmpty) ? s.className! : '';
    final rawLevel = (s.studentLevel != null && s.studentLevel!.isNotEmpty) ? s.studentLevel! : '';
    final effectiveLevel = _getFullNiveauName(rawLevel);
    final combinedPill = [
      if (effectiveClass.isNotEmpty) effectiveClass,
      if (effectiveLevel.isNotEmpty) effectiveLevel,
    ].join(' • ');

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
        onTap: selectionMode ? onSelect : () => onAction('view'),
        onLongPress: onSelect,
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
                    onChanged: (_) => onSelect(),
                    activeColor: const Color(0xFF655DD5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4)),
                  ),
                ),
                const SizedBox(width: 8),
                // User profile pic
                Align(
                  alignment: Alignment.topCenter,
                  child: UserAvatar(
                    name: (s.studentName != null && s.studentName!.isNotEmpty)
                        ? s.studentName!
                        : 'Étudiant',
                    photoUrl: s.studentPhotoUrl,
                    gender: s.studentGender,
                    radius: 16,
                  ),
                ),
                const SizedBox(width: 14),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title: student name
                      searchQuery.isNotEmpty
                          ? _highlightText(
                              (s.studentName != null && s.studentName!.isNotEmpty)
                                  ? s.studentName!
                                  : 'Étudiant',
                              searchQuery,
                              const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: AppColors.textPrimary),
                            )
                          : Text(
                              (s.studentName != null && s.studentName!.isNotEmpty)
                                  ? s.studentName!
                                  : 'Étudiant',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: AppColors.textPrimary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                      // Under student name: neutral text for class + niveau, and - category
                      if (combinedPill.isNotEmpty || typeLabel.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            if (combinedPill.isNotEmpty)
                              Text(
                                combinedPill,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            if (combinedPill.isNotEmpty && typeLabel.isNotEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 6),
                                child: Text('—', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                              ),
                            if (typeLabel.isNotEmpty)
                              Text(
                                typeLabel,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 6),
                      // Description
                      searchQuery.isNotEmpty
                          ? _highlightText(
                              s.content,
                              searchQuery,
                              TextStyle(
                                  fontSize: 13,
                                  color: AppColors.slate500,
                                  height: 1.5),
                            )
                          : Text(
                              s.content.isNotEmpty ? s.content : '(Aucun contenu)',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.slate500,
                                  height: 1.5),
                            ),
                      // Pièce jointe pill at bottom left of content space
                      if (s.hasAttachment || s.attachments.isNotEmpty) ...[
                        const SizedBox(height: 10),
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
                // Right side: 3-dot menu top, date pinned to bottom
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (!selectionMode)
                      PopupMenuButton<String>(
                        onSelected: (v) => onAction(v == 'unread' || v == 'read' ? v : v),
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
                            value: 'view',
                            height: 40,
                            child: Row(children: [
                              Icon(Icons.visibility_outlined,
                                  size: 18, color: AppColors.slate600),
                              const SizedBox(width: 12),
                              Text('Consulter',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.slate600)),
                            ]),
                          ),
                          PopupMenuItem(
                            value: s.isRead ? 'unread' : 'read',
                            height: 40,
                            child: Row(children: [
                              Icon(s.isRead ? Icons.mark_email_unread_outlined : Icons.mark_email_read_outlined,
                                  size: 18, color: AppColors.slate600),
                              const SizedBox(width: 12),
                              Text(s.isRead ? 'Marquer non lu' : 'Marquer lu',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.slate600)),
                            ]),
                          ),
                          PopupMenuItem(
                            value: 'reply',
                            height: 40,
                            child: Row(children: [
                              Icon(Icons.reply_outlined,
                                  size: 18, color: AppColors.slate600),
                              const SizedBox(width: 12),
                              Text('Répondre',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.slate600)),
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
                      )
                    else
                      const SizedBox(height: 24),
                    const Spacer(),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.access_time_rounded,
                            size: 13, color: AppColors.slate400),
                        const SizedBox(width: 4),
                        Text(_getRelativeTime(s.createdAt),
                            style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.slate600)),
                        const SizedBox(width: 6),
                        Text('($dateStr)',
                            style: TextStyle(
                                fontSize: 11,
                                color: AppColors.slate400)),
                        const SizedBox(width: 8),
                        if (s.status == 'replied')
                          const Icon(Icons.done_all, size: 16, color: AppColors.success)
                        else if (s.isRead)
                          const Icon(Icons.done_all, size: 16, color: AppColors.primary)
                        else
                          const Icon(Icons.check, size: 16, color: AppColors.slate400),
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

  void _showImageViewer(BuildContext context, List<SuggestionAttachment> images, int initialIndex) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: Image.network(
                    images[initialIndex].fileUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Container(
                      color: AppColors.slate200,
                      padding: const EdgeInsets.all(40),
                      child: const Icon(Icons.broken_image, size: 64),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.download, color: Colors.white),
                    onPressed: () async {
                      final uri = Uri.parse(images[initialIndex].fileUrl);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri);
                      }
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withOpacity(0.7)],
                  ),
                ),
                child: Text(
                  images[initialIndex].fileName,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    Color bg;
    String label;
    switch (status) {
      case 'pending':
        bg = AppColors.warning;
        label = 'En attente';
        break;
      case 'in_review':
        bg = AppColors.primary;
        label = 'En cours';
        break;
      case 'replied':
        bg = AppColors.success;
        label = 'Répondu';
        break;
      case 'closed':
        bg = AppColors.textTertiary;
        label = 'Fermé';
        break;
      default:
        bg = AppColors.textTertiary;
        label = status;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Text(
        label,
        style: TextStyle(color: bg, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  final String type;
  const _TypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    Color bg;
    String label;
    switch (type) {
      case 'reclamation_note':
        bg = const Color(0xFFEF4444);
        label = 'Note';
        break;
      case 'absence':
        bg = const Color(0xFFF59E0B);
        label = 'Absence';
        break;
      case 'emploi_temps':
        bg = const Color(0xFF3B82F6);
        label = 'EDT';
        break;
      case 'inscription':
        bg = const Color(0xFF8B5CF6);
        label = 'Inscription';
        break;
      case 'paiement':
        bg = const Color(0xFF10B981);
        label = 'Paiement';
        break;
      case 'orientation':
        bg = const Color(0xFFEC4899);
        label = 'Orientation';
        break;
      case 'bourse':
        bg = const Color(0xFF14B8A6);
        label = 'Bourse';
        break;
      case 'transport':
        bg = const Color(0xFF78716C);
        label = 'Transport';
        break;
      case 'restauration':
        bg = const Color(0xFFEAB308);
        label = 'Resto';
        break;
      case 'bibliotheque':
        bg = const Color(0xFF0EA5E9);
        label = 'Biblio';
        break;
      case 'vie_universitaire':
        bg = const Color(0xFFA855F7);
        label = 'Vie univ.';
        break;
      case 'infrastructure':
        bg = const Color(0xFF64748B);
        label = 'Infra.';
        break;
      case 'securite':
        bg = const Color(0xFFDC2626);
        label = 'Sécurité';
        break;
      case 'autre':
        bg = const Color(0xFF6B7280);
        label = 'Autre';
        break;
      default:
        bg = const Color(0xFF9CA3AF);
        label = 'Général';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(color: bg, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _AttachmentChip extends StatelessWidget {
  final SuggestionAttachment attachment;
  const _AttachmentChip({required this.attachment});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(
        attachment.isImage ? Icons.image : Icons.insert_drive_file,
        size: 16,
      ),
      label: Text(attachment.fileName, style: const TextStyle(fontSize: 12)),
      onPressed: () async {
        final uri = Uri.parse(attachment.fileUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
        }
      },
    );
  }
}

/// Horizontal preview of attachments in the card
class _AttachmentsPreview extends StatelessWidget {
  final List<SuggestionAttachment> attachments;
  const _AttachmentsPreview({required this.attachments});

  @override
  Widget build(BuildContext context) {
    final images = attachments.where((a) => a.isImage).toList();
    final files = attachments.where((a) => !a.isImage).toList();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warningSoft,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(color: AppColors.warning.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.attach_file, size: 16, color: AppColors.warning),
              const SizedBox(width: 6),
              Text(
                '${attachments.length} pièce(s) jointe(s)',
                style: TextStyle(
                  color: AppColors.warning,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          if (images.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 80,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: images.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final img = images[index];
                  return GestureDetector(
                    onTap: () => _showImageDialog(context, img),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                      child: Image.network(
                        img.fileUrl,
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 80,
                          height: 80,
                          color: AppColors.slate200,
                          child: const Icon(Icons.broken_image),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          if (files.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: files
                  .map(
                    (f) => Chip(
                      avatar: const Icon(Icons.insert_drive_file, size: 14),
                      label: Text(
                        f.fileName,
                        style: const TextStyle(fontSize: 11),
                      ),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  void _showImageDialog(BuildContext context, SuggestionAttachment img) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: Text(img.fileName),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  icon: const Icon(Icons.download),
                  onPressed: () async {
                    final uri = Uri.parse(img.fileUrl);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri);
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            Flexible(
              child: InteractiveViewer(
                child: Image.network(
                  img.fileUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      const Center(child: Icon(Icons.broken_image, size: 64)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Grid display for attachments in the detail dialog
class _AttachmentsGrid extends StatelessWidget {
  final List<SuggestionAttachment> attachments;
  const _AttachmentsGrid({required this.attachments});

  @override
  Widget build(BuildContext context) {
    final images = attachments.where((a) => a.isImage).toList();
    final files = attachments.where((a) => !a.isImage).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Images grid with preview
        if (images.isNotEmpty) ...[
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: images
                .map((img) => _ImageThumbnail(attachment: img))
                .toList(),
          ),
          if (files.isNotEmpty) const SizedBox(height: 16),
        ],
        // File list
        if (files.isNotEmpty)
          ...files.map(
            (f) => MouseRegion(
              cursor: SystemMouseCursors.click,
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.slate100,
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                  ),
                  child: const Icon(Icons.insert_drive_file, color: AppColors.textTertiary),
                ),
                title: Text(f.fileName),
                subtitle: f.fileSize != null
                    ? Text(_formatFileSize(f.fileSize!))
                    : null,
                trailing: IconButton(
                  icon: const Icon(Icons.download),
                  onPressed: () async {
                    final uri = Uri.parse(f.fileUrl);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri);
                    }
                  },
                ),
                contentPadding: EdgeInsets.zero,
                onTap: () async {
                  final uri = Uri.parse(f.fileUrl);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri);
                  }
                },
              ),
            ),
          ),
      ],
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _ImageThumbnail extends StatelessWidget {
  final SuggestionAttachment attachment;
  const _ImageThumbnail({required this.attachment});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _showFullImage(context),
        child: Container(
        width: 150,
        height: 150,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.slate200),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                attachment.fileUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: AppColors.slate200,
                  child: const Icon(Icons.broken_image, size: 40),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.7),
                      ],
                    ),
                  ),
                  child: Text(
                    attachment.fileName,
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(
                    Icons.zoom_in,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }

  void _showFullImage(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: Image.network(
                    attachment.fileUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Container(
                      color: AppColors.slate200,
                      padding: const EdgeInsets.all(40),
                      child: const Icon(Icons.broken_image, size: 64),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.download, color: Colors.white),
                    onPressed: () async {
                      final uri = Uri.parse(attachment.fileUrl);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri);
                      }
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withOpacity(0.7)],
                  ),
                ),
                child: Text(
                  attachment.fileName,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
