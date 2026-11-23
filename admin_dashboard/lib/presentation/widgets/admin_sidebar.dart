import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../data/services/school_branding_service.dart';
import '../screens/settings/password_reset_requests_screen.dart';
import 'school_logo_preview.dart';

// ═══════════════════════════════════════════════════════════════════
// ░░░  AURORA GLASS — Sidebar Navigation  ░░░
// ═══════════════════════════════════════════════════════════════════

class AdminSidebar extends ConsumerWidget {
  static double _savedOffset = 0;
  final String currentRoute;
  const AdminSidebar({super.key, required this.currentRoute});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentRoute = this.currentRoute;
    final pendingCountAsync = ref.watch(pendingPasswordResetCountProvider);
    final pendingCount = pendingCountAsync.when(
      data: (count) => count,
      loading: () => 0,
      error: (_, __) => 0,
    );
    final schoolBranding = ref.watch(currentSchoolBrandingProvider).value;
    final schoolLogoUrl = schoolBranding?['logo_url'] as String?;
    final schoolName = (schoolBranding?['name'] as String?)?.trim();

    return Container(
      width: 272,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF070B14), Color(0xFF0D1321), Color(0xFF111827)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withOpacity(0.06),
            blurRadius: 40,
            offset: const Offset(4, 0),
          ),
        ],
      ),
      child: Stack(
        children: [
          // ── Decorative gradient orb (top-right) ──
          Positioned(
            top: -40,
            right: -60,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF2563EB).withOpacity(0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // ── Decorative gradient orb (bottom-left) ──
          Positioned(
            bottom: 40,
            left: -50,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF7C3AED).withOpacity(0.08),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // ── Main content ──
          Column(
            children: [
              const SizedBox(height: 28),
              // ── Logo ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: SchoolLogoPreview(
                        logoUrl: schoolLogoUrl,
                        size: 42,
                        borderRadius: 13,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (schoolName != null && schoolName.isNotEmpty)
                                ? schoolName
                                : 'PythaOne',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                          ),
                          Text(
                            'Espace Administration',
                            style: TextStyle(
                              color: const Color(0xFF60A5FA).withOpacity(0.6),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              // ── Divider ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.white.withOpacity(0.08),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // ── Navigation Items ──
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification is ScrollUpdateNotification) {
                      _savedOffset = notification.metrics.pixels;
                    }
                    return false;
                  },
                  child: ListView(
                    key: const PageStorageKey('admin_sidebar_scroll'),
                    controller: ScrollController(
                      initialScrollOffset: _savedOffset,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      _SectionTitle(title: 'PRINCIPAL'),
                      _NavItem(
                        icon: Icons.grid_view_rounded,
                        label: 'Tableau de bord',
                        route: '/dashboard',
                        currentRoute: currentRoute,
                      ),
                      _NavItem(
                        icon: Icons.people_outline_rounded,
                        label: 'Utilisateurs',
                        route: '/users',
                        currentRoute: currentRoute,
                      ),
                      _NavItem(
                        icon: Icons.school_outlined,
                        label: 'Professeurs',
                        route: '/professors',
                        currentRoute: currentRoute,
                      ),
                      const SizedBox(height: 16),
                      _SectionTitle(title: 'ACADÉMIQUE'),
                      _NavItem(
                        icon: Icons.layers_outlined,
                        label: 'Niveaux',
                        route: '/grade-levels',
                        currentRoute: currentRoute,
                      ),
                      _NavItem(
                        icon: Icons.space_dashboard_outlined,
                        label: 'Classes',
                        route: '/classes',
                        currentRoute: currentRoute,
                      ),
                      _NavItem(
                        icon: Icons.date_range_outlined,
                        label: 'Périodes',
                        route: '/semesters',
                        currentRoute: currentRoute,
                      ),
                      _NavItem(
                        icon: Icons.menu_book_outlined,
                        label: 'Matières',
                        route: '/subjects',
                        currentRoute: currentRoute,
                      ),
                      _NavItem(
                        icon: Icons.view_timeline_outlined,
                        label: 'Emplois du temps',
                        route: '/timetables',
                        currentRoute: currentRoute,
                      ),
                      const SizedBox(height: 16),
                      _SectionTitle(title: 'SUIVI'),
                      _NavItem(
                        icon: Icons.person_off_outlined,
                        label: 'Absences',
                        route: '/absences',
                        currentRoute: currentRoute,
                      ),
                      _NavItem(
                        icon: Icons.insights_outlined,
                        label: 'Résultats',
                        route: '/results',
                        currentRoute: currentRoute,
                      ),
                      const SizedBox(height: 16),
                      _SectionTitle(title: 'COMMUNICATION'),
                      _NavItem(
                        icon: Icons.notifications_none_rounded,
                        label: 'Annonces',
                        route: '/announcements',
                        currentRoute: currentRoute,
                      ),
                      _NavItem(
                        icon: Icons.chat_bubble_outline_rounded,
                        label: 'Suggestions',
                        route: '/suggestions',
                        currentRoute: currentRoute,
                      ),
                      const SizedBox(height: 16),
                      _SectionTitle(title: 'INFRASTRUCTURE'),
                      _NavItem(
                        icon: Icons.apartment_outlined,
                        label: 'Structure',
                        route: '/structure',
                        currentRoute: currentRoute,
                      ),
                      const SizedBox(height: 16),
                      _SectionTitle(title: 'GESTION'),
                      _NavItem(
                        icon: Icons.credit_card_outlined,
                        label: 'Paiements',
                        route: '/payments',
                        currentRoute: currentRoute,
                      ),
                      _NavItem(
                        icon: Icons.folder_open_outlined,
                        label: 'Documents',
                        route: '/documents',
                        currentRoute: currentRoute,
                      ),
                      _NavItemWithBadge(
                        icon: Icons.vpn_key_outlined,
                        label: 'Mot de passe',
                        route: '/password-resets',
                        currentRoute: currentRoute,
                        badgeCount: pendingCount,
                      ),
                      _NavItem(
                        icon: Icons.tune_outlined,
                        label: 'Paramètres',
                        route: '/settings',
                        currentRoute: currentRoute,
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
              // ── Logout ──
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.error.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          mouseCursor: SystemMouseCursors.click,
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => context.go('/login'),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: AppColors.error.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Icons.power_settings_new_rounded,
                                    color: AppColors.error.withOpacity(0.9),
                                    size: 17,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  'Déconnexion',
                                  style: TextStyle(
                                    color: Colors.white60,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 14, top: 10, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.white.withOpacity(0.25),
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.8,
        ),
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final String route;
  final String currentRoute;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.route,
    required this.currentRoute,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late final AnimationController _controller;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _scaleAnim = Tween<double>(
      begin: 1.0,
      end: 0.97,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isActive =
        widget.currentRoute == widget.route ||
        (widget.route == '/dashboard' && widget.currentRoute == '/');

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => _controller.forward(),
        onTapUp: (_) {
          _controller.reverse();
          context.go(widget.route);
        },
        onTapCancel: () => _controller.reverse(),
        child: ScaleTransition(
          scale: _scaleAnim,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.only(bottom: 2),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              gradient: isActive
                  ? LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        const Color(0xFF2563EB).withOpacity(0.18),
                        const Color(0xFF7C3AED).withOpacity(0.06),
                      ],
                    )
                  : null,
              color: !isActive && _isHovered
                  ? Colors.white.withOpacity(0.04)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                // ── Active indicator bar ──
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 3,
                  height: isActive ? 24 : 0,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: isActive
                        ? const Color(0xFF60A5FA)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: isActive
                        ? [
                            BoxShadow(
                              color: const Color(0xFF60A5FA).withOpacity(0.6),
                              blurRadius: 8,
                            ),
                          ]
                        : [],
                  ),
                ),
                // ── Icon ──
                Icon(
                  widget.icon,
                  color: isActive
                      ? const Color(0xFF60A5FA)
                      : _isHovered
                      ? Colors.white70
                      : Colors.white38,
                  size: 19,
                ),
                const SizedBox(width: 12),
                // ── Label ──
                Expanded(
                  child: Text(
                    widget.label,
                    style: TextStyle(
                      color: isActive ? Colors.white : Colors.white60,
                      fontSize: 13,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
                // ── Active dot ──
                if (isActive)
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: const Color(0xFF60A5FA),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF60A5FA).withOpacity(0.5),
                          blurRadius: 6,
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

/// Nav item with notification badge
class _NavItemWithBadge extends StatefulWidget {
  final IconData icon;
  final String label;
  final String route;
  final String currentRoute;
  final int badgeCount;

  const _NavItemWithBadge({
    required this.icon,
    required this.label,
    required this.route,
    required this.currentRoute,
    required this.badgeCount,
  });

  @override
  State<_NavItemWithBadge> createState() => _NavItemWithBadgeState();
}

class _NavItemWithBadgeState extends State<_NavItemWithBadge> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isActive = widget.currentRoute == widget.route;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: () => context.go(widget.route),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            gradient: isActive
                ? LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      const Color(0xFF2563EB).withOpacity(0.18),
                      const Color(0xFF7C3AED).withOpacity(0.06),
                    ],
                  )
                : null,
            color: !isActive && _isHovered
                ? Colors.white.withOpacity(0.04)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              // ── Active indicator bar ──
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 3,
                height: isActive ? 24 : 0,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: isActive
                      ? const Color(0xFF60A5FA)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: const Color(0xFF60A5FA).withOpacity(0.6),
                            blurRadius: 8,
                          ),
                        ]
                      : [],
                ),
              ),
              // ── Icon ──
              Icon(
                widget.icon,
                color: isActive
                    ? const Color(0xFF60A5FA)
                    : _isHovered
                    ? Colors.white70
                    : Colors.white38,
                size: 19,
              ),
              const SizedBox(width: 12),
              // ── Label ──
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    color: isActive ? Colors.white : Colors.white60,
                    fontSize: 13,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
              // ── Badge ──
              if (widget.badgeCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    widget.badgeCount > 99 ? '99+' : widget.badgeCount.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
