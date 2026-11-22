// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// Animated shimmer effect for skeleton loaders
class ShimmerLoading extends StatefulWidget {
  final Widget child;
  final bool isLoading;

  const ShimmerLoading({
    super.key,
    required this.child,
    this.isLoading = true,
  });

  @override
  State<ShimmerLoading> createState() => _ShimmerLoadingState();
}

class _ShimmerLoadingState extends State<ShimmerLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.4, end: 0.85).animate(
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
    if (!widget.isLoading) return widget.child;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Opacity(
          opacity: _animation.value,
          child: widget.child,
        );
      },
    );
  }
}

/// Helper block for skeleton shapes with Instagram-style minimalist aesthetics
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double? height;
  final double borderRadius;
  final BoxShape shape;
  final Color? color;

  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius = 8,
    this.shape = BoxShape.rectangle,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color ?? const Color(0xFFE2E8F0),
        shape: shape,
        borderRadius: shape == BoxShape.circle ? null : BorderRadius.circular(borderRadius),
      ),
    );
  }
}

/// Helper for circular skeleton shapes (avatars, icons)
class SkeletonCircle extends StatelessWidget {
  final double size;
  final Color? color;

  const SkeletonCircle({
    super.key,
    required this.size,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color ?? const Color(0xFFE2E8F0),
      ),
    );
  }
}

/// Skeleton loader specifically matching Table layouts (Users, Professors, Absences, Results, etc.)
class TableSkeletonLoader extends StatelessWidget {
  final int rowCount;

