import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

import 'bouncing_wrapper.dart';
import 'ios_loader.dart';

Future<Uint8List?> showWebcamCaptureDialog(BuildContext context) async {
  return showDialog<Uint8List?>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.65),
    builder: (ctx) => const _WebcamCaptureModal(),
  );
}

class _WebcamCaptureModal extends StatefulWidget {
  const _WebcamCaptureModal();

  @override
  State<_WebcamCaptureModal> createState() => _WebcamCaptureModalState();
}

class _WebcamCaptureModalState extends State<_WebcamCaptureModal> {
  html.MediaStream? _stream;
  html.VideoElement? _videoElement;
  String? _viewType;
  bool _isInitializing = true;
  String? _errorMessage;
  bool _isCapturing = false;

  @override
  void initState() {
    super.initState();
    _startWebcam();
  }

  @override
  void dispose() {
    _stopWebcam();
    super.dispose();
  }

  void _stopWebcam() {
    try {
      _stream?.getTracks().forEach((track) {
        track.stop();
      });
      _stream = null;
      if (_videoElement != null) {
        _videoElement!.srcObject = null;
        _videoElement!.remove();
        _videoElement = null;
      }
    } catch (_) {}
  }

  Future<void> _startWebcam() async {
    setState(() {
      _isInitializing = true;
      _errorMessage = null;
    });

    try {
      final mediaDevices = html.window.navigator.mediaDevices;
      if (mediaDevices == null) {
        setState(() {
          _isInitializing = false;
          _errorMessage = 'La caméra n\'est pas supportée par ce navigateur.';
        });
        return;
      }

      final stream = await mediaDevices.getUserMedia({
        'video': {
          'facingMode': 'user',
          'width': {'ideal': 1280},
          'height': {'ideal': 720},
        },
        'audio': false,
      });

      if (!mounted) {
        stream.getTracks().forEach((t) => t.stop());
        return;
      }

      final video = html.VideoElement()
        ..autoplay = true
        ..muted = true
        ..setAttribute('playsinline', 'true')
        ..srcObject = stream
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = 'cover'
        ..style.transform = 'scaleX(-1)'; // Mirror for natural selfie look

      final viewType = 'webcam-capture-${DateTime.now().microsecondsSinceEpoch}';
      ui_web.platformViewRegistry.registerViewFactory(viewType, (int id) => video);

      setState(() {
        _stream = stream;
        _videoElement = video;
        _viewType = viewType;
        _isInitializing = false;
      });
    } catch (e) {
      debugPrint('[WebcamCapture] Error starting webcam: $e');
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _errorMessage =
              'Impossible d\'accéder à la caméra de votre ordinateur.\n'
              'Veuillez autoriser l\'accès dans les paramètres de votre navigateur.';
        });
      }
    }
  }

  Future<void> _capturePhoto() async {
    if (_videoElement == null || _isCapturing) return;

    setState(() => _isCapturing = true);

    try {
      final video = _videoElement!;
      final width = video.videoWidth > 0 ? video.videoWidth : 1280;
      final height = video.videoHeight > 0 ? video.videoHeight : 720;

      final canvas = html.CanvasElement(width: width, height: height);
      final ctx = canvas.context2D;

      // Draw mirrored to match preview
      ctx.translate(width, 0);
      ctx.scale(-1, 1);
      ctx.drawImage(video, 0, 0);

      final dataUrl = canvas.toDataUrl('image/png');
      final base64String = dataUrl.split(',').last;
      final bytes = base64Decode(base64String);

      _stopWebcam();

      if (mounted) {
        Navigator.of(context).pop(bytes);
      }
    } catch (e) {
      debugPrint('[WebcamCapture] Capture error: $e');
      if (mounted) {
        setState(() {
          _isCapturing = false;
          _errorMessage = 'Erreur lors de la capture de l\'image.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Center(
        child: Container(
          width: 500,
          constraints: const BoxConstraints(maxWidth: 500),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 40,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Top Header ──
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 16, 12),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.camera_alt_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Prendre une photo',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Positionnez votre visage au centre du cadre',
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        _stopWebcam();
                        Navigator.of(context).pop(null);
                      },
                      icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 22),
                      tooltip: 'Fermer',
                    ),
                  ],
                ),
              ),

              // ── Viewfinder Viewport ──
              Container(
                height: 360,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (_viewType != null && _videoElement != null)
                      Positioned.fill(
                        child: HtmlElementView(viewType: _viewType!),
                      ),

                    // Loading indicator
                    if (_isInitializing)
                      const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IosLoader(color: Colors.white, size: 36),
                            SizedBox(height: 14),
                            Text(
                              'Activation de la caméra du PC...',
                              style: TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                          ],
                        ),
                      ),

                    // Error state
                    if (_errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.videocam_off_rounded, color: Colors.redAccent, size: 48),
                            const SizedBox(height: 12),
                            Text(
                              _errorMessage!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: _startWebcam,
                              icon: const Icon(Icons.refresh_rounded, size: 16),
                              label: const Text('Réessayer'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2563EB),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Circular Avatar Guide Overlay (Rule of alignment)
                    if (!_isInitializing && _errorMessage == null)
                      IgnorePointer(
                        child: Container(
                          width: 250,
                          height: 250,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.55),
                              width: 2,
                            ),
                          ),
                        ),
                      ),

                    // Flash during capture
                    if (_isCapturing)
                      Container(color: Colors.white.withValues(alpha: 0.85)),
                  ],
                ),
              ),

              // ── Bottom Action Bar ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () {
                        _stopWebcam();
                        Navigator.of(context).pop(null);
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white60,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      child: const Text('Annuler', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    if (!_isInitializing && _errorMessage == null)
                      BouncingWrapper(
                        onTap: _isCapturing ? null : _capturePhoto,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                            ),
                            borderRadius: BorderRadius.circular(100),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF2563EB).withValues(alpha: 0.35),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 22,
                                height: 22,
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                                child: const Center(
                                  child: Icon(Icons.circle, size: 10, color: Color(0xFF2563EB)),
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Text(
                                'Capturer la photo',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      const SizedBox.shrink(),
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
