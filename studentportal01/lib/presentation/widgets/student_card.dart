import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/services/camera_photo_service.dart';
import '../../data/models/user_model.dart';
import '../../data/models/enrollment_model.dart';
import '../../data/models/school_model.dart';
import '../../core/config/supabase_config.dart';
import '../../core/l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import 'ios_loader.dart';
import 'photo_cutout_screen.dart';

class StudentCard extends ConsumerStatefulWidget {
  final UserModel user;
  final EnrollmentModel? enrollment;
  final SchoolModel? school;
  final VoidCallback onMenuTap;
  final VoidCallback? onTap;

  const StudentCard({
    super.key,
    required this.user,
    this.enrollment,
    this.school,
    required this.onMenuTap,
    this.onTap,
  });

  @override
  ConsumerState<StudentCard> createState() => _StudentCardState();
}

class _StudentCardState extends ConsumerState<StudentCard> {
  static const double _baseW = 720;
  static const double _baseH = 480;

  bool _uploadingPhoto = false;

  void _showPhotoSourceSheet() {
    if (_uploadingPhoto) return;
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.camera_alt_rounded,
                      color: Color(0xFF2563EB)),
                ),
                title: Text(
                  l10n.translate('take_photo_desc'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickAndUploadPhoto(ImageSource.camera);
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.photo_library_rounded,
                      color: Color(0xFF8B5CF6)),
                ),
                title: Text(
                  l10n.translate('photo_library'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickAndUploadPhoto(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndUploadPhoto([ImageSource source = ImageSource.gallery]) async {
    if (_uploadingPhoto) return;

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
      initialShape: 'card',
    );
    if (croppedBytes == null) return; // Student cancelled

    setState(() => _uploadingPhoto = true);
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final fileName = '${userId}_${DateTime.now().millisecondsSinceEpoch}.png';
      final storagePath = 'avatars/$fileName';

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

      await supabase
          .from('users')
          .update({'photo_url': publicUrl})
          .eq('id', userId);

      if (mounted) {
        ref.read(authProvider.notifier).refreshUserData();
      }
    } catch (_) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.translate('photo_upload_error'))),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final user = widget.user;
    final enrollment = widget.enrollment;

    final classInfo = enrollment?.classInfo;
    final groupInfo = enrollment?.groupInfo;
    final classText = classInfo != null
        ? '${classInfo.name}${groupInfo != null ? ' - ${groupInfo.name}' : ''}'
        : '—';

    final dobText = user.dateOfBirth != null
        ? DateFormat('dd/MM/yyyy').format(user.dateOfBirth!)
        : '—';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Center(
        child: GestureDetector(
          onTap: widget.onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _baseW),
            child: AspectRatio(
              aspectRatio: _baseW / _baseH,
              child: _CardContent(
                user: user,
                school: widget.school,
                classText: classText,
                dobText: dobText,
                uploadingPhoto: _uploadingPhoto,
                onPhotoTap: _showPhotoSourceSheet,
                onMenuTap: widget.onMenuTap,
                l10n: l10n,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CardContent extends StatelessWidget {
  final UserModel user;
  final SchoolModel? school;
  final String classText;
  final String dobText;
  final bool uploadingPhoto;
  final VoidCallback onPhotoTap;
  final VoidCallback onMenuTap;
  final AppLocalizations l10n;

  const _CardContent({
    required this.user,
    this.school,
    required this.classText,
    required this.dobText,
    required this.uploadingPhoto,
    required this.onPhotoTap,
    required this.onMenuTap,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    return Directionality(
      textDirection: TextDirection.ltr,
      child: LayoutBuilder(
      builder: (context, constraints) {
        final scale = constraints.maxWidth / 720;
        double s(double value) => value * scale;

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF5F7FB),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: const Color(0x5A3A1022),
                blurRadius: s(60),
                offset: Offset(0, s(25)),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _WavePainter(
                    color: const Color(0xFFFF85B0),
                    strokeWidth: s(1.2),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: -s(60),
                height: s(220),
                child: ClipRRect(
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(s(150)),
                    bottomRight: Radius.circular(s(150)),
                  ),
                  child: Stack(
                    children: [
                      Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            stops: [0.0, 0.45, 1.0],
                            colors: [
                              Color(0xFFFF85B0),
                              Color(0xFF54172D),
                              Color(0xFFFF2D78),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: -s(80),
                        top: -s(80),
                        child: Container(
                          width: s(400),
                          height: s(400),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                Color(0x35FFFFFF),
                                Color(0x00FFFFFF),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: isArabic ? s(72) : s(60),
                left: s(300),
                right: s(20),
                child: Text(
                  l10n.studentCardTitle,
                  maxLines: isArabic ? 1 : 2,
                  softWrap: !isArabic,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: isArabic ? s(52) : s(46),
                    fontFamily: isArabic ? GoogleFonts.cairo().fontFamily : null,
                    height: isArabic ? 1.1 : 0.95,
                    letterSpacing: isArabic ? 0 : 1,
                    color: Colors.white,
                  ),
                ),
              ),
              Positioned(
                top: s(95),
                left: s(60),
                child: GestureDetector(
                  onTap: onPhotoTap,
                  child: Stack(
                    children: [
                      Container(
                        width: s(180),
                        height: s(180),
                        padding: EdgeInsets.all(s(8)),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0x664A1223),
                              blurRadius: s(18),
                              offset: Offset(0, s(10)),
                            ),
                          ],
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFFFF85B0),
                              Color(0xFF54172D),
                            ],
                          ),
                        ),
                        child: ClipOval(
                          child: _buildPhotoContent(s),
                        ),
                      ),
                      if (uploadingPhoto)
                        Positioned.fill(
                          child: Container(
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black26,
                            ),
                            child: Center(
                              child: IosLoader(color: Colors.white, size: s(24)),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: s(300),
                top: s(250),
                width: s(380),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _detailRow(l10n.cardName, user.fullName, s, isArabic),
                    _detailRow(l10n.cardClass, '\u200E$classText', s, isArabic),
                    _detailRow(l10n.cardDob, '\u200E$dobText', s, isArabic),
                    _detailRow(l10n.cardAddress, user.address ?? '—', s, isArabic),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                width: s(300),
                top: s(340),
                child: Center(
                  child: Text(
                    '\u200E${user.studentCode ?? '—'}',
                    style: TextStyle(
                      fontFamily: isArabic ? GoogleFonts.tajawal().fontFamily : null,
                      fontSize: s(22),
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                      color: const Color(0xFF2F242A),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: s(32),
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Color(0xFF822B4A),
                        Color(0xFFD6316D),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
  }

  Widget _detailRow(String label, String value, double Function(double) s, bool isArabic) {
    return Padding(
      padding: EdgeInsets.only(bottom: s(16)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: s(96),
            child: Text(
              label,
              style: TextStyle(
                fontFamily: isArabic ? GoogleFonts.tajawal().fontFamily : null,
                fontWeight: FontWeight.w500,
                fontSize: s(18),
                color: const Color(0xFF3B2A32),
              ),
            ),
          ),
          SizedBox(
            width: s(24),
            child: Text(
              ':',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: s(18),
                color: const Color(0xFF3B2A32),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontFamily: isArabic ? GoogleFonts.tajawal().fontFamily : null,
                fontWeight: FontWeight.w500,
                fontSize: s(18),
                color: const Color(0xFF3B2A32),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoContent(double Function(double) s) {
    if (user.photoUrl != null && user.photoUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: user.photoUrl!,
        fit: BoxFit.cover,
        width: s(164),
        height: s(164),
        errorWidget: (_, _, _) => _buildInitials(s),
      );
    }
    return _buildInitials(s);
  }

  Widget _buildInitials(double Function(double) s) {
    final initials = user.fullName
        .split(' ')
        .take(2)
        .map((e) => e.isNotEmpty ? e[0].toUpperCase() : '')
        .join();
    return Container(
      color: const Color(0xFFD0D5DB),
      alignment: Alignment.center,
      child: initials.isNotEmpty
          ? Text(
              initials,
              style: TextStyle(
                fontSize: s(48),
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            )
          : Icon(
              Icons.person,
              size: s(64),
              color: const Color(0xFF8A949E),
            ),
    );
  }

}

class _WavePainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  _WavePainter({required this.color, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final scale = size.width / 720;
    final baseY = size.height * 0.65;
    final gapStart = 2.5 * scale;
    final gapMid = 9.0 * scale;
    final gapEnd = 15.0 * scale;

    for (var i = 0; i < 14; i++) {
      final startY = baseY + gapStart * i;
      final controlY1 = baseY + 140 * scale + gapMid * i;
      final controlY2 = baseY - 50 * scale + gapEnd * i;
      final endY = baseY - 60 * scale + gapEnd * i;

      final path = Path()
        ..moveTo(-20 * scale, startY)
        ..cubicTo(
          240 * scale, controlY1,
          480 * scale, controlY2,
          760 * scale, endY,
        );
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