  const TableSkeletonLoader({
    super.key,
    this.rowCount = 7,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.all(24),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: ShimmerLoading(
            child: Column(
              children: [
                // Header row skeleton
                Container(
                  height: 44,
                  color: const Color(0xFFF9FAFB),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: const Row(
                    children: [
                      SkeletonBox(width: 20, height: 20, borderRadius: 4),
                      SizedBox(width: 24),
                      SkeletonBox(width: 140, height: 14),
                      Spacer(),
                      SkeletonBox(width: 80, height: 14),
                      SizedBox(width: 24),
                      SkeletonBox(width: 80, height: 14),
                      SizedBox(width: 24),
                      SkeletonBox(width: 80, height: 14),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),
                // Body rows
                Expanded(
                  child: ListView.separated(
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: rowCount,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1, color: Color(0xFFF1F5F9)),
                    itemBuilder: (context, index) {
                      return Container(
                        height: 64,
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: const Row(
                          children: [
                            SkeletonBox(width: 16, height: 16, borderRadius: 3),
                            SizedBox(width: 20),
                            // Avatar + Name/Email skeleton
                            SkeletonBox(width: 36, height: 36, borderRadius: 18),
                            SizedBox(width: 12),
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SkeletonBox(width: 130, height: 14),
                                SizedBox(height: 6),
                                SkeletonBox(width: 170, height: 11),
                              ],
                            ),
                            Spacer(),
                            // Badges / Tags
                            SkeletonBox(width: 60, height: 22, borderRadius: 6),
                            SizedBox(width: 20),
                            SkeletonBox(width: 70, height: 22, borderRadius: 6),
                            SizedBox(width: 20),
                            SkeletonBox(width: 90, height: 14),
                            SizedBox(width: 20),
                            SkeletonBox(width: 24, height: 24, borderRadius: 6),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                // Footer pagination skeleton
                Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  color: const Color(0xFFFAFAFB),
                  child: const Row(
                    children: [
                      SkeletonBox(width: 120, height: 24, borderRadius: 6),
                      Spacer(),
                      SkeletonBox(width: 100, height: 14),
                      SizedBox(width: 16),
                      SkeletonBox(width: 60, height: 28, borderRadius: 6),
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

/// Skeleton loader specifically matching the modern Professors table layout
class ProfessorsSkeletonLoader extends StatelessWidget {
  final int rowCount;

  const ProfessorsSkeletonLoader({
    super.key,
    this.rowCount = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.all(24),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: ShimmerLoading(
            child: Column(
              children: [
                // Header row skeleton matching exact columns
                Container(
                  height: 44,
                  color: const Color(0xFFF9FAFB),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: const Row(
                    children: [
                      SizedBox(
                        width: 40,
                        child: Center(
                          child: SkeletonBox(width: 16, height: 16, borderRadius: 3),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: SkeletonBox(width: 130, height: 12, borderRadius: 4),
                        ),
                      ),
                      SizedBox(
                        width: 140,
                        child: Center(
                          child: SkeletonBox(width: 80, height: 12, borderRadius: 4),
                        ),
                      ),
                      SizedBox(
                        width: 100,
                        child: Center(
                          child: SkeletonBox(width: 60, height: 12, borderRadius: 4),
                        ),
                      ),
                      SizedBox(
                        width: 110,
                        child: Center(
                          child: SkeletonBox(width: 60, height: 12, borderRadius: 4),
                        ),
                      ),
                      SizedBox(
                        width: 140,
                        child: Center(
                          child: SkeletonBox(width: 70, height: 12, borderRadius: 4),
                        ),
                      ),
                      SizedBox(
                        width: 70,
                        child: Center(
                          child: SkeletonBox(width: 45, height: 12, borderRadius: 4),
                        ),
                      ),
                      SizedBox(
                        width: 90,
                        child: Center(
                          child: SkeletonBox(width: 50, height: 12, borderRadius: 4),
                        ),
                      ),
                      SizedBox(width: 40),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),
                // Body rows matching exact columns
                Expanded(
                  child: ListView.separated(
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: rowCount,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1, color: Color(0xFFF1F5F9)),
                    itemBuilder: (context, index) {
                      return Container(
                        height: 64,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: const Row(
                          children: [
                            SizedBox(
                              width: 40,
                              child: Center(
                                child: SkeletonBox(width: 16, height: 16, borderRadius: 3),
                              ),
                            ),
                            // Avatar + Name/Email
                            Expanded(
                              flex: 3,
                              child: Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8),
                                child: Row(
                                  children: [
                                    SkeletonBox(width: 36, height: 36, borderRadius: 18),
                                    SizedBox(width: 12),
                                    Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        SkeletonBox(width: 120, height: 13, borderRadius: 4),
                                        SizedBox(height: 6),
                                        SkeletonBox(width: 160, height: 10, borderRadius: 3),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            // Spécialité pill
                            SizedBox(
                              width: 140,
                              child: Center(
                                child: SkeletonBox(width: 85, height: 26, borderRadius: 12),
                              ),
                            ),
                            // Niveaux pill
                            SizedBox(
                              width: 100,
                              child: Center(
                                child: SkeletonBox(width: 65, height: 24, borderRadius: 12),
                              ),
                            ),
                            // Classes pill
                            SizedBox(
                              width: 110,
                              child: Center(
                                child: SkeletonBox(width: 65, height: 24, borderRadius: 12),
                              ),
                            ),
                            // Téléphone
                            SizedBox(
                              width: 140,
                              child: Center(
                                child: SkeletonBox(width: 90, height: 12, borderRadius: 4),
                              ),
                            ),
                            // Statut pill
                            SizedBox(
                              width: 70,
                              child: Center(
                                child: SkeletonBox(width: 50, height: 22, borderRadius: 10),
                              ),
                            ),
                            // Créé le
                            SizedBox(
                              width: 90,
                              child: Center(
                                child: SkeletonBox(width: 65, height: 12, borderRadius: 4),
                              ),
                            ),
                            // Actions
                            SizedBox(
                              width: 40,
                              child: Center(
                                child: SkeletonBox(width: 18, height: 18, borderRadius: 4),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                // Footer pagination skeleton
                Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  color: const Color(0xFFFAFAFB),
                  child: const Row(
                    children: [
                      SkeletonBox(width: 140, height: 16, borderRadius: 4),
                      Spacer(),
                      SkeletonBox(width: 90, height: 14, borderRadius: 4),
                      SizedBox(width: 16),
                      SkeletonBox(width: 60, height: 28, borderRadius: 6),
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

/// Skeleton loader precisely matching the Classes screen (2-Column Layout mirroring PaymentsSkeletonLoader)
class ClassesSkeletonLoader extends StatelessWidget {
  const ClassesSkeletonLoader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF6F6F8),
      child: ShimmerLoading(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── LEFT PANEL: NIVEAUX NAVIGATION (300px) ──
            Container(
              width: 300,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  right: BorderSide(color: const Color(0xFFE5E7EB).withOpacity(0.5)),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // TOTAL ÉTUDIANTS Card
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 16, offset: const Offset(0, 4)),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 40, height: 40,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF655DD5),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.school_rounded, color: Colors.white, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'TOTAL ÉTUDIANTS',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textSecondary.withOpacity(0.7),
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          const SkeletonBox(width: 70, height: 28, borderRadius: 6),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE5E7EB)),

                  // Niveaux List Items
                  Expanded(
                    child: ListView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      itemCount: 6,
                      itemBuilder: (context, i) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.03),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: const [
                              Expanded(
                                child: SkeletonBox(width: 110, height: 15, borderRadius: 4),
                              ),
                              SkeletonBox(width: 26, height: 26, borderRadius: 13),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

            // ── RIGHT AREA: CLASSES GRID ──
            Expanded(
              child: Column(
                children: [
                  // Top bar
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
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
                          children: const [
                            Text(
                              'Toutes les classes',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF111827),
                              ),
                            ),
                            SizedBox(height: 4),
                            SkeletonBox(width: 80, height: 13, borderRadius: 4),
                          ],
                        ),
                        const Spacer(),
                        // Search bar (static)
                        Container(
                          width: 320,
                          height: 40,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.search, size: 18, color: AppColors.textTertiary),
                              const SizedBox(width: 8),
                              Text('Rechercher...', style: TextStyle(color: AppColors.textTertiary, fontSize: 13)),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.slate50,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: Text('⌘K', style: TextStyle(fontSize: 10, color: AppColors.textTertiary, fontFamily: 'monospace')),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        // + Nouvelle classe button (static)
                        Container(
                          height: 40,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF655DD5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.add_rounded, size: 18, color: Colors.white),
                              SizedBox(width: 8),
                              Text(
                                'Nouvelle classe',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Cards Grid
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(28),
                      child: GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 350,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          mainAxisExtent: 200,
                        ),
                        itemCount: 8,
                        itemBuilder: (context, index) {
                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFFF1F5F9)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.03),
                                  blurRadius: 10,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: const [
                                    SkeletonBox(width: 38, height: 38, borderRadius: 10),
                                    SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          SkeletonBox(width: 100, height: 15, borderRadius: 4),
                                          SizedBox(height: 5),
                                          SkeletonBox(width: 60, height: 12, borderRadius: 3),
                                        ],
                                      ),
                                    ),
                                    SkeletonBox(width: 24, height: 24, borderRadius: 6),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: const [
                                    Expanded(
                                      child: SkeletonBox(height: 6, borderRadius: 4),
                                    ),
                                    SizedBox(width: 10),
                                    SkeletonBox(width: 45, height: 12, borderRadius: 3),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: const [
                                    SkeletonCircle(size: 28),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          SkeletonBox(width: 90, height: 12, borderRadius: 3),
                                          SizedBox(height: 4),
                                          SkeletonBox(width: 60, height: 10, borderRadius: 2),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
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
}

/// Minimalist Skeleton Loader for Class Timetable / Cours du jour timeline
class ClassTimetableSkeletonLoader extends StatelessWidget {
  final int itemCount;

  const ClassTimetableSkeletonLoader({
    super.key,
    this.itemCount = 3,
  });

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: Column(
        children: List.generate(itemCount, (index) {
          final isLast = index == itemCount - 1;
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Timeline column
                SizedBox(
                  width: 24,
                  child: Column(
                    children: [
                      const SkeletonCircle(size: 10),
                      if (!isLast)
                        Expanded(
                          child: Container(
                            width: 2,
                            margin: const EdgeInsets.symmetric(vertical: 2),
                            color: const Color(0xFFE4E5EB),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Course card skeleton
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAFAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFEEEFF2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        SkeletonBox(width: 90, height: 13, borderRadius: 4),
                        SizedBox(height: 5),
                        SkeletonBox(width: 110, height: 10, borderRadius: 3),
                        SizedBox(height: 5),
                        Row(
                          children: [
                            SkeletonCircle(size: 14),
                            SizedBox(width: 6),
                            SkeletonBox(width: 65, height: 10, borderRadius: 3),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

/// Minimalist Instagram-style Skeleton Loader for Class Detail Screen (Table + Sidebar Layout)
class ClassDetailSkeletonLoader extends StatelessWidget {
  const ClassDetailSkeletonLoader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8FAFC),
      child: ShimmerLoading(
        child: Column(
          children: [
            // ── TOP BAR (Matching _buildHeader in class_detail_screen.dart) ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: AppColors.border.withOpacity(0.5))),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.slate50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border.withOpacity(0.5)),
                    ),
                    child: const Icon(Icons.arrow_back_rounded, size: 20, color: AppColors.textSecondary),
                  ),
                  const SizedBox(width: 14),
                  const SkeletonBox(width: 110, height: 20, borderRadius: 6),
                  const SizedBox(width: 10),
                  const SkeletonBox(width: 80, height: 24, borderRadius: 9999),
                  const SizedBox(width: 10),
                  const SkeletonBox(width: 70, height: 24, borderRadius: 9999),
                  const Spacer(),
                  const SkeletonBox(width: 220, height: 36, borderRadius: 8),
                ],
              ),
            ),

            // ── MAIN CONTENT: LEFT (STUDENTS + TEACHERS) & RIGHT (AGENDA) ──
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── LEFT COLUMN: Student Table + Teachers Section ──
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      physics: const NeverScrollableScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. Student Table Card
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.border.withOpacity(0.3)),
                              boxShadow: [
                                BoxShadow(color: AppColors.shadow, blurRadius: 8, offset: const Offset(0, 2)),
                              ],
                            ),
                            child: Column(
                              children: [
                                // Table Header Bar
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                  decoration: const BoxDecoration(
                                    border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
                                  ),
                                  child: Row(
                                    children: const [
                                      SkeletonBox(width: 32, height: 32, borderRadius: 8),
                                      SizedBox(width: 12),
                                      SkeletonBox(width: 140, height: 16, borderRadius: 5),
                                      SizedBox(width: 10),
                                      SkeletonBox(width: 90, height: 22, borderRadius: 999),
                                      Spacer(),
                                      SkeletonBox(width: 110, height: 32, borderRadius: 8),
                                    ],
                                  ),
                                ),
                                // Table Column Headers
                                Container(
                                  height: 42,
                                  color: const Color(0xFFF8FAFC),
                                  padding: const EdgeInsets.symmetric(horizontal: 20),
                                  child: const Row(
                                    children: [
                                      SkeletonBox(width: 16, height: 16, borderRadius: 4),
                                      SizedBox(width: 20),
                                      SkeletonBox(width: 130, height: 12, borderRadius: 4),
                                      Spacer(),
                                      SkeletonBox(width: 70, height: 12, borderRadius: 4),
                                      SizedBox(width: 40),
                                      SkeletonBox(width: 60, height: 12, borderRadius: 4),
                                      SizedBox(width: 40),
                                      SkeletonBox(width: 65, height: 12, borderRadius: 4),
                                      SizedBox(width: 30),
                                      SkeletonBox(width: 20, height: 20, borderRadius: 4),
                                    ],
                                  ),
                                ),
                                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                                // Student Rows
                                ...List.generate(6, (i) => Container(
                                  height: 56,
                                  padding: const EdgeInsets.symmetric(horizontal: 20),
                                  decoration: BoxDecoration(
                                    border: i < 5 ? const Border(bottom: BorderSide(color: Color(0xFFF8FAFC))) : null,
                                  ),
                                  child: const Row(
                                    children: [
                                      SkeletonBox(width: 16, height: 16, borderRadius: 4),
                                      SizedBox(width: 20),
                                      SkeletonCircle(size: 32),
                                      SizedBox(width: 12),
                                      Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          SkeletonBox(width: 120, height: 13, borderRadius: 4),
                                          SizedBox(height: 4),
                                          SkeletonBox(width: 140, height: 10, borderRadius: 3),
                                        ],
                                      ),
                                      Spacer(),
                                      SkeletonBox(width: 60, height: 12, borderRadius: 4),
                                      SizedBox(width: 40),
                                      SkeletonBox(width: 50, height: 12, borderRadius: 4),
                                      SizedBox(width: 40),
                                      SkeletonBox(width: 65, height: 22, borderRadius: 11),
                                      SizedBox(width: 30),
                                      SkeletonBox(width: 20, height: 20, borderRadius: 6),
                                    ],
                                  ),
                                )),
                                // Pagination bar
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                  decoration: const BoxDecoration(
                                    border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
                                  ),
                                  child: Row(
                                    children: const [
                                      SkeletonBox(width: 100, height: 13, borderRadius: 4),
                                      Spacer(),
                                      SkeletonBox(width: 28, height: 28, borderRadius: 6),
                                      SizedBox(width: 8),
                                      SkeletonBox(width: 28, height: 28, borderRadius: 6),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 24),

                          // 2. Teachers Section Card
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.border.withOpacity(0.3)),
                              boxShadow: [
                                BoxShadow(color: AppColors.shadow, blurRadius: 8, offset: const Offset(0, 2)),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: const [
                                    SkeletonBox(width: 32, height: 32, borderRadius: 8),
                                    SizedBox(width: 12),
                                    SkeletonBox(width: 160, height: 16, borderRadius: 5),
                                    Spacer(),
                                    SkeletonBox(width: 90, height: 32, borderRadius: 8),
                                  ],
                                ),
                                const SizedBox(height: 18),
                                Row(
                                  children: List.generate(3, (_) => Expanded(
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(horizontal: 6),
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF8FAFC),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: const Color(0xFFF1F5F9)),
                                      ),
                                      child: const Row(
                                        children: [
                                          SkeletonCircle(size: 36),
                                          SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                SkeletonBox(width: 100, height: 13, borderRadius: 4),
                                                SizedBox(height: 5),
                                                SkeletonBox(width: 70, height: 10, borderRadius: 3),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── RIGHT SIDEBAR: AGENDA DE LA CLASSE (320px) ──
                  Container(
                    width: 320,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(left: BorderSide(color: AppColors.border.withOpacity(0.5))),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      physics: const NeverScrollableScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header: Agenda de la classe
                          Row(
                            children: const [
                              SkeletonBox(width: 32, height: 32, borderRadius: 8),
                              SizedBox(width: 10),
                              SkeletonBox(width: 150, height: 16, borderRadius: 4),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const SkeletonBox(width: 120, height: 11, borderRadius: 4),
                          const SizedBox(height: 20),

                          // Timeline slots
                          ...List.generate(4, (i) => Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFF1F5F9)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: const [
                                    SkeletonBox(width: 70, height: 18, borderRadius: 6),
                                    Spacer(),
                                    SkeletonBox(width: 50, height: 16, borderRadius: 4),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                const SkeletonBox(width: 130, height: 14, borderRadius: 4),
                                const SizedBox(height: 6),
                                Row(
                                  children: const [
                                    SkeletonCircle(size: 16),
                                    SizedBox(width: 6),
                                    SkeletonBox(width: 90, height: 11, borderRadius: 3),
                                  ],
                                ),
                              ],
                            ),
                          )),
                        ],
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
}

/// Skeleton loader precisely matching the Announcements / Annonces screen (card table view)
class AnnouncementsSkeletonLoader extends StatelessWidget {
  const AnnouncementsSkeletonLoader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.all(24),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: ShimmerLoading(
            child: Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: 5,
                    itemBuilder: (context, index) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.border),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.02),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SkeletonBox(width: 28, height: 28, borderRadius: 8),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: const [
                                      SkeletonBox(width: 130, height: 16),
                                      SizedBox(width: 10),
                                      SkeletonBox(width: 50, height: 20, borderRadius: 8),
                                      SizedBox(width: 8),
                                      SkeletonBox(width: 65, height: 20, borderRadius: 8),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  const SkeletonBox(width: double.infinity, height: 13),
                                  const SizedBox(height: 6),
                                  const SkeletonBox(width: 280, height: 13),
                                ],
                              ),
                            ),
                            const SizedBox(width: 20),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: const [
                                SkeletonBox(width: 18, height: 18, borderRadius: 4),
                                SizedBox(height: 20),
                                SkeletonBox(width: 80, height: 12),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAFAFB),
                    border: Border(top: BorderSide(color: AppColors.border.withValues(alpha: 0.3))),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(8),
                      bottomRight: Radius.circular(8),
                    ),
                  ),
                  child: const Row(
                    children: [
                      SkeletonBox(width: 110, height: 24, borderRadius: 6),
                      Spacer(),
                      SkeletonBox(width: 90, height: 14),
                      SizedBox(width: 12),
                      SkeletonBox(width: 28, height: 28, borderRadius: 8),
                      SizedBox(width: 8),
                      SkeletonBox(width: 28, height: 28, borderRadius: 8),
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

/// Skeleton loader precisely matching the Suggestions screen
class SuggestionsSkeletonLoader extends StatelessWidget {
  const SuggestionsSkeletonLoader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.all(24),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: ShimmerLoading(
            child: Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: 5,
                    itemBuilder: (context, index) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.border),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.02),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SkeletonBox(width: 28, height: 28, borderRadius: 14),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: const [
                                      SkeletonBox(width: 110, height: 16),
                                      SizedBox(width: 10),
                                      SkeletonBox(width: 55, height: 20, borderRadius: 8),
                                      SizedBox(width: 8),
                                      SkeletonBox(width: 60, height: 20, borderRadius: 8),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  const SkeletonBox(width: double.infinity, height: 13),
                                  const SizedBox(height: 6),
                                  const SkeletonBox(width: 320, height: 13),
                                ],
                              ),
                            ),
                            const SizedBox(width: 20),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: const [
                                SkeletonBox(width: 18, height: 18, borderRadius: 4),
                                SizedBox(height: 20),
                                SkeletonBox(width: 100, height: 12),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAFAFB),
                    border: Border(top: BorderSide(color: AppColors.border.withValues(alpha: 0.3))),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(8),
                      bottomRight: Radius.circular(8),
                    ),
                  ),
                  child: const Row(
                    children: [
                      SkeletonBox(width: 110, height: 24, borderRadius: 6),
                      Spacer(),
                      SkeletonBox(width: 90, height: 14),
                      SizedBox(width: 12),
                      SkeletonBox(width: 28, height: 28, borderRadius: 8),
                      SizedBox(width: 8),
                      SkeletonBox(width: 28, height: 28, borderRadius: 8),
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

/// Skeleton loader precisely matching the Building Structure screen
class BuildingStructureSkeletonLoader extends StatelessWidget {
  const BuildingStructureSkeletonLoader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.all(32),
      child: ShimmerLoading(
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Column(
            children: List.generate(3, (i) => Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  // Building Header
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: const [
                        SkeletonBox(width: 40, height: 40, borderRadius: 10),
                        SizedBox(width: 14),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonBox(width: 140, height: 16),
                            SizedBox(height: 4),
                            SkeletonBox(width: 60, height: 12),
                          ],
                        ),
                        SizedBox(width: 16),
                        SkeletonBox(width: 70, height: 20, borderRadius: 6),
                        SizedBox(width: 8),
                        SkeletonBox(width: 65, height: 20, borderRadius: 6),
                        Spacer(),
                        SkeletonBox(width: 28, height: 28, borderRadius: 6),
                        SizedBox(width: 6),
                        SkeletonBox(width: 28, height: 28, borderRadius: 6),
                        SizedBox(width: 6),
                        SkeletonBox(width: 28, height: 28, borderRadius: 6),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFF1F5F9)),
                  // Floor row
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: const [
                        SkeletonBox(width: 80, height: 24, borderRadius: 6),
                        SizedBox(width: 16),
                        SkeletonBox(width: 90, height: 36, borderRadius: 8),
                        SizedBox(width: 8),
                        SkeletonBox(width: 90, height: 36, borderRadius: 8),
                        SizedBox(width: 8),
                        SkeletonBox(width: 90, height: 36, borderRadius: 8),
                      ],
                    ),
                  ),
                ],
              ),
            )),
          ),
        ),
      ),
    );
  }
}

/// Skeleton loader precisely matching the Payments / Paiements screen (2-Column Classes Layout)
class PaymentsSkeletonLoader extends StatelessWidget {
  const PaymentsSkeletonLoader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF6F6F8),
      child: ShimmerLoading(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── LEFT PANEL: NIVEAUX NAVIGATION (300px) ──
            Container(
              width: 300,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  right: BorderSide(color: const Color(0xFFE5E7EB).withOpacity(0.5)),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Niveaux Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                    child: Row(
                      children: const [
                        SkeletonBox(width: 36, height: 36, borderRadius: 10),
                        SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonBox(width: 80, height: 16, borderRadius: 4),
                            SizedBox(height: 4),
                            SkeletonBox(width: 130, height: 12, borderRadius: 4),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE5E7EB)),

                  // Niveaux List Items
                  Expanded(
                    child: ListView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      itemCount: 6,
                      itemBuilder: (context, i) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.03),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: const [
                              Expanded(
                                child: SkeletonBox(width: 110, height: 15, borderRadius: 4),
                              ),
                              SkeletonBox(width: 26, height: 26, borderRadius: 13),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

            // ── RIGHT AREA: CLASSES PAYMENT GRID ──
            Expanded(
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header row
                    Row(
                      children: const [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonBox(width: 170, height: 22, borderRadius: 4),
                            SizedBox(height: 6),
                            SkeletonBox(width: 85, height: 13, borderRadius: 4),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Grid of Class Payment Cards matching _buildPaymentClassCard
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 350,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        mainAxisExtent: 205,
                      ),
                      itemCount: 6,
                      itemBuilder: (context, index) {
                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFF1F5F9)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.03),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // Header: 36x36 Icon + Class info
                              Row(
                                children: const [
                                  SkeletonBox(width: 36, height: 36, borderRadius: 8),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        SkeletonBox(width: 90, height: 16, borderRadius: 4),
                                        SizedBox(height: 5),
                                        SkeletonBox(width: 60, height: 11, borderRadius: 4),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              // Amounts row: Déjà payé (left) & Total à payer (right)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: const [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      SkeletonBox(width: 50, height: 11, borderRadius: 3),
                                      SizedBox(height: 4),
                                      SkeletonBox(width: 70, height: 15, borderRadius: 4),
                                    ],
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      SkeletonBox(width: 65, height: 11, borderRadius: 3),
                                      SizedBox(height: 4),
                                      SkeletonBox(width: 75, height: 15, borderRadius: 4),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              // Progress Bar + Percentage
                              Row(
                                children: const [
                                  Expanded(child: SkeletonBox(height: 6, borderRadius: 3)),
                                  SizedBox(width: 10),
                                  SkeletonBox(width: 30, height: 12, borderRadius: 3),
                                ],
                              ),
                              const SizedBox(height: 6),
                              // Footer / Remaining
                              Row(
                                children: const [
                                  SkeletonBox(width: 55, height: 11, borderRadius: 3),
                                  SizedBox(width: 6),
                                  SkeletonBox(width: 65, height: 13, borderRadius: 4),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
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
}

/// Skeleton loader precisely matching the Results / Résultats screen (Niveaux / Classes selector)
class ResultsSkeletonLoader extends StatelessWidget {
  const ResultsSkeletonLoader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF6F6F8),
      child: ShimmerLoading(
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Info header with semester badge
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  children: const [
                    SkeletonBox(width: 160, height: 18),
                    Spacer(),
                    SkeletonBox(width: 90, height: 22, borderRadius: 999),
                  ],
                ),
              ),

              // Cycle Card Wrapper
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF655DD5).withValues(alpha: 0.05),
                      blurRadius: 6,
                      offset: const Offset(0, 4),
                    ),
                    BoxShadow(
                      color: const Color(0xFF655DD5).withValues(alpha: 0.03),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    // Card header
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF8FAFC),
                        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                      ),
                      child: Row(
                        children: const [
                          SkeletonBox(width: 36, height: 36, borderRadius: 8),
                          SizedBox(width: 12),
                          SkeletonBox(width: 70, height: 16),
                          SizedBox(width: 12),
                          SkeletonBox(width: 80, height: 20, borderRadius: 999),
                        ],
                      ),
                    ),

                    // Niveau rows (matching _HoverableNiveauRow cards exactly)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: List.generate(3, (i) {
                          final hasSections = i == 1;
                          return Padding(
                            padding: EdgeInsets.only(bottom: i < 2 ? 16 : 0),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                border: Border.all(color: const Color(0xFFF1F5F9)),
                                borderRadius: BorderRadius.circular(12),
                                color: Colors.transparent,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Title row
                                  Row(
                                    children: const [
                                      SkeletonBox(width: 110, height: 15),
                                      SizedBox(width: 8),
                                      SkeletonBox(width: 70, height: 12),
                                      Spacer(),
                                      SkeletonBox(width: 36, height: 18, borderRadius: 4),
                                    ],
                                  ),
                                  // Filières row if present
                                  if (hasSections) ...[
                                    const SizedBox(height: 10),
                                    Row(
                                      children: const [
                                        SkeletonBox(width: 50, height: 11),
                                        SizedBox(width: 12),
                                        SkeletonBox(width: 60, height: 20, borderRadius: 4),
                                        SizedBox(width: 8),
                                        SkeletonBox(width: 70, height: 20, borderRadius: 4),
                                        SizedBox(width: 8),
                                        SkeletonBox(width: 65, height: 20, borderRadius: 4),
                                      ],
                                    ),
                                  ],
                                  // Class pills row
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: List.generate(
                                      i == 0 ? 4 : (i == 1 ? 5 : 3),
                                      (j) => const SkeletonBox(
                                        width: 84,
                                        height: 28,
                                        borderRadius: 999,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ),
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

/// Skeleton loader precisely matching the Results Student List Table (when a class is selected)
class ResultsStudentListSkeletonLoader extends StatelessWidget {
  final int rowCount;
  const ResultsStudentListSkeletonLoader({super.key, this.rowCount = 10});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.all(24),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: ShimmerLoading(
            child: Column(
              children: [
                // Table header
                Container(
                  height: 44,
                  color: const Color(0xFFF9FAFB),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: const [
                      SkeletonBox(width: 16, height: 16, borderRadius: 3),
                      SizedBox(width: 20),
                      SkeletonBox(width: 16, height: 12),
                      SizedBox(width: 24),
                      SkeletonBox(width: 150, height: 12),
                      Spacer(),
                      SkeletonBox(width: 80, height: 12),
                      SizedBox(width: 40),
                      SkeletonBox(width: 60, height: 12),
                      SizedBox(width: 24),
                      SkeletonBox(width: 16, height: 12),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),
                // Table rows
                Expanded(
                  child: ListView.separated(
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: rowCount,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, color: Color(0xFFF1F5F9)),
                    itemBuilder: (context, index) {
                      return Container(
                        height: 64,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: const [
                            SkeletonBox(width: 16, height: 16, borderRadius: 3),
                            SizedBox(width: 20),
                            SkeletonBox(width: 16, height: 12),
                            SizedBox(width: 20),
                            // Avatar + Name/Email
                            SkeletonBox(width: 32, height: 32, borderRadius: 16),
                            SizedBox(width: 12),
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SkeletonBox(width: 130, height: 14),
                                SizedBox(height: 6),
                                SkeletonBox(width: 160, height: 11),
                              ],
                            ),
                            Spacer(),
                            // Matricule pill badge
                            SkeletonBox(width: 85, height: 24, borderRadius: 6),
                            SizedBox(width: 35),
                            // Classe pill badge
                            SkeletonBox(width: 65, height: 24, borderRadius: 6),
                            SizedBox(width: 20),
                            // Action chevron
                            SkeletonBox(width: 16, height: 16, borderRadius: 4),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                // Footer pagination
                Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFAFAFB),
                    border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                  ),
                  child: Row(
                    children: const [
                      SkeletonBox(width: 140, height: 26, borderRadius: 8),
                      Spacer(),
                      SkeletonBox(width: 90, height: 14),
                      SizedBox(width: 12),
                      SkeletonBox(width: 60, height: 28, borderRadius: 6),
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

/// Skeleton loader precisely matching the Single Student Grade Entry / Saisie des notes table layout
class SingleStudentGradeEntrySkeletonLoader extends StatelessWidget {
  final int rowCount;
  const SingleStudentGradeEntrySkeletonLoader({super.key, this.rowCount = 8});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.all(24),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = constraints.maxWidth;
            const checkboxW = 44.0;
            const actionsW = 44.0;
            const codeW = 90.0;
            const coefW = 90.0;
            const evalW = 290.0;
            const noteW = 120.0;
            const statutW = 110.0;

            final fixedW = checkboxW + codeW + coefW + evalW + noteW + statutW + actionsW;
            final nameW = (availableWidth - fixedW).clamp(140.0, 280.0);
            final totalTableW = fixedW + nameW > availableWidth ? fixedW + nameW : availableWidth;

            return ShimmerLoading(
              child: Column(
                children: [
                  // Table content with horizontal scroll if needed
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: totalTableW,
                        child: Column(
                          children: [
                            // Header row
                            Container(
                              height: 44,
                              color: const Color(0xFFF9FAFB),
                              child: Row(
                                children: [
                                  const SizedBox(
                                    width: checkboxW,
                                    child: Center(
                                      child: SkeletonBox(width: 16, height: 16, borderRadius: 3),
                                    ),
                                  ),
                                  const SizedBox(
                                    width: codeW,
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 8),
                                      child: SkeletonBox(width: 48, height: 11, borderRadius: 3),
                                    ),
                                  ),
                                  SizedBox(
                                    width: nameW,
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 8),
                                      child: SkeletonBox(width: 100, height: 11, borderRadius: 3),
                                    ),
                                  ),
                                  const SizedBox(
                                    width: coefW,
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 8),
                                      child: SkeletonBox(width: 65, height: 11, borderRadius: 3),
                                    ),
                                  ),
                                  const SizedBox(
                                    width: evalW,
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 8),
                                      child: SkeletonBox(width: 95, height: 11, borderRadius: 3),
                                    ),
                                  ),
                                  const SizedBox(
                                    width: noteW,
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 8),
                                      child: SkeletonBox(width: 85, height: 11, borderRadius: 3),
                                    ),
                                  ),
                                  const SizedBox(
                                    width: statutW,
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 8),
                                      child: SkeletonBox(width: 55, height: 11, borderRadius: 3),
                                    ),
                                  ),
                                  const SizedBox(width: actionsW),
                                ],
                              ),
                            ),
                            const Divider(height: 1, color: Color(0xFFE2E8F0)),
                            // Body rows
                            Expanded(
                              child: ListView.separated(
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: rowCount,
                                separatorBuilder: (_, _) =>
                                    const Divider(height: 1, color: Color(0xFFF1F5F9)),
                                itemBuilder: (context, index) {
                                  return SizedBox(
                                    height: 58,
                                    child: Row(
                                      children: [
                                        const SizedBox(
                                          width: checkboxW,
                                          child: Center(
                                            child: SkeletonBox(width: 16, height: 16, borderRadius: 3),
                                          ),
                                        ),
                                        // CODE pill
                                        const SizedBox(
                                          width: codeW,
                                          child: Padding(
                                            padding: EdgeInsets.symmetric(horizontal: 8),
                                            child: SkeletonBox(width: 52, height: 24, borderRadius: 9999),
                                          ),
                                        ),
                                        // MATIÈRE (Icon + Name)
                                        SizedBox(
                                          width: nameW,
                                          child: const Padding(
                                            padding: EdgeInsets.symmetric(horizontal: 8),
                                            child: Row(
                                              children: [
                                                SkeletonBox(width: 28, height: 28, borderRadius: 6),
                                                SizedBox(width: 10),
                                                Expanded(
                                                  child: SkeletonBox(height: 13, borderRadius: 4),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        // COEFFICIENT pill
                                        const SizedBox(
                                          width: coefW,
                                          child: Padding(
                                            padding: EdgeInsets.symmetric(horizontal: 8),
                                            child: SkeletonBox(width: 56, height: 24, borderRadius: 9999),
                                          ),
                                        ),
                                        // ÉVALUATIONS pills
                                        const SizedBox(
                                          width: evalW,
                                          child: Padding(
                                            padding: EdgeInsets.symmetric(horizontal: 8),
                                            child: Row(
                                              children: [
                                                SkeletonBox(width: 60, height: 24, borderRadius: 9999),
                                                SizedBox(width: 6),
                                                SkeletonBox(width: 68, height: 24, borderRadius: 9999),
                                              ],
                                            ),
                                          ),
                                        ),
                                        // NOTE / MOYENNE
                                        const SizedBox(
                                          width: noteW,
                                          child: Padding(
                                            padding: EdgeInsets.symmetric(horizontal: 8),
                                            child: SkeletonBox(width: 65, height: 14, borderRadius: 4),
                                          ),
                                        ),
                                        // STATUT pill
                                        const SizedBox(
                                          width: statutW,
                                          child: Padding(
                                            padding: EdgeInsets.symmetric(horizontal: 8),
                                            child: SkeletonBox(width: 72, height: 24, borderRadius: 9999),
                                          ),
                                        ),
                                        // Actions menu
                                        const SizedBox(
                                          width: actionsW,
                                          child: Center(
                                            child: SkeletonBox(width: 16, height: 16, borderRadius: 4),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Footer pagination
                  Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFAFAFB),
                      border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                    ),
                    child: const Row(
                      children: [
                        SkeletonBox(width: 130, height: 26, borderRadius: 8),
                        Spacer(),
                        SkeletonBox(width: 85, height: 14, borderRadius: 4),
                        SizedBox(width: 12),
                        SkeletonBox(width: 60, height: 28, borderRadius: 6),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Skeleton loader precisely matching the Historique d'absences screen (Image 3)
class StudentAbsencesSkeletonLoader extends StatelessWidget {
  final bool showHeader;
  const StudentAbsencesSkeletonLoader({super.key, this.showHeader = true});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF5F7FA),
      child: ShimmerLoading(
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showHeader) ...[
                // ── TOP BAR: BACK ARROW + TITLE + VOIR LE PROFIL ──
                Row(
                  children: const [
                    SkeletonBox(width: 40, height: 40, borderRadius: 10),
                    SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(width: 200, height: 22),
                        SizedBox(height: 4),
                        SkeletonBox(width: 130, height: 13),
                      ],
                    ),
                    Spacer(),
                    SkeletonBox(width: 110, height: 38, borderRadius: 10),
                  ],
                ),
                const SizedBox(height: 24),
              ],

              // ── PROFILE SUMMARY CARD ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Avatar circle
                    const SkeletonBox(width: 80, height: 80, borderRadius: 40),
                    const SizedBox(width: 24),
                    // Name & Badge Pills
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SkeletonBox(width: 180, height: 20),
                          const SizedBox(height: 4),
                          const SkeletonBox(width: 100, height: 13),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: const [
                              SkeletonBox(width: 150, height: 26, borderRadius: 6),
                              SkeletonBox(width: 60, height: 26, borderRadius: 6),
                              SkeletonBox(width: 70, height: 26, borderRadius: 6),
                              SkeletonBox(width: 60, height: 26, borderRadius: 6),
                              SkeletonBox(width: 80, height: 26, borderRadius: 6),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    // Right Contact
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: const [
                        Row(
                          children: [
                            SkeletonBox(width: 14, height: 14, borderRadius: 3),
                            SizedBox(width: 8),
                            SkeletonBox(width: 140, height: 13),
                          ],
                        ),
                        SizedBox(height: 8),
                        Row(
                          children: [
                            SkeletonBox(width: 14, height: 14, borderRadius: 3),
                            SizedBox(width: 8),
                            SkeletonBox(width: 110, height: 13),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ── 2-COLUMN SECTION: CALENDRIER & STATISTIQUES ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left Card: Calendrier des absences (58%)
                  Expanded(
                    flex: 58,
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Calendar Header with month switcher
                          Row(
                            children: const [
                              SkeletonBox(width: 180, height: 17),
                              Spacer(),
                              SkeletonBox(width: 32, height: 32, borderRadius: 8),
                              SizedBox(width: 8),
                              SkeletonBox(width: 100, height: 14),
                              SizedBox(width: 8),
                              SkeletonBox(width: 32, height: 32, borderRadius: 8),
                            ],
                          ),
                          const SizedBox(height: 24),
                          // Weekdays row
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: List.generate(7, (i) => const SkeletonBox(width: 20, height: 14)),
                          ),
                          const SizedBox(height: 16),
                          // Calendar 5 rows of 7 days
                          ...List.generate(5, (row) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: List.generate(7, (col) => Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFFF1F5F9)),
                                ),
                              )),
                            ),
                          )),
                          const SizedBox(height: 16),
                          // Legend Row
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              SkeletonBox(width: 8, height: 8, borderRadius: 4),
                              SizedBox(width: 6),
                              SkeletonBox(width: 45, height: 11),
                              SizedBox(width: 16),
                              SkeletonBox(width: 8, height: 8, borderRadius: 4),
                              SizedBox(width: 6),
                              SkeletonBox(width: 45, height: 11),
                              SizedBox(width: 16),
                              SkeletonBox(width: 8, height: 8, borderRadius: 4),
                              SizedBox(width: 6),
                              SkeletonBox(width: 45, height: 11),
                              SizedBox(width: 16),
                              SkeletonBox(width: 8, height: 8, borderRadius: 4),
                              SizedBox(width: 6),
                              SkeletonBox(width: 65, height: 11),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),

                  // Right Card: Statistiques (42%)
                  Expanded(
                    flex: 42,
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              SkeletonBox(width: 100, height: 17),
                              Spacer(),
                              SkeletonBox(width: 70, height: 13),
                            ],
                          ),
                          const SizedBox(height: 28),
                          // Donut Chart skeleton
                          Center(
                            child: Container(
                              width: 170,
                              height: 170,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFFE2E8F0), width: 14),
                              ),
                              child: const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SkeletonBox(width: 60, height: 26),
                                  SizedBox(height: 6),
                                  SkeletonBox(width: 50, height: 11),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 36),
                          // 4 Metric rows
                          ...List.generate(4, (i) => Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Row(
                              children: const [
                                SkeletonBox(width: 18, height: 18, borderRadius: 4),
                                SizedBox(width: 12),
                                SkeletonBox(width: 110, height: 13),
                                Spacer(),
                                SkeletonBox(width: 45, height: 15),
                              ],
                            ),
                          )),
                        ],
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
}

/// Minimalist Instagram-style Skeleton Loader for Student Profile Screen
class StudentProfileSkeletonLoader extends StatelessWidget {
  const StudentProfileSkeletonLoader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8FAFC),
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header (buttons are static UI, only user's name is a variable)
            Container(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 20),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
              ),
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => Navigator.of(context).maybePop(),
                        child: const Padding(
                          padding: EdgeInsets.all(10),
                          child: Icon(
                            Icons.arrow_back_rounded,
                            size: 20,
                            color: Color(0xFF475569),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ShimmerLoading(
                          child: SkeletonBox(
                            width: 190,
                            height: 22,
                            borderRadius: 6,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Profil étudiant',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  IgnorePointer(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _buildHeaderOutlineButton(
                          Icons.mail_outline_rounded,
                          'Envoyer message élève',
                        ),
                        _buildHeaderOutlineButton(
                          Icons.lock_reset_rounded,
                          'Réinitialiser mot de passe',
                        ),
                        _buildHeaderOutlineButton(
                          Icons.verified_user_outlined,
                          'Accès actif',
                        ),
                        SizedBox(
                          height: 40,
                          child: ElevatedButton.icon(
                            onPressed: () {},
                            icon: const Icon(Icons.edit_outlined, size: 16),
                            label: const Text(
                              'Modifier',
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
                              shadowColor:
                                  const Color(0xFF6D4CF6).withValues(alpha: 0.3),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // 2-Column Body (360px Left + Expanded Right)
            ShimmerLoading(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left Column
                  SizedBox(
                    width: 360,
                    child: Column(
                      children: [
                        // Profile Card
                        Container(
                          padding: const EdgeInsets.all(28),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            children: [
                              const SkeletonCircle(size: 100),
                              const SizedBox(height: 16),
                              const SkeletonBox(width: 170, height: 18, borderRadius: 5),
                              const SizedBox(height: 8),
                              const SkeletonBox(width: 84, height: 24, borderRadius: 20),
                              const SizedBox(height: 6),
                              const SkeletonBox(width: 88, height: 12, borderRadius: 4),
                              const SizedBox(height: 24),
                              ...List.generate(
                                5,
                                (_) => const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 6),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 100,
                                        child: SkeletonBox(width: 68, height: 12, borderRadius: 4),
                                      ),
                                      Expanded(
                                        child: SkeletonBox(width: double.infinity, height: 12, borderRadius: 4),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              const Divider(height: 1, color: Color(0xFFE2E8F0)),
                              const SizedBox(height: 16),
                              const Align(
                                alignment: Alignment.centerLeft,
                                child: SkeletonBox(width: 105, height: 13, borderRadius: 4),
                              ),
                              const SizedBox(height: 12),
                              ...List.generate(
                                3,
                                (_) => const Padding(
                                  padding: EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    children: [
                                      SkeletonBox(width: 28, height: 28, borderRadius: 8),
                                      SizedBox(width: 10),
                                      Expanded(
                                        child: SkeletonBox(width: double.infinity, height: 12, borderRadius: 4),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Security Card
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  SkeletonBox(width: 18, height: 18, borderRadius: 4),
                                  SizedBox(width: 8),
                                  SkeletonBox(width: 75, height: 15, borderRadius: 4),
                                ],
                              ),
                              SizedBox(height: 16),
                              SkeletonBox(width: 115, height: 12, borderRadius: 4),
                              SizedBox(height: 8),
                              SkeletonBox(width: double.infinity, height: 42, borderRadius: 10),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 32),

                  // Right Column
                  Expanded(
                    child: Column(
                      children: [
                        // Stats Grid (4 cards)
                        Row(
                          children: List.generate(4, (i) {
                            return Expanded(
                              child: Container(
                                margin: EdgeInsets.only(right: i < 3 ? 16 : 0),
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: const Row(
                                  children: [
                                    SkeletonBox(width: 42, height: 42, borderRadius: 12),
                                    SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          SkeletonBox(width: 38, height: 22, borderRadius: 5),
                                          SizedBox(height: 6),
                                          SkeletonBox(width: double.infinity, height: 12, borderRadius: 4),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: 32),

                        // Calendar + Payments Cards (440px height)
                        SizedBox(
                          height: 440,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Presence Calendar Skeleton
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(24),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: const Color(0xFFE2E8F0)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Row(
                                        children: [
                                          SkeletonBox(width: 150, height: 16, borderRadius: 4),
                                          Spacer(),
                                          SkeletonBox(width: 110, height: 26, borderRadius: 8),
                                        ],
                                      ),
                                      const SizedBox(height: 20),
                                      Row(
                                        children: List.generate(
                                          7,
                                          (_) => const Expanded(
                                            child: Center(
                                              child: SkeletonBox(width: 22, height: 12, borderRadius: 3),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Expanded(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: List.generate(
                                            5,
                                            (_) => Row(
                                              children: List.generate(
                                                7,
                                                (_) => const Expanded(
                                                  child: Center(
                                                    child: SkeletonBox(width: 30, height: 30, borderRadius: 8),
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
                              ),
                              const SizedBox(width: 32),

                              // Payments Donut Card Skeleton
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(24),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: const Color(0xFFE2E8F0)),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Row(
                                        children: [
                                          SkeletonBox(width: 90, height: 16, borderRadius: 4),
                                          Spacer(),
                                          SkeletonBox(width: 55, height: 13, borderRadius: 4),
                                        ],
                                      ),
                                      const SkeletonCircle(size: 156),
                                      Column(
                                        children: List.generate(
                                          5,
                                          (_) => const Padding(
                                            padding: EdgeInsets.only(top: 10),
                                            child: Row(
                                              children: [
                                                SkeletonBox(width: 18, height: 18, borderRadius: 4),
                                                SizedBox(width: 10),
                                                SkeletonBox(width: 80, height: 12, borderRadius: 4),
                                                Spacer(),
                                                SkeletonBox(width: 60, height: 12, borderRadius: 4),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),

                        // Activity Log Card Skeleton
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                                  child: Row(
                                    children: [
                                      SkeletonBox(width: 135, height: 16, borderRadius: 4),
                                      Spacer(),
                                      SkeletonBox(width: 75, height: 12, borderRadius: 4),
                                    ],
                                  ),
                                ),
                                Container(
                                  height: 44,
                                  padding: const EdgeInsets.symmetric(horizontal: 24),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFF9FAFB),
                                    border: Border(
                                      top: BorderSide(color: Color(0xFFE2E8F0)),
                                      bottom: BorderSide(color: Color(0xFFE2E8F0)),
                                    ),
                                  ),
                                  child: const Row(
                                    children: [
                                      Expanded(flex: 2, child: Align(alignment: Alignment.centerLeft, child: SkeletonBox(width: 55, height: 11))),
                                      Expanded(flex: 5, child: Align(alignment: Alignment.centerLeft, child: SkeletonBox(width: 75, height: 11))),
                                      Expanded(flex: 2, child: Align(alignment: Alignment.centerLeft, child: SkeletonBox(width: 45, height: 11))),
                                    ],
                                  ),
                                ),
                                ...List.generate(
                                  3,
                                  (idx) => Column(
                                    children: [
                                      const Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                                        child: Row(
                                          children: [
                                            Expanded(flex: 2, child: Align(alignment: Alignment.centerLeft, child: SkeletonBox(width: 72, height: 22, borderRadius: 8))),
                                            Expanded(flex: 5, child: Align(alignment: Alignment.centerLeft, child: SkeletonBox(width: 210, height: 13))),
                                            Expanded(flex: 2, child: Align(alignment: Alignment.centerLeft, child: SkeletonBox(width: 80, height: 12))),
                                          ],
                                        ),
                                      ),
                                      if (idx < 2)
                                        const Divider(height: 1, color: Color(0xFFF1F5F9)),
                                    ],
                                  ),
                                ),
                                Container(
                                  height: 50,
                                  color: const Color(0xFFFAFAFB),
                                  padding: const EdgeInsets.symmetric(horizontal: 24),
                                  child: const Row(
                                    children: [
                                      SkeletonBox(width: 115, height: 24, borderRadius: 8),
                                      Spacer(),
                                      SkeletonBox(width: 80, height: 12),
                                      SizedBox(width: 12),
                                      SkeletonBox(width: 58, height: 28, borderRadius: 6),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
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

  Widget _buildHeaderOutlineButton(IconData icon, String label) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: const Color(0xFF64748B)),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Minimalist Instagram-style Skeleton Loader for Teacher / Professor Profile Screen
class TeacherProfileSkeletonLoader extends StatelessWidget {
  const TeacherProfileSkeletonLoader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8FAFC),
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header (buttons & subtitle are static UI, only teacher name is a variable)
            Container(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 20),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
              ),
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => Navigator.of(context).maybePop(),
                        child: const Padding(
                          padding: EdgeInsets.all(10),
                          child: Icon(
                            Icons.arrow_back_rounded,
                            size: 20,
                            color: Color(0xFF475569),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ShimmerLoading(
                          child: SkeletonBox(
                            width: 190,
                            height: 22,
                            borderRadius: 6,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Profil enseignant',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        height: 40,
                        width: 105,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                      ),
                      Container(
                        height: 40,
                        width: 145,
                        decoration: BoxDecoration(
                          color: const Color(0xFF6D4CF6).withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Body: Top 2-Column Row + Full-Width Timetable Below
            ShimmerLoading(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left Column: Profile Card (360px)
                      Container(
                        width: 360,
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          children: [
                            const SkeletonCircle(size: 100),
                            const SizedBox(height: 16),
                            const SkeletonBox(width: 170, height: 18, borderRadius: 5),
                            const SizedBox(height: 8),
                            // Single status badge
                            const SkeletonBox(width: 64, height: 24, borderRadius: 20),
                            const SizedBox(height: 6),
                            const SkeletonBox(width: 95, height: 12, borderRadius: 4),
                            const SizedBox(height: 24),
                            ...List.generate(
                              3,
                              (_) => const Padding(
                                padding: EdgeInsets.symmetric(vertical: 6),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 100,
                                      child: SkeletonBox(width: 68, height: 12, borderRadius: 4),
                                    ),
                                    Expanded(
                                      child: SkeletonBox(width: double.infinity, height: 12, borderRadius: 4),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            const Divider(height: 1, color: Color(0xFFE2E8F0)),
                            const SizedBox(height: 16),
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: SkeletonBox(width: 105, height: 13, borderRadius: 4),
                            ),
                            const SizedBox(height: 12),
                            ...List.generate(
                              2,
                              (_) => const Padding(
                                padding: EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    SkeletonBox(width: 28, height: 28, borderRadius: 8),
                                    SizedBox(width: 10),
                                    Expanded(
                                      child: SkeletonBox(width: double.infinity, height: 12, borderRadius: 4),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(width: 32),

                      // Right Column: Specialty + Classes
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Card 1: Spécialité & Niveaux
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFFE5E7EB)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SkeletonBox(width: 145, height: 11, borderRadius: 4),
                                  const SizedBox(height: 14),
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 10,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      const SkeletonBox(width: 115, height: 38, borderRadius: 12),
                                      Container(width: 1, height: 32, color: const Color(0xFFE5E7EB)),
                                      const SkeletonBox(width: 92, height: 36, borderRadius: 12),
                                      const SkeletonBox(width: 108, height: 36, borderRadius: 12),
                                      const SkeletonBox(width: 96, height: 36, borderRadius: 12),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 24),

                            // Section 2: Classes Assignées (Header + 2-column grid of cards)
                            const Row(
                              children: [
                                SkeletonBox(width: 165, height: 20, borderRadius: 5),
                                Spacer(),
                                SkeletonBox(width: 72, height: 26, borderRadius: 12),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: List.generate(2, (i) {
                                return Expanded(
                                  child: Container(
                                    margin: EdgeInsets.only(right: i == 0 ? 16 : 0),
                                    padding: const EdgeInsets.all(20),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: const Color(0xFFE5E7EB)),
                                    ),
                                    child: const Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  SkeletonBox(width: 115, height: 17, borderRadius: 5),
                                                  SizedBox(height: 6),
                                                  SkeletonBox(width: 85, height: 12, borderRadius: 4),
                                                ],
                                              ),
                                            ),
                                            SkeletonBox(width: 40, height: 40, borderRadius: 12),
                                          ],
                                        ),
                                        SizedBox(height: 14),
                                        Divider(height: 1, color: Color(0xFFF1F5F9)),
                                        SizedBox(height: 14),
                                        Row(
                                          children: [
                                            SkeletonBox(width: 90, height: 12, borderRadius: 4),
                                            SizedBox(width: 20),
                                            SkeletonBox(width: 60, height: 12, borderRadius: 4),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Full Width: Emploi du temps Card Below
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            SkeletonBox(width: 20, height: 20, borderRadius: 4),
                            SizedBox(width: 10),
                            SkeletonBox(width: 150, height: 20, borderRadius: 5),
                            SizedBox(width: 12),
                            SkeletonBox(width: 110, height: 22, borderRadius: 20),
                            Spacer(),
                            SkeletonBox(width: 165, height: 36, borderRadius: 12),
                          ],
                        ),
                        const SizedBox(height: 20),
                        // Working Hours Bar Chart Skeleton
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF9FAFB),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                          ),
                          child: Column(
                            children: [
                              const Row(
                                children: [
                                  SkeletonBox(width: 190, height: 11, borderRadius: 3),
                                  Spacer(),
                                  SkeletonBox(width: 55, height: 13, borderRadius: 4),
                                ],
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                height: 82,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    const Expanded(child: Center(child: SkeletonBox(width: 28, height: 48, borderRadius: 6))),
                                    const Expanded(child: Center(child: SkeletonBox(width: 28, height: 34, borderRadius: 6))),
                                    const Expanded(child: Center(child: SkeletonBox(width: 28, height: 54, borderRadius: 6))),
                                    const Expanded(child: Center(child: SkeletonBox(width: 28, height: 40, borderRadius: 6))),
                                    const Expanded(child: Center(child: SkeletonBox(width: 28, height: 28, borderRadius: 6))),
                                    const Expanded(child: Center(child: SkeletonBox(width: 28, height: 14, borderRadius: 6))),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        ...List.generate(
                          3,
                          (_) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              children: [
                                const SizedBox(
                                  width: 56,
                                  child: Column(
                                    children: [
                                      SkeletonBox(width: 40, height: 12, borderRadius: 3),
                                      SizedBox(height: 4),
                                      SkeletonBox(width: 34, height: 10, borderRadius: 3),
                                    ],
                                  ),
                                ),
                                Container(width: 1, height: 48, color: const Color(0xFFE5E7EB)),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: const Color(0xFFE5E7EB)),
                                    ),
                                    child: const Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        SkeletonBox(width: 160, height: 14, borderRadius: 4),
                                        SizedBox(height: 6),
                                        SkeletonBox(width: 115, height: 12, borderRadius: 4),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
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
}

/// Generic Skeleton loader for simple Grid / Cards layout
class GridSkeletonLoader extends StatelessWidget {
  final int itemCount;

  const GridSkeletonLoader({
    super.key,
    this.itemCount = 6,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.all(24),
      child: ShimmerLoading(
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 340,
            mainAxisSpacing: 20,
            crossAxisSpacing: 20,
            childAspectRatio: 1.3,
          ),
          itemCount: itemCount,
          itemBuilder: (context, index) {
            return Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SkeletonBox(width: 44, height: 44, borderRadius: 12),
                      SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBox(width: 120, height: 16),
                          SizedBox(height: 6),
                          SkeletonBox(width: 70, height: 12),
                        ],
                      ),
                      Spacer(),
                      SkeletonBox(width: 24, height: 24, borderRadius: 6),
                    ],
                  ),
                  Spacer(),
                  SkeletonBox(width: double.infinity, height: 12),
                  SizedBox(height: 8),
                  SkeletonBox(width: 160, height: 12),
                  Spacer(),
                  Row(
                    children: [
                      SkeletonBox(width: 80, height: 24, borderRadius: 12),
                      Spacer(),
                      SkeletonBox(width: 90, height: 24, borderRadius: 12),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Skeleton loader precisely matching Grade Levels & Filières (Niveaux)
class GradeLevelsSkeletonLoader extends StatelessWidget {
  const GradeLevelsSkeletonLoader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF6F6F8),
      child: ShimmerLoading(
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 3 Stat Overview Cards
              Row(
                children: List.generate(3, (i) => Expanded(
                  child: Container(
                    margin: EdgeInsets.only(right: i < 2 ? 16 : 0),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Row(
                      children: [
                        SkeletonBox(width: 48, height: 48, borderRadius: 12),
                        const SizedBox(width: 14),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            SkeletonBox(width: 90, height: 12),
                            SizedBox(height: 8),
                            SkeletonBox(width: 50, height: 22),
                          ],
                        ),
                      ],
                    ),
                  ),
                )),
              ),
              const SizedBox(height: 28),

              // Cycle Header
              Row(
                children: const [
                  SkeletonBox(width: 4, height: 22, borderRadius: 2),
                  SizedBox(width: 10),
                  SkeletonBox(width: 140, height: 18),
                  Spacer(),
                  SkeletonBox(width: 80, height: 26, borderRadius: 8),
                ],
              ),
              const SizedBox(height: 16),

              // Grade Level Accordion Cards
              ...List.generate(3, (i) => Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        SkeletonBox(width: 36, height: 36, borderRadius: 8),
                        SizedBox(width: 14),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonBox(width: 160, height: 16),
                            SizedBox(height: 6),
                            SkeletonBox(width: 100, height: 12),
                          ],
                        ),
                        Spacer(),
                        SkeletonBox(width: 70, height: 24, borderRadius: 12),
                        SizedBox(width: 10),
                        SkeletonBox(width: 28, height: 28, borderRadius: 6),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(height: 1, color: Color(0xFFF1F5F9)),
                    const SizedBox(height: 14),
                    // Section Chips
                    Row(
                      children: const [
                        SkeletonBox(width: 70, height: 12),
                        SizedBox(width: 12),
                        SkeletonBox(width: 80, height: 24, borderRadius: 6),
                        SizedBox(width: 8),
                        SkeletonBox(width: 90, height: 24, borderRadius: 6),
                        SizedBox(width: 8),
                        SkeletonBox(width: 75, height: 24, borderRadius: 6),
                      ],
                    ),
                  ],
                ),
              )),
            ],
          ),
        ),
      ),
    );
  }
}

/// Minimalist Instagram-style Skeleton Loader for Semesters / Periods Page
class SemestersSkeletonLoader extends StatelessWidget {
  const SemestersSkeletonLoader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8FAFC),
      child: ShimmerLoading(
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Period Cards List
              ...List.generate(2, (index) => Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFF1F5F9)),
                ),
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header row
                    Row(
                      children: [
                        const SkeletonBox(width: 42, height: 42, borderRadius: 12),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  SkeletonBox(width: 140, height: 18, borderRadius: 5),
                                  SizedBox(width: 10),
                                  SkeletonBox(width: 60, height: 20, borderRadius: 6),
                                ],
                              ),
                              SizedBox(height: 6),
                              SkeletonBox(width: 170, height: 12, borderRadius: 4),
                            ],
                          ),
                        ),
                        const SkeletonBox(width: 32, height: 32, borderRadius: 8),
                        const SizedBox(width: 8),
                        const SkeletonBox(width: 32, height: 32, borderRadius: 8),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Duration pill
                    const SkeletonBox(width: 120, height: 24, borderRadius: 12),
                    const SizedBox(height: 20),

                    // Horizontal month timeline nodes
                    SizedBox(
                      height: 60,
                      child: Row(
                        children: List.generate(4, (i) => Expanded(
                          child: Row(
                            children: [
                              const Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SkeletonBox(width: 28, height: 9, borderRadius: 3),
                                  SizedBox(height: 6),
                                  SkeletonCircle(size: 30),
                                  SizedBox(height: 4),
                                  SkeletonBox(width: 30, height: 9, borderRadius: 3),
                                ],
                              ),
                              if (i < 3)
                                const Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 4),
                                    child: SkeletonBox(width: double.infinity, height: 2, borderRadius: 1),
                                  ),
                                ),
                            ],
                          ),
                        )),
                      ),
                    ),
                  ],
                ),
              )),
            ],
          ),
        ),
      ),
    );
  }
}

/// Minimalist Instagram-style Skeleton Loader for Subjects Management Screen (Matières)
class SubjectsSkeletonLoader extends StatelessWidget {
  const SubjectsSkeletonLoader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF6F7FB),
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Static Title Header (never skeleton loaded)
            Row(
              children: [
                Container(
                  width: 4,
                  height: 24,
                  decoration: BoxDecoration(
                    color: const Color(0xFF655DD5),
                    borderRadius: BorderRadius.circular(9999),
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Liste des Matières',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                ),
                const Spacer(),
                const ShimmerLoading(
                  child: SkeletonBox(width: 100, height: 32, borderRadius: 9999),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // 4-Column Grid of Subject Cards
            ShimmerLoading(
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  childAspectRatio: 0.85,
                  crossAxisSpacing: 20,
                  mainAxisSpacing: 20,
                ),
                itemCount: 8,
                itemBuilder: (context, index) {
                  return Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFECECF3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Top Code badge + Menu dots
                        const Row(
                          children: [
                            SkeletonBox(width: 42, height: 42, borderRadius: 12),
                            Spacer(),
                            SkeletonBox(width: 20, height: 20, borderRadius: 5),
                          ],
                        ),
                        const SizedBox(height: 14),
                        // Subject Name
                        SkeletonBox(width: 120 + (index % 3) * 15.0, height: 16, borderRadius: 5),
                        const SizedBox(height: 8),
                        // Coef chip + Category
                        const Row(
                          children: [
                            SkeletonBox(width: 48, height: 20, borderRadius: 10),
                            SizedBox(width: 8),
                            SkeletonBox(width: 60, height: 12, borderRadius: 4),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Divider(height: 1, color: Color(0xFFF1F5F9)),
                        const SizedBox(height: 12),
                        // NIVEAUX section
                        const Row(
                          children: [
                            SkeletonBox(width: 14, height: 14, borderRadius: 3),
                            SizedBox(width: 6),
                            SkeletonBox(width: 50, height: 10, borderRadius: 3),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Row(
                          children: [
                            SkeletonBox(width: 42, height: 20, borderRadius: 10),
                            SizedBox(width: 6),
                            SkeletonBox(width: 46, height: 20, borderRadius: 10),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // ENSEIGNANTS section
                        const Row(
                          children: [
                            SkeletonBox(width: 14, height: 14, borderRadius: 3),
                            SizedBox(width: 6),
                            SkeletonBox(width: 65, height: 10, borderRadius: 3),
                          ],
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 24,
                          child: Stack(
                            children: List.generate(3, (ti) => Positioned(
                              left: ti * 16.0,
                              child: Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 1.5),
                                ),
                                child: const SkeletonCircle(size: 24),
                              ),
                            )),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Skeleton loader precisely matching Weekly Timetable (Emploi du temps) Grid
class TimetablesSkeletonLoader extends StatelessWidget {
  const TimetablesSkeletonLoader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: ShimmerLoading(
        child: Column(
          children: [
            // Days Header Row
            Container(
              height: 48,
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Row(
                children: [
                  // Time col header
                  Container(
                    width: 70,
                    alignment: Alignment.center,
                    child: const SkeletonBox(width: 36, height: 12),
                  ),
                  // 6 Days
                  ...List.generate(6, (i) => Expanded(
                    child: Container(
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        border: Border(left: BorderSide(color: Color(0xFFE2E8F0))),
                      ),
                      child: const SkeletonBox(width: 60, height: 14),
                    ),
                  )),
                ],
              ),
            ),

            // Time Slots Grid
            Expanded(
              child: ListView.builder(
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 6,
                itemBuilder: (context, rowIndex) {
                  return Container(
                    height: 80,
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
                    ),
                    child: Row(
                      children: [
                        // Time label
                        Container(
                          width: 70,
                          alignment: Alignment.center,
                          child: const SkeletonBox(width: 44, height: 11),
                        ),
                        // 6 Day slots
                        ...List.generate(6, (dayIndex) {
                          final hasClass = (rowIndex + dayIndex) % 3 != 0;
                          return Expanded(
                            child: Container(
                              margin: const EdgeInsets.all(4),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: hasClass ? const Color(0xFFF8FAFC) : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                border: hasClass ? Border.all(color: const Color(0xFFE2E8F0)) : null,
                              ),
                              child: hasClass
                                  ? Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: const [
                                        SkeletonBox(width: 70, height: 12),
                                        SizedBox(height: 4),
                                        SkeletonBox(width: 50, height: 10),
                                      ],
                                    )
                                  : null,
                            ),
                          );
                        }),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DocumentsSkeletonLoader extends StatelessWidget {
  final int rowCount;
  const DocumentsSkeletonLoader({super.key, this.rowCount = 7});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8FAFC),
      child: ShimmerLoading(
        child: Column(
          children: [
            // 6 Category Tabs skeleton (Tous, Académiques, Administratif, Cours, Examens, Autre)
            Container(
              padding: const EdgeInsets.only(left: 24, top: 12, bottom: 12),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: Color(0xFFE9EAF2))),
              ),
              child: const Row(
                children: [
                  SkeletonBox(width: 72, height: 26, borderRadius: 6),
                  SizedBox(width: 24),
                  SkeletonBox(width: 112, height: 26, borderRadius: 6),
                  SizedBox(width: 24),
                  SkeletonBox(width: 112, height: 26, borderRadius: 6),
                  SizedBox(width: 24),
                  SkeletonBox(width: 76, height: 26, borderRadius: 6),
                  SizedBox(width: 24),
                  SkeletonBox(width: 92, height: 26, borderRadius: 6),
                  SizedBox(width: 24),
                  SkeletonBox(width: 74, height: 26, borderRadius: 6),
                ],
              ),
            ),

            // Semester segmented pills bar skeleton (exact Users page pills bar shape)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: Color(0xFFE9EAF2))),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Row(
                      children: [
                        SkeletonBox(width: 68, height: 28, borderRadius: 20, color: Colors.white),
                        SizedBox(width: 6),
                        SkeletonBox(width: 96, height: 28, borderRadius: 20),
                        SizedBox(width: 6),
                        SkeletonBox(width: 96, height: 28, borderRadius: 20),
                        SizedBox(width: 6),
                        SkeletonBox(width: 96, height: 28, borderRadius: 20),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Table skeleton
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Column(
                      children: [
                        // Table header
                        Container(
                          height: 44,
                          color: const Color(0xFFF9FAFB),
                          padding: const EdgeInsets.fromLTRB(14, 0, 20, 0),
                          child: const Row(
                            children: [
                              SkeletonBox(width: 16, height: 16, borderRadius: 3),
                              SizedBox(width: 14),
                              SkeletonBox(width: 140, height: 12),
                              Spacer(),
                              SkeletonBox(width: 70, height: 12),
                              SizedBox(width: 32),
                              SkeletonBox(width: 90, height: 12),
                              SizedBox(width: 32),
                              SkeletonBox(width: 80, height: 12),
                              SizedBox(width: 32),
                              SkeletonBox(width: 30, height: 12),
                            ],
                          ),
                        ),
                        const Divider(height: 1, color: Color(0xFFE2E8F0)),

                        // Table rows
                        Expanded(
                          child: ListView.separated(
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: rowCount,
                            separatorBuilder: (context, index) =>
                                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                            itemBuilder: (context, index) {
                              return Container(
                                height: 60,
                                padding: const EdgeInsets.fromLTRB(14, 0, 20, 0),
                                child: const Row(
                                  children: [
                                    SkeletonBox(width: 16, height: 16, borderRadius: 3),
                                    SizedBox(width: 14),
                                    SkeletonBox(width: 36, height: 36, borderRadius: 8),
                                    SizedBox(width: 12),
                                    Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        SkeletonBox(width: 160, height: 13),
                                        SizedBox(height: 6),
                                        SkeletonBox(width: 110, height: 10),
                                      ],
                                    ),
                                    Spacer(),
                                    SkeletonBox(width: 68, height: 22, borderRadius: 6),
                                    SizedBox(width: 32),
                                    SkeletonBox(width: 84, height: 22, borderRadius: 6),
                                    SizedBox(width: 32),
                                    SkeletonBox(width: 80, height: 13),
                                    SizedBox(width: 32),
                                    SkeletonBox(width: 24, height: 24, borderRadius: 6),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),

                        // Pagination footer skeleton (Users page style)
                        Container(
                          height: 50,
                          color: const Color(0xFFFAFAFB),
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: const Row(
                            children: [
                              SkeletonBox(width: 115, height: 24, borderRadius: 8),
                              Spacer(),
                              SkeletonBox(width: 80, height: 12),
                              SizedBox(width: 12),
                              SkeletonBox(width: 58, height: 28, borderRadius: 6),
                            ],
                          ),
                        ),
                      ],
                    ),
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

/// Minimalist Instagram-style Skeleton Loader for Password Reset Requests Screen
class PasswordResetsSkeletonLoader extends StatelessWidget {
  final int rowCount;
  const PasswordResetsSkeletonLoader({super.key, this.rowCount = 7});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8FAFC),
      child: ShimmerLoading(
        child: Column(
          children: [
            // Subtabs skeleton (matching DocumentsSkeletonLoader)
            Container(
              padding: const EdgeInsets.only(left: 24, top: 12, bottom: 12),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: Color(0xFFE9EAF2))),
              ),
              child: const Row(
                children: [
                  SkeletonBox(width: 106, height: 26, borderRadius: 6),
                  SizedBox(width: 24),
                  SkeletonBox(width: 112, height: 26, borderRadius: 6),
                  SizedBox(width: 24),
                  SkeletonBox(width: 96, height: 26, borderRadius: 6),
                  SizedBox(width: 24),
                  SkeletonBox(width: 82, height: 26, borderRadius: 6),
                ],
              ),
            ),

            // Table Card Skeleton
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Column(
                      children: [
                        // Header row skeleton
                        Container(
                          height: 44,
                          color: const Color(0xFFF9FAFB),
                          padding: const EdgeInsets.fromLTRB(14, 0, 20, 0),
                          child: const Row(
                            children: [
                              SkeletonBox(width: 16, height: 16, borderRadius: 3),
                              SizedBox(width: 14),
                              SkeletonBox(width: 120, height: 12),
                              Spacer(flex: 3),
                              SkeletonBox(width: 110, height: 12),
                              Spacer(flex: 2),
                              SkeletonBox(width: 90, height: 12),
                              Spacer(flex: 2),
                              SkeletonBox(width: 70, height: 12),
                              Spacer(),
                              SkeletonBox(width: 30, height: 12),
                            ],
                          ),
                        ),
                        const Divider(height: 1, color: Color(0xFFE2E8F0)),

                        // Table rows
                        Expanded(
                          child: ListView.separated(
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: rowCount,
                            separatorBuilder: (context, index) =>
                                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                            itemBuilder: (context, index) {
                              return Container(
                                height: 64,
                                padding: const EdgeInsets.fromLTRB(14, 0, 20, 0),
                                child: const Row(
                                  children: [
                                    SkeletonBox(width: 16, height: 16, borderRadius: 3),
                                    SizedBox(width: 14),
                                    SkeletonCircle(size: 36),
                                    SizedBox(width: 12),
                                    Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        SkeletonBox(width: 150, height: 13),
                                        SizedBox(height: 6),
                                        SkeletonBox(width: 180, height: 10),
                                      ],
                                    ),
                                    Spacer(flex: 3),
                                    SkeletonBox(width: 100, height: 12),
                                    Spacer(flex: 2),
                                    SkeletonBox(width: 80, height: 12),
                                    Spacer(flex: 2),
                                    SkeletonBox(width: 76, height: 22, borderRadius: 6),
                                    Spacer(),
                                    SkeletonBox(width: 24, height: 24, borderRadius: 6),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),

                        // Pagination footer skeleton (Documents page style)
                        Container(
                          height: 50,
                          color: const Color(0xFFFAFAFB),
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: const Row(
                            children: [
                              SkeletonBox(width: 115, height: 24, borderRadius: 8),
                              Spacer(),
                              SkeletonBox(width: 80, height: 12),
                              SizedBox(width: 12),
                              SkeletonBox(width: 58, height: 28, borderRadius: 6),
                            ],
                          ),
                        ),
                      ],
                    ),
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

/// Minimalist Instagram-style Skeleton Loader for Settings Screen
class SettingsSkeletonLoader extends StatelessWidget {
  const SettingsSkeletonLoader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8FAFC),
      child: ShimmerLoading(
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(32, 20, 32, 36),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1060),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Section 1: Profil Administrateur Hero Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SkeletonBox(width: 170, height: 16),
                        const SizedBox(height: 6),
                        const SkeletonBox(width: 260, height: 12),
                        const SizedBox(height: 16),
                        const Divider(height: 1, color: Color(0xFFF1F5F9)),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            const SkeletonCircle(size: 56),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: const [
                                  SkeletonBox(width: 160, height: 16),
                                  SizedBox(height: 6),
                                  SkeletonBox(width: 200, height: 13),
                                ],
                              ),
                            ),
                            const SkeletonBox(width: 130, height: 38, borderRadius: 10),
                            const SizedBox(width: 10),
                            const SkeletonBox(width: 120, height: 38, borderRadius: 10),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Section 2: Établissement Card
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                          child: Row(
                            children: const [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SkeletonBox(width: 180, height: 15),
                                    SizedBox(height: 6),
                                    SkeletonBox(width: 250, height: 12),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1, color: Color(0xFFF1F5F9)),
                        _buildSkeletonTile(),
                        const Divider(height: 1, color: Color(0xFFF1F5F9)),
                        _buildSkeletonTile(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Section 3: Sécurité Card with Switches
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                          child: Row(
                            children: const [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SkeletonBox(width: 150, height: 15),
                                    SizedBox(height: 6),
                                    SkeletonBox(width: 280, height: 12),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1, color: Color(0xFFF1F5F9)),
                        _buildSkeletonSwitchTile(),
                        const Divider(height: 1, color: Color(0xFFF1F5F9)),
                        _buildSkeletonSwitchTile(),
                        const Divider(height: 1, color: Color(0xFFF1F5F9)),
                        _buildSkeletonSwitchTile(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Widget _buildSkeletonTile() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: const [
          SkeletonBox(width: 36, height: 36, borderRadius: 10),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 180, height: 14),
                SizedBox(height: 6),
                SkeletonBox(width: 260, height: 12),
              ],
            ),
          ),
          SkeletonBox(width: 18, height: 18, borderRadius: 4),
        ],
      ),
    );
  }

  static Widget _buildSkeletonSwitchTile() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: const [
          SkeletonBox(width: 36, height: 36, borderRadius: 10),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 190, height: 14),
                SizedBox(height: 6),
                SkeletonBox(width: 300, height: 12),
              ],
            ),
          ),
          SkeletonBox(width: 38, height: 22, borderRadius: 11),
        ],
      ),
    );
  }
}

/// Minimalist Instagram-style Skeleton Loader for School Info Subpage
class SchoolInfoSkeletonLoader extends StatelessWidget {
  const SchoolInfoSkeletonLoader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8FAFC),
      child: ShimmerLoading(
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Section 1: Identité
              _buildSkeletonCard(
                titleWidth: 190,
                child: Column(
                  children: const [
                    SkeletonBox(width: double.infinity, height: 48, borderRadius: 10),
                    SizedBox(height: 20),
                    SkeletonBox(width: double.infinity, height: 110, borderRadius: 10),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Section 2: Logo
              _buildSkeletonCard(
                titleWidth: 140,
                child: Row(
                  children: const [
                    SkeletonBox(width: 80, height: 80, borderRadius: 16),
                    SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBox(width: 180, height: 14),
                          SizedBox(height: 8),
                          SkeletonBox(width: 220, height: 12),
                          SizedBox(height: 12),
                          SkeletonBox(width: 150, height: 36, borderRadius: 10),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Section 3: Année scolaire
              _buildSkeletonCard(
                titleWidth: 210,
                child: Column(
                  children: const [
                    SkeletonBox(width: double.infinity, height: 48, borderRadius: 10),
                    SizedBox(height: 20),
                    SkeletonBox(width: double.infinity, height: 70, borderRadius: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildSkeletonCard({required double titleWidth, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Color(0x08060E1F), blurRadius: 20, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: titleWidth, height: 16, borderRadius: 6),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}

/// Minimalist Instagram-style Skeleton Loader for Contact Info Subpage
class ContactInfoSkeletonLoader extends StatelessWidget {
  const ContactInfoSkeletonLoader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8FAFC),
      child: ShimmerLoading(
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Section 1: Contact
              _buildSkeletonCard(
                titleWidth: 180,
                child: Row(
                  children: const [
                    Expanded(child: SkeletonBox(height: 48, borderRadius: 10)),
                    SizedBox(width: 20),
                    Expanded(child: SkeletonBox(height: 48, borderRadius: 10)),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Section 2: Horaires
              _buildSkeletonCard(
                titleWidth: 220,
                child: Column(
                  children: [
                    const SkeletonBox(width: double.infinity, height: 48, borderRadius: 10),
                    const SizedBox(height: 16),
                    ...List.generate(6, (i) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: const [
                          SkeletonBox(width: 50, height: 28, borderRadius: 8),
                          SizedBox(width: 14),
                          SkeletonBox(width: 90, height: 14),
                          SizedBox(width: 16),
                          SkeletonBox(width: 38, height: 22, borderRadius: 11),
                          Spacer(),
                          SkeletonBox(width: 90, height: 36, borderRadius: 10),
                          SizedBox(width: 12),
                          SkeletonBox(width: 90, height: 36, borderRadius: 10),
                        ],
                      ),
                    )),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Section 3: Réseaux Sociaux
              _buildSkeletonCard(
                titleWidth: 200,
                child: Column(
                  children: const [
                    SkeletonBox(width: double.infinity, height: 48, borderRadius: 10),
                    SizedBox(height: 14),
                    SkeletonBox(width: double.infinity, height: 48, borderRadius: 10),
                    SizedBox(height: 14),
                    SkeletonBox(width: double.infinity, height: 48, borderRadius: 10),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildSkeletonCard({required double titleWidth, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Color(0x08060E1F), blurRadius: 20, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: titleWidth, height: 16, borderRadius: 6),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}

/// Minimalist Instagram/Aurora-style Skeleton Loader for Dashboard Screen
class DashboardSkeletonLoader extends StatelessWidget {
  const DashboardSkeletonLoader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8FAFC),
      child: ShimmerLoading(
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 5 KPI Metric Cards
              Row(
                children: List.generate(5, (index) => Expanded(
                  child: Container(
                    margin: EdgeInsets.only(right: index < 4 ? 14 : 0),
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFF1F5F9)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Row(
                          children: [
                            SkeletonBox(width: 40, height: 40, borderRadius: 12),
                            Spacer(),
                            SkeletonBox(width: 50, height: 20, borderRadius: 10),
                          ],
                        ),
                        SizedBox(height: 16),
                        SkeletonBox(width: 90, height: 12, borderRadius: 4),
                        SizedBox(height: 8),
                        SkeletonBox(width: 110, height: 24, borderRadius: 6),
                        SizedBox(height: 10),
                        SkeletonBox(width: 100, height: 11, borderRadius: 4),
                      ],
                    ),
                  ),
                )),
              ),
              const SizedBox(height: 24),

              // Row 2: Cashflow (65%) & Category (35%)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 65,
                    child: Container(
                      height: 340,
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFF1F5F9)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Row(
                            children: [
                              SkeletonBox(width: 120, height: 18, borderRadius: 4),
                              SizedBox(width: 16),
                              SkeletonBox(width: 140, height: 14, borderRadius: 4),
                              Spacer(),
                              SkeletonBox(width: 110, height: 32, borderRadius: 8),
                            ],
                          ),
                          SizedBox(height: 24),
                          Expanded(
                            child: SkeletonBox(width: double.infinity, height: double.infinity, borderRadius: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    flex: 35,
                    child: Container(
                      height: 340,
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFF1F5F9)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Row(
                            children: [
                              SkeletonBox(width: 160, height: 18, borderRadius: 4),
                              Spacer(),
                              SkeletonBox(width: 20, height: 20, borderRadius: 4),
                            ],
                          ),
                          SizedBox(height: 20),
                          SkeletonBox(width: 140, height: 28, borderRadius: 6),
                          SizedBox(height: 8),
                          SkeletonBox(width: 100, height: 14, borderRadius: 4),
                          SizedBox(height: 20),
                          SkeletonBox(width: double.infinity, height: 14, borderRadius: 7),
                          Spacer(),
                          SkeletonBox(width: double.infinity, height: 24, borderRadius: 6),
                          SizedBox(height: 12),
                          SkeletonBox(width: double.infinity, height: 24, borderRadius: 6),
                          SizedBox(height: 12),
                          SkeletonBox(width: double.infinity, height: 24, borderRadius: 6),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Row 3: 3 Cards (Donut, Calendar, Attendance)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Container(
                      height: 300,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFF1F5F9)),
                      ),
                      child: Column(
                        children: const [
                          Row(
                            children: [
                              SkeletonBox(width: 130, height: 16, borderRadius: 4),
                              Spacer(),
                              SkeletonBox(width: 18, height: 18, borderRadius: 4),
                            ],
                          ),
                          SizedBox(height: 20),
                          SkeletonBox(width: 130, height: 130, borderRadius: 65),
                          Spacer(),
                          Row(
                            children: [
                              Expanded(child: SkeletonBox(height: 28, borderRadius: 6)),
                              SizedBox(width: 8),
                              Expanded(child: SkeletonBox(height: 28, borderRadius: 6)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 4,
                    child: Container(
                      height: 300,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFF1F5F9)),
                      ),
                      child: Column(
                        children: const [
                          Row(
                            children: [
                              SkeletonBox(width: 140, height: 16, borderRadius: 4),
                              Spacer(),
                              SkeletonBox(width: 18, height: 18, borderRadius: 4),
                            ],
                          ),
                          SizedBox(height: 14),
                          SkeletonBox(width: double.infinity, height: 32, borderRadius: 8),
                          SizedBox(height: 14),
                          SkeletonBox(width: double.infinity, height: 70, borderRadius: 10),
                          SizedBox(height: 10),
                          SkeletonBox(width: double.infinity, height: 70, borderRadius: 10),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 3,
                    child: Container(
                      height: 300,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFF1F5F9)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              SkeletonBox(width: 140, height: 16, borderRadius: 4),
                              Spacer(),
                              SkeletonBox(width: 18, height: 18, borderRadius: 4),
                            ],
                          ),
                          const SizedBox(height: 20),
                          ...List.generate(4, (i) => Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Row(
                                  children: [
                                    SkeletonBox(width: 110, height: 12, borderRadius: 3),
                                    Spacer(),
                                    SkeletonBox(width: 32, height: 12, borderRadius: 3),
                                  ],
                                ),
                                SizedBox(height: 6),
                                SkeletonBox(width: double.infinity, height: 7, borderRadius: 4),
                              ],
                            ),
                          )),
                        ],
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
}



