import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/l10n/app_localizations.dart';
import '../../../core/services/camera_photo_service.dart';
import '../../../core/theme/arabic_typography.dart';
import '../../../data/services/ai_data_provider.dart';
import '../../../data/services/ai_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/nav_bar_provider.dart';
import '../../../core/utils/file_download_helper.dart';
import '../../widgets/bouncing_wrapper.dart';
import '../../widgets/ios_edge_swipe_back.dart';
import '../../widgets/ios_photo_gallery_viewer.dart';
import '../../../core/services/connectivity_service.dart';
import '../../widgets/ios_bounce_zoom_transition.dart';

// ─── Constants ────────────────────────────────────────────────────────────────
const Color _pink = Color(0xFFFF2D78);
const Color _pinkLight = Color(0xFFFF5CA0);
const String _openRouterApiKey = String.fromEnvironment(
  'OPENROUTER_API_KEY',
  defaultValue: kDefaultOpenRouterApiKey,
);

// Free OpenRouter model (universal auto-fallback router, 99.9% uptime)
const String _freeModel = 'openrouter/free';

// ─── Arabic Typography & Gender Helpers ────────────────────────────────────────
bool _isArabicText(String text) {
  return RegExp(r'[\u0600-\u06FF]').hasMatch(text);
}

/// Detects if a student's first name is feminine (Tunisian / Arab / French names)
bool _isFemaleName(String name) {
  if (name.isEmpty) return false;
  final clean = name.trim().toLowerCase()
      .replaceAll('é', 'e')
      .replaceAll('è', 'e')
      .replaceAll('ê', 'e')
      .replaceAll('ë', 'e')
      .replaceAll('ï', 'i')
      .replaceAll('î', 'i')
      .replaceAll('à', 'a')
      .replaceAll('â', 'a');

  const femaleNames = <String>{
    'nour', 'noor', 'ines', 'inès', 'mariem', 'maryem', 'maryam', 'meriem', 'myriam',
    'sarra', 'sara', 'sarah', 'yasmine', 'yasmina', 'yasmin', 'aya', 'eya',
    'salma', 'selma', 'fatma', 'fatima', 'fatma zahra', 'khadija', 'rym', 'rim',
    'sirine', 'cyrine', 'chaima', 'chayma', 'shayma', 'hela', 'amira', 'manel',
    'rania', 'ons', 'wiem', 'lina', 'maya', 'ghofrane', 'emna', 'dorra', 'farah',
    'asma', 'souhir', 'sonia', 'leila', 'layla', 'hiba', 'nesrine', 'nisrine',
    'nourhene', 'nourhen', 'hadil', 'islem', 'rawen', 'tasnim', 'tasneem',
    'chafia', 'habiba', 'samia', 'nadia', 'hanen', 'sihem', 'sana', 'olfa',
    'mayssa', 'marwa', 'safa', 'soumaya', 'chahd', 'shahd', 'molka', 'roua',
    'lobna', 'ikram', 'afef', 'rahma', 'ghada', 'bochra', 'bouchra', 'emma',
    'lea', 'chloe', 'julie', 'marie', 'sophie', 'camille', 'alice', 'clara',
    'louise', 'manon', 'jade', 'eva', 'zoe', 'lola', 'lena', 'kenza', 'amina',
    'amal', 'amel', 'hanan', 'maha', 'dina', 'rawan', 'reem',
  };

  if (femaleNames.contains(clean)) return true;

  // Arabic characters check (names ending in ة, ى, اء, or common Arabic feminine roots)
  if (name.endsWith('ة') || name.endsWith('ى') || name.endsWith('اء') ||
      name.contains('نور') || name.contains('مريم') || name.contains('إيناس') ||
      name.contains('سارة') || name.contains('فاطمة') || name.contains('خديجة') ||
      name.contains('آية') || name.contains('ياسمين') || name.contains('سلمى') ||
      name.contains('شيماء') || name.contains('ريم') || name.contains('أميرة')) {
    return true;
  }

  if (clean.endsWith('ine') || clean.endsWith('ette') || clean.endsWith('ia') || clean.endsWith('ina')) {
    return true;
  }

  return false;
}

/// Pink flower 🌸 for girls, energetic ⚡ for boys, ✨ fallback
String _getGreetingEmoji(String firstName) {
  if (firstName.isEmpty) return '✨';
  return _isFemaleName(firstName) ? '🌸' : '⚡';
}

/// Intercepts questions about administrative dashboards, school-wide registration,
/// or cross-student queries to prevent hallucinations and strictly enforce privacy (GDPR).
String? _checkPrivacyGuardrail(String userQuery, String languageCode) {
  final q = userQuery.trim().toLowerCase();

  final isCrossStudent =
      // English
      q.contains('smartest student') ||
      q.contains('who is the smartest') ||
      q.contains('best student') ||
      q.contains('top student') ||
      q.contains('how many student') ||
      q.contains('how many stcunet') ||
      q.contains('number of students') ||
      q.contains('other student') ||
      q.contains('another student') ||
      q.contains('all students') ||
      // French
      q.contains('plus intelligent') ||
      q.contains('meilleur eleve') ||
      q.contains('meilleur élève') ||
      q.contains('meilleur etudiant') ||
      q.contains('meilleur étudiant') ||
      q.contains('combien d\'eleve') ||
      q.contains('combien d\'élève') ||
      q.contains('combien d\'etudiant') ||
      q.contains('combien d\'étudiant') ||
      q.contains('combien de eleve') ||
      q.contains('nombre d\'eleve') ||
      q.contains('nombre d\'élève') ||
      q.contains('les autres eleves') ||
      q.contains('les autres élèves') ||
      q.contains('les autres etudiants') ||
      q.contains('les autres étudiants') ||
      q.contains('tous les eleves') ||
      q.contains('tous les élèves') ||
      // Arabic / Derja
      q.contains('أذكى تلميذ') ||
      q.contains('أذكى طالب') ||
      q.contains('اشكون اذكى') ||
      q.contains('chkoune adki') ||
      q.contains('chkoun adka') ||
      q.contains('قدّاش من تلميذ') ||
      q.contains('قداش فما تلامذة');

  final isAdminQuery =
      // English
      q.contains('admin dashboard') ||
      q.contains('registered in the admin') ||
      q.contains('registered in admin') ||
      q.contains('last student registered') ||
      q.contains('admin panel') ||
      q.contains('admin system') ||
      q.contains('admin database') ||
      q.contains('admin credentials') ||
      // French
      q.contains('tableau de bord admin') ||
      q.contains('dans le dashboard') ||
      q.contains('inscrit dans l\'admin') ||
      q.contains('derniere inscription') ||
      q.contains('dernière inscription') ||
      q.contains('dernier eleve inscrit') ||
      q.contains('dernier élève inscrit') ||
      q.contains('panneau admin') ||
      q.contains('base de donnees') ||
      q.contains('base de données');

  if (isCrossStudent || isAdminQuery) {
    if (languageCode == 'ar') {
      return '''🔒 **إشعار الخصوصية وحماية البيانات**
*حماية المعطيات الشخصية*

أنا مساعدك الأكاديمي الشخصي. وفقاً لمعايير الخصوصية وحماية المعطيات الشخصية، لدي وصول حصري إلى **ملفك الدراسي الشخصي فقط**.

ليس لدي **أي وصول** إلى لوحة تحكم الإدارة، ولا إلى ملفات أو أعداد بقية الطلاب أو إحصائيات المدرسة.''';
    } else if (languageCode == 'fr') {
      return '''🔒 **Confidentialité & Protection des Données**
*Respect de la vie privée (RGPD)*

Je suis ton assistant académique personnel. Pour des raisons strictes de confidentialité et de protection des données, j'ai uniquement accès à **ton dossier scolaire personnel**.

Je ne dispose d'**aucun accès** au tableau de bord administrateur, aux dossiers des autres élèves ni aux effectifs globaux de l'établissement.''';
    } else {
      return '''🔒 **Privacy & Data Protection Notice**
*Student Data Confidentiality (GDPR)*

I am your personal academic assistant. For privacy and data protection reasons, I only have access to **your personal academic records**.

I have **zero access** to administrative dashboards, other students' files, or school-wide student statistics.''';
    }
  }

  return null;
}

TextStyle _aiTextStyle(
  BuildContext context, {
  required String text,
  double fontSize = 14.5,
  FontWeight fontWeight = FontWeight.w400,
  Color? color,
  double? height,
  double? letterSpacing,
  FontStyle? fontStyle,
  TextDecoration? decoration,
  Color? decorationColor,
}) {
  final hasArabic = _isArabicText(text) || Directionality.of(context) == TextDirection.rtl;
  if (hasArabic) {
    return GoogleFonts.tajawal(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height ?? 1.5,
      letterSpacing: letterSpacing,
      fontStyle: fontStyle,
      decoration: decoration,
      decorationColor: decorationColor,
    );
  }
  return TextStyle(
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    height: height ?? 1.5,
    letterSpacing: letterSpacing,
    fontStyle: fontStyle,
    decoration: decoration,
    decorationColor: decorationColor,
  );
}


// ─── Data Models ──────────────────────────────────────────────────────────────
class _ConversationMessage {
  final String id;
  final String role;
  final String content;
  final DateTime timestamp;
  final String? attachedFileName;
  final String? attachedImagePath;

  const _ConversationMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.attachedFileName,
    this.attachedImagePath,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
        if (attachedFileName != null) 'attachedFileName': attachedFileName,
        if (attachedImagePath != null) 'attachedImagePath': attachedImagePath,
      };

  factory _ConversationMessage.fromJson(Map<String, dynamic> json) =>
      _ConversationMessage(
        id: json['id'] as String,
        role: json['role'] as String,
        content: json['content'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        attachedFileName: json['attachedFileName'] as String?,
        attachedImagePath: json['attachedImagePath'] as String?,
      );
}

class _Conversation {
  final String id;
  String title;
  List<_ConversationMessage> messages;
  DateTime updatedAt;

