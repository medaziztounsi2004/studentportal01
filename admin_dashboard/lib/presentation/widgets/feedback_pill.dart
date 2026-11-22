import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum FeedbackPillType {
  success,
  error,
  info,
  processing,
  undo,
}

class FeedbackPill {
  static void show(
    BuildContext context, {
    required String message,
    FeedbackPillType type = FeedbackPillType.info,
    Duration duration = const Duration(seconds: 3),
    VoidCallback? onAction,
    String actionLabel = 'Annuler',
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger.hideCurrentSnackBar();

    Color iconColor;
    Widget leadingWidget;

    switch (type) {
      case FeedbackPillType.success:
        iconColor = const Color(0xFF34D399); // emerald-400
        leadingWidget = Icon(Icons.check_circle_rounded, color: iconColor, size: 18);
        break;
      case FeedbackPillType.error:
        iconColor = const Color(0xFFF87171); // rose-400
        leadingWidget = Icon(Icons.error_rounded, color: iconColor, size: 18);
        break;
      case FeedbackPillType.processing:
        iconColor = const Color(0xFFA78BFA); // violet-400
        leadingWidget = const SizedBox(
          width: 16,
          height: 16,
          child: CupertinoActivityIndicator(radius: 8, color: Colors.white),
        );
        break;
      case FeedbackPillType.undo:
        iconColor = const Color(0xFFA78BFA);
        leadingWidget = Icon(Icons.undo_rounded, color: iconColor, size: 18);
        break;
      case FeedbackPillType.info:
        iconColor = const Color(0xFF60A5FA); // blue-400
        leadingWidget = Icon(Icons.info_rounded, color: iconColor, size: 18);
        break;
    }

    final double targetWidth = (message.length * 7.5 + (onAction != null ? 140 : 80))
        .clamp(280.0, 440.0);

    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        width: targetWidth,
        elevation: 8,
        backgroundColor: const Color(0xFF0F172A), // Slate 900 capsule
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        duration: duration,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(100),
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.12),
            width: 1,
          ),
        ),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            leadingWidget,
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.1,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onAction != null) ...[
              const SizedBox(width: 8),
              InkWell(
                onTap: () {
                  messenger.hideCurrentSnackBar();
                  onAction();
                },
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(
                    actionLabel,
                    style: GoogleFonts.plusJakartaSans(
                      color: const Color(0xFFA78BFA),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static void showSuccess(BuildContext context, String message, {Duration duration = const Duration(seconds: 3)}) {
    show(context, message: message, type: FeedbackPillType.success, duration: duration);
  }

  static void showError(BuildContext context, String message, {Duration duration = const Duration(seconds: 4)}) {
    show(context, message: message, type: FeedbackPillType.error, duration: duration);
  }

  static void showProcessing(BuildContext context, String message, {Duration duration = const Duration(seconds: 15)}) {
    show(context, message: message, type: FeedbackPillType.processing, duration: duration);
  }

  static void showInfo(BuildContext context, String message, {Duration duration = const Duration(seconds: 3)}) {
    show(context, message: message, type: FeedbackPillType.info, duration: duration);
  }

  static void showUndo(BuildContext context, {required String message, VoidCallback? onUndo, String actionLabel = 'Annuler'}) {
    show(context, message: message, type: FeedbackPillType.undo, onAction: onUndo, actionLabel: actionLabel);
  }

  static void hide(BuildContext context) {
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
  }
}
