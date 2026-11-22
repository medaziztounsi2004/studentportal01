import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'ios_loader.dart';

/// Interactive circular photo cropper dialog for student/user profile pictures.
///
/// Features:
/// - Pan, pinch-zoom, and mouse wheel zoom support (desktop + web friendly).
/// - Rule-of-thirds alignment grid inside a circular viewfinder.
/// - Rotate 90°, Center, and Reset buttons.
/// - Outputs a crisp 512x512 square PNG via [PictureRecorder].
class AvatarCropperDialog extends StatefulWidget {
  final Uint8List rawImageBytes;

  const AvatarCropperDialog({
    super.key,
    required this.rawImageBytes,
  });

  /// Displays the cropper dialog and returns the cropped 512x512 PNG bytes,
  /// or `null` if cancelled.
  static Future<Uint8List?> show({
    required BuildContext context,
    required Uint8List rawImageBytes,
  }) {
    return showDialog<Uint8List>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.75),
      builder: (ctx) => AvatarCropperDialog(rawImageBytes: rawImageBytes),
    );
  }

  @override
  State<AvatarCropperDialog> createState() => _AvatarCropperDialogState();
}

class _AvatarCropperDialogState extends State<AvatarCropperDialog> {
  ui.Image? _uiImage;
  bool _isLoading = true;
  bool _hasError = false;
  bool _isCropping = false;

  // Viewfinder diameter
  double _cropSize = 280.0;

  // Transformations
  double _scale = 1.0;
  Offset _offset = Offset.zero;
  int _rotationTurns = 0; // 0, 1, 2, 3

  // Gesture tracking
  double _startScale = 1.0;
  Offset _lastFocalPoint = Offset.zero;

  @override
  void initState() {
    super.initState();
    _decodeImage();
  }

  @override
  void dispose() {
    _uiImage?.dispose();
    super.dispose();
  }