  _Conversation({
    required this.id,
    required this.title,
    required this.messages,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'messages': messages.map((m) => m.toJson()).toList(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory _Conversation.fromJson(Map<String, dynamic> json) => _Conversation(
        id: json['id'] as String,
        title: json['title'] as String,
        messages: (json['messages'] as List)
            .map((m) => _ConversationMessage.fromJson(m as Map<String, dynamic>))
            .toList(),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
}

class _ChatMessage {
  final String id;
  final String role;
  final String content;
  final DateTime timestamp;
  final String? attachedFileName;
  final String? attachedImagePath;

  const _ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.attachedFileName,
    this.attachedImagePath,
  });
}

// ─── Screen ───────────────────────────────────────────────────────────────────
class AIChatScreen extends ConsumerStatefulWidget {
  const AIChatScreen({super.key});

  @override
  ConsumerState<AIChatScreen> createState() => _AIChatScreenState();
}

class _AIChatScreenState extends ConsumerState<AIChatScreen>
    with TickerProviderStateMixin {
  final List<_ChatMessage> _messages = [];
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocus = FocusNode();

  bool _isTyping = false;

  // Attach modal
  String? _pendingFileText;   // extracted text from file
  String? _pendingFileName;   // original file name
  XFile? _pendingImage;       // image for display only

  // History panel
  bool _showHistory = false;
  List<_Conversation> _conversations = [];
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  String? _currentConversationId;

  // Typing animation
  late AnimationController _typingAnimCtrl;
  late Animation<double> _typingAnim;

  // Suggestions state & iOS animation
  late AnimationController _suggestionsAnimCtrl;
  int _suggestionBatchIndex = 0;

  // Cached snapshot & greeting cache
  StudentAISnapshot? _cachedSnapshot;
  static String? _cachedStudentFirstName;
  static String? _cachedWelcomeGreeting;

  // Persistent active session cache so ongoing conversation & scroll offset are never lost
  static List<_ChatMessage>? _activeSessionMessages;
  static String? _activeSessionConversationId;
  static double? _activeSessionScrollOffset;

  static void syncActiveSession(List<_ChatMessage> messages, String? convId, [double? scrollOffset]) {
    if (messages.isNotEmpty) {
      _activeSessionMessages = List.from(messages);
      _activeSessionConversationId = convId;
      if (scrollOffset != null) {
        _activeSessionScrollOffset = scrollOffset;
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _typingAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _typingAnim = CurvedAnimation(parent: _typingAnimCtrl, curve: Curves.easeInOut);
    _typingAnimCtrl.repeat(reverse: true);

    _suggestionsAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _suggestionsAnimCtrl.forward();

    _inputFocus.addListener(() {
      if (_inputFocus.hasFocus) {
        _scrollToBottom();
      }
    });

    SharedPreferences.getInstance().then((prefs) {
      final savedName = prefs.getString('cached_student_first_name');
      if (savedName != null && savedName.isNotEmpty) {
        _cachedStudentFirstName = savedName;
      }
    });

    if (_activeSessionMessages != null && _activeSessionMessages!.isNotEmpty) {
      _messages.addAll(_activeSessionMessages!);
      _currentConversationId = _activeSessionConversationId;
      if (_activeSessionScrollOffset != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scrollController.hasClients && _activeSessionScrollOffset != null) {
            _scrollController.jumpTo(_activeSessionScrollOffset!);
          }
        });
      }
    }

    _loadConversations();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initAI();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Render initial cached greeting message immediately on mount without waiting for network
    if (_messages.isEmpty && _currentConversationId == null && (_activeSessionMessages == null || _activeSessionMessages!.isEmpty)) {
      final authName = ref.read(authProvider).user?.fullName.split(' ').first;
      final name = authName ?? _cachedStudentFirstName ?? '';
      if (name.isNotEmpty) {
        _cachedStudentFirstName = name;
      }
      final greeting = _cachedWelcomeGreeting ?? _buildWelcomeMessage(name);
      _cachedWelcomeGreeting = greeting;
      _messages.add(_ChatMessage(
        id: 'welcome',
        role: 'assistant',
        content: greeting,
        timestamp: DateTime.now(),
      ));
    }
  }

  void _openHistory() {
    setState(() => _showHistory = true);
    _loadConversations();
    ref.read(backSwipeInterceptorProvider.notifier).state = () {
      _closeHistory();
      return true;
    };
  }

  void _closeHistory() {
    FocusScope.of(context).unfocus();
    ref.read(backSwipeInterceptorProvider.notifier).state = null;
    setState(() => _showHistory = false);
  }

  Future<void> _initAI() async {
    if (!mounted) return;
    try {
      // Pre-fetch snapshot in background (will be ready when first message sent)
      final snapshot = await ref.read(studentAISnapshotProvider.future);
      _cachedSnapshot = snapshot;
      final fullName = snapshot.studentContext?.fullName;
      if (fullName != null && fullName.isNotEmpty) {
        final firstName = fullName.split(' ').first;
        if (firstName.isNotEmpty) {
          _cachedStudentFirstName = firstName;
          SharedPreferences.getInstance().then((prefs) {
            prefs.setString('cached_student_first_name', firstName);
          });
          // Update welcome greeting if needed
          if (_messages.isNotEmpty &&
              _messages.first.id == 'welcome' &&
              !_messages.first.content.contains(firstName)) {
            final updatedGreeting = _buildWelcomeMessage(firstName);
            _cachedWelcomeGreeting = updatedGreeting;
            setState(() {
              _messages[0] = _ChatMessage(
                id: 'welcome',
                role: 'assistant',
                content: updatedGreeting,
                timestamp: _messages.first.timestamp,
              );
            });
          }
        }
      }
    } catch (_) {}
    if (!mounted) return;
    if (_messages.isEmpty && _currentConversationId == null) {
      _addWelcome();
    }
  }

  // ─── Conversation Persistence ───────────────────────────────────────────────
  Future<void> _loadConversations() async {
    if (kIsWeb) return;
    try {
      final dir = await getConversationDir();
      final files = dir.listSync().whereType<File>().toList();
      final convs = <_Conversation>[];
      for (final f in files) {
        try {
          final data = jsonDecode(await f.readAsString());
          convs.add(_Conversation.fromJson(data as Map<String, dynamic>));
        } catch (_) {}
      }
      convs.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      if (mounted) setState(() => _conversations = convs);
    } catch (_) {}
  }

  Future<void> _saveCurrentConversation() async {
    if (kIsWeb) return;
    if (_messages.isEmpty) return;
    final convId = _currentConversationId ??
        DateTime.now().millisecondsSinceEpoch.toString();
    _currentConversationId ??= convId;
    final firstUser = _messages.firstWhere(
      (m) => m.role == 'user',
      orElse: () => _messages.first,
    );
    final title = firstUser.content.length > 45
        ? '${firstUser.content.substring(0, 45)}...'
        : firstUser.content;
    final conv = _Conversation(
      id: convId,
      title: title,
      messages: _messages
          .map((m) => _ConversationMessage(
                id: m.id,
                role: m.role,
                content: m.content,
                timestamp: m.timestamp,
              ))
          .toList(),
      updatedAt: DateTime.now(),
    );
    final dir = await getConversationDir();
    await File('${dir.path}/$convId.json').writeAsString(jsonEncode(conv.toJson()));
    final idx = _conversations.indexWhere((c) => c.id == convId);
    if (idx >= 0) {
      _conversations[idx] = conv;
    } else {
      _conversations.insert(0, conv);
    }
    _conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (mounted) setState(() {});
  }

  Future<void> _deleteConversation(String id) async {
    final conv = _conversations.firstWhere((c) => c.id == id);
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (ctx) => _DeleteDialog(title: conv.title),
    );
    if (confirmed != true) return;
    try {
      final dir = await getConversationDir();
      final file = File('${dir.path}/$id.json');
      if (file.existsSync()) await file.delete();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _conversations.removeWhere((c) => c.id == id);
        if (_currentConversationId == id) {
          _currentConversationId = null;
          _startNewChat();
        }
      });
    }
  }

  void _loadConversation(_Conversation conv) {
    setState(() {
      _messages.clear();
      for (final m in conv.messages) {
        _messages.add(_ChatMessage(
          id: m.id,
          role: m.role,
          content: m.content,
          timestamp: m.timestamp,
          attachedFileName: m.attachedFileName,
          attachedImagePath: m.attachedImagePath,
        ));
      }
      _currentConversationId = conv.id;
      syncActiveSession(_messages, _currentConversationId, 0.0);
      _showHistory = false;
      ref.read(backSwipeInterceptorProvider.notifier).state = null;
    });
    _scrollToBottom();
  }

  void _addWelcome() {
    if (_messages.isNotEmpty) return;
    final authName = ref.read(authProvider).user?.fullName.split(' ').first;
    final name = _cachedSnapshot?.studentContext?.fullName?.split(' ').first ??
        authName ??
        _cachedStudentFirstName ??
        '';
    if (name.isNotEmpty) {
      _cachedStudentFirstName = name;
    }
    final greeting = _buildWelcomeMessage(name);
    _cachedWelcomeGreeting = greeting;
    setState(() {
      _messages.add(_ChatMessage(
        id: 'welcome',
        role: 'assistant',
        content: greeting,
        timestamp: DateTime.now(),
      ));
    });
  }

  String _buildWelcomeMessage(String firstName) {
    final lang = Localizations.localeOf(context).languageCode;
    final name = firstName.isNotEmpty ? ', $firstName' : '';
    final emoji = _getGreetingEmoji(firstName);

    if (lang == 'ar') {
      return '''## مرحباً$name ! $emoji

أنا **NOVA**، مساعدك الأكاديمي الذكي.

لدي وصول **كامل** إلى بياناتك المدرسية — الأعداد والنتائج، جدول الأوقات، الغيابات، والإشعارات.

> 💡 اسألني أي سؤال أو أرسل ملفاً لتحليله.

### كيف يمكنني مساعدتك اليوم؟''';
    } else if (lang == 'fr') {
      return '''## Bonjour$name ! $emoji

Je suis **NOVA**, ton assistant académique intelligent.

J'ai accès **complet** à tes données scolaires — notes, emploi du temps, absences, notifications, et documents.

> 💡 Pose-moi n'importe quelle question ou envoie un fichier à analyser.

### Comment puis-je t'aider aujourd'hui ?''';
    } else {
      return '''## Hello$name! $emoji

I'm **NOVA**, your smart academic assistant.

I have **complete** access to your academic data — grades, timetable, absences, notifications, and documents.

> 💡 Ask me any question or upload a file to analyze.

### How can I help you today?''';
    }
  }

  // ─── Messaging ──────────────────────────────────────────────────────────────
  void _sendMessage(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty && _pendingFileText == null && _pendingImage == null) return;

    final fileName = _pendingFileName;
    final fileText = _pendingFileText;
    final imagePath = _pendingImage?.path;

    String displayContent = trimmed;
    if (fileName != null) {
      displayContent = trimmed.isEmpty
          ? '📎 $fileName'
          : '$trimmed\n\n📎 $fileName';
    }

    final ts = DateTime.now();
    setState(() {
      _messages.add(_ChatMessage(
        id: ts.millisecondsSinceEpoch.toString(),
        role: 'user',
        content: displayContent,
        timestamp: ts,
        attachedFileName: fileName,
        attachedImagePath: imagePath,
      ));
      syncActiveSession(_messages, _currentConversationId);
      _isTyping = true;
      _inputController.clear();
      _pendingFileText = null;
      _pendingFileName = null;
      _pendingImage = null;
    });
    _scrollToBottom();
    _callOpenRouter(userDisplayContent: displayContent, fileText: fileText);
  }

  Future<void> _callOpenRouter({
    required String userDisplayContent,
    String? fileText,
  }) async {
    // Dynamically detect user's input language (supports mid-conversation language switching)
    String effectiveLang = Localizations.localeOf(context).languageCode;
    final cleanQuery = userDisplayContent.trim().toLowerCase();
    if (RegExp(r'[\u0600-\u06FF]').hasMatch(userDisplayContent)) {
      effectiveLang = 'ar';
    } else if (RegExp(r'\b(list|all|my|material|results|what|is|the|schedule|balance|grades|how|when|where|who|why|grade|result)\b')
        .hasMatch(cleanQuery)) {
      effectiveLang = 'en';
    } else if (RegExp(r'\b(donne|affiche|mes|mon|ma|notes|cours|quel|quelle|quels|quelles|combien|solde|bonjour|salut)\b')
        .hasMatch(cleanQuery)) {
      effectiveLang = 'fr';
    }

    // Deterministic Privacy Guardrail: Strictly prevent cross-student queries & admin dashboard hallucinations
    final privacyRefusal = _checkPrivacyGuardrail(userDisplayContent, effectiveLang);
    if (privacyRefusal != null) {
      if (!mounted) return;
      final ts = DateTime.now();
      setState(() {
        _isTyping = false;
        _messages.add(_ChatMessage(
          id: ts.millisecondsSinceEpoch.toString(),
          role: 'assistant',
          content: privacyRefusal,
          timestamp: ts,
        ));
        syncActiveSession(_messages, _currentConversationId);
      });
      _scrollToBottom();
      _saveCurrentConversation();
      return;
    }

    try {
      // Always ensure snapshot is fresh from database
      try {
        _cachedSnapshot = await ref.refresh(studentAISnapshotProvider.future);
      } catch (_) {
        _cachedSnapshot ??= await ref.read(studentAISnapshotProvider.future);
      }
      final snapshot = _cachedSnapshot!;

      final pastMemory = _buildPastConversationsMemory();
      final systemPrompt = buildSystemPrompt(
        snapshot: snapshot,
        languageCode: effectiveLang,
        conversationMemory: pastMemory.isNotEmpty ? pastMemory : null,
      );

      // Build history excluding welcome message
      final history = _messages
          .where((m) => m.id != 'welcome')
          .map((m) => formatMessageForAPI(
                role: m.role,
                content: m.content,
                fileText: m.id == _messages.last.id ? fileText : null,
              ))
          .toList();

      final reply = await callOpenRouter(
        apiKey: _openRouterApiKey,
        systemPrompt: systemPrompt,
        history: history,
        model: _freeModel,
        snapshot: snapshot,
        userQuery: userDisplayContent,
        languageCode: effectiveLang,
      );

      if (!mounted) return;
      final ts = DateTime.now();
      final cleanedReply = _sanitizeAiReply(reply);
      setState(() {
        _isTyping = false;
        _messages.add(_ChatMessage(
          id: ts.millisecondsSinceEpoch.toString(),
          role: 'assistant',
          content: cleanedReply,
          timestamp: ts,
        ));
        syncActiveSession(_messages, _currentConversationId);
      });
      _scrollToBottom();
      _saveCurrentConversation();
    } catch (e, st) {
      debugPrint('Error calling AI service: $e\n$st');
      if (!mounted) return;
      final errStr = e.toString().toLowerCase();
      final isOffline = ConnectivityService.instance.isOffline ||
          errStr.contains('socketexception') ||
          errStr.contains('failed host lookup') ||
          errStr.contains('network is unreachable');
      final isQuota = errStr.contains('429') ||
          errStr.contains('quota') ||
          errStr.contains('limite');
      final isMaintenance = errStr.contains('maintenance');
      final isConfigError = errStr.contains('clé api') ||
          errStr.contains('api key') ||
          errStr.contains('user not found') ||
          errStr.contains('non configurée');

      String errorMessage;
      if (isOffline) {
        errorMessage = effectiveLang == 'ar'
            ? '⚠️ لا يوجد اتصال بالإنترنت. يرجى التحقق من اتصالك والمحاولة مرة أخرى.'
            : (effectiveLang == 'fr'
                ? '⚠️ Pas de connexion internet. Vérifie ta connexion et réessaie.'
                : '⚠️ No internet connection. Please check your network and try again.');
      } else if (isQuota) {
        errorMessage = effectiveLang == 'ar'
            ? '⏳ تم بلوغ الحد اليومي لرسائل المساعد الذكي. نلتقي غداً!'
            : (effectiveLang == 'fr'
                ? '⏳ Quota de messages IA atteint. Rendez-vous demain !'
                : '⏳ Daily AI message limit reached. See you tomorrow!');
      } else if (isMaintenance) {
        errorMessage = effectiveLang == 'ar'
            ? '🛠️ خدمة المساعد الذكي في صيانة حالياً. يرجى المحاولة لاحقاً.'
            : (effectiveLang == 'fr'
                ? '🛠️ Le service IA NOVA est temporairement en maintenance. Merci de réessayer plus tard.'
                : '🛠️ AI service is temporarily undergoing maintenance. Please try again later.');
      } else if (isConfigError) {
        errorMessage = effectiveLang == 'ar'
            ? '⚠️ مفتاح خدمة الذكاء الاصطناعي منتهي أو غير صالح. يرجى إعلام الإدارة لتحديثه.'
            : (effectiveLang == 'fr'
                ? '⚠️ La clé du service IA OpenRouter est expirée ou invalide. Veuillez mettre à jour la clé OPENROUTER_API_KEY dans Supabase.'
                : '⚠️ AI service API key is expired or invalid. Please update OPENROUTER_API_KEY in Supabase secrets.');
      } else {
        errorMessage = effectiveLang == 'ar'
            ? '⚠️ تعذر على المساعد الذكي الإجابة حالياً. يرجى إعادة المحاولة في لحظات.'
            : (effectiveLang == 'fr'
                ? '⚠️ Impossible d\'obtenir une réponse du modèle IA pour le moment. Veuillez réessayer dans un instant.'
                : '⚠️ Unable to get a response from the AI model at this moment. Please try again shortly.');
      }

      final ts = DateTime.now();
      setState(() {
        _isTyping = false;
        _messages.add(_ChatMessage(
          id: ts.millisecondsSinceEpoch.toString(),
          role: 'assistant',
          content: errorMessage,
          timestamp: ts,
        ));
        syncActiveSession(_messages, _currentConversationId);
      });
      _scrollToBottom();
      _saveCurrentConversation();
    }
  }

  String _buildPastConversationsMemory() {
    if (_conversations.isEmpty) return '';
    final sb = StringBuffer();
    int count = 0;
    for (final c in _conversations) {
      if (c.id == _currentConversationId) continue;
      final userMsgs = c.messages.where((m) => m.role == 'user').toList();
      final aiMsgs = c.messages.where((m) => m.role == 'assistant').toList();
      if (userMsgs.isEmpty) continue;

      final lastUserMsg = userMsgs.last.content.replaceAll('\n', ' ').trim();
      final cleanUser = lastUserMsg.length > 90 ? '${lastUserMsg.substring(0, 90)}...' : lastUserMsg;

      String cleanAi = '';
      if (aiMsgs.isNotEmpty) {
        final rawAi = aiMsgs.last.content.split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '').trim();
        cleanAi = rawAi.length > 90 ? '${rawAi.substring(0, 90)}...' : rawAi;
      }

      sb.writeln('- Topic "${c.title}": Student asked: "$cleanUser"${cleanAi.isNotEmpty ? ' -> Response: "$cleanAi"' : ''}');
      count++;
      if (count >= 5) break;
    }
    return sb.toString().trim();
  }

  String _sanitizeAiReply(String reply) {
    var cleaned = reply.trim();
    // Strip leading student email / name header lines like:
    // "👤 Nour El Houda Khalil | ✉️ nour.new06@school.tn"
    // "👤 Nour El Houda Khalil"
    final headerRegex = RegExp(r'^(?:👤[^\n|]+(?:\|\s*✉️[^\n]+)?|👤[^\n]+)\s*\n*', multiLine: false);
    cleaned = cleaned.replaceFirst(headerRegex, '').trim();

    while (cleaned.startsWith('👤')) {
      final firstNewline = cleaned.indexOf('\n');
      if (firstNewline != -1) {
        cleaned = cleaned.substring(firstNewline + 1).trim();
      } else {
        break;
      }
    }
    return cleaned;
  }



  void _scrollToBottom({int delayMs = 60}) {
    Future.delayed(Duration(milliseconds: delayMs), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  // ─── File Attachment ─────────────────────────────────────────────────────────
  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
      if (result != null && result.files.isNotEmpty && mounted) {
        final file = result.files.first;
        final (name, text) = await FileTextExtractor.extract(file);
        setState(() {
          _pendingFileName = name;
          _pendingFileText = text;
          _pendingImage = null;
        });
      }
    } catch (_) {}
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final image = await CameraPhotoService.pickPhoto(
        context: context,
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
      );
      if (image != null && mounted) {
        // Convert image to text description for the AI
        setState(() {
          _pendingImage = image;
          _pendingFileName = image.name;
          _pendingFileText =
              '[Image attached: ${image.name}] — The student has attached an image. Please ask them to describe it if you need to analyze its content, as image vision is not available in this mode.';
        });
      }
    } catch (_) {}
  }

  void _clearAttachment() {
    setState(() {
      _pendingFileText = null;
      _pendingFileName = null;
      _pendingImage = null;
    });
  }

  // ─── Quick Prompts Pool & Selection (3 distinct items each time) ────────────
  List<String> _getPromptsPool(String lang) {
    if (lang == 'ar') {
      return [
        // Batch 1
        '📊 ما هو معدلي العام؟',
        '📅 ما هو جدولي غداً؟',
        '⚠️ كم غياباً لديّ؟',
        // Batch 2
        '💰 ما وضعي المالي ورصيدي؟',
        '📢 ما هي آخر الإعلانات؟',
        '📚 ما هي أفضل مادة عندي؟',
        // Batch 3
        '🕒 متى تبدأ حصتي القادمة؟',
        '📄 ما هي الوثائق التي يمكنني طلبها؟',
        '📉 ما هي المواد التي تحتاج مراجعة؟',
      ];
    } else if (lang == 'fr') {
      return [
        // Batch 1
        '📊 Quelle est ma moyenne générale ?',
        '📅 Quel est mon emploi du temps demain ?',
        '⚠️ Combien d\'absences ai-je ?',
        // Batch 2
        '💰 Quel est mon solde actuel ?',
        '📢 Quelles sont les dernières annonces ?',
        '📚 Quelle est ma meilleure matière ?',
        // Batch 3
        '🕒 À quelle heure commence mon prochain cours ?',
        '📄 Quels documents puis-je demander ?',
        '📉 Quelles matières dois-je réviser ?',
      ];
    } else {
      return [
        // Batch 1
        '📊 What\'s my overall average?',
        '📅 What\'s my schedule tomorrow?',
        '⚠️ How many absences do I have?',
        // Batch 2
        '💰 What is my payment balance?',
        '📢 What are the latest announcements?',
        '📚 Which subject am I best at?',
        // Batch 3
        '🕒 When is my next class?',
        '📄 What documents can I request?',
        '📉 Which subjects should I review?',
      ];
    }
  }

  List<String> _getThreeSuggestions() {
    final lang = Localizations.localeOf(context).languageCode;
    final pool = _getPromptsPool(lang);
    final totalBatches = pool.length ~/ 3;
    final batch = _suggestionBatchIndex % totalBatches;
    final startIndex = batch * 3;
    return pool.sublist(startIndex, startIndex + 3);
  }

  void _startNewChat() {
    _activeSessionMessages = null;
    _activeSessionConversationId = null;
    _activeSessionScrollOffset = null;
    _currentConversationId = null;
    _searchQuery = '';
    _searchController.clear();
    _suggestionBatchIndex++;
    _suggestionsAnimCtrl.forward(from: 0.0);
    setState(() {
      _messages.clear();
      _addWelcome();
    });
  }

  @override
  void dispose() {
    if (_messages.isNotEmpty) {
      _activeSessionMessages = List.from(_messages);
      _activeSessionConversationId = _currentConversationId;
      if (_scrollController.hasClients) {
        _activeSessionScrollOffset = _scrollController.offset;
      }
    }
    if (_showHistory) {
      ref.read(backSwipeInterceptorProvider.notifier).state = null;
    }
    _inputController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    _typingAnimCtrl.dispose();
    _suggestionsAnimCtrl.dispose();
    super.dispose();
  }

  // ─── Build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final screenWidth = MediaQuery.of(context).size.width;
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    // Show quick prompts only when there's only the welcome message
    final showQuickPrompts = _messages.length == 1 &&
        _messages.first.role == 'assistant' &&
        !_isTyping;

    // Build items in reverse order so index 0 is newest and anchored at bottom
    final List<Widget> listItems = [];
    if (_isTyping) {
      listItems.add(_TypingIndicator(listenable: _typingAnim));
    }
    for (int i = _messages.length - 1; i >= 0; i--) {
      if (showQuickPrompts && i == 0) {
        listItems.add(_buildQuickPrompts());
      }
      listItems.add(_MessageBubble(message: _messages[i]));
    }

    return PopScope(
      canPop: !_showHistory,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _showHistory) {
          _closeHistory();
          return;
        }
        if (didPop) {
                  }
      },
      child: Stack(
        children: [
          // Main Chat Area (blurred when history open)
          ImageFiltered(
            enabled: _showHistory,
            imageFilter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Scaffold(
              resizeToAvoidBottomInset: false,
              body: Container(
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
                child: SafeArea(
                  top: false,
                  bottom: false,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: Column(
                        children: [
                          // Top Bar with safe spacing
                          Padding(
                            padding: EdgeInsets.only(
                              top: topPadding + 8,
                              left: 16,
                              right: 16,
                              bottom: 6,
                            ),
                            child: _buildTopBar(),
                          ),

                          // Messages List - reverse: true anchors newest messages right above input bar
                          // Wrapped in LTR Directionality so Arabic chat is never mirrored (keeps same layout as Latin)
                          Expanded(
                            child: ClipRect(
                              child: Directionality(
                                textDirection: TextDirection.ltr,
                                child: ScrollConfiguration(
                                  behavior: const ScrollBehavior().copyWith(
                                    overscroll: false,
                                    physics: const BouncingScrollPhysics(
                                      parent: AlwaysScrollableScrollPhysics(),
                                    ),
                                  ),
                                  child: GestureDetector(
                                    onTap: () => FocusScope.of(context).unfocus(),
                                    behavior: HitTestBehavior.translucent,
                                    child: ListView.builder(
                                      controller: _scrollController,
                                      reverse: true,
                                      physics: const BouncingScrollPhysics(
                                        parent: AlwaysScrollableScrollPhysics(),
                                      ),
                                      keyboardDismissBehavior:
                                          ScrollViewKeyboardDismissBehavior.onDrag,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 8,
                                      ),
                                      itemCount: listItems.length,
                                      itemBuilder: (context, index) => listItems[index],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // Attachment preview
                          if (_pendingFileName != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 4),
                              child: _buildAttachmentPreview(),
                            ),

                          // Bottom Input Bar - direct child of Column with keyboard clearance
                          Builder(
                            builder: (context) {
                              final bottomInset = MediaQuery.of(context).padding.bottom;
                              final viewInsetsBottom =
                                  MediaQuery.of(context).viewInsets.bottom;
                              final isKeyboardOpen = viewInsetsBottom > 50;
                              final bottomPadding = isKeyboardOpen
                                  ? (viewInsetsBottom + 14.0)
                                  : (bottomInset > 0 ? bottomInset + 4.0 : 12.0);

                              return Padding(
                                padding: EdgeInsets.fromLTRB(16, 2, 16, bottomPadding),
                                child: Center(
                                  child: Container(
                                    constraints:
                                        const BoxConstraints(maxWidth: 600),
                                    child: _buildInputBar(isRtl),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // History sidebar overlay
          IgnorePointer(
            ignoring: !_showHistory,
            child: AnimatedOpacity(
              opacity: _showHistory ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              child: GestureDetector(
                onTap: _closeHistory,
                child: Container(color: Colors.black.withValues(alpha: 0.25)),
              ),
            ),
          ),
          // Edge drag gesture to open history drawer from the opposite edge of the screen exit gesture
          if (!_showHistory)
            Positioned(
              left: isRtl ? 0 : null,
              right: isRtl ? null : 0,
              top: 0,
              bottom: 0,
              width: 35,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: (details) {
                  if (isRtl) {
                    if ((details.primaryDelta ?? 0) > 8) _openHistory();
                  } else {
                    if ((details.primaryDelta ?? 0) < -8) _openHistory();
                  }
                },
              ),
            ),

          AnimatedPositioned(
            left: isRtl ? (_showHistory ? 0 : -screenWidth * 0.82) : null,
            right: isRtl ? null : (_showHistory ? 0 : -screenWidth * 0.82),
            top: 0,
            bottom: 0,
            width: screenWidth * 0.82,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            child: GestureDetector(
              onHorizontalDragUpdate: (details) {
                if (isRtl) {
                  if ((details.primaryDelta ?? 0) < -8) _closeHistory();
                } else {
                  if ((details.primaryDelta ?? 0) > 8) _closeHistory();
                }
              },
              child: ClipRRect(
                borderRadius: BorderRadius.zero,
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.65),
                      border: Border(
                        left: isRtl
                            ? BorderSide.none
                            : BorderSide(
                                color: Colors.white.withValues(alpha: 0.3),
                                width: 1,
                              ),
                        right: isRtl
                            ? BorderSide(
                                color: Colors.white.withValues(alpha: 0.3),
                                width: 1,
                              )
                            : BorderSide.none,
                      ),
                    ),
                    child: SafeArea(
                      top: true,
                      bottom: false,
                      child: Material(
                        type: MaterialType.transparency,
                        child: _buildHistoryPanel(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

        ],
      ),
    );
  }

  // ─── Widgets ─────────────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    final l10n = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(44),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7A8698).withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(44),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(44),
            ),
            child: Row(
              children: [
                // Back
                GestureDetector(
                  onTap: () {
                    final swipeBack = IosEdgeSwipeBack.of(context);
                    if (swipeBack != null) {
                      swipeBack.animateBack();
                    } else if (context.canPop()) {
                      context.pop();
                    } else {
                      final origin = ref.read(aiChatOriginRouteProvider);
                      context.go(origin);
                    }
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: Icon(
                        Directionality.of(context) == TextDirection.rtl
                            ? Icons.arrow_forward_ios_rounded
                            : Icons.arrow_back_ios_new_rounded,
                        color: const Color(0xFF475569),
                        size: 20,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // NOVA avatar
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [_pink, _pinkLight],
                    ),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'NOVA',
                        style: ArabicTypography.headerStyle(
                          context,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF1E293B),
                        ),
                      ),
                      Text(
                        _isTyping
                            ? l10n.translate('ai_thinking')
                            : l10n.translate('ai_assistant_role'),
                        style: ArabicTypography.bodyStyle(
                          context,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: _pink,
                        ),
                      ),
                    ],
                  ),
                ),
                // History
                BouncingWrapper(
                  shrinkScale: 0.88,
                  onTap: _openHistory,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFF1F5F9).withValues(alpha: 0.5),
                    ),
                    child: const Icon(Icons.menu_rounded,
                        color: Color(0xFF64748B), size: 20),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickPrompts() {
    final suggestions = _getThreeSuggestions();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(suggestions.length, (index) {
          final p = suggestions[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _AnimatedSuggestionChip(
              key: ValueKey('${_suggestionBatchIndex}_$index'),
              text: p,
              index: index,
              controller: _suggestionsAnimCtrl,
              onTap: () {
                _inputController.text = p;
                _sendMessage(p);
              },
            ),
          );
        }),
      ),
    );
  }

  Widget _buildAttachmentPreview() {
    if (_pendingImage != null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              GestureDetector(
                onTap: () => _showExpandedImage(context, _pendingImage!.path),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.file(
                      File(_pendingImage!.path),
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _fileIcon(),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: -6,
                right: -6,
                child: GestureDetector(
                  onTap: _clearAttachment,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _fileIcon(),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              _pendingFileName ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ArabicTypography.bodyStyle(
                context,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1E293B),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _clearAttachment,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close_rounded,
                size: 16,
                color: Color(0xFF64748B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fileIcon() {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: const Color(0xFF6366F1).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(Icons.insert_drive_file_rounded, color: Color(0xFF6366F1), size: 20),
    );
  }

  Widget _buildInputBar(bool isRtl) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(36),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7A8698).withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(36),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(36),
            ),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Row(
                children: [
                  // Attach button (on the left)
                  BouncingWrapper(
                    shrinkScale: 0.86,
                    overshootScale: 1.10,
                    delayNavigation: false,
                    hitPadding: const EdgeInsets.all(8),
                    onTap: () {
                      FocusScope.of(context).unfocus();
                      _showAttachDialog(context);
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFFF1F5F9),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(Icons.add, size: 22, color: Color(0xFF64748B)),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Text input (middle)
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      focusNode: _inputFocus,
                      textInputAction: TextInputAction.send,
                      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
                      textAlign: isRtl ? TextAlign.right : TextAlign.left,
                      maxLines: 5,
                      minLines: 1,
                      style: _aiTextStyle(
                        context,
                        text: _inputController.text.isNotEmpty
                            ? _inputController.text
                            : (isRtl ? 'ع' : ''),
                        fontSize: 15,
                        color: const Color(0xFF475569),
                      ),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.transparent,
                        border: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        hintText: AppLocalizations.of(context)
                            .translate('ask_ai_question_hint'),
                        hintStyle: _aiTextStyle(
                          context,
                          text: AppLocalizations.of(context)
                              .translate('ask_ai_question_hint'),
                          fontSize: 14,
                          color: const Color(0xFF94A3B8),
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 10),
                        isDense: true,
                      ),
                      onSubmitted: (val) => _sendMessage(val),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  // Bouncing Send button (on the right)
                  _BouncingSendButton(
                    enabled: (_inputController.text.trim().isNotEmpty ||
                                _pendingFileText != null) &&
                            !_isTyping,
                    onTap: () => _sendMessage(_inputController.text),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showAttachDialog(BuildContext ctx) {
    final l10n = AppLocalizations.of(ctx);
    showGeneralDialog(
      context: ctx,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black.withValues(alpha: 0.35),
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (dialogCtx, animation, secondaryAnimation) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Material(
              type: MaterialType.transparency,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.6),
                        width: 1.5,
                      ),
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
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Padding(
                              padding: const EdgeInsetsDirectional.only(start: 20),
                              child: Text(
                                l10n.translate('attach_title'),
                                style: ArabicTypography.headerStyle(
                                  dialogCtx,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF1E293B),
                                  letterSpacing: -0.3,
                                ).copyWith(decoration: TextDecoration.none),
                              ),
                            ),
                            BouncingWrapper(
                              shrinkScale: 0.86,
                              overshootScale: 1.10,
                              delayNavigation: false,
                              hitPadding: const EdgeInsets.all(12),
                              onTap: () => Navigator.of(dialogCtx).pop(),
                              child: Container(
                                width: 36,
                                height: 36,
                                margin: const EdgeInsetsDirectional.only(end: 16),
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Color(0xFFF1F5F9),
                                ),
                                child: const Icon(
                                  Icons.close_rounded,
                                  size: 20,
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _AttachOption(
                          icon: Icons.insert_drive_file_outlined,
                          iconColor: Colors.white,
                          bgColor: const Color(0xFF6366F1),
                          title: 'Document / PDF',
                          subtitle: 'PDF, DOCX, TXT, CSV...',
                          onTap: () {
                            Navigator.of(dialogCtx).pop();
                            _pickFile();
                          },
                        ),
                        _AttachOption(
                          icon: Icons.image_outlined,
                          iconColor: Colors.white,
                          bgColor: _pink,
                          title: l10n.translate('photo_library'),
                          subtitle: l10n.translate('photo_library_desc'),
                          onTap: () {
                            Navigator.of(dialogCtx).pop();
                            _pickImage(ImageSource.gallery);
                          },
                        ),
                        _AttachOption(
                          icon: Icons.camera_alt_outlined,
                          iconColor: Colors.white,
                          bgColor: _pink,
                          title: l10n.translate('take_photo'),
                          subtitle: l10n.translate('take_photo_desc'),
                          onTap: () {
                            Navigator.of(dialogCtx).pop();
                            _pickImage(ImageSource.camera);
                          },
                        ),
                      ],
                    ),
                  ),
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
          backdropSigma: 15.0,
          maxFlightBlur: 14.0,
        );
      },
    );
  }

  // ─── History Panel ────────────────────────────────────────────────────────────
  Widget _buildHistoryPanel() {
    final l10n = AppLocalizations.of(context);
    final filtered = _searchQuery.isEmpty
        ? _conversations
        : _conversations
            .where(
              (c) => c.title.toLowerCase().contains(_searchQuery.toLowerCase()),
            )
            .toList();

    return Material(
      type: MaterialType.transparency,
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search + Close
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 44,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: const Color(0xFFE2E8F0),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: l10n.search,
                      hintStyle: ArabicTypography.bodyStyle(
                        context,
                        color: const Color(0xFF94A3B8),
                        fontSize: 14,
                      ),
                      prefixIcon: const Icon(Icons.search_rounded,
                          color: Color(0xFF94A3B8), size: 20),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? GestureDetector(
                              onTap: () {
                                setState(() {
                                  _searchQuery = '';
                                  _searchController.clear();
                                });
                              },
                              child: const Icon(Icons.close_rounded,
                                  color: Color(0xFF94A3B8), size: 18),
                            )
                          : null,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    cursorColor: const Color(0xFF374151),
                    style: ArabicTypography.bodyStyle(
                      context,
                      fontSize: 14,
                      color: const Color(0xFF374151),
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              BouncingWrapper(
                shrinkScale: 0.86,
                hitPadding: const EdgeInsets.all(8),
                onTap: _closeHistory,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F7FB),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.close_rounded,
                      color: Color(0xFF374151), size: 20),
                ),
              ),
            ],
          ),
        ),

        // Section title
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 20, 6),
          child: Text(
            l10n.translate('chat_history'),
            style: ArabicTypography.headerStyle(
              context,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1E293B),
              letterSpacing: -0.3,
            ),
          ),
        ),

        // Conversation list
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: const BoxDecoration(
                          color: Color(0xFFF5F7FB),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.chat_bubble_outline_rounded,
                            color: Color(0xFF94A3B8), size: 26),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _searchQuery.isEmpty
                            ? l10n.translate('no_conversations')
                            : l10n.noResults,
                        style: ArabicTypography.bodyStyle(
                          context,
                          color: const Color(0xFF94A3B8),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final conv = filtered[index];
                    final isCurrent = conv.id == _currentConversationId;
                    return _buildConversationTile(conv, isCurrent);
                  },
                ),
        ),

        // New conversation
        Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            math.max(MediaQuery.of(context).padding.bottom, 16.0) + 4.0,
          ),
          child: BouncingWrapper(
            shrinkScale: 0.94,
            overshootScale: 1.04,
            onTap: () {
              _closeHistory();
              _startNewChat();
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_rounded, color: Colors.grey[700], size: 20),
                  const SizedBox(width: 8),
                  Text(
                    l10n.translate('new_conversation'),
                    style: ArabicTypography.buttonStyle(
                      context,
                      color: Colors.grey[700]!,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

  Widget _buildConversationTile(_Conversation conv, bool isCurrent) {
    return Dismissible(
      key: Key(conv.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsetsDirectional.only(end: 20),
        color: Colors.red.withValues(alpha: 0.15),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 22),
      ),
      onDismissed: (_) => _deleteConversation(conv.id),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          onTap: () => _loadConversation(conv),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isCurrent
                  ? _pink.withValues(alpha: 0.12)
                  : const Color(0xFFF5F7FB),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isCurrent
                  ? Icons.chat_bubble_rounded
                  : Icons.chat_bubble_outline_rounded,
              color: isCurrent ? _pink : const Color(0xFF374151),
              size: 20,
            ),
          ),
          title: Text(
            conv.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ArabicTypography.headerStyle(
              context,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: isCurrent ? _pink : const Color(0xFF374151),
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              _formatDate(conv.updatedAt),
              style: ArabicTypography.bodyStyle(
                context,
                fontSize: 12,
                color: const Color(0xFF94A3B8),
              ),
            ),
          ),
          trailing: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _deleteConversation(conv.id),
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.close_rounded, size: 18, color: Color(0xFFCBD5E1)),
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

// ─── Delete Dialog ─────────────────────────────────────────────────────────────
class _DeleteDialog extends StatelessWidget {
  final String title;
  const _DeleteDialog({required this.title});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.5), width: 1.5),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFFF43F5E), Color(0xFFEC4899)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFF43F5E).withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.delete_outline_rounded,
                      color: Colors.white, size: 28),
                ),
                const SizedBox(height: 20),
                Text(
                  l10n.translate('delete_conversation'),
                  textAlign: TextAlign.center,
                  style: ArabicTypography.headerStyle(
                    context,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1E293B),
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '"${title.length > 30 ? '${title.substring(0, 30)}...' : title}"',
                  textAlign: TextAlign.center,
                  style: ArabicTypography.bodyStyle(
                    context,
                    fontSize: 14,
                    color: const Color(0xFF64748B),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context, false),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Center(
                            child: Text(
                              l10n.cancel,
                              style: ArabicTypography.buttonStyle(
                                context,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF64748B),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context, true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFF43F5E), Color(0xFFEC4899)],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    const Color(0xFFF43F5E).withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              l10n.delete,
                              style: ArabicTypography.buttonStyle(
                                context,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Expandable Full Image Modal Viewer ─────────────────────────────────────────
void _showExpandedImage(BuildContext context, String? imagePath) {
  if (imagePath == null) return;
  final file = File(imagePath);
  if (!file.existsSync()) return;

  showDialog(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.9),
    barrierDismissible: true,
    builder: (ctx) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            // Tap outside image to dismiss
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(ctx).pop(),
                child: const SizedBox.expand(),
              ),
            ),
            // Pinch-to-zoom interactive viewer
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 60),
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4.0,
                  clipBehavior: Clip.none,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.file(
                      file,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
            // Close button at top-right
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 14, right: 18),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => Navigator.of(ctx).pop(),
                      borderRadius: BorderRadius.circular(30),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.3),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.35),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

