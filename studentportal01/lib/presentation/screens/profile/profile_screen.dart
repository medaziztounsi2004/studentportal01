import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../core/config/supabase_config.dart';
import '../../../core/services/camera_photo_service.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../data/models/user_model.dart';
import '../../../data/models/enrollment_model.dart';
import '../../../data/services/core_data_service.dart';
import '../../providers/avatar_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/school_provider.dart';
import '../../providers/student_context_provider.dart';
import '../../../core/theme/arabic_typography.dart';
import '../../../core/theme/responsive.dart';
import '../../widgets/ios_loader.dart';
import '../../widgets/profile_skeleton.dart';
import '../../widgets/ios_bounce_zoom_transition.dart';
import '../../widgets/bouncing_wrapper.dart';
import '../../widgets/ios_edge_swipe_back.dart';
import '../../widgets/photo_cutout_screen.dart';
import '../../providers/nav_bar_provider.dart';

const Color _navPink = Color(0xFFFF2D78);

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _isUploadingPhoto = false;

  Future<void> _pickAndUploadPhoto(ImageSource source) async {
    if (_isUploadingPhoto) return;

    final image = await CameraPhotoService.pickPhoto(
      context: context,
      source: source,
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 88,
    );

    if (image == null) return;

    final rawBytes = await image.readAsBytes();
    if (!mounted) return;

    // Launch interactive photo cutout and alignment screen
    final croppedBytes = await PhotoCutoutScreen.show(
      context: context,
      rawImageBytes: rawBytes,
      initialShape: 'avatar',
    );
    if (croppedBytes == null) return; // Student cancelled

    setState(() => _isUploadingPhoto = true);

    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('user_not_connected');

      final fileName = '${userId}_${DateTime.now().millisecondsSinceEpoch}.png';
      final storagePath = 'avatars/$fileName';

      // Upload cropped square PNG to Supabase Storage
      await supabase.storage
          .from(SupabaseConfig.profileBucket)
          .uploadBinary(
            storagePath,
            croppedBytes,
            fileOptions:
                const FileOptions(contentType: 'image/png', upsert: true),
          );

      final publicUrl = supabase.storage
          .from(SupabaseConfig.profileBucket)
          .getPublicUrl(storagePath);

      // Update users table in Supabase
      await supabase
          .from('users')
          .update({
            'photo_url': publicUrl,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', userId);

      // Update local avatar state
      ref.read(avatarProvider.notifier).selectCustom(image.path);

      // Refresh auth provider state and in-memory photo url
      await ref.read(authProvider.notifier).updateProfilePhoto(publicUrl);
      await ref.read(authProvider.notifier).refreshUserData();

      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(child: Text(l10n.translate('photo_updated_success'))),
              ],
            ),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(child: Text(l10n.translate('photo_upload_error'))),
              ],
            ),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingPhoto = false);
      }
    }
  }

  void _showFloatingPhotoPicker() {
    showGeneralDialog(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black.withValues(alpha: 0.35),
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (ctx, animation, secondaryAnimation) {
        return Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Material(
                color: Colors.transparent,
                child: _FloatingPhotoPickerCard(
                  onPickCamera: () {
                    Navigator.of(ctx).pop();
                    _pickAndUploadPhoto(ImageSource.camera);
                  },
                  onPickGallery: () {
                    Navigator.of(ctx).pop();
                    _pickAndUploadPhoto(ImageSource.gallery);
                  },
                  onClose: () => Navigator.of(ctx).pop(),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return buildIosBounceZoomTransition(
          context: context,
          animation: animation,
          child: child,
          backdropSigma: 12.0,
          maxFlightBlur: 14.0,
        );
      },
    );
  }

  Future<void> _handleLogout() async {
    final l10n = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          l10n.logout,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        content: Text(l10n.logoutConfirmMsg),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel, style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(l10n.logout, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ref.read(authProvider.notifier).signOut();
      if (mounted) {
        context.go('/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final authState = ref.watch(authProvider);
    final user = authState.user;
    final enrollment = authState.enrollment;
    final studentContext = ref.watch(studentContextProvider).valueOrNull;
    final schoolAsync = ref.watch(schoolProvider);
    final school = schoolAsync.valueOrNull;

    if (authState.isLoading) {
      return const ProfileSkeleton();
    }

    if (user == null && !authState.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(authProvider.notifier).refreshUserData();
      });
    }

    final now = DateTime.now();
    final effectiveUser = user ??
        UserModel(
          id: '',
          role: 'student',
          fullName: 'Étudiant',
          email: '',
          createdAt: now,
          updatedAt: now,
          accountStatus: 'active',
          isActive: true,
        );

    return _GradientBackground(
      child: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            await ref.read(authProvider.notifier).refreshUserData();
          },
          color: _navPink,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              padding: EdgeInsets.fromLTRB(context.horizontalPadding, 16, context.horizontalPadding, 24 + MediaQuery.of(context).padding.bottom),
              children: [
              _buildHeader(l10n),
              const SizedBox(height: 20),
              // Hero Profile Card
              _ProfileHeroCard(
                user: effectiveUser,
                enrollment: enrollment,
                isUploading: _isUploadingPhoto,
                onEditPhoto: _showFloatingPhotoPicker,
              ),
              const SizedBox(height: 20),

              // Section 1: Informations Personnelles (Unified Card with title at top-left inside)
              _UnifiedSectionCard(
                title: l10n.personalInfo,
                items: [
                  _InfoItem(
                    icon: Icons.person_outline_rounded,
                    label: l10n.fullName,
                    value: effectiveUser.fullName,
                    color: const Color(0xFF3B82F6),
                  ),
                  _InfoItem(
                    icon: Icons.badge_outlined,
                    label: l10n.studentCode,
                    value: effectiveUser.studentCode ?? 'Non défini',
                    color: const Color(0xFF6366F1),
                    trailing: effectiveUser.studentCode != null
                        ? GestureDetector(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: effectiveUser.studentCode!));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(l10n.studentCodeCopied),
                                  duration: const Duration(seconds: 1),
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.copy_rounded, size: 16, color: Color(0xFF6366F1)),
                            ),
                          )
                        : null,
                  ),
                  _InfoItem(
                    icon: Icons.email_outlined,
                    label: l10n.email,
                    value: effectiveUser.email.isNotEmpty ? effectiveUser.email : '-',
                    color: const Color(0xFF10B981),
                    onTap: effectiveUser.email.isNotEmpty
                        ? () {
                            Clipboard.setData(ClipboardData(text: effectiveUser.email));
                            HapticFeedback.lightImpact();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(l10n.emailCopied),
                                duration: const Duration(seconds: 1),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            );
                          }
                        : null,
                    trailing: effectiveUser.email.isNotEmpty
                        ? GestureDetector(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: effectiveUser.email));
                              HapticFeedback.lightImpact();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(l10n.emailCopied),
                                  duration: const Duration(seconds: 1),
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.copy_rounded, size: 16, color: Color(0xFF10B981)),
                            ),
                          )
                        : null,
                  ),
                  if (effectiveUser.phone != null && effectiveUser.phone!.isNotEmpty)
                    _InfoItem(
                      icon: Icons.phone_outlined,
                      label: l10n.phone,
                      value: '\u200E${effectiveUser.phone!}',
                      color: const Color(0xFFF59E0B),
                    ),
                  if (effectiveUser.dateOfBirth != null)
                    _InfoItem(
                      icon: Icons.cake_outlined,
                      label: l10n.dateOfBirth,
                      value: '\u200E${DateFormat('dd/MM/yyyy').format(effectiveUser.dateOfBirth!)}',
                      color: const Color(0xFFEC4899),
                    ),
                  if (effectiveUser.address != null && effectiveUser.address!.isNotEmpty)
                    _InfoItem(
                      icon: Icons.location_on_outlined,
                      label: l10n.address,
                      value: effectiveUser.address!,
                      color: const Color(0xFF8B5CF6),
                    ),
                ],
              ),
              const SizedBox(height: 20),

              // Section 2: Informations Académiques (Unified Card with title at top-left inside)
              _UnifiedSectionCard(
                title: l10n.academicInfo,
                items: [
                  _InfoItem(
                    icon: Icons.account_balance_outlined,
                    label: l10n.etablissement,
                    value: school?.name ?? 'Lycée Pythagore',
                    color: const Color(0xFF3B82F6),
                  ),
                  _InfoItem(
                    icon: Icons.layers_outlined,
                    label: l10n.niveau,
                    value: '\u200E${_resolveLevel(context, studentContext, effectiveUser, enrollment)}',
                    color: const Color(0xFF8B5CF6),
                  ),
                  _InfoItem(
                    icon: Icons.school_outlined,
                    label: l10n.filiere,
                    value: '\u200E${_resolveField(context, studentContext, effectiveUser, enrollment)}',
                    color: const Color(0xFFEC4899),
                  ),
                  _InfoItem(
                    icon: Icons.class_outlined,
                    label: l10n.currentClass,
                    value: '\u200E${enrollment?.classInfo?.name ?? studentContext?.className ?? '-'}',
                    color: const Color(0xFF10B981),
                  ),
                  if (enrollment?.groupInfo != null)
                    _InfoItem(
                      icon: Icons.group_outlined,
                      label: l10n.group,
                      value: enrollment!.groupInfo!.name,
                      color: const Color(0xFFF59E0B),
                    ),
                  _InfoItem(
                    icon: Icons.verified_outlined,
                    label: l10n.enrollmentStatus,
                    value: l10n.enrolledAndActive,
                    color: const Color(0xFF10B981),
                  ),
                ],
              ),
              const SizedBox(height: 28),

              // Déconnexion Button at Bottom of Profile Page
              BouncingWrapper(
                shrinkScale: 0.92,
                onTap: _handleLogout,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 18,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.logout_rounded,
                        color: Color(0xFFEF4444),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        l10n.logout,
                        style: ArabicTypography.buttonStyle(
                          context,
                          color: const Color(0xFFEF4444),
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
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
    ),
  ),
);
  }

  String _resolveLevel(
    BuildContext context,
    StudentContext? studentContext,
    UserModel? user,
    EnrollmentModel? enrollment,
  ) {
    if (studentContext?.niveauName != null && studentContext!.niveauName!.isNotEmpty) {
      return studentContext.niveauName!;
    }
    if (studentContext?.niveauCode != null && studentContext!.niveauCode!.isNotEmpty) {
      return studentContext.niveauCode!;
    }
    if (user?.niveau != null && user!.niveau!.isNotEmpty) {
      return user.niveau!;
    }
    if (user?.niveauCode != null && user!.niveauCode!.isNotEmpty) {
      return user.niveauCode!;
    }
    if (enrollment?.classInfo?.level != null && enrollment!.classInfo!.level!.isNotEmpty) {
      return enrollment.classInfo!.level!;
    }
    if (enrollment?.classInfo?.niveauName != null && enrollment!.classInfo!.niveauName!.isNotEmpty) {
      return enrollment.classInfo!.niveauName!;
    }
    if (enrollment?.classInfo?.niveauCode != null && enrollment!.classInfo!.niveauCode!.isNotEmpty) {
      return enrollment.classInfo!.niveauCode!;
    }

    final className = enrollment?.classInfo?.name ?? studentContext?.className ?? '';
    return _deduceLevelFromClassName(className, context);
  }

  String _deduceLevelFromClassName(String className, BuildContext context) {
    final lang = Localizations.localeOf(context).languageCode;
    final upper = className.toUpperCase().trim();

    if (upper.startsWith('9B') || upper.startsWith('9 B') || upper.contains('9ÈME') || upper.contains('9EME')) {
      if (lang == 'ar') return 'السنة التاسعة أساسي';
      if (lang == 'en') return '9th Grade Basic';
      return '9ème Année de Base';
    }
    if (upper.startsWith('8B') || upper.startsWith('8 B') || upper.contains('8ÈME') || upper.contains('8EME')) {
      if (lang == 'ar') return 'السنة الثامنة أساسي';
      if (lang == 'en') return '8th Grade Basic';
      return '8ème Année de Base';
    }
    if (upper.startsWith('7B') || upper.startsWith('7 B') || upper.contains('7ÈME') || upper.contains('7EME')) {
      if (lang == 'ar') return 'السنة السابعة أساسي';
      if (lang == 'en') return '7th Grade Basic';
      return '7ème Année de Base';
    }
    if (upper.startsWith('1S') || upper.startsWith('1 S') || upper.contains('1ÈRE') || upper.contains('1ERE')) {
      if (lang == 'ar') return 'السنة الأولى ثانوي';
      if (lang == 'en') return '1st Year Secondary';
      return '1ère Année Secondaire';
    }
    if (upper.startsWith('2S') || upper.startsWith('2 S')) {
      if (lang == 'ar') return 'السنة الثانية ثانوي';
      if (lang == 'en') return '2nd Year Secondary';
      return '2ème Année Secondaire';
    }
    if (upper.startsWith('3S') || upper.startsWith('3 S') || upper.startsWith('3M') || upper.startsWith('3SC') || upper.startsWith('3TECH') || upper.startsWith('3ECO') || upper.startsWith('3INF') || upper.startsWith('3LET')) {
      if (lang == 'ar') return 'السنة الثالثة ثانوي';
      if (lang == 'en') return '3rd Year Secondary';
      return '3ème Année Secondaire';
    }
    if (upper.startsWith('4S') || upper.startsWith('4 S') || upper.startsWith('4M') || upper.startsWith('4SC') || upper.startsWith('4TECH') || upper.startsWith('4ECO') || upper.startsWith('4INF') || upper.startsWith('4LET') || upper.contains('BAC')) {
      if (lang == 'ar') return 'السنة الرابعة ثانوي (باكالوريا)';
      if (lang == 'en') return '4th Year Secondary (Bac)';
      return '4ème Année Secondaire (Bac)';
    }

    if (className.isNotEmpty) return className;
    return '9ème Année de Base';
  }

  String _resolveField(
    BuildContext context,
    StudentContext? studentContext,
    UserModel? user,
    EnrollmentModel? enrollment,
  ) {
    if (studentContext?.sectionName != null && studentContext!.sectionName!.isNotEmpty) {
      return studentContext.sectionName!;
    }
    if (studentContext?.sectionCode != null && studentContext!.sectionCode!.isNotEmpty) {
      return studentContext.sectionCode!;
    }
    if (user?.sectionCode != null && user!.sectionCode!.isNotEmpty) {
      return user.sectionCode!;
    }
    if (enrollment?.classInfo?.section != null && enrollment!.classInfo!.section!.isNotEmpty) {
      return enrollment.classInfo!.section!;
    }
    if (enrollment?.classInfo?.sectionName != null && enrollment!.classInfo!.sectionName!.isNotEmpty) {
      return enrollment.classInfo!.sectionName!;
    }
    if (enrollment?.classInfo?.sectionCode != null && enrollment!.classInfo!.sectionCode!.isNotEmpty) {
      return enrollment.classInfo!.sectionCode!;
    }

    final className = enrollment?.classInfo?.name ?? studentContext?.className ?? '';
    return _deduceFieldFromClassName(className, studentContext?.cycle, context);
  }

  String _deduceFieldFromClassName(String className, String? cycle, BuildContext context) {
    final lang = Localizations.localeOf(context).languageCode;
    final upper = className.toUpperCase().trim();

    if (cycle == 'base' || upper.contains('9B') || upper.contains('8B') || upper.contains('7B') || upper.contains('BASE')) {
      if (lang == 'ar') return 'التعليم الأساسي';
      if (lang == 'en') return 'Basic Education';
      return 'Enseignement de Base';
    }

    if (upper.startsWith('1S') || upper.contains('TRONC')) {
      if (lang == 'ar') return 'جذع مشترك';
      if (lang == 'en') return 'Common Core';
      return 'Tronc Commun';
    }

    if (upper.contains('SC') || upper.contains('EXP')) {
      if (lang == 'ar') return 'علوم تجريبية';
      if (lang == 'en') return 'Experimental Sciences';
      return 'Sciences Expérimentales';
    }

    if (upper.contains('MATH') || upper.contains('3M') || upper.contains('4M')) {
      if (lang == 'ar') return 'رياضيات';
      if (lang == 'en') return 'Mathematics';
      return 'Mathématiques';
    }

    if (upper.contains('TECH')) {
      if (lang == 'ar') return 'علوم تقنية';
      if (lang == 'en') return 'Technical Sciences';
      return 'Sciences Techniques';
    }

    if (upper.contains('ECO') || upper.contains('GEST')) {
      if (lang == 'ar') return 'اقتصاد وتصرف';
      if (lang == 'en') return 'Economics & Management';
      return 'Économie et Gestion';
    }

    if (upper.contains('INF') || upper.contains('TI')) {
      if (lang == 'ar') return 'علوم الإعلامية';
      if (lang == 'en') return 'Computer Science';
      return 'Sciences de l\'Informatique';
    }

    if (upper.contains('LET') || upper.contains('LIT')) {
      if (lang == 'ar') return 'آداب';
      if (lang == 'en') return 'Literature';
      return 'Lettres';
    }

    if (lang == 'ar') return 'التعليم الأساسي';
    if (lang == 'en') return 'Basic Education';
    return 'Enseignement de Base';
  }

  Widget _buildHeader(AppLocalizations l10n) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    return Row(
      children: [
        BouncingWrapper(
          shrinkScale: 0.86,
          overshootScale: 1.10,
          delayNavigation: false,
          hitPadding: const EdgeInsets.symmetric(vertical: 8),
          onTap: () {
            final swipeBack = IosEdgeSwipeBack.of(context);
            if (swipeBack != null) {
              swipeBack.animateBack();
            } else {
              final fromAIChat = ref.read(navigatedFromAIChatProvider);
              if (fromAIChat) {
                ref.read(navigatedFromAIChatProvider.notifier).state = false;
                context.go('/ai-chat');
              } else {
                ref.read(sideDrawerOpenProvider.notifier).state = true;
                                context.go('/');
              }
            }
          },
          child: Container(
            width: context.scaleW(44).clamp(38.0, 48.0),
            height: context.scaleW(44).clamp(38.0, 48.0),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Center(
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Icon(
                  isRtl ? Icons.arrow_forward_ios_rounded : Icons.arrow_back_ios_new_rounded,
                  size: context.scaleW(18).clamp(16.0, 20.0),
                  color: const Color(0xFF1F2937),
                ),
              ),
            ),
          ),
        ),
        SizedBox(width: context.scaleW(14).clamp(10.0, 16.0)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  l10n.monProfil,
                  style: ArabicTypography.headerStyle(
                    context,
                    fontSize: context.sp(24),
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF1F2937),
                    letterSpacing: -0.6,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                l10n.profilSubtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ArabicTypography.subtitleStyle(
                  context,
                  fontSize: context.sp(13.5),
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GradientBackground extends StatelessWidget {
  final Widget child;
  const _GradientBackground({required this.child});

  @override
  Widget build(BuildContext context) {
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
      child: child,
    );
  }
}

// Hero Profile Card - Clean, no bottom glow shadow under avatar, pink camera badge, no "Étudiant" pill
class _ProfileHeroCard extends ConsumerWidget {
  final UserModel user;
  final dynamic enrollment;
  final bool isUploading;
  final VoidCallback onEditPhoto;

  const _ProfileHeroCard({
    required this.user,
    required this.enrollment,
    required this.isUploading,
    required this.onEditPhoto,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final avatarState = ref.watch(avatarProvider);
    final initials = user.fullName
        .split(' ')
        .take(2)
        .map((e) => e.isNotEmpty ? e[0].toUpperCase() : '')
        .join();

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppResponsive.cardPadding(context, base: 20.0),
        vertical: 24,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Avatar with clean border and PINK camera badge
          GestureDetector(
            onTap: onEditPhoto,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Clean Photo Container (No outer glowing blur)
                Container(
                  width: 110,
                  height: 110,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [_navPink, Color(0xFFFF5E98)],
                    ),
                  ),
                  padding: const EdgeInsets.all(3.5),
                  child: Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                    padding: const EdgeInsets.all(2),
                    child: ClipOval(
                      child: isUploading
                          ? const Center(child: IosLoader(color: _navPink))
                          : _buildAvatarContent(avatarState, initials),
                    ),
                  ),
                ),
                // Camera edit badge - PINK color
                Positioned(
                  bottom: 2,
                  right: 2,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [_navPink, Color(0xFFFF5E98)],
                      ),
                      border: Border.all(color: Colors.white, width: 2.5),
                      boxShadow: [
                        BoxShadow(
                          color: _navPink.withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 18),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Full Name
          Text(
            user.fullName,
            style: ArabicTypography.headerStyle(
              context,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF1F2937),
              letterSpacing: -0.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          // Email (copyable)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              Clipboard.setData(ClipboardData(text: user.email));
              HapticFeedback.lightImpact();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l10n.emailCopied),
                  duration: const Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              );
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  user.email,
                  style: ArabicTypography.bodyStyle(
                    context,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w400,
                    color: Colors.grey.shade600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.copy_rounded,
                  size: 13,
                  color: Colors.grey.shade400,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarContent(AvatarState state, String initials) {
    final hasValidCustomFile = state.customFilePath != null &&
        (kIsWeb || File(state.customFilePath!).existsSync());

    if (hasValidCustomFile) {
      if (kIsWeb) {
        return Image.network(
          state.customFilePath!,
          fit: BoxFit.cover,
          width: 110,
          height: 110,
          errorBuilder: (context, error, stackTrace) => _buildInitials(initials),
        );
      } else {
        return Image.file(
          File(state.customFilePath!),
          fit: BoxFit.cover,
          width: 110,
          height: 110,
          errorBuilder: (context, error, stackTrace) => _buildInitials(initials),
        );
      }
    } else if (user.photoUrl != null && user.photoUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: user.photoUrl!,
        fit: BoxFit.cover,
        width: 110,
        height: 110,
        placeholder: (_, _) => const Center(child: IosLoader(color: _navPink, size: 24)),
        errorWidget: (context, error, stackTrace) => _buildInitials(initials),
      );
    } else if (state.presetPath != null) {
      return Image.asset(
        state.presetPath!,
        fit: BoxFit.cover,
        width: 110,
        height: 110,
        errorBuilder: (context, error, stackTrace) => _buildInitials(initials),
      );
    }
    return _buildInitials(initials);
  }

  Widget _buildInitials(String initials) {
    return Container(
      width: 110,
      height: 110,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_navPink, Color(0xFFFF5E98)],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          fontSize: 36,
          fontWeight: FontWeight.w900,
          color: Colors.white,
        ),
      ),
    );
  }
}

