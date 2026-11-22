import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../presentation/widgets/webcam_capture_stub.dart'
    if (dart.library.html) '../../presentation/widgets/webcam_capture_web.dart';
import 'biometric_service.dart';

/// Unified cross-platform camera & gallery photo service.
/// - Web (PC/Laptop): Opens an interactive live webcam dialog to snap photos directly from the computer.
/// - Desktop (Windows): Gracefully informs the user and opens file selection instead of crashing.
/// - Mobile (Android/iOS): Safely triggers the system camera or gallery with biometric grace handling.
class CameraPhotoService {
  static final ImagePicker _picker = ImagePicker();

  static Future<XFile?> pickPhoto({
    required BuildContext context,
    required ImageSource source,
    double maxWidth = 1200,
    double maxHeight = 1200,
    int imageQuality = 88,
  }) async {
    if (source == ImageSource.camera) {
      // ── 1. Web Platform (PC / Laptop in Chrome/Edge/Firefox) ──
      if (kIsWeb) {
        try {
          final rawBytes = await showWebcamCaptureDialog(context);
          if (rawBytes != null && rawBytes.isNotEmpty) {
            return XFile.fromData(
              rawBytes,
              name: 'webcam_${DateTime.now().millisecondsSinceEpoch}.png',
              mimeType: 'image/png',
            );
          }
          return null;
        } catch (e) {
          debugPrint('[CameraPhotoService] Web webcam error: $e');
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Impossible d\'accéder à la webcam. Veuillez choisir un fichier.'),
                backgroundColor: Color(0xFFF59E0B),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          return _picker.pickImage(
            source: ImageSource.gallery,
            maxWidth: maxWidth,
            maxHeight: maxHeight,
            imageQuality: imageQuality,
          );
        }
      }

      // ── 2. Windows Desktop (PC) ──
      if (!kIsWeb && Platform.isWindows) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('La caméra n\'est pas disponible sur Windows. Veuillez choisir une image.'),
              backgroundColor: Color(0xFF3B82F6),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return _picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: maxWidth,
          maxHeight: maxHeight,
          imageQuality: imageQuality,
        );
      }

      // ── 3. Mobile (Android & iOS) ──
      BiometricService.instance.setExternalIntentActive(true);
      try {
        XFile? file = await _picker.pickImage(
          source: ImageSource.camera,
          maxWidth: maxWidth,
          maxHeight: maxHeight,
          imageQuality: imageQuality,
        );

        if (file == null && !kIsWeb && Platform.isAndroid) {
          final lost = await _picker.retrieveLostData();
          if (lost.file != null) {
            file = lost.file;
          }
        }
        return file;
      } catch (e) {
        debugPrint('[CameraPhotoService] Mobile camera error: $e');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Impossible d\'ouvrir l\'appareil photo. Veuillez vérifier les autorisations.'),
              backgroundColor: Color(0xFFEF4444),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return null;
      } finally {
        Future.delayed(const Duration(milliseconds: 1500), () {
          BiometricService.instance.setExternalIntentActive(false);
        });
      }
    } else {
      // ── Gallery / File Picker (all platforms) ──
      BiometricService.instance.setExternalIntentActive(true);
      try {
        return await _picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: maxWidth,
          maxHeight: maxHeight,
          imageQuality: imageQuality,
        );
      } catch (e) {
        debugPrint('[CameraPhotoService] Gallery picker error: $e');
        return null;
      } finally {
        Future.delayed(const Duration(milliseconds: 1500), () {
          BiometricService.instance.setExternalIntentActive(false);
        });
      }
    }
  }
}