// ─── Message Bubble with Markdown Rendering ────────────────────────────────────
class _MessageBubble extends StatelessWidget {
  final _ChatMessage message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            // NOVA avatar
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [_pink, _pinkLight],
                ),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.auto_awesome, color: Colors.white, size: 14),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: isUser
                ? _buildUserBubble(context, isRtl)
                : Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.84,
                    ),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                        bottomLeft: Radius.circular(5),
                        bottomRight: Radius.circular(20),
                      ),
                      border: Border.all(color: const Color(0xFFE8ECF1)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x1A64748B),
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: _buildAssistantContent(context),
                  ),
          ),
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildUserBubble(BuildContext context, bool isRtl) {
    final imagePath = message.attachedImagePath;
    final hasImgFile = imagePath != null && File(imagePath).existsSync();
    final hasImgExt = message.attachedFileName != null &&
        ['jpg', 'jpeg', 'png', 'webp', 'gif']
            .contains(message.attachedFileName!.split('.').last.toLowerCase());
    final hasImg = hasImgFile || hasImgExt;

    String cleanText = message.content;
    if (message.attachedFileName != null) {
      cleanText = cleanText
          .replaceAll('\n\n📎 ${message.attachedFileName}', '')
          .replaceAll('\n📎 ${message.attachedFileName}', '')
          .replaceAll('📎 ${message.attachedFileName}\n\n', '')
          .replaceAll('📎 ${message.attachedFileName}', '')
          .trim();
    }

    final hasText = cleanText.isNotEmpty;
    final hasNonImgFile = !hasImg && message.attachedFileName != null;

    if (!hasImg) {
      return Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.84,
        ),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _pink,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(4),
          ),
          boxShadow: [
            BoxShadow(
              color: _pink.withValues(alpha: 0.22),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasNonImgFile) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.attach_file, color: Colors.white, size: 14),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        message.attachedFileName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ArabicTypography.bodyStyle(
                          context,
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (hasText) const SizedBox(height: 8),
            ],
            if (hasText)
              Text(
                cleanText,
                style: _aiTextStyle(
                  context,
                  text: cleanText,
                  fontSize: 14.5,
                  color: Colors.white,
                  height: 1.5,
                ),
              ),
          ],
        ),
      );
    }

    // Has image: image preview thumbnail sits OUTSIDE and ON TOP OF the chat bubble
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Small preview thumbnail outside the bubble
        BouncingWrapper(
          shrinkScale: 0.92,
          onTap: () => _showExpandedImage(context, imagePath),
          child: Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFFE2E8F0),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12.5),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (hasImgFile)
                    Image.file(
                      File(imagePath),
                      fit: BoxFit.cover,
                    )
                  else
                    Container(
                      color: const Color(0xFFF1F5F9),
                      child: const Icon(Icons.image_rounded, color: Color(0xFF94A3B8), size: 36),
                    ),
                  // Subtle expand icon badge
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.fullscreen_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (hasText) ...[
          const SizedBox(height: 6),
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.84,
            ),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _pink,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(4),
              ),
              boxShadow: [
                BoxShadow(
                  color: _pink.withValues(alpha: 0.22),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Text(
              cleanText,
              style: _aiTextStyle(
                context,
                text: cleanText,
                fontSize: 14.5,
                color: Colors.white,
                height: 1.5,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAssistantContent(BuildContext context) {
    final isWelcome = message.id == 'welcome';
    final actions = isWelcome
        ? _getWelcomeActions(context)
        : _detectRouteActions(message.content, context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MarkdownText(
          text: message.content,
          textColor: const Color(0xFF334155),
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: actions.take(3).map((act) {
              return BouncingWrapper(
                shrinkScale: 0.92,
                overshootScale: 1.06,
                delayNavigation: true,
                onTap: () {
                  final safeRoute = resolveSafeStudentRoute(act.route);
                  if (safeRoute == null) return;
                  ProviderScope.containerOf(context)
                      .read(navigatedFromAIChatProvider.notifier)
                      .state = true;
                  context.go(safeRoute);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF0F5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(act.icon, size: 14, color: _pink),
                      const SizedBox(width: 6),
                      Text(
                        act.label,
                        style: ArabicTypography.bodyStyle(
                          context,
                          fontSize: 12.5,
                          color: _pink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Directionality.of(context) == TextDirection.rtl
                            ? Icons.chevron_left_rounded
                            : Icons.chevron_right_rounded,
                        size: 13,
                        color: _pink,
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }
}

/// Authoritative whitelist of active student routes in the application.
/// Guarantees that the AI assistant can never suggest or navigate to a missing/obsolete page.
const Set<String> kValidStudentRoutes = {
  '/',
  '/emploi',
  '/resultats',
  '/absences',
  '/mon-solde',
  '/documents',
  '/messages',
  '/notifications',
  '/suggestions',
  '/profile',
  '/settings',
  '/contact',
  '/about',
};

/// Validates a target route against active student screens and gracefully maps
/// any legacy/hallucinated routes (such as /courses or /stats) to their actual destination.
String? resolveSafeStudentRoute(String route) {
  final clean = route.trim().split('?').first;
  if (clean == '/courses' || clean.startsWith('/courses/')) {
    return '/emploi';
  }
  if (clean == '/stats') {
    return '/resultats';
  }
  if (kValidStudentRoutes.contains(clean) || clean.startsWith('/absences/')) {
    return clean;
  }
  return null;
}

class _RouteAction {
  final String route;
  final String label;
  final IconData icon;

  const _RouteAction({
    required this.route,
    required this.label,
    required this.icon,
  });
}

List<_RouteAction> _getWelcomeActions(BuildContext context) {
  final lang = Localizations.localeOf(context).languageCode;
  return [
    _RouteAction(
      route: '/emploi',
      label: lang == 'ar'
          ? 'جدول الأوقات'
          : (lang == 'fr' ? 'Emploi du temps' : 'Timetable'),
      icon: Icons.calendar_today_rounded,
    ),
    _RouteAction(
      route: '/absences',
      label: lang == 'ar'
          ? 'سجل الغيابات'
          : (lang == 'fr' ? 'Consulter Absences' : 'Check Absences'),
      icon: Icons.event_busy_rounded,
    ),
    _RouteAction(
      route: '/documents',
      label: lang == 'ar'
          ? 'المستندات والشهادات'
          : (lang == 'fr' ? 'Mes Documents' : 'My Documents'),
      icon: Icons.folder_open_rounded,
    ),
  ];
}

List<_RouteAction> _detectRouteActions(String content, BuildContext context) {
  final lang = Localizations.localeOf(context).languageCode;
  return _detectRouteActionsForLang(content, lang);
}

/// Pure helper returning the validated list of quick-navigation route paths
/// detected in an AI response for a given language code.
List<String> detectAIRoutesForLanguage(String content, String lang) {
  return _detectRouteActionsForLang(content, lang).map((e) => e.route).toList();
}

List<_RouteAction> _detectRouteActionsForLang(String content, String lang) {
  final actions = <_RouteAction>[];
  final lower = content.toLowerCase();

  bool matchesKeyword(String kw) {
    if (kw.startsWith('/')) {
      return lower.contains(kw);
    }
    // Use word boundaries for Latin words to prevent substring false positives
    if (RegExp(r'^[a-zàâäéèêëïîôöùûüç\s-]+$', caseSensitive: false).hasMatch(kw)) {
      return RegExp(r'\b' + RegExp.escape(kw) + r'\b', caseSensitive: false)
          .hasMatch(lower);
    }
    return lower.contains(kw);
  }

  void check({
    required List<String> keywords,
    required String route,
    required String labelAr,
    required String labelFr,
    required String labelEn,
    required IconData icon,
  }) {
    final safeRoute = resolveSafeStudentRoute(route);
    if (safeRoute == null) return;
    if (keywords.any(matchesKeyword)) {
      final label = switch (lang) {
        'ar' => labelAr,
        'fr' => labelFr,
        _ => labelEn,
      };
      if (!actions.any((a) => a.route == safeRoute)) {
        actions.add(_RouteAction(route: safeRoute, label: label, icon: icon));
      }
    }
  }

  check(
    keywords: ['/emploi', 'emploi du temps', 'جدول الأوقات', 'timetable', 'حصص', 'حصة', 'حصتي', 'prochain cours', 'séance'],
    route: '/emploi',
    labelAr: 'فتح جدول الأوقات',
    labelFr: 'Emploi du temps',
    labelEn: 'Open Timetable',
    icon: Icons.calendar_today_rounded,
  );
  check(
    keywords: ['/resultats', 'résultat', 'résultats', 'النتائج', 'معدل', 'درجات', 'grades', 'bulletin', 'moyenne'],
    route: '/resultats',
    labelAr: 'عرض النتائج والمعدلات',
    labelFr: 'Voir les Résultats',
    labelEn: 'View Results',
    icon: Icons.school_rounded,
  );
  check(
    keywords: ['/absences', 'absence', 'absences', 'غياب', 'غيابات', 'attendance'],
    route: '/absences',
    labelAr: 'سجل الغيابات',
    labelFr: 'Consulter Absences',
    labelEn: 'Check Absences',
    icon: Icons.event_busy_rounded,
  );
  check(
    keywords: ['/mon-solde', 'solde', 'paiement', 'frais', 'الرصيد', 'دفع', 'مصاريف', 'payments', 'balance'],
    route: '/mon-solde',
    labelAr: 'الرصيد والمصاريف',
    labelFr: 'Mon Solde',
    labelEn: 'My Balance',
    icon: Icons.account_balance_wallet_rounded,
  );
  check(
    keywords: ['/documents', 'document', 'documents', 'شهادة', 'مستند', 'وثائق', 'attestation', 'certificat'],
    route: '/documents',
    labelAr: 'المستندات والشهادات',
    labelFr: 'Mes Documents',
    labelEn: 'My Documents',
    icon: Icons.folder_open_rounded,
  );
  check(
    keywords: ['/messages', 'message de classe', 'messages de classe', 'رسائل الفصل', 'رسائل'],
    route: '/messages',
    labelAr: 'رسائل الفصل',
    labelFr: 'Messages de classe',
    labelEn: 'Class Messages',
    icon: Icons.mail_rounded,
  );
  check(
    keywords: ['/notifications', 'notification', 'notifications', 'إشعار', 'إعلانات', 'announcement', 'annonce'],
    route: '/notifications',
    labelAr: 'الإعلانات والإشعارات',
    labelFr: 'Notifications',
    labelEn: 'Notifications',
    icon: Icons.notifications_rounded,
  );
  check(
    keywords: ['/suggestions', 'suggestion', 'suggestions', 'مقترح', 'شكوى', 'reclamation'],
    route: '/suggestions',
    labelAr: 'صندوق المقترحات',
    labelFr: 'Boîte à suggestions',
    labelEn: 'Suggestions',
    icon: Icons.lightbulb_rounded,
  );
  check(
    keywords: ['/profile', 'mon profil', 'الملف الشخصي', 'profile'],
    route: '/profile',
    labelAr: 'الملف الشخصي',
    labelFr: 'Mon Profil',
    labelEn: 'My Profile',
    icon: Icons.person_rounded,
  );

  return actions;
}

// ─── Markdown Text Renderer ───────────────────────────────────────────────────
/// Renders a subset of markdown: headers, bold, italic, bullets, numbered lists,
/// blockquotes, horizontal rules, and emojis — all native Flutter Text widgets.
class _MarkdownText extends StatelessWidget {
  final String text;
  final Color textColor;

  const _MarkdownText({required this.text, required this.textColor});

  @override
  Widget build(BuildContext context) {
    final rawLines = text.split('\n');
    final lines = <String>[];
    for (final raw in rawLines) {
      final t = raw.trim();
      // Skip empty blockquotes like '>' or '>>>'
      if (t == '>' || t == '>>>') continue;
      lines.add(raw);
    }

    final widgets = <Widget>[];
    bool lastWasEmpty = false;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();

      // Empty line → collapse consecutive empty lines into a single controlled gap
      if (trimmed.isEmpty) {
        if (!lastWasEmpty && widgets.isNotEmpty) {
          widgets.add(const SizedBox(height: 8));
          lastWasEmpty = true;
        }
        continue;
      }
      lastWasEmpty = false;

      // Markdown Table: | Header 1 | Header 2 | ... |
      if (trimmed.startsWith('|') && trimmed.endsWith('|') && trimmed.contains('|')) {
        if (i + 1 < lines.length) {
          final nextTrimmed = lines[i + 1].trim();
          final nextRowParts = _parseTableRow(nextTrimmed);
          final isSeparator = nextTrimmed.startsWith('|') &&
              nextTrimmed.endsWith('|') &&
              nextRowParts.isNotEmpty &&
              nextRowParts.every((c) => RegExp(r'^:?-+:?$').hasMatch(c));

          if (isSeparator) {
            final tableLines = <String>[trimmed];
            int j = i + 1;
            while (j < lines.length && lines[j].trim().startsWith('|') && lines[j].trim().endsWith('|')) {
              tableLines.add(lines[j].trim());
              j++;
            }
            final headerParts = _parseTableRow(tableLines[0]);
            final dataRows = <List<String>>[];
            for (int r = 2; r < tableLines.length; r++) {
              dataRows.add(_parseTableRow(tableLines[r]));
            }

            if (headerParts.isNotEmpty) {
              widgets.add(Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: _MarkdownTableWidget(
                  headers: headerParts,
                  rows: dataRows,
                  textColor: textColor,
                ),
              ));
              i = j - 1;
              continue;
            }
          }
        }
      }

      // Embedded Image Markdown: ![alt](url) (supports optional leading bullet)
      final imgMatch = RegExp(r'^(?:[-*•]\s*)?!\[(.*?)\]\((https?://[^\s)]+)\)$').firstMatch(trimmed);
      if (imgMatch != null) {
        final alt = imgMatch.group(1)?.trim() ?? '';
        final url = imgMatch.group(2)!.trim();
        widgets.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: _ChatEmbeddedImageCard(imageUrl: url, caption: alt),
        ));
        continue;
      }

      // Embedded Standalone File Link: [title](url) where url is http/https (supports optional leading bullet)
      final fileMatch = RegExp(r'^(?:[-*•]\s*)?\[(.*?)\]\((https?://[^\s)]+)\)$').firstMatch(trimmed);
      if (fileMatch != null) {
        final title = fileMatch.group(1)?.trim() ?? '';
        final url = fileMatch.group(2)!.trim();
        final isImg = url.toLowerCase().contains('.png') ||
            url.toLowerCase().contains('.jpg') ||
            url.toLowerCase().contains('.jpeg') ||
            url.toLowerCase().contains('.webp');
        if (isImg) {
          widgets.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: _ChatEmbeddedImageCard(imageUrl: url, caption: title),
          ));
        } else {
          widgets.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: _ChatEmbeddedFileCard(title: title, url: url),
          ));
        }
        continue;
      }

      // Raw or prefixed URL line: "• URL : https://...", "URL : https://...", "Lien : https://...", or bare "https://..."
      final rawUrlMatch = RegExp(r'^(?:[-*•]\s*)?(?:URL|Lien|Fichier|Image|Document)?\s*[:：]?\s*(https?://[^\s)]+)\s*$', caseSensitive: false).firstMatch(trimmed);
      if (rawUrlMatch != null) {
        final url = rawUrlMatch.group(1)!.trim();
        final isImg = url.toLowerCase().contains('.png') ||
            url.toLowerCase().contains('.jpg') ||
            url.toLowerCase().contains('.jpeg') ||
            url.toLowerCase().contains('.webp') ||
            url.toLowerCase().contains('image');
        if (isImg) {
          widgets.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: _ChatEmbeddedImageCard(imageUrl: url, caption: 'Photo'),
          ));
          continue;
        } else {
          final uri = Uri.tryParse(url);
          final rawFileName = uri?.pathSegments.lastOrNull ?? 'Document';
          final decodedName = Uri.decodeComponent(rawFileName);
          widgets.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: _ChatEmbeddedFileCard(title: decodedName, url: url),
          ));
          continue;
        }
      }

      // Horizontal rule
      if (trimmed == '---' || trimmed == '***' || trimmed == '___') {
        widgets.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Divider(color: textColor.withValues(alpha: 0.15), thickness: 1),
        ));
        continue;
      }

      // Headings (#, ##, ###, ####, #####, ######)
      final headerMatch = RegExp(r'^(#{1,6})\s*(.+)$').firstMatch(trimmed);
      if (headerMatch != null) {
        final level = headerMatch.group(1)!.length;
        final content = headerMatch.group(2)!.trim();
        double fontSize;
        FontWeight weight = FontWeight.w800;
        double topPadding;
        double bottomPadding = 4;
        Color headerColor = const Color(0xFF0F172A);

        switch (level) {
          case 1:
            fontSize = 20.5;
            topPadding = i == 0 ? 0 : 14;
            bottomPadding = 6;
            break;
          case 2:
            fontSize = 18.0;
            topPadding = i == 0 ? 0 : 12;
            bottomPadding = 6;
            break;
          case 3:
            fontSize = 15.5;
            topPadding = i == 0 ? 0 : 10;
            bottomPadding = 4;
            break;
          case 4:
            fontSize = 14.5;
            weight = FontWeight.w700;
            topPadding = i == 0 ? 0 : 8;
            bottomPadding = 4;
            headerColor = const Color(0xFF1E293B);
            break;
          default:
            fontSize = 13.5;
            weight = FontWeight.w700;
            topPadding = i == 0 ? 0 : 6;
            bottomPadding = 3;
            headerColor = const Color(0xFF334155);
        }

        widgets.add(Padding(
          padding: EdgeInsets.only(top: topPadding, bottom: bottomPadding),
          child: RichText(
            text: _parseInline(
              content,
              context,
              _aiTextStyle(
                context,
                text: content,
                fontSize: fontSize,
                fontWeight: weight,
                color: headerColor,
                letterSpacing: -0.3,
              ),
            ),
          ),
        ));
        continue;
      }

      // Standalone Bold Section / Subject Title (e.g. "**📊 General Results**" or "**📐 Mathématiques** (Coeff 3.0) — **14.25/20**")
      final isStandaloneBoldTitle = (trimmed.startsWith('**') && trimmed.endsWith('**') && trimmed.length > 4) ||
          RegExp(r'^([\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]\s*)?\*\*(.+?)\*\*[:\s]*$', unicode: true).hasMatch(trimmed) ||
          RegExp(r'^([\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]\s*)?\*\*(.+?)\*\*\s*(`.+?`)?\s*([—–-]\s*\*\*.+?\*\*)?$', unicode: true).hasMatch(trimmed);

      if (isStandaloneBoldTitle) {
        final rawTitle = trimmed.replaceAll('**', '').replaceAll('`', '');
        widgets.add(Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : 10, bottom: 4),
          child: RichText(
            text: _parseInline(
              trimmed,
              context,
              _aiTextStyle(
                context,
                text: rawTitle,
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
                letterSpacing: -0.2,
              ),
            ),
          ),
        ));
        continue;
      }

      // Blockquote (>) - styled callout container with soft pink tint and left accent bar
      if (trimmed.startsWith('> ') || (trimmed.startsWith('>') && trimmed.length > 1)) {
        final bqLines = <String>[trimmed.replaceFirst(RegExp(r'^>\s*'), '')];
        while (i + 1 < lines.length) {
          final nextTrimmed = lines[i + 1].trim();
          if (nextTrimmed.startsWith('> ') || (nextTrimmed.startsWith('>') && nextTrimmed.length > 1)) {
            bqLines.add(nextTrimmed.replaceFirst(RegExp(r'^>\s*'), ''));
            i++;
          } else {
            break;
          }
        }
        final content = bqLines.join('\n').trim();
        if (content.isEmpty) continue;
        widgets.add(Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF0F5),
            borderRadius: BorderRadius.circular(14),
          ),
          clipBehavior: Clip.antiAlias,
          child: IntrinsicHeight(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 3.5,
                    color: _pink,
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                      child: RichText(
                        text: _parseInline(
                          content,
                          context,
                          _aiTextStyle(
                            context,
                            text: content,
                            fontSize: 13.5,
                            color: const Color(0xFF475569),
                            fontStyle: FontStyle.italic,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ));
        continue;
      }

      // Standalone italic subtitle (e.g. "*Semestre 1 · par matière*")
      if ((trimmed.startsWith('*') && trimmed.endsWith('*') && !trimmed.startsWith('**') && trimmed.length > 2) ||
          (trimmed.startsWith('_') && trimmed.endsWith('_') && !trimmed.startsWith('__') && trimmed.length > 2)) {
        final content = trimmed.substring(1, trimmed.length - 1).trim();
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 0, bottom: 8),
          child: RichText(
            text: _parseInline(
              content,
              context,
              _aiTextStyle(
                context,
                text: content,
                fontSize: 12.5,
                color: const Color(0xFF64748B),
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ));
        continue;
      }

      // Insight / Lecture line (e.g. "**Lecture :** ton CC en Informatique...")
      if (trimmed.startsWith('**Lecture :**') || trimmed.startsWith('**Lecture:**') || trimmed.startsWith('**Conseil :**')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 3),
          child: RichText(
            text: _parseInline(
              trimmed,
              context,
              _aiTextStyle(
                context,
                text: trimmed,
                fontSize: 13.5,
                color: const Color(0xFF1E293B),
                height: 1.45,
              ),
            ),
          ),
        ));
        continue;
      }

      // Standalone medal rank row (e.g. "🥇 **Informatique** : **16.75**/20 · Coeff 1.0")
      if (trimmed.startsWith('🥇') || trimmed.startsWith('🥈') || trimmed.startsWith('🥉')) {
        widgets.add(Padding(
          padding: const EdgeInsetsDirectional.only(start: 2, top: 3, bottom: 2),
          child: RichText(
            text: _parseInline(
              trimmed,
              context,
              _aiTextStyle(
                context,
                text: trimmed,
                fontSize: 14.5,
                color: textColor,
                height: 1.5,
              ),
            ),
          ),
        ));
        continue;
      }

      // Bullet list (- , * , • , •) with indentation support for sub-items
      final isIndented = line.startsWith('  ') || line.startsWith('\t');

      // Indented detail sub-line under a row (e.g. "   Orale 19.00 · CC 10.00 · Synthèse 19.00")
      if (isIndented && !trimmed.startsWith('-') && !trimmed.startsWith('*') && !trimmed.startsWith('•')) {
        widgets.add(Padding(
          padding: const EdgeInsetsDirectional.only(start: 22, bottom: 4),
          child: RichText(
            text: _parseInline(
              trimmed,
              context,
              _aiTextStyle(
                context,
                text: trimmed,
                fontSize: 13,
                color: const Color(0xFF64748B),
                height: 1.45,
              ),
            ),
          ),
        ));
        continue;
      }

      if (trimmed.startsWith('- ') ||
          trimmed.startsWith('* ') ||
          trimmed.startsWith('• ') ||
          trimmed.startsWith('•')) {
        final content = trimmed.replaceFirst(RegExp(r'^([-*•]\s*|\u2022\s*)'), '');

        // Check if this is an empty heading bullet like "Strong Performers:" without content
        final isCategoryHeadingOnly = content.endsWith(':') && !content.contains('(') && !content.contains('/');
        if (isCategoryHeadingOnly) {
          widgets.add(Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 2),
            child: RichText(
              text: _parseInline(
                content,
                context,
                _aiTextStyle(
                  context,
                  text: content,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1E293B),
                ),
              ),
            ),
          ));
          continue;
        }

        widgets.add(Padding(
          padding: EdgeInsetsDirectional.only(
            start: isIndented ? 18 : 2,
            bottom: isIndented ? 2.5 : 4,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsetsDirectional.only(
                  start: isIndented ? 2 : 2,
                  top: isIndented ? 6.5 : 7,
                  end: isIndented ? 6 : 8,
                ),
                child: Container(
                  width: isIndented ? 4.0 : 5.5,
                  height: isIndented ? 4.0 : 5.5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isIndented
                        ? _pink.withValues(alpha: 0.45)
                        : _pink.withValues(alpha: 0.85),
                  ),
                ),
              ),
              Expanded(
                child: RichText(
                  text: _parseInline(
                    content,
                    context,
                    _aiTextStyle(
                      context,
                      text: content,
                      fontSize: isIndented ? 13 : 14,
                      color: isIndented ? const Color(0xFF475569) : textColor,
                      height: isIndented ? 1.4 : 1.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ));
        continue;
      }

      // Numbered list (1. 2. etc.)
      final numberedMatch =
          RegExp(r'^(\d+)\.\s(.+)$').firstMatch(trimmed);
      if (numberedMatch != null) {
        final num = numberedMatch.group(1)!;
        final content = numberedMatch.group(2)!;
        final startsWithMedal = content.startsWith('🥇') || content.startsWith('🥈') || content.startsWith('🥉');

        if (startsWithMedal) {
          widgets.add(Padding(
            padding: const EdgeInsetsDirectional.only(start: 2, top: 3, bottom: 2),
            child: RichText(
              text: _parseInline(
                content,
                context,
                _aiTextStyle(
                  context,
                  text: content,
                  fontSize: 14.5,
                  color: textColor,
                  height: 1.5,
                ),
              ),
            ),
          ));
          continue;
        }

        widgets.add(Padding(
          padding: const EdgeInsetsDirectional.only(start: 2, bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 20,
                height: 20,
                margin: const EdgeInsetsDirectional.only(end: 8, top: 1),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _pink.withValues(alpha: 0.12),
                ),
                alignment: Alignment.center,
                child: Text(
                  num,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _pink,
                  ),
                ),
              ),
              Expanded(
                child: RichText(
                  text: _parseInline(
                    content,
                    context,
                    _aiTextStyle(
                      context,
                      text: content,
                      fontSize: 14,
                      color: textColor,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ));
        continue;
      }

      // Regular paragraph
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: RichText(
          text: _parseInline(
            trimmed,
            context,
            _aiTextStyle(
              context,
              text: trimmed,
              fontSize: 14.5,
              color: textColor,
              height: 1.55,
            ),
          ),
        ),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  static List<String> _parseTableRow(String line) {
    var trimmed = line.trim();
    if (trimmed.startsWith('|')) trimmed = trimmed.substring(1);
    if (trimmed.endsWith('|')) trimmed = trimmed.substring(0, trimmed.length - 1);
    return trimmed.split('|').map((c) => c.trim()).toList();
  }

  /// Parse inline markdown: **bold**, *italic*, `code`, [title](url)
  TextSpan _parseInline(String text, BuildContext context, TextStyle base) =>
      parseInline(text, context, base);

  static TextSpan parseInline(String text, BuildContext context, TextStyle base) {
    final spans = <InlineSpan>[];
    // Pattern: [title](url), **bold**, *italic*, `code`
    final pattern = RegExp(r'\[(.+?)\]\((.+?)\)|\*\*(.+?)\*\*|\*(.+?)\*|`(.+?)`');
    int lastEnd = 0;

    for (final match in pattern.allMatches(text)) {
      if (match.start > lastEnd) {
        final chunk = text.substring(lastEnd, match.start);
        spans.add(TextSpan(
          text: chunk,
          style: _isArabicText(chunk)
              ? GoogleFonts.tajawal(
                  fontSize: base.fontSize,
                  fontWeight: base.fontWeight,
                  color: base.color,
                  height: base.height,
                  fontStyle: base.fontStyle,
                )
              : base,
        ));
      }
      if (match.group(1) != null && match.group(2) != null) {
        // [title](url)
        final linkTitle = match.group(1)!;
        final linkTarget = match.group(2)!;
        spans.add(TextSpan(
          text: linkTitle,
          style: _isArabicText(linkTitle)
              ? GoogleFonts.tajawal(
                  fontSize: base.fontSize,
                  color: _pink,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.underline,
                  decorationColor: _pink.withValues(alpha: 0.5),
                )
              : base.copyWith(
                  color: _pink,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.underline,
                  decorationColor: _pink.withValues(alpha: 0.5),
                ),
          recognizer: TapGestureRecognizer()
            ..onTap = () {
              if (linkTarget.startsWith('/')) {
                final safeRoute = resolveSafeStudentRoute(linkTarget);
                if (safeRoute != null) {
                  ProviderScope.containerOf(context)
                      .read(navigatedFromAIChatProvider.notifier)
                      .state = true;
                  context.go(safeRoute);
                }
              } else if (linkTarget.startsWith('http://') || linkTarget.startsWith('https://')) {
                final isImg = linkTarget.toLowerCase().contains('.png') ||
                    linkTarget.toLowerCase().contains('.jpg') ||
                    linkTarget.toLowerCase().contains('.jpeg') ||
                    linkTarget.toLowerCase().contains('.webp');
                if (isImg) {
                  IosPhotoGalleryViewer.show(
                    context: context,
                    imageUrls: [linkTarget],
                  );
                } else {
                  FileDownloadHelper.downloadFile(
                    context: context,
                    url: linkTarget,
                    fileName: linkTitle.replaceAll('📥', '').replaceAll('📎', '').trim().isNotEmpty
                        ? linkTitle.replaceAll('📥', '').replaceAll('📎', '').trim()
                        : 'document',
                  );
                }
              }
            },
        ));
      } else if (match.group(3) != null) {
        // **bold**
        final boldContent = match.group(3)!;
        spans.add(TextSpan(
          text: boldContent,
          style: _isArabicText(boldContent)
              ? GoogleFonts.tajawal(
                  fontSize: base.fontSize,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                  height: base.height,
                )
              : base.copyWith(fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
        ));
      } else if (match.group(4) != null) {
        // *italic*
        final italicContent = match.group(4)!;
        spans.add(TextSpan(
          text: italicContent,
          style: _isArabicText(italicContent)
              ? GoogleFonts.tajawal(
                  fontSize: base.fontSize,
                  fontStyle: FontStyle.italic,
                  color: base.color,
                  height: base.height,
                )
              : base.copyWith(fontStyle: FontStyle.italic),
        ));
      } else if (match.group(5) != null) {
        // `code` / badge pill
        final codeText = match.group(5)!;
        spans.add(TextSpan(
          text: ' $codeText ',
          style: base.copyWith(
            fontFamily: 'monospace',
            backgroundColor: const Color(0xFFFFF1F2),
            color: const Color(0xFFE11D48),
            fontWeight: FontWeight.w700,
            fontSize: (base.fontSize ?? 14) * 0.92,
          ),
        ));
      }
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      final chunk = text.substring(lastEnd);
      spans.add(TextSpan(
        text: chunk,
        style: _isArabicText(chunk)
            ? GoogleFonts.tajawal(
                fontSize: base.fontSize,
                fontWeight: base.fontWeight,
                color: base.color,
                height: base.height,
                fontStyle: base.fontStyle,
              )
            : base,
      ));
    }
    return TextSpan(children: spans);
  }
}

/// Real minimal rounded tables inside AI chat with clean radius (14px) and horizontal scrolling
class _MarkdownTableWidget extends StatelessWidget {
  final List<String> headers;
  final List<List<String>> rows;
  final Color textColor;

  const _MarkdownTableWidget({
    required this.headers,
    required this.rows,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    if (headers.isEmpty && rows.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFFE2E8F0),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(
              const Color(0xFFF8FAFC),
            ),
            horizontalMargin: 16,
            columnSpacing: 20,
            headingRowHeight: 40,
            dataRowMinHeight: 38,
            dataRowMaxHeight: 56,
            dividerThickness: 0.8,
            columns: headers.map((h) {
              return DataColumn(
                label: RichText(
                  text: _MarkdownText.parseInline(
                    h.trim(),
                    context,
                    _aiTextStyle(
                      context,
                      text: h,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                ),
              );
            }).toList(),
            rows: rows.map((row) {
              return DataRow(
                cells: List.generate(headers.length, (idx) {
                  final cellText = idx < row.length ? row[idx].trim() : '';
                  return DataCell(
                    RichText(
                      text: _MarkdownText.parseInline(
                        cellText,
                        context,
                        _aiTextStyle(
                          context,
                          text: cellText,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: textColor,
                        ),
                      ),
                    ),
                  );
                }),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

/// Embedded Image Card inside AI chat responses with tap-to-zoom and download
class _ChatEmbeddedImageCard extends StatelessWidget {
  final String imageUrl;
  final String caption;

  const _ChatEmbeddedImageCard({required this.imageUrl, required this.caption});

  @override
  Widget build(BuildContext context) {
    final effectiveCaption = caption.isNotEmpty ? caption : 'Image';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          BouncingWrapper(
            onTap: () {
              IosPhotoGalleryViewer.show(
                context: context,
                imageUrls: [imageUrl],
              );
            },
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220, minHeight: 120),
                  child: Image.network(
                    imageUrl,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    loadingBuilder: (ctx, child, progress) {
                      if (progress == null) return child;
                      return Container(
                        height: 140,
                        color: const Color(0xFFF1F5F9),
                        child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2, color: _pink),
                        ),
                      );
                    },
                    errorBuilder: (ctx, err, stack) {
                      return Container(
                        height: 120,
                        color: const Color(0xFFF1F5F9),
                        child: const Center(
                          child: Icon(Icons.broken_image_rounded, color: Colors.grey, size: 36),
                        ),
                      );
                    },
                  ),
                ),
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.zoom_in_rounded, color: Colors.white, size: 14),
                        SizedBox(width: 4),
                        Text(
                          'Aperçu',
                          style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    effectiveCaption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF334155),
                    ),
                  ),
                ),
                BouncingWrapper(
                  onTap: () {
                    FileDownloadHelper.downloadFile(
                      context: context,
                      url: imageUrl,
                      fileName: effectiveCaption.endsWith('.png') ||
                              effectiveCaption.endsWith('.jpg') ||
                              effectiveCaption.endsWith('.jpeg')
                          ? effectiveCaption
                          : '$effectiveCaption.jpg',
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _pink.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.download_rounded, color: _pink, size: 14),
                        SizedBox(width: 4),
                        Text(
                          'Télécharger',
                          style: TextStyle(
                            color: _pink,
                            fontSize: 11.5,
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
        ],
      ),
    );
  }
}

/// Embedded File Card inside AI chat responses with one-tap download
class _ChatEmbeddedFileCard extends StatelessWidget {
  final String title;
  final String url;

  const _ChatEmbeddedFileCard({required this.title, required this.url});

  @override
  Widget build(BuildContext context) {
    final cleanTitle = title.replaceAll('📥', '').replaceAll('📎', '').trim();
    final isPdf = url.toLowerCase().contains('.pdf') || cleanTitle.toLowerCase().endsWith('.pdf');
    final isImg = url.toLowerCase().contains('.png') ||
        url.toLowerCase().contains('.jpg') ||
        url.toLowerCase().contains('.jpeg') ||
        url.toLowerCase().contains('.webp');

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            if (isImg) {
              IosPhotoGalleryViewer.show(context: context, imageUrls: [url]);
            } else {
              FileDownloadHelper.downloadFile(
                context: context,
                url: url,
                fileName: cleanTitle.isNotEmpty ? cleanTitle : 'document',
              );
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isPdf ? const Color(0xFFFFEBEE) : const Color(0xFFFFF0F5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isPdf ? Icons.picture_as_pdf_rounded : (isImg ? Icons.image_rounded : Icons.insert_drive_file_rounded),
                    color: isPdf ? const Color(0xFFD32F2F) : _pink,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cleanTitle.isNotEmpty ? cleanTitle : 'Document joint',
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E293B),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Appuyer pour télécharger / ouvrir',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _pink.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.download_rounded, color: _pink, size: 18),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Typing Indicator ─────────────────────────────────────────────────────────
class _TypingIndicator extends AnimatedWidget {
  const _TypingIndicator({required super.listenable});

  Animation<double> get _animation => listenable as Animation<double>;

  @override
  Widget build(BuildContext context) {
    final value = _animation.value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [_pink, _pinkLight]),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.auto_awesome, color: Colors.white, size: 14),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomLeft: Radius.circular(5),
                bottomRight: Radius.circular(20),
              ),
              border: Border.all(color: const Color(0xFFE8ECF1)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1A64748B),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                final delay = i * 0.33;
                final animVal = ((value - delay) % 1.0).clamp(0.0, 1.0);
                final bounce = animVal < 0.5 ? animVal * 2 : (1 - animVal) * 2;
                return Transform.translate(
                  offset: Offset(0, -bounce * 5),
                  child: Container(
                    width: 7,
                    height: 7,
                    margin: EdgeInsets.only(right: i < 2 ? 5 : 0),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _pink.withValues(alpha: 0.4 + bounce * 0.6),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Attach Option ────────────────────────────────────────────────────────────
class _AttachOption extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color bgColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AttachOption({
    required this.icon,
    required this.iconColor,
    required this.bgColor,
    required this.title,
    required this.subtitle,
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFF8FAFC))),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(icon, color: iconColor, size: 22),
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
                      ).copyWith(decoration: TextDecoration.none),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: ArabicTypography.bodyStyle(
                        context,
                        fontSize: 12,
                        color: const Color(0xFF94A3B8),
                      ).copyWith(decoration: TextDecoration.none),
                    ),
                  ],
                ),
              ),
              Icon(
                isRtl ? Icons.chevron_left : Icons.chevron_right,
                size: 18,
                color: const Color(0xFFCBD5E1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Animated iOS-Style Suggestion Chip ────────────────────────────────────────
class _AnimatedSuggestionChip extends StatefulWidget {
  final String text;
  final int index;
  final AnimationController controller;
  final VoidCallback onTap;

  const _AnimatedSuggestionChip({
    super.key,
    required this.text,
    required this.index,
    required this.controller,
    required this.onTap,
  });

  @override
  State<_AnimatedSuggestionChip> createState() => _AnimatedSuggestionChipState();
}

class _AnimatedSuggestionChipState extends State<_AnimatedSuggestionChip> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final start = (widget.index * 0.16).clamp(0.0, 0.6);
    final end = (start + 0.44).clamp(0.0, 1.0);
    final anim = CurvedAnimation(
      parent: widget.controller,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );

    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) {
        final opacity = anim.value.clamp(0.0, 1.0);
        final translateY = (1.0 - anim.value) * 18.0;
        final scale = 0.94 + (0.06 * anim.value);

        return Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(0, translateY),
            child: Transform.scale(
              scale: _isPressed ? 0.96 : scale,
              child: child,
            ),
          ),
        );
      },
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10.5),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF64748B).withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Text(
            widget.text,
            style: _aiTextStyle(
              context,
              text: widget.text,
              fontSize: 13.5,
              color: const Color(0xFF334155),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Bouncing Send Button ───────────────────────────────────────────────────
class _BouncingSendButton extends StatefulWidget {
  final bool enabled;
  final VoidCallback? onTap;

  const _BouncingSendButton({
    required this.enabled,
    required this.onTap,
  });

  @override
  State<_BouncingSendButton> createState() => _BouncingSendButtonState();
}

class _BouncingSendButtonState extends State<_BouncingSendButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 360),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.82).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
        reverseCurve: Curves.elasticOut,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails _) {
    if (widget.enabled) {
      _controller.forward();
    }
  }

  void _handleTapUp(TapUpDetails _) {
    if (widget.enabled) {
      _controller.reverse();
      widget.onTap?.call();
    }
  }

  void _handleTapCancel() {
    if (widget.enabled) {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: AnimatedBuilder(
          animation: _scaleAnimation,
          builder: (context, child) => Transform.scale(
            scale: _scaleAnimation.value,
            child: child,
          ),
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.enabled ? _pink : const Color(0xFFCBD5E1),
              boxShadow: widget.enabled
                  ? [
                      BoxShadow(
                        color: _pink.withValues(alpha: 0.32),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: const Icon(Icons.send, size: 18, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

