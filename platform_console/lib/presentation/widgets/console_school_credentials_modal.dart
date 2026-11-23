import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/services/user_management_service.dart';

void showConsoleSchoolCredentialsModal({
  required BuildContext context,
  required Map<String, dynamic> school,
  Map<String, dynamic>? preselectedUser,
  VoidCallback? onPasswordChanged,
}) {
  showDialog(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (ctx) => BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
      child: _ConsoleSchoolCredentialsDialog(
        school: school,
        preselectedUser: preselectedUser,
        onPasswordChanged: onPasswordChanged,
      ),
    ),
  );
}

class _ConsoleSchoolCredentialsDialog extends StatefulWidget {
  final Map<String, dynamic> school;
  final Map<String, dynamic>? preselectedUser;
  final VoidCallback? onPasswordChanged;

  const _ConsoleSchoolCredentialsDialog({
    required this.school,
    this.preselectedUser,
    this.onPasswordChanged,
  });

  @override
  State<_ConsoleSchoolCredentialsDialog> createState() =>
      _ConsoleSchoolCredentialsDialogState();
}

class _ConsoleSchoolCredentialsDialogState
    extends State<_ConsoleSchoolCredentialsDialog> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _adminUsers = [];
  Map<String, dynamic>? _selectedUser;

  bool _showCurrentPassword = false;
  String _currentPassword = '';

  final _newPasswordCtrl = TextEditingController();
  bool _showNewPassword = false;
  bool _isSaving = false;

  String? _successMessage;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadCredentials();
  }

  @override
  void dispose() {
    _newPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCredentials() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    final schoolId = widget.school['id']?.toString() ?? '';

    // If a preselected user was passed in
    if (widget.preselectedUser != null) {
      final user = widget.preselectedUser!;
      _selectedUser = user;
      _adminUsers = [user];
      _currentPassword = (user['initial_password'] as String?)?.trim() ?? '';
      setState(() => _isLoading = false);
      return;
    }

    // Otherwise load admin accounts for this school
    final admins = await UserManagementService.getSchoolAdmins(schoolId);
    if (!mounted) return;

    setState(() {
      _adminUsers = admins;
      if (admins.isNotEmpty) {
        _selectedUser = admins.first;
        _currentPassword =
            (_selectedUser?['initial_password'] as String?)?.trim() ?? '';
      }
      _isLoading = false;
    });
  }

  void _onUserChanged(Map<String, dynamic>? user) {
    if (user == null) return;
    setState(() {
      _selectedUser = user;
      _currentPassword = (user['initial_password'] as String?)?.trim() ?? '';
      _showCurrentPassword = false;
      _successMessage = null;
      _errorMessage = null;
    });
  }

  void _generateSecurePassword() {
    const chars = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#\$%*';
    final rnd = Random.secure();
    final pass = List.generate(12, (_) => chars[rnd.nextInt(chars.length)]).join();
    setState(() {
      _newPasswordCtrl.text = pass;
      _showNewPassword = true;
      _errorMessage = null;
    });
  }

  Future<void> _saveNewPassword() async {
    final newPass = _newPasswordCtrl.text.trim();
    if (newPass.length < 6) {
      setState(() {
        _errorMessage = 'Le mot de passe doit comporter au moins 6 caractères.';
      });
      return;
    }

    final userId = _selectedUser?['id']?.toString();
    if (userId == null) {
      setState(() {
        _errorMessage = 'Aucun utilisateur sélectionné.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
      _successMessage = null;
    });

    final res = await UserManagementService.resetPassword(
      userId: userId,
      newPassword: newPass,
    );

    if (!mounted) return;

    if (res['success'] == true) {
      final savedPass = res['password']?.toString() ?? newPass;
      setState(() {
        _isSaving = false;
        _currentPassword = savedPass;
        _showCurrentPassword = true; // Automatically unhide so super admin sees it
        if (_selectedUser != null) {
          _selectedUser!['initial_password'] = savedPass;
        }
        _newPasswordCtrl.clear();
        _successMessage = 'Mot de passe mis à jour avec succès !';
      });

      widget.onPasswordChanged?.call();
    } else {
      setState(() {
        _isSaving = false;
        _errorMessage = res['error']?.toString() ??
            'Erreur lors de la mise à jour du mot de passe.';
      });
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Text('$label copié dans le presse-papier !'),
          ],
        ),
        backgroundColor: const Color(0xFF059669),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final schoolName = widget.school['name']?.toString() ?? 'Établissement';
    final schoolCode = (widget.school['code'] ?? '—').toString().toUpperCase();

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxWidth: 620),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Modal Header ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: const Icon(
                      Icons.key_rounded,
                      size: 22,
                      color: Color(0xFFD97706),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                schoolName,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0F172A),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                schoolCode,
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'monospace',
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Identifiants & Gestion des Mots de Passe',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded,
                        size: 20, color: Color(0xFF94A3B8)),
                    tooltip: 'Fermer',
                    splashRadius: 18,
                  ),
                ],
              ),
            ),

            // ── Body Content ──
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: _isLoading
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Color(0xFF6D4CF6),
                          ),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Success Banner
                          if (_successMessage != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFECFDF5),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFA7F3D0)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.check_circle_rounded,
                                      size: 18, color: Color(0xFF059669)),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _successMessage!,
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF065F46),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          // Error Banner
                          if (_errorMessage != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF2F2),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFFECACA)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.error_outline_rounded,
                                      size: 18, color: Color(0xFFDC2626)),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _errorMessage!,
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF991B1B),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          // User Selector (if multiple admin accounts exist)
                          if (_adminUsers.length > 1) ...[
                            const Text(
                              'Compte Administrateur',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF64748B),
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<Map<String, dynamic>>(
                                  value: _selectedUser,
                                  isExpanded: true,
                                  items: _adminUsers.map((u) {
                                    final uName = u['full_name'] ?? 'Utilisateur';
                                    final uRole = (u['role'] ?? 'admin').toString();
                                    return DropdownMenuItem(
                                      value: u,
                                      child: Text(
                                        '$uName ($uRole)',
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: _onUserChanged,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          if (_selectedUser == null) ...[
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFFBEB),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFFDE68A)),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.info_outline_rounded,
                                      color: Color(0xFFD97706), size: 20),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Aucun compte administrateur trouvé pour cet établissement.',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: Color(0xFF92400E),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ] else ...[
                            // ── Section 1: Current Credentials Card ──
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 16,
                                        backgroundColor: const Color(0xFFEFF6FF),
                                        child: Text(
                                          (_selectedUser?['full_name'] as String? ?? 'A')
                                              .isNotEmpty
                                              ? (_selectedUser!['full_name'] as String)[0].toUpperCase()
                                              : 'A',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF2563EB),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _selectedUser?['full_name'] ?? 'Directeur',
                                              style: const TextStyle(
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF0F172A),
                                              ),
                                            ),
                                            Text(
                                              'Rôle: ${_selectedUser?['role'] ?? 'owner'}',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Color(0xFF64748B),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                                  const SizedBox(height: 14),

                                  // Email row
                                  const Text(
                                    'EMAIL DE CONNEXION',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF64748B),
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 9),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            border: Border.all(
                                                color: const Color(0xFFCBD5E1)),
                                          ),
                                          child: Text(
                                            _selectedUser?['email'] ?? '—',
                                            style: const TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF1E293B),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        onPressed: () => _copyToClipboard(
                                          _selectedUser?['email'] ?? '',
                                          'Email',
                                        ),
                                        icon: const Icon(Icons.copy_rounded,
                                            size: 18, color: Color(0xFF64748B)),
                                        tooltip: 'Copier l\'email',
                                        splashRadius: 18,
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 14),

                                  // Password row with Unhide Toggle
                                  const Text(
                                    'MOT DE PASSE ACTUEL',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF64748B),
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 9),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            border: Border.all(
                                              color: _showCurrentPassword &&
                                                      _currentPassword.isNotEmpty
                                                  ? const Color(0xFF10B981)
                                                  : const Color(0xFFCBD5E1),
                                              width: _showCurrentPassword &&
                                                      _currentPassword.isNotEmpty
                                                  ? 1.5
                                                  : 1,
                                            ),
                                          ),
                                          child: _currentPassword.isEmpty
                                              ? const Text(
                                                  'Non archivé ou personnalisé (Définissez un nouveau mot de passe)',
                                                  style: TextStyle(
                                                    fontSize: 11.5,
                                                    fontStyle: FontStyle.italic,
                                                    color: Color(0xFF94A3B8),
                                                  ),
                                                )
                                              : Text(
                                                  _showCurrentPassword
                                                      ? _currentPassword
                                                      : '••••••••••••••••',
                                                  style: TextStyle(
                                                    fontSize: _showCurrentPassword
                                                        ? 13
                                                        : 16,
                                                    fontFamily:
                                                        _showCurrentPassword
                                                            ? 'monospace'
                                                            : null,
                                                    fontWeight: FontWeight.w700,
                                                    color: _showCurrentPassword
                                                        ? const Color(0xFF0F172A)
                                                        : const Color(0xFF64748B),
                                                    letterSpacing:
                                                        _showCurrentPassword
                                                            ? 0.5
                                                            : 2,
                                                  ),
                                                ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      // Toggle unhide button
                                      IconButton(
                                        onPressed: _currentPassword.isEmpty
                                            ? null
                                            : () => setState(() =>
                                                _showCurrentPassword =
                                                    !_showCurrentPassword),
                                        icon: Icon(
                                          _showCurrentPassword
                                              ? Icons.visibility_off_rounded
                                              : Icons.visibility_rounded,
                                          size: 19,
                                          color: _currentPassword.isEmpty
                                              ? const Color(0xFFCBD5E1)
                                              : const Color(0xFF6D4CF6),
                                        ),
                                        tooltip: _showCurrentPassword
                                            ? 'Masquer le mot de passe'
                                            : 'Afficher le mot de passe',
                                        splashRadius: 18,
                                      ),
                                      // Copy button
                                      IconButton(
                                        onPressed: _currentPassword.isEmpty
                                            ? null
                                            : () => _copyToClipboard(
                                                  _currentPassword,
                                                  'Mot de passe',
                                                ),
                                        icon: Icon(
                                          Icons.copy_rounded,
                                          size: 18,
                                          color: _currentPassword.isEmpty
                                              ? const Color(0xFFCBD5E1)
                                              : const Color(0xFF64748B),
                                        ),
                                        tooltip: 'Copier le mot de passe',
                                        splashRadius: 18,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 24),

                            // ── Section 2: Change Password ──
                            const Text(
                              'CHANGER LE MOT DE PASSE',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F172A),
                                letterSpacing: 0.6,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Définissez un nouveau mot de passe pour cet établissement à tout moment.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF64748B),
                              ),
                            ),
                            const SizedBox(height: 12),

                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _newPasswordCtrl,
                                    obscureText: !_showNewPassword,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'monospace',
                                    ),
                                    decoration: InputDecoration(
                                      hintText: 'Saisir un nouveau mot de passe...',
                                      hintStyle: const TextStyle(
                                        fontSize: 12.5,
                                        fontFamily: 'sans-serif',
                                        color: Color(0xFF94A3B8),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 14, vertical: 12),
                                      border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(10),
                                        borderSide: const BorderSide(
                                            color: Color(0xFFCBD5E1)),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(10),
                                        borderSide: const BorderSide(
                                            color: Color(0xFFE2E8F0)),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(10),
                                        borderSide: const BorderSide(
                                            color: Color(0xFF6D4CF6),
                                            width: 1.5),
                                      ),
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _showNewPassword
                                              ? Icons.visibility_off_rounded
                                              : Icons.visibility_rounded,
                                          size: 18,
                                          color: const Color(0xFF94A3B8),
                                        ),
                                        onPressed: () => setState(() =>
                                            _showNewPassword = !_showNewPassword),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Generate Password Button
                                OutlinedButton.icon(
                                  onPressed: _generateSecurePassword,
                                  icon: const Icon(Icons.auto_awesome_rounded,
                                      size: 15, color: Color(0xFF7C3AED)),
                                  label: const Text(
                                    'Générer',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF7C3AED),
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 13),
                                    side: const BorderSide(
                                        color: Color(0xFFDDD6FE)),
                                    backgroundColor: const Color(0xFFF5F3FF),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 16),

                            // Submit Button
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _isSaving ? null : _saveNewPassword,
                                icon: _isSaving
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.save_rounded,
                                        size: 18, color: Colors.white),
                                label: Text(
                                  _isSaving
                                      ? 'Mise à jour en cours...'
                                      : 'Enregistrer le nouveau mot de passe',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF6D4CF6),
                                  disabledBackgroundColor:
                                      const Color(0xFFC4B5FD),
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  elevation: 0,
                                ),
                              ),
                            ),
                          ],
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