// Unified Section Card: Title at top-left inside card with list items
class _UnifiedSectionCard extends StatelessWidget {
  final String title;
  final List<_InfoItem> items;

  const _UnifiedSectionCard({
    required this.title,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppResponsive.cardPadding(context, base: 20.0),
        vertical: 22,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header left: Section Title WITHOUT external icon
          Text(
            title,
            style: ArabicTypography.subtitleStyle(
              context,
              fontSize: 17.5,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF0F172A),
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 16),
          // Items
          ...items.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            final isLast = index == items.length - 1;

            return Column(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: item.onTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: item.color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(item.icon, color: item.color, size: 20),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.label,
                                style: ArabicTypography.bodyStyle(
                                  context,
                                  fontSize: 12,
                                  color: Colors.grey.shade500,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item.value,
                                style: ArabicTypography.bodyStyle(
                                  context,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF1F2937),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (item.trailing != null) item.trailing!,
                      ],
                    ),
                  ),
                ),
                if (!isLast)
                  const Divider(height: 20, color: Color(0xFFF1F5F9)),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _InfoItem {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _InfoItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.trailing,
    this.onTap,
  });
}

// Floating Photo Picker Card Dialog
class _FloatingPhotoPickerCard extends StatelessWidget {
  final VoidCallback onPickCamera;
  final VoidCallback onPickGallery;
  final VoidCallback onClose;