  Future<void> _decodeImage() async {
    try {
      final ui.Image decoded = await decodeImageFromList(widget.rawImageBytes);
      if (!mounted) {
        decoded.dispose();
        return;
      }
      setState(() {
        _uiImage = decoded;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[AvatarCropperDialog] Failed to decode image: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    }
  }

  double _calculateBaseScale(ui.Image image, double cropSize, int rotationTurns) {
    final bool isRotated90 = (rotationTurns % 2 != 0);
    final double visualWidth =
        isRotated90 ? image.height.toDouble() : image.width.toDouble();
    final double visualHeight =
        isRotated90 ? image.width.toDouble() : image.height.toDouble();
    return math.max(cropSize / visualWidth, cropSize / visualHeight);
  }

  void _clampOffset() {
    if (_uiImage == null) return;
    final baseScale =
        _calculateBaseScale(_uiImage!, _cropSize, _rotationTurns);
    final isRotated90 = (_rotationTurns % 2 != 0);
    final visualW =
        isRotated90 ? _uiImage!.height.toDouble() : _uiImage!.width.toDouble();
    final visualH =
        isRotated90 ? _uiImage!.width.toDouble() : _uiImage!.height.toDouble();

    final renderedW = visualW * baseScale * _scale;
    final renderedH = visualH * baseScale * _scale;

    final maxDragX = math.max(0.0, (renderedW - _cropSize) / 2) + 90.0;
    final maxDragY = math.max(0.0, (renderedH - _cropSize) / 2) + 90.0;

    _offset = Offset(
      _offset.dx.clamp(-maxDragX, maxDragX),
      _offset.dy.clamp(-maxDragY, maxDragY),
    );
  }

  void _rotate90() {
    HapticFeedback.lightImpact();
    setState(() {
      _rotationTurns = (_rotationTurns + 1) % 4;
      _offset = Offset.zero;
      _clampOffset();
    });
  }

  void _centerAndReset() {
    HapticFeedback.mediumImpact();
    setState(() {
      _scale = 1.0;
      _offset = Offset.zero;
      _rotationTurns = 0;
    });
  }

  Future<void> _confirmAndCrop() async {
    if (_uiImage == null || _isCropping) return;

    setState(() => _isCropping = true);
    HapticFeedback.mediumImpact();

    try {
      const double outputSize = 512.0;
      final double outputScale = outputSize / _cropSize;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(
        recorder,
        const Rect.fromLTWH(0, 0, outputSize, outputSize),
      );

      // Clip to exact square output boundary
      canvas.clipRect(const Rect.fromLTWH(0, 0, outputSize, outputSize));

      // Translate origin to output center
      canvas.translate(outputSize / 2, outputSize / 2);

      // Apply pan translation scaled to output canvas
      canvas.translate(_offset.dx * outputScale, _offset.dy * outputScale);

      // Apply rotation around center
      if (_rotationTurns != 0) {
        canvas.rotate(_rotationTurns * math.pi / 2);
      }

      // Apply zoom scale
      final baseScale =
          _calculateBaseScale(_uiImage!, _cropSize, _rotationTurns);
      final effectiveScale = baseScale * _scale * outputScale;
      canvas.scale(effectiveScale, effectiveScale);

      // Draw the image centered
      canvas.drawImage(
        _uiImage!,
        Offset(-_uiImage!.width / 2, -_uiImage!.height / 2),
        Paint()..filterQuality = FilterQuality.high,
      );

      final picture = recorder.endRecording();
      final croppedUi =
          await picture.toImage(outputSize.toInt(), outputSize.toInt());
      final byteData =
          await croppedUi.toByteData(format: ui.ImageByteFormat.png);

      croppedUi.dispose();
      picture.dispose();

      if (byteData == null) {
        throw Exception('Failed to encode cropped image to PNG');
      }

      final croppedBytes = byteData.buffer.asUint8List();

      if (mounted) {
        Navigator.of(context).pop(croppedBytes);
      }
    } catch (e) {
      debugPrint('[AvatarCropperDialog] Error during cropping: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erreur lors du recadrage de la photo.'),
            backgroundColor: Color(0xFFEF4444),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCropping = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Center(
        child: Container(
          width: 540,
          constraints: const BoxConstraints(maxHeight: 640),
          decoration: BoxDecoration(
            color: const Color(0xFF111827),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
            border: Border.all(
              color: Colors.white.withOpacity(0.12),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Top Header ──
              _buildHeader(),

              const Divider(height: 1, color: Color(0xFF1F2937)),

              // ── Central Interactive Viewfinder ──
              Flexible(
                child: SizedBox(
                  height: 360,
                  child: _isLoading
                      ? const Center(
                          child: IosLoader(color: Colors.white, size: 36),
                        )
                      : _hasError
                          ? const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.broken_image_rounded,
                                      color: Colors.white54, size: 48),
                                  SizedBox(height: 12),
                                  Text(
                                    'Impossible de charger l\'image.',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : _buildViewfinderArea(),
                ),
              ),

              const Divider(height: 1, color: Color(0xFF1F2937)),

              // ── Control Deck (Slider & buttons) ──
              _buildControlDeck(),

              const Divider(height: 1, color: Color(0xFF1F2937)),

              // ── Footer Action Buttons ──
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF6D4CF6).withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.crop_rotate_rounded,
              color: Color(0xFFA78BFA),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Ajuster la photo de profil',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Faites glisser et zoomez pour bien cadrer le visage',
                  style: TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(null),
            icon: const Icon(Icons.close_rounded, color: Color(0xFF9CA3AF), size: 20),
            tooltip: 'Fermer',
          ),
        ],
      ),
    );
  }

  Widget _buildViewfinderArea() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxDimension = math.min(
          constraints.maxWidth - 32,
          constraints.maxHeight - 20,
        );
        _cropSize = maxDimension.clamp(200.0, 300.0);

        final baseScale =
            _calculateBaseScale(_uiImage!, _cropSize, _rotationTurns);

        return Listener(
          onPointerSignal: (pointerSignal) {
            if (pointerSignal is PointerScrollEvent) {
              final zoomDelta = pointerSignal.scrollDelta.dy > 0 ? -0.1 : 0.1;
              setState(() {
                _scale = (_scale + zoomDelta).clamp(0.7, 4.0);
                _clampOffset();
              });
            }
          },
          child: ClipRect(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: (details) {
                _startScale = _scale;
                _lastFocalPoint = details.localFocalPoint;
              },
              onScaleUpdate: (details) {
                setState(() {
                  _scale = (_startScale * details.scale).clamp(0.7, 4.0);
                  final delta = details.localFocalPoint - _lastFocalPoint;
                  _offset += delta;
                  _lastFocalPoint = details.localFocalPoint;
                  _clampOffset();
                });
              },
              onDoubleTap: () {
                HapticFeedback.lightImpact();
                setState(() {
                  if (_scale > 1.2) {
                    _scale = 1.0;
                    _offset = Offset.zero;
                  } else {
                    _scale = 2.0;
                  }
                  _clampOffset();
                });
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 1. Raw photo rendered with pan/zoom/rotation
                  CustomPaint(
                    painter: _CutoutImagePainter(
                      image: _uiImage!,
                      scale: _scale,
                      offset: _offset,
                      rotationTurns: _rotationTurns,
                      baseScale: baseScale,
                    ),
                  ),

                  // 2. Viewfinder dark mask, circular border & grid
                  IgnorePointer(
                    child: CustomPaint(
                      painter: _ViewfinderOverlayPainter(
                        cropSize: _cropSize,
                        maskColor: Colors.black.withOpacity(0.72),
                        borderColor: const Color(0xFF6D4CF6),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildControlDeck() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: const Color(0xFF0F172A),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Zoom slider
          Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: const Icon(Icons.remove_circle_outline_rounded,
                    color: Colors.white70, size: 20),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _scale = (_scale - 0.15).clamp(0.7, 4.0);
                    _clampOffset();
                  });
                },
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: const Color(0xFF6D4CF6),
                    inactiveTrackColor: Colors.white.withOpacity(0.2),
                    thumbColor: Colors.white,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayColor:
                        const Color(0xFF6D4CF6).withOpacity(0.2),
                    trackHeight: 3,
                  ),
                  child: Slider(
                    value: _scale.clamp(0.7, 4.0),
                    min: 0.7,
                    max: 4.0,
                    onChanged: (v) {
                      setState(() {
                        _scale = v;
                        _clampOffset();
                      });
                    },
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: const Icon(Icons.add_circle_outline_rounded,
                    color: Colors.white70, size: 20),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _scale = (_scale + 0.15).clamp(0.7, 4.0);
                    _clampOffset();
                  });
                },
              ),
            ],
          ),

          const SizedBox(height: 6),

          // Action buttons: Rotate, Center, Reset
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildActionButton(
                icon: Icons.rotate_right_rounded,
                label: 'Pivoter 90°',
                onTap: _rotate90,
              ),
              const SizedBox(width: 8),
              _buildActionButton(
                icon: Icons.filter_center_focus_rounded,
                label: 'Centrer',
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _offset = Offset.zero;
                    _clampOffset();
                  });
                },
              ),
              const SizedBox(width: 8),
              _buildActionButton(
                icon: Icons.restart_alt_rounded,
                label: 'Réinitialiser',
                onTap: _centerAndReset,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.white.withOpacity(0.12),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white70, size: 14),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          SizedBox(
            height: 38,
            child: TextButton(
              onPressed: _isCropping ? null : () => Navigator.of(context).pop(null),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF9CA3AF),
                padding: const EdgeInsets.symmetric(horizontal: 18),
              ),
              child: const Text(
                'Annuler',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 38,
            child: ElevatedButton.icon(
              onPressed: _isCropping ? null : _confirmAndCrop,
              icon: _isCropping
                  ? const IosLoader.small(color: Colors.white)
                  : const Icon(Icons.check_rounded, size: 16),
              label: Text(
                _isCropping ? 'Recadrage...' : 'Valider le cadrage',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6D4CF6),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// CUSTOM PAINTER: Cutout Image with 2D transformations
// ═══════════════════════════════════════════════════════════════════

class _CutoutImagePainter extends CustomPainter {
  final ui.Image image;
  final double scale;
  final Offset offset;
  final int rotationTurns;
  final double baseScale;

  _CutoutImagePainter({
    required this.image,
    required this.scale,
    required this.offset,
    required this.rotationTurns,
    required this.baseScale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    canvas.save();

    // 1. Center of viewport
    canvas.translate(center.dx, center.dy);

    // 2. Pan offset
    canvas.translate(offset.dx, offset.dy);

    // 3. Rotation (0, 90, 180, 270 deg)
    if (rotationTurns != 0) {
      canvas.rotate(rotationTurns * math.pi / 2);
    }

    // 4. Zoom scale
    final effectiveScale = baseScale * scale;
    canvas.scale(effectiveScale, effectiveScale);

    // 5. Draw image centered
    canvas.drawImage(
      image,
      Offset(-image.width / 2, -image.height / 2),
      Paint()..filterQuality = FilterQuality.medium,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CutoutImagePainter oldDelegate) {
    return oldDelegate.scale != scale ||
        oldDelegate.offset != offset ||
        oldDelegate.rotationTurns != rotationTurns ||
        oldDelegate.baseScale != baseScale;
  }
}

// ═══════════════════════════════════════════════════════════════════
// CUSTOM PAINTER: Circular Viewfinder Overlay
// ═══════════════════════════════════════════════════════════════════

class _ViewfinderOverlayPainter extends CustomPainter {
  final double cropSize;
  final Color maskColor;
  final Color borderColor;

  _ViewfinderOverlayPainter({
    required this.cropSize,
    required this.maskColor,
    required this.borderColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final cropRect = Rect.fromCenter(
      center: center,
      width: cropSize,
      height: cropSize,
    );

    // 1. Dark mask with circular cutout hole
    final fullRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final Path maskPath = Path()..addRect(fullRect);
    final Path holePath = Path()..addOval(cropRect);

    final combinedMask =
        Path.combine(PathOperation.difference, maskPath, holePath);
    canvas.drawPath(combinedMask, Paint()..color = maskColor);

    // 2. Rule of thirds grid lines inside the circle
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.25)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    canvas.save();
    canvas.clipPath(Path()..addOval(cropRect));

    final third = cropSize / 3.0;
    // Vertical grid lines
    canvas.drawLine(
      Offset(cropRect.left + third, cropRect.top),
      Offset(cropRect.left + third, cropRect.bottom),
      gridPaint,
    );
    canvas.drawLine(
      Offset(cropRect.left + third * 2, cropRect.top),
      Offset(cropRect.left + third * 2, cropRect.bottom),
      gridPaint,
    );
    // Horizontal grid lines
    canvas.drawLine(
      Offset(cropRect.left, cropRect.top + third),
      Offset(cropRect.right, cropRect.top + third),
      gridPaint,
    );
    canvas.drawLine(
      Offset(cropRect.left, cropRect.top + third * 2),
      Offset(cropRect.right, cropRect.top + third * 2),
      gridPaint,
    );

    // Center focal point
    final centerDotPaint = Paint()..color = Colors.white.withOpacity(0.6);
    canvas.drawCircle(center, 2.5, centerDotPaint);

    canvas.restore();

    // 3. Circular Viewfinder Outer Border
    final borderPaint = Paint()
      ..color = borderColor.withOpacity(0.9)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    canvas.drawOval(cropRect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _ViewfinderOverlayPainter oldDelegate) {
    return oldDelegate.cropSize != cropSize ||
        oldDelegate.maskColor != maskColor ||
        oldDelegate.borderColor != borderColor;
  }
}
