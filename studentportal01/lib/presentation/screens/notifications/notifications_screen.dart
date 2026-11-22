// ignore_for_file: unused_element, unused_field, unused_local_variable

import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/arabic_typography.dart';
import '../../../core/theme/responsive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:url_launcher/url_launcher.dart';
import '../../providers/announcements_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/detail_modal_sheet.dart';
import '../../widgets/bouncing_wrapper.dart';
import '../../providers/nav_bar_provider.dart';
import '../../widgets/ios_loader.dart';
import '../../widgets/notifications_screen_skeleton.dart';
import '../../widgets/ios_photo_gallery_viewer.dart';
import '../../../core/utils/file_download_helper.dart';
import '../../../data/services/student_seen_service.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  final String? initialNotificationId;

  const NotificationsScreen({
    super.key,
    this.initialNotificationId,
  });

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen>
    with SingleTickerProviderStateMixin {
  bool _isSearching = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  late AnimationController _animationController;
  late Animation<double> _searchWidthAnimation;
  late Animation<double> _iconSizeAnimation;
  bool _hasHandledInitialNotification = false;

  static const Color _accentColor = Color(0xFFEC4899);

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _searchWidthAnimation = Tween<double>(begin: 44, end: 200).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );
    _iconSizeAnimation = Tween<double>(begin: 22, end: 18).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );
  }

  void _checkAutoOpenInitial(List<StudentAnnouncement> list) {
    if (_hasHandledInitialNotification || widget.initialNotificationId == null) return;
    final match = list.where((a) => a.id == widget.initialNotificationId).firstOrNull;
    if (match != null) {
      _hasHandledInitialNotification = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showAnnouncementDetail(match);
        }
      });
    }
  }

  @override
  void didUpdateWidget(NotificationsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialNotificationId != oldWidget.initialNotificationId &&
        widget.initialNotificationId != null) {
      _hasHandledInitialNotification = false;
      ref.read(globalAnnouncementsProvider).whenData((list) {
        _checkAutoOpenInitial(list);
      });
    }
  }

  @override
  void dispose() {
    if (_isSearching) {
      ref.read(backSwipeInterceptorProvider.notifier).state = null;
    }
    _searchController.dispose();
    _searchFocusNode.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (_isSearching) {
        _animationController.forward();
        ref.read(backSwipeInterceptorProvider.notifier).state = () {
          _toggleSearch();
          return true;
        };
        Future.delayed(const Duration(milliseconds: 150), () {
          _searchFocusNode.requestFocus();
        });
      } else {
        ref.read(backSwipeInterceptorProvider.notifier).state = null;
        _animationController.reverse();
        _searchController.clear();
        _searchQuery = '';
        _searchFocusNode.unfocus();
      }
    });
  }

  // Build the animated header
  Widget _buildAnimatedHeader() {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        final slideValue = _animationController.value;
        final fadeOut = 1.0 - slideValue;
        final fadeIn = slideValue;

        final searchBtnSize = (50.0 * context.responsiveScale).clamp(44.0, 50.0);
        final headerBlur = slideValue * 14.0;

        return SizedBox(
          height: 76,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Normal header - slides out to left and blurs on hiding / un-blurs on showing
              Transform.translate(
                offset: Offset(-60 * slideValue, 0),
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(
                    sigmaX: headerBlur,
                    sigmaY: headerBlur,
                  ),
                  child: Opacity(
                    opacity: fadeOut.clamp(0.0, 1.0),
                    child: Row(
                    children: [
                      // Icon with scale animation
                      Transform.scale(
                        scale: 1.0 - (0.3 * slideValue),
                        child: Container(
                          width: context.scaleW(56).clamp(44.0, 60.0),
                          height: context.scaleW(56).clamp(44.0, 60.0),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFFEC4899), Color(0xFFF43F5E)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFEC4899).withValues(alpha: 0.4),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.notifications_rounded,
                            color: Colors.white,
                            size: context.scaleW(28).clamp(22.0, 30.0),
                          ),
                        ),
                      ),
                      SizedBox(width: context.scaleW(14).clamp(10.0, 16.0)),
                      // Title
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(
                                AppLocalizations.of(context).notifications,
                                style: ArabicTypography.headerStyle(
                                  context,
                                  fontSize: context.sp(28),
                                  fontWeight: FontWeight.w900,
                                  color: Colors.grey[900],
                                  letterSpacing: -0.8,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              AppLocalizations.of(context).notificationsSubtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: ArabicTypography.subtitleStyle(
                                context,
                                fontSize: context.sp(14),
                                fontWeight: FontWeight.w500,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Search button
                      BouncingWrapper(
                        shrinkScale: 0.86,
                        overshootScale: 1.10,
                        delayNavigation: false,
                        onTap: _toggleSearch,
                        child: Container(
                          width: searchBtnSize,
                          height: searchBtnSize,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.95),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.black.withValues(alpha: 0.08),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.10),
                                blurRadius: 16,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.search_rounded,
                            color: Colors.grey[800],
                            size: (26 * context.responsiveScale).clamp(22.0, 26.0),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
              // Search bar - starts exactly at search button level and expands across
              LayoutBuilder(
                builder: (context, constraints) {
                  final totalWidth = constraints.maxWidth;
                  final isRtl = Directionality.of(context) == TextDirection.rtl;
                  final searchOriginOffset = isRtl
                      ? -(totalWidth - searchBtnSize)
                      : (totalWidth - searchBtnSize);
                  return Transform.translate(
                    offset: Offset(
                      searchOriginOffset * (1.0 - slideValue),
                      0,
                    ),
                    child: Opacity(
                      opacity: fadeIn.clamp(0.0, 1.0),
                      child: Row(
                    children: [
                      // Cancel button
                      BouncingWrapper(
                        shrinkScale: 0.86,
                        overshootScale: 1.10,
                        delayNavigation: false,
                        onTap: _toggleSearch,
                        child: Container(
                          width: searchBtnSize,
                          height: searchBtnSize,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.95),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.black.withValues(alpha: 0.08),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.10),
                                blurRadius: 16,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.close_rounded,
                            color: Colors.grey[800],
                            size: (26 * context.responsiveScale).clamp(22.0, 26.0),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Search field - pill shaped
                      Expanded(
                        child: Container(
                          height: searchBtnSize,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.98),
                            borderRadius: BorderRadius.circular(searchBtnSize / 2),
                            border: Border.all(
                              color: Colors.black.withValues(alpha: 0.08),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.10),
                                blurRadius: 18,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const SizedBox(width: 16),
                              Icon(
                                Icons.search_rounded,
                                color: Colors.grey[600],
                                size: 24,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Center(
                                  child: TextField(
                                    controller: _searchController,
                                    focusNode: _searchFocusNode,
                                    cursorColor: Colors.grey[800],
                                    textAlignVertical: TextAlignVertical.center,
                                    onChanged: (value) =>
                                        setState(() => _searchQuery = value),
                                    style: ArabicTypography.bodyStyle(
                                      context,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.grey[900],
                                    ),
                                    decoration: InputDecoration(
                                      hintText: AppLocalizations.of(context).search,
                                      hintStyle: ArabicTypography.bodyStyle(
                                        context,
                                        color: Colors.grey[500],
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      filled: false,
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      isDense: true,
                                      isCollapsed: true,
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                  ),
                                ),
                              ),
                              if (_searchQuery.isNotEmpty)
                                GestureDetector(
                                  onTap: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                  child: Container(
                                    margin: const EdgeInsetsDirectional.only(end: 8),
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[200],
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.close_rounded,
                                      color: Colors.grey[600],
                                      size: 22,
                                    ),
                                  ),
                                )
                              else
                                const SizedBox(width: 18),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
            ],
          ),
        );
      },
    );
  }

  // Normal header with icon, title and search button
  Widget _buildNormalHeader() {
    return Row(
      children: [
        // Icon
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFEC4899), Color(0xFFF43F5E)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFEC4899).withValues(alpha: 0.4),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(
            Icons.notifications_rounded,
            color: Colors.white,
            size: 28,
          ),
        ),
        const SizedBox(width: 16),
        // Title
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.of(context).notifications,
                style: ArabicTypography.headerStyle(
                  context,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: Colors.grey[900],
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                AppLocalizations.of(context).notificationsSubtitle,
                style: ArabicTypography.subtitleStyle(
                  context,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
        // Search button
        Builder(
          builder: (context) {
            final scale = context.responsiveScale;
            final searchBtnSize = (50.0 * scale).clamp(44.0, 50.0);
            return BouncingWrapper(
              shrinkScale: 0.86,
              hitPadding: const EdgeInsets.all(8),
              onTap: _toggleSearch,
              child: Container(
                width: searchBtnSize,
                height: searchBtnSize,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.95),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.08),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.10),
                      blurRadius: 16,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.search_rounded,
                  color: Colors.grey[800],
                  size: (26 * scale).clamp(22.0, 26.0),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // Search header with full-width search bar
  Widget _buildSearchHeader() {
    final scale = context.responsiveScale;
    final searchBtnSize = (50.0 * scale).clamp(44.0, 50.0);

    return Row(
      children: [
        // Cancel button
        BouncingWrapper(
          shrinkScale: 0.86,
          hitPadding: const EdgeInsets.all(8),
          onTap: _toggleSearch,
          child: Container(
            width: searchBtnSize,
            height: searchBtnSize,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.95),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.black.withValues(alpha: 0.08),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 16,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Icon(
              Icons.close_rounded,
              color: Colors.grey[800],
              size: (26 * scale).clamp(22.0, 26.0),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Search field - pill shaped
        Expanded(
          child: Container(
            height: searchBtnSize,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.98),
              borderRadius: BorderRadius.circular(searchBtnSize / 2),
              border: Border.all(
                color: Colors.black.withValues(alpha: 0.08),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 18,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(width: 16),
                Icon(
                  Icons.search_rounded,
                  color: Colors.grey[600],
                  size: 24,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Center(
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      cursorColor: Colors.grey[800],
                      textAlignVertical: TextAlignVertical.center,
                      onChanged: (value) => setState(() => _searchQuery = value),
                      style: ArabicTypography.bodyStyle(
                        context,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey[900],
                      ),
                      decoration: InputDecoration(
                        hintText: AppLocalizations.of(context).search,
                        hintStyle: ArabicTypography.bodyStyle(
                          context,
                          color: Colors.grey[500],
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                        isCollapsed: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ),
                if (_searchQuery.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(end: 12),
                      child: Icon(
                        Icons.close_rounded,
                        color: Colors.grey[600],
                        size: 22,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final authState = ref.watch(authProvider);
    final announcementsAsync = ref.watch(globalAnnouncementsProvider);
    final isRefreshing = ref.watch(notificationsRefreshingProvider);

    announcementsAsync.whenData((list) {
      _checkAutoOpenInitial(list);
    });

    // Show loading if auth is still loading
    final isAuthLoading = authState.isLoading;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFF8F0FC),
            Color(0xFFF0E6F8),
            Color(0xFFEAF0FA),
            Color(0xFFF4F8FC),
            Color(0xFFFAFCFD),
          ],
          stops: [0.0, 0.25, 0.5, 0.75, 1.0],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.read(notificationsRefreshingProvider.notifier).state = true;
            try {
              // ignore: unused_result
              await ref.refresh(globalAnnouncementsProvider.future);
            } finally {
              ref.read(notificationsRefreshingProvider.notifier).state = false;
            }
          },
          color: const Color(0xFFFF2D78),
          backgroundColor: Colors.white,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              if (_isSearching) _toggleSearch();
            },
            onHorizontalDragUpdate: (details) {
              if (_isSearching) {
                final isRtl = Directionality.of(context) == TextDirection.rtl;
                if (isRtl) {
                  if ((details.primaryDelta ?? 0) > 8) _toggleSearch();
                } else {
                  if ((details.primaryDelta ?? 0) < -8) _toggleSearch();
                }
              }
            },
            child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            slivers: [
              // Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(context.horizontalPadding, 20, context.horizontalPadding, 24),
                  child: _buildAnimatedHeader(),
                ),
              ),

            // Notifications List
            // Show loading if auth is still loading
            if (isAuthLoading)
              const SliverToBoxAdapter(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: IosLoader(),
                  ),
                ),
              )
            else if (isRefreshing)
              const NotificationsCardsSkeleton()
            else
            announcementsAsync.when(
              loading: () => const NotificationsCardsSkeleton(),
              error: (e, _) => SliverToBoxAdapter(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Column(
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 48,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '${l10n.error}: $e',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              data: (announcements) {
                // Filter announcements by search
                var filtered = announcements;
                if (_searchQuery.isNotEmpty) {
                  final query = _searchQuery.toLowerCase();
                  filtered = announcements.where((a) {
                    final localizedTitle = l10n
                        .localizeAnnouncementTitle(a.announcementType, a.title)
                        .toLowerCase();
                    final localizedBody = l10n
                        .localizeAnnouncementBody(
                          a.announcementType,
                          a.payload,
                          a.body,
                        )
                        .toLowerCase();
                    final localizedKeyInfo = _extractKeyInfo(
                      a.announcementType,
                      a.payload,
                      a.body,
                    ).toLowerCase();
                    final localizedType = _getTypeLabel(
                      a.announcementType,
                    ).toLowerCase();
                    final localizedSender = l10n
                        .localizeSenderLabel(a.senderLabel)
                        .toLowerCase();
                    return a.title.toLowerCase().contains(query) ||
                        a.body.toLowerCase().contains(query) ||
                        localizedTitle.contains(query) ||
                        localizedBody.contains(query) ||
                        localizedKeyInfo.contains(query) ||
                        localizedType.contains(query) ||
                        localizedSender.contains(query) ||
                        (a.senderLabel?.toLowerCase().contains(query) ??
                            false) ||
                        (a.announcementType?.toLowerCase().contains(query) ??
                            false);
                  }).toList();
                }

                if (filtered.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: context.horizontalPadding, vertical: 16),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Colors.white,
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 20,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFFF2B6D), Color(0xFFE11D48)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFFF2B6D).withValues(alpha: 0.3),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.notifications_off_rounded,
                                size: 34,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              l10n.noNotifications,
                              textAlign: TextAlign.center,
                              style: ArabicTypography.headerStyle(
                                context,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF1F2937),
                                letterSpacing: -0.4,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              l10n.notificationsAppearHere,
                              textAlign: TextAlign.center,
                              style: ArabicTypography.bodyStyle(
                                context,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF6B7280),
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }

                return SliverPadding(
                  padding: EdgeInsets.fromLTRB(context.horizontalPadding, 0, context.horizontalPadding, 124 + MediaQuery.of(context).padding.bottom),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) =>
                          _buildNotificationCard(filtered[index]),
                      childCount: filtered.length,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        ),
        ),
      ),
    );
  }

  /// Formats markdown-like text, rendering **bold** sections with strong weight and contrast.
  Widget _buildFormattedText(
    String text, {
    required TextStyle baseStyle,
    TextStyle? boldStyle,
    int? maxLines,
    TextOverflow? overflow,
    TextAlign textAlign = TextAlign.start,
  }) {
    if (text.isEmpty) return const SizedBox.shrink();

    final isAr = ArabicTypography.isArabic(context) ||
        RegExp(r'[\u0600-\u06FF]').hasMatch(text);

    final effectiveBase = isAr
        ? ArabicTypography.bodyStyle(
            context,
            fontSize: baseStyle.fontSize ?? 13.5,
            fontWeight: baseStyle.fontWeight ?? FontWeight.w500,
            color: baseStyle.color,
            height: baseStyle.height ?? 1.45,
          )
        : baseStyle;

    final effectiveBold = boldStyle ??
        (isAr
            ? ArabicTypography.bodyStyle(
                context,
                fontSize: baseStyle.fontSize ?? 13.5,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF111827),
                height: baseStyle.height ?? 1.45,
              )
            : effectiveBase.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF111827),
              ));

    if (!text.contains('**')) {
      return Text(
        text,
        style: effectiveBase,
        maxLines: maxLines,
        overflow: overflow,
        textAlign: textAlign,
      );
    }

    final spans = <InlineSpan>[];
    final regex = RegExp(r'\*\*(.*?)\*\*');
    int lastIndex = 0;

    for (final match in regex.allMatches(text)) {
      if (match.start > lastIndex) {
        spans.add(
          TextSpan(
            text: text.substring(lastIndex, match.start),
            style: effectiveBase,
          ),
        );
      }
      final boldText = match.group(1) ?? '';
      if (boldText.isNotEmpty) {
        spans.add(
          TextSpan(
            text: boldText,
            style: effectiveBold,
          ),
        );
      }
      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      spans.add(
        TextSpan(
          text: text.substring(lastIndex),
          style: effectiveBase,
        ),
      );
    }

    return Text.rich(
      TextSpan(children: spans),
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
    );
  }

  /// Dedicated picture preview card for notifications with attached image(s)
  Widget _buildImageCardPreview(dynamic announcement) {
    final imageAttachments = (announcement.attachments as List)
        .where((att) => _isImageFile(att.fileUrl))
        .toList();
    if (imageAttachments.isEmpty) return const SizedBox.shrink();

    final imageUrls =
        imageAttachments.map((att) => att.fileUrl as String).toList();
    final firstImageUrl = imageUrls.first;
    final count = imageUrls.length;

    return BouncingWrapper(
      shrinkScale: 0.95,
      overshootScale: 1.05,
      onTap: () => _showImageViewer(imageUrls, 0),
      child: Container(
        height: 160,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.black.withValues(alpha: 0.08),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                firstImageUrl,
                fit: BoxFit.cover,
                width: double.infinity,
                height: 160,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: Colors.grey[100],
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.broken_image_rounded,
                          size: 32, color: Colors.grey[400]),
                      const SizedBox(height: 6),
                      Text(
                        AppLocalizations.of(context).imageUnavailable,
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ),
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    color: Colors.grey[100],
                    child: const Center(child: IosLoader(size: 24)),
                  );
                },
              ),
              // Gradient overlay at bottom
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 48,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.4),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              // Fullscreen zoom indicator on top right
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.fullscreen_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
              // Multiple images badge
              if (count > 1)
                Positioned(
                  bottom: 8,
                  left: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.photo_library_rounded,
                          size: 13,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$count',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
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

  Widget _buildNotificationCard(dynamic announcement) {
    final l10n = AppLocalizations.of(context);
    final isImportant = announcement.isImportant;
    final isPinned = announcement.isPinned;
    final color = _getTypeColor(announcement.announcementType);
    final icon = _getTypeIcon(announcement.announcementType);
    final typeLabel = _getTypeLabel(announcement.announcementType);
    final localizedTitle = l10n.localizeAnnouncementTitle(
      announcement.announcementType,
      announcement.title,
    );
    final localizedBody = l10n.localizeAnnouncementBody(
      announcement.announcementType,
      announcement.payload,
      announcement.body,
    );
    final keyInfo = _extractKeyInfo(
      announcement.announcementType,
      announcement.payload,
      announcement.body,
    );
    
    // Check for non-image attachments (documents)
    final hasDocumentAttachment = announcement.attachments.any(
      (att) => !_isImageFile(att.fileUrl),
    );
    final isRead = ref.watch(readAnnouncementsProvider).contains(announcement.id);
    // Count images and documents separately
    final imageCount = announcement.attachments.where(
      (att) => _isImageFile(att.fileUrl),
    ).length;
    final documentCount = announcement.attachments.where(
      (att) => !_isImageFile(att.fileUrl),
    ).length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: BouncingWrapper(
        shrinkScale: 0.93,
        overshootScale: 1.055,
        delayNavigation: false,
        onTap: () {
          ref.read(readAnnouncementsProvider.notifier).markAsRead(announcement.id, itemType: StudentSeenService.typeAnnouncement);
          _showAnnouncementDetail(announcement);
        },
        child: ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(AppResponsive.cardPadding(context, base: 20.0)),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.6),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row with icon, title, and badges
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Type icon
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [color, color.withValues(alpha: 0.7)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: color.withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Icon(icon, color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 12),
                      // Type label, date sent, and Title
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              typeLabel,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isRead ? FontWeight.w700 : FontWeight.w900,
                                color: color,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              l10n.formatAnnouncementDateTime(announcement.publishedAt),
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: isRead ? FontWeight.w500 : FontWeight.w800,
                                color: isRead ? Colors.grey[500] : const Color(0xFF1F2937),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (localizedTitle.isNotEmpty &&
                                localizedTitle.toLowerCase() != typeLabel.toLowerCase()) ...[
                              const SizedBox(height: 3),
                              _buildFormattedText(
                                localizedTitle,
                                baseStyle: TextStyle(
                                  fontSize: 16,
                                  fontWeight: isRead ? FontWeight.w800 : FontWeight.w900,
                                  color: isRead ? const Color(0xFF1F2937) : const Color(0xFF111827),
                                  letterSpacing: -0.3,
                                  height: 1.25,
                                ),
                                boldStyle: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF111827),
                                  letterSpacing: -0.3,
                                  height: 1.25,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                      // Pinned badge at top trailing position
                      if (isPinned) ...[
                        const SizedBox(width: 8),
                        _buildBadge(l10n.pinnedLabel, const Color(0xFFFF2D78), Icons.push_pin),
                      ],
                    ],
                  ),
                  // Badges row
                  if (isImportant || hasDocumentAttachment) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (isImportant)
                          _buildBadge(
                            l10n.importantLabel,
                            Colors.red,
                            Icons.priority_high,
                          ),
                        if (hasDocumentAttachment)
                          _buildBadge(
                            l10n.attachment,
                            Colors.purple,
                            Icons.attach_file,
                          ),
                      ],
                    ),
                  ],
                  // Key info summary if available (structured with boldness in content)
                  if (keyInfo.isNotEmpty && !localizedBody.contains(keyInfo)) ...[
                    const SizedBox(height: 10),
                    _buildFormattedText(
                      '**$keyInfo**',
                      baseStyle: TextStyle(
                        fontSize: 13.5,
                        fontWeight: isRead ? FontWeight.w700 : FontWeight.w900,
                        color: isRead ? Colors.grey[800] : const Color(0xFF111827),
                        height: 1.4,
                      ),
                      boldStyle: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF111827),
                        height: 1.4,
                      ),
                    ),
                  ],
                  // Body content formatted with markdown bold support
                  if (localizedBody.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _buildFormattedText(
                      localizedBody,
                      baseStyle: TextStyle(
                        fontSize: 13.5,
                        fontWeight: isRead ? FontWeight.w500 : FontWeight.w700,
                        color: isRead ? Colors.grey[700] : const Color(0xFF111827),
                        height: 1.45,
                      ),
                      boldStyle: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF111827),
                        height: 1.45,
                      ),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  // Prominent image preview when picture is attached
                  if (imageCount > 0) ...[
                    const SizedBox(height: 12),
                    _buildImageCardPreview(announcement),
                  ],
                  const SizedBox(height: 12),
                  // Footer with time
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Timestamp
                      Icon(
                        Icons.access_time,
                        size: 12,
                        color: isRead ? Colors.grey[500] : const Color(0xFF1F2937),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatTime(announcement.publishedAt),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: isRead ? FontWeight.w600 : FontWeight.w900,
                          color: isRead ? Colors.grey[500] : const Color(0xFF1F2937),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(String label, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttachmentPreview(String url, String? name) {
    final l10n = AppLocalizations.of(context);
    final isImage = _isImageFile(url);

    return BouncingWrapper(
      behavior: HitTestBehavior.opaque,
      shrinkScale: 0.94,
      overshootScale: 1.05,
      delayNavigation: false,
      onTap: () => _openAttachment(url),
      child: isImage
          ? ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                constraints: const BoxConstraints(maxHeight: 120),
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                ),
                child: Stack(
                  children: [
                    Image.network(
                      url,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          height: 80,
                          color: Colors.grey[100],
                          child: Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              value: loadingProgress.expectedTotalBytes != null
                                  ? loadingProgress.cumulativeBytesLoaded /
                                        loadingProgress.expectedTotalBytes!
                                  : null,
                            ),
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) => Container(
                        height: 60,
                        color: Colors.grey[100],
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.broken_image, color: Colors.grey[400]),
                            const SizedBox(width: 8),
                            Text(
                              l10n.imageUnavailable,
                              style: TextStyle(color: Colors.grey[500]),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.6),
                            ],
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.image_rounded,
                              size: 14,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                l10n.openLabel,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Icon(
                              Icons.open_in_new_rounded,
                              size: 14,
                              color: Colors.white,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.purple.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.purple.withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _getAttachmentIcon(url),
                    size: 18,
                    color: Colors.purple[600],
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _getCleanFileName(name, url),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.purple[700],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.download_rounded,
                    size: 16,
                    color: Colors.purple[600],
                  ),
                ],
              ),
            ),
    );
  }

  bool _isImageFile(String url) {
    final lower = url.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp');
  }

  Widget _buildDetailAttachment(String url, String? name) {
    final l10n = AppLocalizations.of(context);
    final isImage = _isImageFile(url);
    final fileName = _getCleanFileName(name, url);

    if (isImage) {
      return BouncingWrapper(
        behavior: HitTestBehavior.opaque,
        shrinkScale: 0.94,
        overshootScale: 1.05,
        delayNavigation: false,
        onTap: () => _showImageViewer([url], 0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.network(
            url,
            fit: BoxFit.cover,
            width: double.infinity,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Container(
                height: 200,
                color: Colors.grey[100],
                child: Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded /
                              loadingProgress.expectedTotalBytes!
                        : null,
                  ),
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) => Container(
              height: 100,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.broken_image, color: Colors.grey[400]),
                  const SizedBox(width: 8),
                  Text(
                    l10n.imageUnavailable,
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
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
                url: url,
                fileName: fileName,
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
                      _getAttachmentIcon(url),
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
                          fileName,
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
                          l10n.tapToDownload,
                          style: TextStyle(
                            fontSize: 11.5,
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
                url: url,
                fileName: fileName,
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

  void _showAnnouncementDetail(dynamic announcement) {
    ref.read(readAnnouncementsProvider.notifier).markAsRead(announcement.id, itemType: StudentSeenService.typeAnnouncement);
    final l10n = AppLocalizations.of(context);
    final color = _getTypeColor(announcement.announcementType);
    final icon = _getTypeIcon(announcement.announcementType);
    final typeLabel = _getTypeLabel(announcement.announcementType);
    final localizedTitle = l10n.localizeAnnouncementTitle(
      announcement.announcementType,
      announcement.title,
    );
    final localizedBody = l10n.localizeAnnouncementBody(
      announcement.announcementType,
      announcement.payload,
      announcement.body,
    );
    final keyInfo = _extractKeyInfo(
      announcement.announcementType,
      announcement.payload,
      announcement.body,
    );

    DetailModalSheet.show(
      context: context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with icon
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [color, color.withValues(alpha: 0.7)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        typeLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.formatAnnouncementDateTime(
                        announcement.publishedAt,
                      ),
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
          // Badges (Attachment pill only shown outside)
          if (announcement.isPinned || announcement.isImportant) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (announcement.isPinned)
                  _buildBadge(l10n.pinnedLabel, const Color(0xFFFF2D78), Icons.push_pin),
                if (announcement.isImportant)
                  _buildBadge(
                    l10n.importantLabel,
                    Colors.red,
                    Icons.priority_high,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          // Title
          _buildFormattedText(
            localizedTitle,
            baseStyle: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1F2937),
              letterSpacing: -0.5,
            ),
            boldStyle: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Color(0xFF111827),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 12),
          // Key info summary if available (Omit if it just repeats the date, which is already in header)
          if (keyInfo.isNotEmpty && !_isDateOnlyKeyInfo(keyInfo)) ...[
            _buildFormattedText(
              keyInfo,
              baseStyle: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey[500],
                height: 1.2,
              ),
              boldStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Color(0xFF374151),
                height: 1.2,
              ),
            ),
            const SizedBox(height: 10),
          ],
          // Body content with markdown bold formatting
          if (localizedBody.isNotEmpty) ...[
            _buildFormattedText(
              localizedBody,
              baseStyle: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
                height: 1.6,
              ),
              boldStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Color(0xFF111827),
                height: 1.6,
              ),
            ),
          ],
          // Attachments - show all from attachments list
          if (announcement.attachments.isNotEmpty) ...[
            const SizedBox(height: 16),
            ...announcement.attachments.map(
              (att) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildDetailAttachment(
                  att.fileUrl,
                  att.effectiveName,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

    Future<void> _openAttachment(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).cannotOpenFile),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showImageViewer(List<String> imageUrls, int initialIndex) {
    IosPhotoGalleryViewer.show(
      context: context,
      imageUrls: imageUrls,
      initialIndex: initialIndex,
    );
  }

  IconData _getAttachmentIcon(String url) {
    final lower = url.toLowerCase();
    if (lower.endsWith('.pdf')) return Icons.picture_as_pdf_rounded;
    if (lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.gif')) {
      return Icons.image_rounded;
    }
    if (lower.endsWith('.doc') || lower.endsWith('.docx')) {
      return Icons.description_rounded;
    }
    if (lower.endsWith('.xls') || lower.endsWith('.xlsx')) {
      return Icons.table_chart_rounded;
    }
    if (lower.endsWith('.ppt') || lower.endsWith('.pptx')) {
      return Icons.slideshow_rounded;
    }
    return Icons.insert_drive_file_rounded;
  }

  String _getAttachmentName(String url) {
    try {
      final uri = Uri.parse(url);
      final path = uri.pathSegments.last;
      return Uri.decodeComponent(path);
    } catch (e) {
      return AppLocalizations.of(context).attachedFile;
    }
  }

  /// Get clean display name for file attachments
  /// Uses custom name if provided, otherwise generates a friendly name based on file type
  String _getCleanFileName(String? customName, String url) {
    return AppLocalizations.of(context).getCleanAttachmentFileName(
      customName,
      url,
    );
  }

  String _getTypeLabel(String? type) {
    return AppLocalizations.of(context).getAnnouncementTypeLabel(type);
  }

  Color _getTypeColor(String? type) {
    final norm = AppLocalizations.normalizeAnnouncementType(type);
    switch (norm) {
      case 'teacher_absent':
        return const Color(0xFFEF4444);
      case 'room_change':
        return const Color(0xFF3B82F6);
      case 'exam':
        return const Color(0xFFF59E0B);
      case 'reminder':
        return const Color(0xFF8B5CF6);
      case 'closure':
        return const Color(0xFF64748B);
      case 'trip':
        return const Color(0xFF10B981);
      case 'party':
        return const Color(0xFFF97316);
      case 'payment':
        return const Color(0xFF06B6D4);
      case 'avertissement':
        return const Color(0xFFEAB308);
      case 'retenue':
        return const Color(0xFFDC2626);
      case 'exclusion_classe':
        return const Color(0xFFEA580C);
      case 'exclusion_etablissement':
        return const Color(0xFFB91C1C);
      case 'convocation_parents':
        return const Color(0xFF7C3AED);
      case 'conseil_discipline':
        return const Color(0xFF4F46E5);
      case 'exclusion_definitive':
        return const Color(0xFF111827);
      case 'general':
      default:
        return const Color(0xFF6366F1);
    }
  }

  IconData _getTypeIcon(String? type) {
    final norm = AppLocalizations.normalizeAnnouncementType(type);
    switch (norm) {
      case 'teacher_absent':
        return Icons.person_off_rounded;
      case 'room_change':
        return Icons.meeting_room_rounded;
      case 'exam':
        return Icons.quiz_rounded;
      case 'reminder':
        return Icons.notifications_active_rounded;
      case 'closure':
        return Icons.lock_rounded;
      case 'trip':
        return Icons.directions_bus_rounded;
      case 'party':
        return Icons.celebration_rounded;
      case 'payment':
        return Icons.payment_rounded;
      case 'avertissement':
        return Icons.warning_amber_rounded;
      case 'retenue':
        return Icons.access_time_rounded;
      case 'exclusion_classe':
        return Icons.no_meeting_room_rounded;
      case 'exclusion_etablissement':
        return Icons.block_rounded;
      case 'convocation_parents':
        return Icons.family_restroom_rounded;
      case 'conseil_discipline':
        return Icons.gavel_rounded;
      case 'exclusion_definitive':
        return Icons.cancel_rounded;
      case 'general':
      default:
        return Icons.campaign_rounded;
    }
  }

  /// Extracts key information from announcement based on type and payload
  String _extractKeyInfo(String? type, Map<String, dynamic> payload, String body) {
    return AppLocalizations.of(context).extractAnnouncementKeyInfo(
      type,
      payload,
      body,
    );
  }

  bool _isDateOnlyKeyInfo(String info) {
    final trimmed = info.trim();
    return RegExp(
      r'^(?:Le|On|يوم|À partir du|From|Avant le|Before|قبل)?\s*\d{1,2}/\d{1,2}/\d{2,4}(?:\s*(?:•|→|-)\s*(?:\d{1,2}/\d{1,2}/\d{2,4}|\d{1,2}:\d{2}))?$',
      caseSensitive: false,
    ).hasMatch(trimmed);
  }

  String _formatTime(DateTime time) {
    final localTime = time.toLocal();
    final now = DateTime.now();
    final difference = now.difference(localTime);
    String lang = 'fr';
    try {
      lang = Localizations.localeOf(context).languageCode;
    } catch (_) {}

    // If sent just now, or with clock skew / future timestamp, show instant indicator
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
        return 'منذ ${difference.inDays} يوم';
      } else {
        return ArabicTypography.toLatinDigits(DateFormat('d MMM', 'ar').format(localTime));
      }
    } else if (lang == 'en') {
      if (difference.inMinutes < 60) {
        return '${difference.inMinutes}m ago';
      } else if (difference.inHours < 24) {
        return '${difference.inHours}h ago';
      } else if (difference.inDays < 7) {
        return '${difference.inDays}d ago';
      } else {
        return DateFormat('d MMM', 'en').format(localTime);
      }
    }

    if (difference.inMinutes < 60) {
      return 'Il y a ${difference.inMinutes} min';
    } else if (difference.inHours < 24) {
      return 'Il y a ${difference.inHours}h';
    } else if (difference.inDays < 7) {
      return 'Il y a ${difference.inDays}j';
    } else {
      return DateFormat('d MMM', 'fr_FR').format(localTime);
    }
  }
}
