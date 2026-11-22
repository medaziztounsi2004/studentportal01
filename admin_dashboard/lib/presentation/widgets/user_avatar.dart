import 'dart:typed_data';
import 'package:flutter/material.dart';

/// Consistent avatar widget used across the entire admin dashboard.
///
/// Displays [photoUrl] as a circular image when available, falling back
/// to 1–2 letter initials derived from [name].
///
/// Colour is deterministic: females get a pink palette; everyone else
/// gets one of five pastel palettes picked by the first letter of [name].
///
/// Usage:
/// ```dart
/// UserAvatar(name: user.fullName, photoUrl: user.photoUrl, radius: 17)
/// ```
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.name,
    this.photoUrl,
    this.imageBytes,
    this.radius = 17,
    this.gender,
    this.borderColor,
    this.borderWidth = 0,
    this.fontSize,
    this.backgroundColor,
    this.textColor,
  });

  /// Full name – used for initials and deterministic colour.
  final String name;

  /// Optional network URL for a profile photo.
  final String? photoUrl;

  /// Optional in-memory bytes for immediate local preview without flicker.
  final Uint8List? imageBytes;

  /// Circle radius (default 17 → 34×34 logical pixels).
  final double radius;

  /// 'F' or 'M' or null – females get a pink palette.
  final String? gender;

  /// Optional outer border colour (e.g. Colors.white for stacked avatars).
  final Color? borderColor;

  /// Border width. Only drawn when [borderColor] is not null.
  final double borderWidth;

  /// Override the initials font size. Defaults to radius * 0.72.
  final double? fontSize;

  /// Force a specific background colour instead of the deterministic one.
  final Color? backgroundColor;

  /// Force a specific text colour instead of the deterministic one.
  final Color? textColor;

  // ── Colour palettes ──────────────────────────────────────────

  static const _femalePalette = (Color(0xFFFCE7F3), Color(0xFFDB2777));

  static const _palettes = [
    (Color(0xFFFFF7ED), Color(0xFFEA580C)), // orange
    (Color(0xFFEFF6FF), Color(0xFF2563EB)), // blue
    (Color(0xFFF0FDF4), Color(0xFF16A34A)), // green
    (Color(0xFFFEF2F2), Color(0xFFDC2626)), // red
    (Color(0xFFFDF4FF), Color(0xFF9333EA)), // purple
  ];

  (Color bg, Color fg) _colors() {
    if (backgroundColor != null || textColor != null) {
      return (
        backgroundColor ?? _palettes[0].$1,
        textColor ?? _palettes[0].$2,
      );
    }
    if (gender == 'F') return _femalePalette;
    final letter = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final code = letter.codeUnitAt(0);
    return _palettes[code % _palettes.length];
  }

  // ── Initials ─────────────────────────────────────────────────

  String _initials() {
    if (name.isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }

  // ── Build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _colors();
    final size = radius * 2;
    final fs = fontSize ?? (radius * 0.72);
    final hasPhoto = photoUrl != null && photoUrl!.isNotEmpty;

    Widget circle = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: borderColor != null
            ? Border.all(color: borderColor!, width: borderWidth)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 4,
          ),
        ],
      ),
      child: imageBytes != null
          ? ClipOval(
              child: Image.memory(
                imageBytes!,
                fit: BoxFit.cover,
                width: size,
                height: size,
                errorBuilder: (_, _, _) => Center(
                  child: Text(
                    _initials(),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: fs,
                      color: fg,
                    ),
                  ),
                ),
              ),
            )
          : hasPhoto
          ? ClipOval(
              child: Image.network(
                photoUrl!,
                fit: BoxFit.cover,
                width: size,
                height: size,
                errorBuilder: (_, _, _) => Center(
                  child: Text(
                    _initials(),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: fs,
                      color: fg,
                    ),
                  ),
                ),
              ),
            )
          : Center(
              child: Text(
                _initials(),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: fs,
                  color: fg,
                ),
              ),
            ),
    );

    return circle;
  }
}