  const _FloatingPhotoPickerCard({
    required this.onPickCamera,
    required this.onPickGallery,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 36,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.translate('change_photo'),
                      style: ArabicTypography.headerStyle(
                        context,
                        fontSize: 18.5,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF1E293B),
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      l10n.translate('choose_photo_source'),
                      style: ArabicTypography.bodyStyle(
                        context,
                        fontSize: 13,
                        color: const Color(0xFF64748B),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              BouncingWrapper(
                shrinkScale: 0.86,
                overshootScale: 1.10,
                delayNavigation: false,
                hitPadding: const EdgeInsets.all(12),
                onTap: onClose,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF1F5F9),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF64748B)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Option 1: Camera
          _PickerOptionButton(
            icon: Icons.camera_alt_rounded,
            title: l10n.translate('take_photo'),
            subtitle: l10n.translate('take_photo_subtitle'),
            color: _navPink,
            onTap: onPickCamera,
          ),
          const SizedBox(height: 4),
          // Option 2: Gallery
          _PickerOptionButton(
            icon: Icons.photo_library_rounded,
            title: l10n.translate('choose_gallery'),
            subtitle: l10n.translate('choose_gallery_subtitle'),
            color: const Color(0xFF3B82F6),
            onTap: onPickGallery,
          ),
        ],
      ),
    );
  }
}

class _PickerOptionButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _PickerOptionButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    return BouncingWrapper(
      shrinkScale: 0.93,
      overshootScale: 1.055,
      delayNavigation: false,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFF8FAFC))),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: ArabicTypography.headerStyle(
                      context,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: ArabicTypography.bodyStyle(
                      context,
                      fontSize: 12.5,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              isRtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
              color: const Color(0xFF94A3B8),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
