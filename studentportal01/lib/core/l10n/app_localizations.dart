import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import '../theme/arabic_typography.dart';

class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        AppLocalizations(const Locale('fr'));
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static const List<Locale> supportedLocales = [
    Locale('fr', ''), // French
    Locale('ar', ''), // Arabic
    Locale('en', ''), // English
  ];

  static const List<LocalizationsDelegate> localizationsDelegates = [
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  // Translations map
  static final Map<String, Map<String, String>> _localizedValues = {
    'en': {
      // App
      'app_name': 'Student Portal',
      'welcome': 'Welcome',
      'logout': 'Logout',
      'settings': 'Settings',
      'profile': 'Profile',
      'contact_us': 'Contact Us',
      'about': 'About',

      // Auth
      'login': 'Login',
      'register': 'Register',
      'email': 'Email',
      'password': 'Password',
      'confirm_password': 'Confirm Password',
      'forgot_password': 'Forgot Password?',
      'no_account': 'Don\'t have an account?',
      'already_account': 'Already have an account?',
      'sign_in': 'Sign In',
      'sign_up': 'Sign Up',
      'invalid_credentials': 'Email or password is incorrect.',
      'server_error': 'Server connection error. Please try again later.',
      'network_error': 'Please check your internet connection.',
      'offline_mode': 'Offline Mode',
      'offline_short': 'Offline',
      'server_down_short': 'Offline',
      'online_restored': 'Online',

      // Home Menu Items
      'note_info': 'Info Notes',
      'messages': 'Messages',
      'suggestions': 'Suggestions',
      'absences': 'Absences',
      'resultats': 'Results',
      'emploi': 'Timetable',
      'mon_groupe': 'My Group',
      'mon_solde': 'My Balance',
      'documents': 'Documents',

      // Bottom Nav
      'my_profile': 'My Profile',
      'contact': 'Contact Us',
      'home': 'Home',
      'notifications': 'Notifications',

      // Absences
      'absence_list': 'Absence: List of Periods',
      'select_semester': 'Select Semester',
      'semester': 'Semester',
      'total_hours_charge': 'Total Hourly Load',
      'weekly_ci_hours': 'CI Hours/Week',
      'weekly_tp_hours': 'TP Hours/Week',
      'weeks': 'Weeks',
      'total_absent': 'Total Absent',
      'absence_percent': 'Absence %',
      'warning_absence':
          'Warning! You are approaching the allowed absence threshold.',
      'critical_absence':
          'Warning! You have exceeded the critical absence threshold.',
      'eliminated_absence':
          'Warning! You have been eliminated from the main exam session.',

      // Results
      'semester_average': 'Semester Average',
      'coefficient': 'Coefficient',
      'subject_average': 'Subject Average',
      'grade_not_available': 'N/A',
      'grade_not_planned': 'N/P',

      // Suggestions
      'subject': 'Subject',
      'message': 'Message',
      'attachment': 'Attachment',
      'send': 'Send',
      'status_sent': 'Sent',
      'status_read': 'Read',
      'status_replied': 'Replied',

      // Payments
      'total_amount': 'Total Amount',
      'paid_amount': 'Paid Amount',
      'remaining_amount': 'Remaining Amount',
      'payment_history': 'Payment History',
      'payment_date': 'Date',
      'date': 'Date',
      'payment_method': 'Method',
      'payment_status': 'Status',
      'payment_pending': 'Pending',
      'payment_paid': 'Paid',
      'payment_overdue': 'Overdue',

      // Timetable
      'monday': 'Monday',
      'tuesday': 'Tuesday',
      'wednesday': 'Wednesday',
      'thursday': 'Thursday',
      'friday': 'Friday',
      'saturday': 'Saturday',
      'sunday': 'Sunday',
      'room': 'Room',
      'teacher': 'Teacher',

      // Documents
      'download': 'Download',
      'category': 'Category',
      'administrative': 'Administrative',
      'courses': 'Courses',
      'exams': 'Exams',
      'other': 'Other',

      // Group
      'class_name': 'Class',
      'level': 'Level',
      'group': 'Group',
      'section': 'Section',

      // Settings
      'language': 'Language',
      'theme': 'Theme',
      'light_theme': 'Light',
      'dark_theme': 'Dark',
      'system_theme': 'System',
      'notifications_enabled': 'Notifications',

      // Common
      'loading': 'Loading...',
      'error': 'Error',
      'retry': 'Retry',
      'refresh': 'Refresh',
      'cancel': 'Cancel',
      'save': 'Save',
      'delete': 'Delete',
      'edit': 'Edit',
      'confirm': 'Confirm',
      'no_data': 'No data available',
      'search': 'Search',
      'submit': 'Submit',
      'field_required': 'This field is required',
      'announcements': 'Announcements',

      // Absences Extended
      'total_hours': 'Total Hours',
      'ci_hours': 'CI Hours',
      'tp_hours': 'TP Hours',
      'absences_count': 'absences',
      'no_absences': 'No absences recorded',
      'no_absences_desc': 'You have no absences recorded for this semester.',
      'no_search_results_desc': 'No matching subjects found.',
      'absence_warning':
          'Warning! You are approaching the allowed absence threshold.',
      'absence_critical':
          'Critical! You have exceeded the critical absence threshold.',
      'absence_fail':
          'Eliminated! You have been eliminated from the main exam session.',
      'no_classes': 'No classes scheduled',

      // Results Extended
      'component': 'Component',
      'weight': 'Weight',
      'grade': 'Grade',
      'no_grades_yet': 'No grades available yet',
      'passed': 'Passed',
      'failed': 'Failed',

      // Suggestions Extended
      'my_suggestions': 'My Suggestions',
      'new_suggestion': 'New Suggestion',
      'pending': 'Pending',
      'in_review': 'In Review',
      'replied': 'Replied',
      'closed': 'Closed',
      'reply': 'reply',
      'submitted_at': 'Submitted on',
      'admin_response': 'Admin Response',
      'submit_suggestion': 'Submit a Suggestion',
      'suggestion_desc': 'Share your ideas and feedback with us',
      'enter_subject': 'Enter subject',
      'your_suggestion': 'Your suggestion',
      'enter_suggestion': 'Describe your suggestion in detail...',
      'suggestion_min_length': 'Suggestion must be at least 20 characters',
      'suggestion_submitted': 'Suggestion submitted successfully!',

      // Payments Extended
      'payment_plan': 'Payment Plan',
      'remaining_balance': 'Remaining Balance',
      'remaining_short': 'Remaining',
      'paid': 'Paid',
      'total': 'Total',
      'fully_paid': 'Fully Paid',
      'in_progress': 'In Progress',
      'installment': 'Installment',
      'due_date': 'Due Date',
      'no_payments': 'No payments recorded',
      'no_payments_desc': 'No payment schedule or transaction recorded for the moment.',
      'cash': 'Cash',
      'bank_transfer': 'Bank Transfer',
      'check': 'Check',
      'card': 'Card',
      'receipt': 'Receipt',

      // Documents Extended
      'certificates': 'Certificates',
      'transcripts': 'Transcripts',
      'id_cards': 'ID Cards',
      'other_docs': 'Other Documents',
      'no_documents': 'No documents available',
      'downloading': 'Downloading',

      // Group Extended
      'search_students': 'Search students...',

      // Profile
      'personal_info': 'Personal Information',
      'academic_info': 'Academic Information',
      'full_name': 'Full Name',
      'phone': 'Phone',
      'birth_date': 'Birth Date',
      'group_name': 'Group',
      'academic_year': 'Academic Year',
      'student_id': 'Student ID',

      // Profile Extended
      'date_of_birth': 'Date of Birth',
      'address': 'Address',
      'student_code': 'Student Code',
      'current_class': 'Current Class',

      // Documents Extended
      'documents_description': 'Official documents and forms',
      'document_administrative': 'Administrative',
      'document_exams': 'Exams',
      'document_other': 'Other',
      'sort_by': 'Sort by',
      'all_types': 'All types',
      'no_docs_for_semester': 'No documents for Semester {sem}',
      'no_matching_documents': 'No matching documents',
      'try_select_another_type': 'Try selecting another type',
      'doc_type_administrative': 'Administrative',
      'doc_type_attestation': 'School Attendance Certificate',
      'doc_type_releve_notes': 'Transcript of Records',
      'doc_type_certificat': 'Registration Certificate',
      'doc_type_carte_etudiant': 'Student Card',
      'doc_type_exams': 'Exams & Evaluations',
      'doc_type_planning': 'Timetable & Schedule',
      'doc_type_courses': 'Course Materials & Syllabus',
      'doc_type_stage_pfe': 'Internship Agreement / FYP',
      'doc_type_reglement': 'Internal Regulations',
      'doc_type_other': 'Other document',
      'application_developer': 'Application Developer',
      'visit_portfolio': 'Visit Portfolio',
      'report_a_bug': 'Report a Bug',
      'report_bug_subtitle': 'Help us fix it',
      'bug_title_label': 'Bug Title',
      'bug_title_hint': 'E.g., Button not responding on timetable',
      'bug_desc_label': 'Description',
      'bug_desc_hint': 'Explain what happened and steps to reproduce...',
      'bug_type_label': 'Issue Category',
      'bug_type_visual': 'Visual / UI glitch',
      'bug_type_functional': 'Feature not working',
      'bug_type_crash': 'Crash or freeze',
      'bug_type_other': 'Other problem',
      'add_screenshots': 'Attach Screenshots (optional)',
      'bug_screenshot_label': 'Screenshots',
      'submit_bug_report': 'Send Bug Report',
      'bug_report_success': 'Bug report submitted successfully! The developers have received it.',

      // Timetable Extended
      'no_courses': 'No courses scheduled',

      // Absences Extended
      'absence_hours': 'hours of absence',

      // Payments Extended
      'payment_schedule': 'Payment Schedule',
      'status_paid': 'Paid',
      'status_overdue': 'Overdue',
      'status_pending': 'Pending',

      // Contact
      'need_help': 'Need Help?',
      'contact_desc':
          'We are here to assist you with any questions or concerns.',
      'email_us': 'Email Us',
      'call_us': 'Call Us',
      'visit_us': 'Visit Us',
      'office_hours': 'Office Hours',
      'office_hours_value': 'Mon-Fri: 8:00 - 17:00',
      'follow_us': 'Follow Us',

      // About
      'about_desc':
          'Student Portal is your comprehensive academic companion, designed to help you stay connected with your school and manage your academic journey effectively.',
      'features': 'Features',
      'feature_academic_tracking_title': 'Smart Academic Tracking',
      'feature_academic_tracking_desc':
          'Live averages, weighted coefficients and in-depth performance analytics',
      'feature_dynamic_schedule_title': 'Dynamic Class Timetable',
      'feature_dynamic_schedule_desc':
          'Interactive weekly schedule, room assignments and live period updates',
      'feature_attendance_title': 'Attendance & Absences Monitoring',
      'feature_attendance_desc':
          'Accurate hourly calculation, automatic threshold alerts and justification management',
      'feature_documents_title': 'Digital School Documents',
      'feature_documents_desc':
          'Direct access and fast download of certificates, transcripts and course files',
      'feature_financial_title': 'Financial & Payment Tracking',
      'feature_financial_desc':
          'Transparent tuition management, upcoming installments and payment receipts',
      'feature_ai_title': 'NOVA AI & Direct Assistance',
      'feature_ai_desc':
          '24/7 intelligent academic assistant and direct school suggestions box',
      'feature_announcements': 'Real-time announcements and messages',
      'feature_grades': 'View your grades and academic performance',
      'feature_absences': 'Track your attendance and absences',
      'feature_timetable': 'Access your class schedule',
      'feature_payments': 'Manage tuition payments',
      'feature_documents': 'Download official documents',
      'developed_by': 'Developed By',
      'all_rights_reserved': 'All rights reserved.',
      'privacy_policy': 'Privacy Policy',
      'terms_of_service': 'Terms of Service',
      'etablissement': 'School',
      'niveau': 'Level',
      'filiere': 'Field',
      'enrollment_status': 'Enrollment Status',
      'enrolled_and_active': 'Enrolled & Active',
      'personal_info_title': 'Personal Information',
      'student_code_copied': 'Student code copied!',
      'email_copied': 'Email copied to clipboard!',
      'settings_subtitle': 'Preferences & Customization',
      'notifications_alerts': 'Notifications & Alerts',
      'notif_grades_title': 'Grades & Evaluations',
      'notif_grades_subtitle': 'Instant alert when a grade is published',
      'notif_timetable_title': 'Timetable & Courses',
      'notif_timetable_subtitle': 'Course reminders and schedule changes',
      'notif_absences_title': 'Absences & Late',
      'notif_absences_subtitle': 'Notification when an absence is recorded',
      'notif_announcements_title': 'Announcements & Official Messages',
      'notif_announcements_subtitle': 'Important communications from the school',
      'security_access': 'Security & Access',
      'change_password': 'Change Password',
      'change_password_subtitle': 'Modify your access code',
      'biometric_lock': 'Biometric Lock',
      'biometric_lock_subtitle': 'Unlock with Face ID or Fingerprint',
      'appearance': 'Appearance',
      'theme_subtitle': 'Choose a display mode',
      'privacy': 'Privacy & Data',
      'clear_cache': 'Clear Cache',
      'clear_cache_subtitle': 'Free up local storage',
      'home_subtitle_absences': 'Check your absences',
      'home_subtitle_suggestions': 'Share your ideas',
      'home_subtitle_results': 'View your results',
      'home_subtitle_timetable': 'Your week\'s schedule',
      'home_subtitle_group': 'Your classmates',
      'home_subtitle_solde': 'Manage your payments',
      'home_subtitle_documents': 'Access documents',
      'suggestions_subtitle': 'Share your ideas',
      'share_ideas': 'Share your ideas',
      'join_us_social': 'Join us on social media',
      'nos_coordonnees': 'Our Coordinates',
      'call_us_contact': 'Call Us',
      'visit_us_contact': 'Visit Us',
      'office_hours_schedule': 'Opening Hours',
      'mon_profil': 'My Profile',
      'profil_subtitle': 'Personal account & information',
      'app_version': 'Version',
      'developed_with_love': 'Application developed with ❤️',
          'student_card_title': 'STUDENT\nCARD',
      'card_name': 'Name',
      'card_class': 'Class',
      'card_dob': 'D.O.B',
      'card_address': 'Address',
      'schedule_title': 'Opening Hours',
      'open_to_all': 'Open to all',
      'location_access': 'Location & Access',
      'directions': 'Directions',
      'website': 'Website',
      'logout_confirm_msg': 'Are you sure you want to log out of your account?',
      'day_lun': 'Mon',
      'day_mar': 'Tue',
      'day_mer': 'Wed',
      'day_jeu': 'Thu',
      'day_ven': 'Fri',
      'day_sam': 'Sat',
      'day_dim': 'Sun',
          'about_subtitle': 'Discover our institution',
      'month': 'Month',
      'week': 'Week',
      'absences_subtitle': 'Attendance tracking',
      'overall_absence_rate': 'Overall absence rate',
      'unknown_subject': 'Unknown subject',
      'critical': 'critical',
      'no_absences_month': 'No absences this month',
      'no_absences_week': 'No absences this week',
      'justified_absence': 'Justified Absence',
      'unjustified_absence': 'Unjustified Absence',
      'sessions_count': 'sessions',
      'coeff_label': 'Coeff',
      'total_label': 'Total',
      'sem_label': 'Wks',
      'absent_label': 'Absent',
      'ci_label': 'CI',
      'error_loading_details': 'Unable to load details',
      'academic_subject': 'Subject',
      'emploi_subtitle': 'Class Timetable',
      'exam_timetable_subtitle': 'Exam Schedule',
      'upcoming_semester': 'Upcoming Semester',
      'timetable_available_from': 'Timetable will be available from {date}.',
      'timetable_available_start': 'Timetable will be available at the start of the semester.',
      'no_exams_scheduled': 'No Exams Scheduled',
      'no_exams_desc': 'Exam schedules for this semester have not yet been published by administration.',
      'timetable_not_available': 'Timetable Not Available',
      'timetable_not_available_desc': 'Class timetable for this semester has not yet been created by administration.',
      'results_subtitle': 'Track your grades',
      'solde_subtitle': 'Payment tracking',
      'suggestion_type': 'Suggestion type',
      'select_type': 'Select type',
      'description_label': 'Description',
      'describe_suggestion_hint': 'Describe your suggestion in detail...',
      'suggestion_submitted_success': 'Suggestion submitted successfully!',
      'please_fill_description': 'Please fill in the description',
      'error_selecting_files': 'Error selecting files',
      'no_suggestions': 'No suggestions',
      'no_results': 'No results',
      'due_date_label': 'Due Date',
      'payment_date_label': 'Payment Date',
      'delay_label': 'Delay',
      'amount_label': 'Amount',
      'method_label': 'Method',
      'close_label': 'Close',
      'st_reclamation_note': 'Grade Inquiry / Claim',
      'st_absence': 'Absence / Justification',
      'st_emploi_temps': 'Timetable / Schedule',
      'st_inscription': 'Registration / Re-enrollment',
      'st_paiement': 'Payment / Tuition fees',
      'st_orientation': 'Orientation / Major change',
      'st_bourse': 'Scholarship / Financial aid',
      'st_transport': 'Transport / Housing',
      'st_restauration': 'University dining',
      'st_bibliotheque': 'Library / Resources',
      'st_vie_universitaire': 'Campus life / Activities',
      'st_infrastructure': 'Infrastructure / Facilities',
      'st_securite': 'Security / Hygiene',
      'st_stage': 'Internship / Graduation project',
      'st_autre': 'Other',
      'st_general': 'General',
      'st_request': 'Request / Inquiry',
      'st_administrative': 'Administrative',
      'st_short_reclamation_note': 'Grade',
      'st_short_absence': 'Absence',
      'st_short_emploi_temps': 'Schedule',
      'st_short_inscription': 'Registration',
      'st_short_paiement': 'Payment',
      'st_short_stage': 'Internship',
      'st_short_orientation': 'Orientation',
      'st_short_bourse': 'Scholarship',
      'st_short_transport': 'Transport',
      'st_short_restauration': 'Dining',
      'st_short_bibliotheque': 'Library',
      'st_short_vie_universitaire': 'Campus life',
      'st_short_infrastructure': 'Facilities',
      'st_short_securite': 'Security',
      'st_short_autre': 'Other',
      'st_short_general': 'General',
      'st_short_request': 'Request',
      'st_short_administrative': 'Admin.',
      'administration': 'Administration',
          'repartition_categorie': 'Breakdown by category',
      'hour_unit': 'h',
      'solde_restant': 'Remaining Balance',
      'currency_tnd': 'TND',
      'reste': 'Remaining',
      'completed': 'Paid',
      'incomplete': 'Pending',
      'progress': 'Progress',
      'category_details': 'Category Details',
      'cat_scolarite': 'Tuition',
      'cat_transport': 'Transport / Bus',
      'cat_inscription': 'Registration',
      'cat_uniforme': 'Uniform',
      'cat_cantine': 'Dining / Cafeteria',
      'cat_activites': 'Activities',
      'cat_autres': 'Other',
      'badge_current': 'Current',
      'badge_upcoming': 'Upcoming',
      'weight_label': 'Weight',
      'progression_semestre': 'Semester Progress',
      'matieres_completes': 'Completed subjects',
      'details_par_matiere': 'Details by subject',
      'no_subjects_assigned': 'No subjects assigned',
      'exam_control_1': 'Control Test 1',
      'exam_control_2': 'Control Test 2',
      'exam_control_3': 'Control Test 3',
      'exam_synthesis': 'Synthesis Exam',
      'exam_practical': 'Practical Work',
      'exam_continuous': 'Continuous Assessment',
      'exam_project': 'Project',
      'exam_oral': 'Oral Exam',
      'exam_generic': 'Exam',
      'welcome_portal': 'Welcome to EduPortal',
      'email_address': 'Email address',
      'email_hint': 'your@email.com',
      'email_required': 'Please enter your email',
      'email_invalid': 'Invalid email address',
      'password_required': 'Please enter your password',
      'forgot_password_q': 'Forgot password?',
      'forgot_password_title': 'Forgot Password',
      'forgot_password_desc': 'Enter your email to request a password reset.',
      'admin_process_notice': 'The administrator will process your request shortly.',
      'request_sent_title': 'Request Sent!',
      'request_sent_desc': 'Your reset request has been sent to the administrator.',
      'request_sent_note': 'You will receive a new password once your request is approved.',
      'btn_understood': 'Understood',
      'btn_send_request': 'Send request',
      'access_denied': 'Access Denied',
      'access_denied_student_only': 'This application is for students only.',
      'access_denied_admin_dashboard': 'If you are an administrator, please use the admin dashboard.',
      'not_assigned': 'Not assigned',
      'file_label': 'File',
      'size_label': 'Size',
      'downloading_status': 'Downloading...',
      'pinned': 'Pinned',
      'important': 'Important',
      'sent_by': 'Sent by',
      'delete_conversation': 'Delete conversation',
      'change_photo': 'Change your photo',
      'choose_photo_source': 'Choose source:',
      'take_photo': 'Take a photo',
      'take_photo_subtitle': 'Use your camera directly',
      'choose_gallery': 'Choose from gallery',
      'choose_gallery_subtitle': 'Select an image from your device',
      'current_password': 'Current password',
      'new_password': 'New password',
      'confirm_new_password': 'Confirm new password',
      'passwords_mismatch': 'New passwords do not match',
      'password_updated_success': 'Password updated successfully!',
      'current_password_required': 'Please enter your current password',
      'password_too_short': 'Password must be at least 6 characters',
      'current_password_incorrect': 'Current password is incorrect',
      'password_update_failed': 'Failed to update password. Please try again',
      'cache_cleared_success': 'Cache cleared successfully! (14.8 MB freed)',
      'photo_updated_success': 'Profile photo updated successfully!',
      'photo_upload_error': 'Failed to upload photo. Please try again',
      'adjust_photo': 'Adjust Photo',
      'crop_photo_hint': 'Pinch & drag to frame',
      'crop_card_shape': 'Student Card',
      'crop_avatar_shape': 'Avatar Circle',
      'crop_rotate': 'Rotate',
      'crop_reset': 'Reset',
      'crop_center': 'Center',
      'crop_done': 'Done',
      'cropping_photo': 'Cropping...',
      'user_not_connected': 'User not connected',
      'base_education': 'Basic Education',
      'general_branch': 'Common Core',
      'saving': 'Saving...',
      'notifications_subtitle': 'Stay informed',
      'messages_subtitle': 'Class messages',
      'no_notifications': 'No notifications',
      'notifications_appear_here': 'Notifications will appear here',
      'no_messages': 'No messages',
      'messages_appear_here': 'Class messages will appear here',
      'tap_to_download': 'Tap to download',
      'image_unavailable': 'Image unavailable',
      'open_label': 'Open',
      'cannot_open_file': 'Unable to open file',
      'attached_file': 'Attached file',
      'doc_pdf': 'PDF Document',
      'doc_word': 'Word Document',
      'doc_excel': 'Excel File',
      'doc_ppt': 'Presentation',
      'doc_image': 'Image',
      'doc_video': 'Video',
      'doc_audio': 'Audio',
      'doc_archive': 'Archive',
      'at_teacher_absent': 'Teacher absence',
      'at_room_change': 'Room change',
      'at_exam': 'Exam',
      'at_reminder': 'Reminder',
      'at_closure': 'Closure',
      'at_trip': 'Trip / Excursion',
      'at_party': 'Event',
      'at_payment': 'Payment',
      'at_retenue': 'Detention',
      'at_avertissement': 'Warning',
      'at_exclusion_classe': 'Class exclusion',
      'at_exclusion_etablissement': 'School suspension',
      'at_convocation_parents': 'Parent summons',
      'at_conseil_discipline': 'Disciplinary council',
      'at_exclusion_definitive': 'Permanent expulsion',
      'at_general': 'General',

      // AI Chat
      'ai_assistant_name': 'NOVA',
      'ai_assistant_role': 'Student Assistant',
      'ai_thinking': 'Thinking...',
      'ai_welcome_message': 'Hello, how can I help you today?',
      'ask_ai_question_hint': 'Ask your question...',
      'attached_image': 'Attached image',
      'attach_title': 'Attach',
      'photo_library': 'Photo library',
      'photo_library_desc': 'Share an image or document',
      'take_photo_desc': 'Capture a document or note',
      'chat_history': 'Chat History',
      'no_conversations': 'No conversations yet',
      'new_conversation': 'New conversation',
      'delete_conversation_confirm': 'Are you sure you want to delete this conversation?',
      'time_just_now': 'Just now',
      'time_mins_ago': '{min}m ago',
      'time_hours_ago': '{hours}h ago',
      'time_days_ago': '{days}d ago',
    },
    'fr': {
      // App
      'app_name': 'Portail Étudiant',
      'welcome': 'Bienvenue',
      'logout': 'Déconnexion',
      'settings': 'Paramètres',
      'profile': 'Profil',
      'contact_us': 'Contactez-nous',
      'about': 'À propos de',

      // Auth
      'login': 'Connexion',
      'register': 'Inscription',
      'email': 'Email',
      'password': 'Mot de passe',
      'confirm_password': 'Confirmer le mot de passe',
      'forgot_password': 'Mot de passe oublié?',
      'no_account': 'Vous n\'avez pas de compte?',
      'already_account': 'Vous avez déjà un compte?',
      'sign_in': 'Se connecter',
      'sign_up': 'S\'inscrire',
      'invalid_credentials': 'Email ou mot de passe incorrect.',
      'server_error': 'Erreur de connexion au serveur. Veuillez réessayer plus tard.',
      'network_error': 'Veuillez vérifier votre connexion Internet.',
      'offline_mode': 'Mode hors ligne',
      'offline_short': 'Hors ligne',
      'server_down_short': 'Hors ligne',
      'online_restored': 'En ligne',

      // Home Menu Items
      'note_info': 'Notifications',
      'messages': 'Messages',
      'suggestions': 'Suggestions',
      'absences': 'Absences',
      'resultats': 'Résultats',
      'emploi': 'Emploi',
      'mon_groupe': 'Mon Groupe',
      'mon_solde': 'Mon Solde',
      'documents': 'Documents',

      // Bottom Nav
      'my_profile': 'Mon Profil',
      'contact': 'Contactez-nous',
      'home': 'Accueil',
      'notifications': 'Notifications',

      // Absences
      'absence_list': 'Absence: Liste des périodes',
      'select_semester': 'Sélectionner le Semestre',
      'semester': 'Semestre',
      'total_hours_charge': 'Charge horaire totale',
      'weekly_ci_hours': 'Nbr H CI',
      'weekly_tp_hours': 'Nbr H TP',
      'weeks': 'Semaines',
      'total_absent': 'Total Absent',
      'absence_percent': '% Absence',
      'warning_absence':
          'Attention! Vous approchez du seuil d\'absences autorisé.',
      'critical_absence':
          'Attention! Vous avez dépassé le seuil critique d\'absences.',
      'eliminated_absence':
          'Attention! Vous avez été éliminé de la session principale des examens.',

      // Results
      'semester_average': 'Moy Semestre',
      'coefficient': 'Coefficient',
      'subject_average': 'Moyenne Matière',
      'grade_not_available': 'ND',
      'grade_not_planned': 'NP',

      // Suggestions
      'subject': 'Sujet',
      'message': 'Message',
      'attachment': 'Pièce jointe',
      'send': 'Envoyer',
      'status_sent': 'Envoyé',
      'status_read': 'Lu',
      'status_replied': 'Répondu',

      // Payments
      'total_amount': 'Montant Total',
      'paid_amount': 'Montant Payé',
      'remaining_amount': 'Montant Restant',
      'payment_history': 'Historique des Paiements',
      'payment_date': 'Date',
      'date': 'Date',
      'payment_method': 'Méthode',
      'payment_status': 'Statut',
      'payment_pending': 'En attente',
      'payment_paid': 'Payé',
      'payment_overdue': 'En retard',

      // Timetable
      'monday': 'Lundi',
      'tuesday': 'Mardi',
      'wednesday': 'Mercredi',
      'thursday': 'Jeudi',
      'friday': 'Vendredi',
      'saturday': 'Samedi',
      'sunday': 'Dimanche',
      'room': 'Salle',
      'teacher': 'Enseignant',

      // Documents
      'download': 'Télécharger',
      'category': 'Catégorie',
      'administrative': 'Administratif',
      'courses': 'Cours',
      'exams': 'Examens',
      'other': 'Autre',

      // Group
      'class_name': 'Classe',
      'level': 'Niveau',
      'group': 'Groupe',
      'section': 'Section',

      // Settings
      'language': 'Langue',
      'theme': 'Thème',
      'light_theme': 'Clair',
      'dark_theme': 'Sombre',
      'system_theme': 'Système',
      'notifications_enabled': 'Notifications',

      // Common
      'loading': 'Chargement...',
      'error': 'Erreur',
      'retry': 'Réessayer',
      'refresh': 'Actualiser',
      'cancel': 'Annuler',
      'save': 'Enregistrer',
      'delete': 'Supprimer',
      'edit': 'Modifier',
      'confirm': 'Confirmer',
      'no_data': 'Aucune donnée disponible',
      'search': 'Rechercher',
      'submit': 'Envoyer',
      'field_required': 'Ce champ est requis',
      'announcements': 'Annonces',

      // Absences Extended
      'total_hours': 'Charge horaire totale',
      'ci_hours': 'Nbr H CI',
      'tp_hours': 'Nbr H TP',
      'absences_count': 'absences',
      'no_absences': 'Aucune absence enregistrée',
      'no_absences_desc': 'Aucune absence enregistrée pour ce semestre.',
      'no_search_results_desc': 'Aucune matière correspondante trouvée.',
      'absence_warning':
          'Attention! Vous approchez du seuil d\'absences autorisé.',
      'absence_critical':
          'Critique! Vous avez dépassé le seuil critique d\'absences.',
      'absence_fail':
          'Éliminé! Vous avez été éliminé de la session principale des examens.',
      'no_classes': 'Pas de cours programmés',

      // Results Extended
      'component': 'Composante',
      'weight': 'Poids',
      'grade': 'Note',
      'no_grades_yet': 'Aucune note disponible pour le moment',
      'passed': 'Validé',
      'failed': 'Non Validé',

      // Suggestions Extended
      'my_suggestions': 'Mes Suggestions',
      'new_suggestion': 'Nouvelle Suggestion',
      'pending': 'En attente',
      'in_review': 'En cours de traitement',
      'replied': 'Répondu',
      'closed': 'Fermé',
      'reply': 'réponse',
      'submitted_at': 'Soumis le',
      'admin_response': 'Réponse de l\'administration',
      'submit_suggestion': 'Soumettre une Suggestion',
      'suggestion_desc': 'Partagez vos idées et commentaires avec nous',
      'enter_subject': 'Entrez le sujet',
      'your_suggestion': 'Votre suggestion',
      'enter_suggestion': 'Décrivez votre suggestion en détail...',
      'suggestion_min_length':
          'La suggestion doit contenir au moins 20 caractères',
      'suggestion_submitted': 'Suggestion soumise avec succès!',

      // Payments Extended
      'payment_plan': 'Plan de Paiement',
      'remaining_balance': 'Solde Restant',
      'remaining_short': 'Reste',
      'paid': 'Payé',
      'total': 'Total',
      'fully_paid': 'Entièrement Payé',
      'in_progress': 'En cours',
      'installment': 'Tranche',
      'due_date': 'Échéance',
      'no_payments': 'Aucun paiement enregistré',
      'no_payments_desc': 'Aucun échéancier ou paiement n\'est enregistré pour le moment.',
      'cash': 'Espèces',
      'bank_transfer': 'Virement bancaire',
      'check': 'Chèque',
      'card': 'Carte bancaire',
      'receipt': 'Reçu',

      // Documents Extended
      'certificates': 'Attestations',
      'transcripts': 'Relevés de notes',
      'id_cards': 'Cartes d\'étudiant',
      'other_docs': 'Autres documents',
      'no_documents': 'Aucun document disponible',
      'downloading': 'Téléchargement',

      // Group Extended
      'search_students': 'Rechercher des étudiants...',

      // Profile
      'personal_info': 'Informations Personnelles',
      'academic_info': 'Informations Académiques',
      'full_name': 'Nom Complet',
      'phone': 'Téléphone',
      'birth_date': 'Date de Naissance',
      'group_name': 'Groupe',
      'academic_year': 'Année Académique',
      'student_id': 'Numéro Étudiant',

      // Profile Extended
      'date_of_birth': 'Date de Naissance',
      'address': 'Adresse',
      'student_code': 'Code Étudiant',
      'current_class': 'Classe Actuelle',

      // Documents Extended FR
      'documents_description': 'Documents officiels et formulaires',
      'document_administrative': 'Administratif',
      'document_exams': 'Examens',
      'document_other': 'Autre',
      'sort_by': 'Trier par',
      'all_types': 'Tous les types',
      'no_docs_for_semester': 'Aucun document pour le Semestre {sem}',
      'no_matching_documents': 'Aucun document correspondant',
      'try_select_another_type': 'Essayez de sélectionner un autre type',
      'doc_type_administrative': 'Administratif',
      'doc_type_attestation': 'Attestation de scolarité',
      'doc_type_releve_notes': 'Relevé de notes',
      'doc_type_certificat': 'Certificat d\'inscription',
      'doc_type_carte_etudiant': 'Carte d\'étudiant',
      'doc_type_exams': 'Examens & Évaluations',
      'doc_type_planning': 'Emploi du temps & Planning',
      'doc_type_courses': 'Supports de cours & Syllabus',
      'doc_type_stage_pfe': 'Convention de stage / PFE',
      'doc_type_reglement': 'Règlement intérieur',
      'doc_type_other': 'Autre document',
      'application_developer': 'Développeur de l\'application',
      'visit_portfolio': 'Voir le portfolio',
      'report_a_bug': 'Signaler un bug',
      'report_bug_subtitle': 'Aidez-nous à corriger',
      'bug_title_label': 'Titre du bug',
      'bug_title_hint': 'Ex: Bouton ne répond pas sur l\'emploi du temps',
      'bug_desc_label': 'Description détaillée',
      'bug_desc_hint': 'Expliquez ce qui s\'est passé et les étapes pour reproduire...',
      'bug_type_label': 'Catégorie de l\'anomalie',
      'bug_type_visual': 'Problème visuel / Affichage',
      'bug_type_functional': 'Fonctionnalité bloquée',
      'bug_type_crash': 'Plantage ou blocage',
      'bug_type_other': 'Autre problème',
      'add_screenshots': 'Captures d\'écran (optionnel)',
      'bug_screenshot_label': 'Capture d\'écran',
      'submit_bug_report': 'Envoyer le signalement',
      'bug_report_success': 'Signalement envoyé avec succès ! Il a été transmis aux développeurs.',

      // Timetable Extended FR
      'no_courses': 'Pas de cours programmés',

      // Absences Extended FR
      'absence_hours': 'heures d\'absence',

      // Payments Extended FR
      'payment_schedule': 'Échéancier de Paiement',
      'status_paid': 'Payé',
      'status_overdue': 'En retard',
      'status_pending': 'En attente',

      // Contact
      'need_help': 'Besoin d\'aide?',
      'contact_desc':
          'Nous sommes là pour vous aider avec toutes vos questions ou préoccupations.',
      'email_us': 'Envoyez-nous un Email',
      'call_us': 'Appelez-nous',
      'visit_us': 'Visitez-nous',
      'office_hours': 'Heures d\'ouverture',
      'office_hours_value': 'Lun-Ven: 8h00 - 17h00',
      'follow_us': 'Suivez-nous',

      // About
      'about_desc':
          'Le Portail Étudiant est votre compagnon académique complet, conçu pour vous aider à rester connecté avec votre école et à gérer efficacement votre parcours académique.',
      'features': 'Fonctionnalités',
      'feature_academic_tracking_title': 'Suivi Académique Intelligent',
      'feature_academic_tracking_desc':
          'Moyennes en direct, coefficients et analyses détaillées des performances',
      'feature_dynamic_schedule_title': 'Emploi du Temps Dynamique',
      'feature_dynamic_schedule_desc':
          'Planning hebdomadaire interactif, salles de cours et mises à jour synchronisées',
      'feature_attendance_title': 'Assiduité & Contrôle des Présences',
      'feature_attendance_desc':
          'Décompte horaire précis, seuils d\'alerte automatisés et justifications',
      'feature_documents_title': 'E-Documents Scolaires',
      'feature_documents_desc':
          'Téléchargement direct d\'attestations, relevés et supports pédagogiques',
      'feature_financial_title': 'Suivi Financier & Échéanciers',
      'feature_financial_desc':
          'Transparence totale des règlements, échéances de paiement et reçus',
      'feature_ai_title': 'Assistant IA NOVA & Boîte à Idées',
      'feature_ai_desc':
          'Assistance intelligente 24h/24 et canal direct de suggestions avec l\'administration',
      'feature_announcements': 'Annonces et messages en temps réel',
      'feature_grades': 'Consultez vos notes et performances académiques',
      'feature_absences': 'Suivez votre présence et vos absences',
      'feature_timetable': 'Accédez à votre emploi du temps',
      'feature_payments': 'Gérez vos paiements de scolarité',
      'feature_documents': 'Téléchargez des documents officiels',
      'developed_by': 'Développé par',
      'all_rights_reserved': 'Tous droits réservés.',
      'privacy_policy': 'Politique de Confidentialité',
      'terms_of_service': 'Conditions d\'Utilisation',
      'etablissement': 'Établissement',
      'niveau': 'Niveau',
      'filiere': 'Filière',
      'enrollment_status': 'Statut de scolarité',
      'enrolled_and_active': 'Inscrit & Actif',
      'personal_info_title': 'Informations Personnelles',
      'student_code_copied': 'Code étudiant copié !',
      'email_copied': 'Email copié dans le presse-papiers !',
      'settings_subtitle': 'Préférences et personnalisation',
      'notifications_alerts': 'Notifications & Alertes',
      'notif_grades_title': 'Notes & Évaluations',
      'notif_grades_subtitle': 'Alerte instantanée dès qu\'une note est publiée',
      'notif_timetable_title': 'Emploi du temps & Cours',
      'notif_timetable_subtitle': 'Rappels des cours et changements d\'horaires',
      'notif_absences_title': 'Absences & Retards',
      'notif_absences_subtitle': 'Notification en cas d\'absence enregistrée',
      'notif_announcements_title': 'Annonces & Messages officiels',
      'notif_announcements_subtitle': 'Communiqués importants du lycée',
      'security_access': 'Sécurité & Accès',
      'change_password': 'Changer le mot de passe',
      'change_password_subtitle': 'Modifier votre code d\'accès secret',
      'biometric_lock': 'Verrouillage Biométrique',
      'biometric_lock_subtitle': 'Déverrouiller avec Face ID ou Empreinte',
      'appearance': 'Apparence',
      'theme_subtitle': 'Choisissez un mode d\'affichage',
      'privacy': 'Confidentialité & Données',
      'clear_cache': 'Vider le cache',
      'clear_cache_subtitle': 'Libérer le stockage local',
      'home_subtitle_absences': 'Consultez vos absences',
      'home_subtitle_suggestions': 'Partagez vos idées',
      'home_subtitle_results': 'Voir vos résultats',
      'home_subtitle_timetable': 'Votre emploi de la semaine',
      'home_subtitle_group': 'Vos camarades de classe',
      'home_subtitle_solde': 'Gérez vos paiements',
      'home_subtitle_documents': 'Accédez aux documents',
      'suggestions_subtitle': 'Partagez vos idées',
      'share_ideas': 'Partagez vos idées',
      'join_us_social': 'Rejoignez-nous sur les réseaux',
      'nos_coordonnees': 'Nos Coordonnées',
      'call_us_contact': 'Appelez-nous',
      'visit_us_contact': 'Visitez-nous',
      'office_hours_schedule': 'Horaires d\'ouverture',
      'mon_profil': 'Mon Profil',
      'profil_subtitle': 'Compte personnel & informations',
      'app_version': 'Version',
      'developed_with_love': 'Application développée avec ❤️',
      'student_card_title': "CARTE\nD'ÉTUDIANT",
      'card_name': 'Nom',
      'card_class': 'Cl',
      'card_dob': 'D.D.N',
      'card_address': 'Adresse',
      'schedule_title': 'Horaires',
      'open_to_all': 'Ouvert à tous',
      'location_access': 'Emplacement & Accès',
      'directions': 'Itinéraire',
      'website': 'Site Web',
      'logout_confirm_msg': 'Êtes-vous sûr de vouloir vous déconnecter de votre compte ?',
      'day_lun': 'Lun',
      'day_mar': 'Mar',
      'day_mer': 'Mer',
      'day_jeu': 'Jeu',
      'day_ven': 'Ven',
      'day_sam': 'Sam',
      'day_dim': 'Dim',
          'about_subtitle': 'Découvrez notre institution',
      'month': 'Mois',
      'week': 'Semaine',
      'absences_subtitle': 'Suivi de présence',
      'overall_absence_rate': "Taux d'absence global",
      'unknown_subject': 'Matière inconnue',
      'critical': 'critique',
      'no_absences_month': 'Aucune absence ce mois-ci',
      'no_absences_week': 'Aucune absence cette semaine',
      'justified_absence': 'Absence Justifiée',
      'unjustified_absence': 'Absence Non Justifiée',
      'sessions_count': 'séances',
      'coeff_label': 'Coeff',
      'total_label': 'Total',
      'sem_label': 'Sem.',
      'absent_label': 'Absent',
      'ci_label': 'CI',
      'error_loading_details': 'Impossible de charger les détails',
      'academic_subject': 'Matière',
      'emploi_subtitle': 'Emploi du temps de la classe',
      'exam_timetable_subtitle': 'Horaires des épreuves d\'examen',
      'upcoming_semester': 'Semestre à venir',
      'timetable_available_from': 'L\'emploi du temps sera disponible à partir du {date}.',
      'timetable_available_start': 'L\'emploi du temps sera disponible dès le début du semestre.',
      'no_exams_scheduled': 'Aucun examen planifié',
      'no_exams_desc': 'Les horaires des examens pour ce semestre n\'ont pas encore été publiés par l\'administration.',
      'timetable_not_available': 'Emploi du temps non disponible',
      'timetable_not_available_desc': 'L\'emploi du temps de la classe pour ce semestre n\'a pas encore été créé par l\'administration.',
      'results_subtitle': 'Suivi de vos notes',
      'solde_subtitle': 'Suivi des paiements',
      'suggestion_type': 'Type de suggestion',
      'select_type': 'Sélectionner',
      'description_label': 'Description',
      'describe_suggestion_hint': 'Décrivez votre suggestion en détail...',
      'suggestion_submitted_success': 'Suggestion envoyée avec succès!',
      'please_fill_description': 'Veuillez remplir la description',
      'error_selecting_files': 'Erreur lors de la sélection des fichiers',
      'no_suggestions': 'Aucune suggestion',
      'no_results': 'Aucun résultat',
      'due_date_label': 'Échéance',
      'payment_date_label': 'Date de paiement',
      'delay_label': 'Retard',
      'amount_label': 'Montant',
      'method_label': 'Méthode',
      'close_label': 'Fermer',
      'st_reclamation_note': 'Réclamation de note',
      'st_absence': 'Absence / Justification',
      'st_emploi_temps': 'Emploi du temps',
      'st_inscription': 'Inscription / Réinscription',
      'st_paiement': 'Paiement / Frais de scolarité',
      'st_orientation': 'Orientation / Changement de filière',
      'st_bourse': 'Bourse / Aide sociale',
      'st_transport': 'Transport / Hébergement',
      'st_restauration': 'Restauration universitaire',
      'st_bibliotheque': 'Bibliothèque / Ressources',
      'st_vie_universitaire': 'Vie universitaire / Activités',
      'st_infrastructure': 'Infrastructure / Équipements',
      'st_securite': 'Sécurité / Hygiène',
      'st_stage': 'Stage / PFE',
      'st_autre': 'Autre',
      'st_general': 'Général',
      'st_request': 'Demande / Requête',
      'st_administrative': 'Administratif',
      'st_short_reclamation_note': 'Note',
      'st_short_absence': 'Absence',
      'st_short_emploi_temps': 'EDT',
      'st_short_inscription': 'Inscription',
      'st_short_paiement': 'Paiement',
      'st_short_stage': 'Stage/PFE',
      'st_short_orientation': 'Orientation',
      'st_short_bourse': 'Bourse',
      'st_short_transport': 'Transport',
      'st_short_restauration': 'Resto',
      'st_short_bibliotheque': 'Biblio',
      'st_short_vie_universitaire': 'Vie univ.',
      'st_short_infrastructure': 'Infra.',
      'st_short_securite': 'Sécurité',
      'st_short_autre': 'Autre',
      'st_short_general': 'Général',
      'st_short_request': 'Demande',
      'st_short_administrative': 'Admin.',
      'administration': 'Administration',
          'repartition_categorie': 'Répartition par catégorie',
      'hour_unit': 'h',
      'solde_restant': 'Solde restant',
      'currency_tnd': 'TND',
      'reste': 'Reste',
      'completed': 'Payé',
      'incomplete': 'Non payé',
      'progress': 'Progression',
      'category_details': 'Détails de la catégorie',
      'cat_scolarite': 'Scolarité',
      'cat_transport': 'Transport/Bus',
      'cat_inscription': 'Inscription',
      'cat_uniforme': 'Uniforme',
      'cat_cantine': 'Cantine',
      'cat_activites': 'Activités',
      'cat_autres': 'Autres',
      'badge_current': 'Actuel',
      'badge_upcoming': 'À venir',
      'weight_label': 'Poids',
      'progression_semestre': 'Progression Semestre',
      'matieres_completes': 'Matières complètes',
      'details_par_matiere': 'Détails par matière',
      'no_subjects_assigned': 'Aucune matière assignée',
      'exam_control_1': 'Devoir de Contrôle 1',
      'exam_control_2': 'Devoir de Contrôle 2',
      'exam_control_3': 'Devoir de Contrôle 3',
      'exam_synthesis': 'Devoir de Synthèse',
      'exam_practical': 'Travaux Pratiques',
      'exam_continuous': 'Contrôle Continu',
      'exam_project': 'Projet',
      'exam_oral': 'Examen Oral',
      'exam_generic': 'Examen',
      'welcome_portal': 'Bienvenue sur EduPortail',
      'email_address': 'Adresse e-mail',
      'email_hint': 'votre@email.com',
      'email_required': 'Veuillez entrer votre email',
      'email_invalid': 'Email invalide',
      'password_required': 'Veuillez entrer votre mot de passe',
      'forgot_password_q': 'Mot de passe oublié ?',
      'forgot_password_title': 'Mot de passe oublié',
      'forgot_password_desc': 'Entrez votre email pour demander une réinitialisation de mot de passe.',
      'admin_process_notice': 'L\'administrateur traitera votre demande dans les plus brefs délais.',
      'request_sent_title': 'Demande envoyée !',
      'request_sent_desc': 'Votre demande de réinitialisation a été envoyée à l\'administrateur.',
      'request_sent_note': 'Vous recevrez un nouveau mot de passe une fois votre demande approuvée.',
      'btn_understood': 'Compris',
      'btn_send_request': 'Envoyer la demande',
      'access_denied': 'Accès Refusé',
      'access_denied_student_only': 'Cette application est réservée aux étudiants uniquement.',
      'access_denied_admin_dashboard': 'Si vous êtes administrateur, veuillez utiliser le tableau de bord admin.',
      'not_assigned': 'Non assigné',
      'file_label': 'Fichier',
      'size_label': 'Taille',
      'downloading_status': 'Téléchargement en cours...',
      'pinned': 'Épinglé',
      'important': 'Important',
      'sent_by': 'Envoyé par',
      'delete_conversation': 'Supprimer la conversation',
      'change_photo': 'Modifier votre photo',
      'choose_photo_source': 'Choisir une source :',
      'take_photo': 'Prendre une photo',
      'take_photo_subtitle': 'Utiliser l\'appareil photo directement',
      'choose_gallery': 'Choisir depuis la galerie',
      'choose_gallery_subtitle': 'Sélectionner une image de votre téléphone',
      'current_password': 'Mot de passe actuel',
      'new_password': 'Nouveau mot de passe',
      'confirm_new_password': 'Confirmer le nouveau mot de passe',
      'passwords_mismatch': 'Les nouveaux mots de passe ne correspondent pas',
      'password_updated_success': 'Mot de passe mis à jour avec succès!',
      'current_password_required': 'Veuillez saisir votre mot de passe actuel',
      'password_too_short': 'Le mot de passe doit comporter au moins 6 caractères',
      'current_password_incorrect': 'Le mot de passe actuel est incorrect',
      'password_update_failed': 'Échec de la mise à jour du mot de passe. Veuillez réessayer',
      'cache_cleared_success': 'Cache vidé avec succès ! (14.8 Mo libérés)',
      'photo_updated_success': 'Photo de profil mise à jour avec succès !',
      'photo_upload_error': 'Échec de l\'envoi de la photo. Veuillez réessayer',
      'adjust_photo': 'Ajuster la photo',
      'crop_photo_hint': 'Pincez et glissez pour cadrer',
      'crop_card_shape': 'Carte Étudiant',
      'crop_avatar_shape': 'Cercle Profil',
      'crop_rotate': 'Pivoter',
      'crop_reset': 'Réinitialiser',
      'crop_center': 'Centrer',
      'crop_done': 'Valider',
      'cropping_photo': 'Recadrage...',
      'user_not_connected': 'Utilisateur non connecté',
      'base_education': 'Enseignement de Base',
      'general_branch': 'Tronc Commun',
      'saving': 'Modification...',
      'notifications_subtitle': 'Restez informé',
      'messages_subtitle': 'Messages de classe',
      'no_notifications': 'Aucune notification',
      'notifications_appear_here': 'Les notifications apparaîtront ici',
      'no_messages': 'Aucun message',
      'messages_appear_here': 'Les messages de classe apparaîtront ici',
      'tap_to_download': 'Appuyez pour télécharger',
      'image_unavailable': 'Image non disponible',
      'open_label': 'Ouvrir',
      'cannot_open_file': 'Impossible d\'ouvrir le fichier',
      'attached_file': 'Fichier joint',
      'doc_pdf': 'Document PDF',
      'doc_word': 'Document Word',
      'doc_excel': 'Fichier Excel',
      'doc_ppt': 'Présentation',
      'doc_image': 'Image',
      'doc_video': 'Vidéo',
      'doc_audio': 'Audio',
      'doc_archive': 'Archive',
      'at_teacher_absent': 'Absence prof',
      'at_room_change': 'Changement salle',
      'at_exam': 'Examen',
      'at_reminder': 'Rappel',
      'at_closure': 'Fermeture',
      'at_trip': 'Sortie/Voyage',
      'at_party': 'Événement',
      'at_payment': 'Paiement',
      'at_retenue': 'Retenue',
      'at_avertissement': 'Avertissement',
      'at_exclusion_classe': 'Exclusion classe',
      'at_exclusion_etablissement': 'Exclusion établissement',
      'at_convocation_parents': 'Convocation parents',
      'at_conseil_discipline': 'Conseil discipline',
      'at_exclusion_definitive': 'Exclusion définitive',
      'at_general': 'Général',

      // AI Chat
      'ai_assistant_name': 'NOVA',
      'ai_assistant_role': 'Assistant Étudiant',
      'ai_thinking': 'Réfléchit...',
      'ai_welcome_message': 'Bonjour, comment puis-je vous aider aujourd\'hui ?',
      'ask_ai_question_hint': 'Posez votre question...',
      'attached_image': 'Image attachée',
      'attach_title': 'Joindre',
      'photo_library': 'Bibliothèque photo',
      'photo_library_desc': 'Partager une image ou un document',
      'take_photo_desc': 'Capturer un document ou une note',
      'chat_history': 'Historique',
      'no_conversations': 'Aucune conversation',
      'new_conversation': 'Nouvelle conversation',
      'delete_conversation_confirm': 'Voulez-vous vraiment supprimer cette conversation ?',
      'time_just_now': 'À l\'instant',
      'time_mins_ago': 'Il y a {min} min',
      'time_hours_ago': 'Il y a {hours}h',
      'time_days_ago': 'Il y a {days} jours',
    },
    'ar': {
      // App
      'app_name': 'بوابة الطالب',
      'welcome': 'مرحباً',
      'logout': 'تسجيل الخروج',
      'settings': 'الإعدادات',
      'profile': 'الملف الشخصي',
      'contact_us': 'اتصل بنا',
      'about': 'حول',

      // Auth
      'login': 'تسجيل الدخول',
      'register': 'التسجيل',
      'email': 'البريد الإلكتروني',
      'password': 'كلمة المرور',
      'confirm_password': 'تأكيد كلمة المرور',
      'forgot_password': 'نسيت كلمة المرور؟',
      'no_account': 'ليس لديك حساب؟',
      'already_account': 'لديك حساب بالفعل؟',
      'sign_in': 'دخول',
      'sign_up': 'إنشاء حساب',
      'invalid_credentials': 'البريد الإلكتروني أو كلمة المرور غير صحيحة.',
      'server_error': 'خطأ في الاتصال بالخادم. يرجى المحاولة لاحقاً.',
      'network_error': 'يرجى التحقق من الاتصال بالإنترنت.',
      'offline_mode': 'وضع غير متصل',
      'offline_short': 'غير متصل',
      'server_down_short': 'غير متصل',
      'online_restored': 'متصل',

      // Home Menu Items
      'note_info': 'ملاحظات',
      'messages': 'الرسائل',
      'suggestions': 'الاقتراحات',
      'absences': 'الغيابات',
      'resultats': 'النتائج',
      'emploi': 'الجدول الزمني',
      'mon_groupe': 'مجموعتي',
      'mon_solde': 'رصيدي',
      'documents': 'الوثائق',

      // Bottom Nav
      'my_profile': 'ملفي الشخصي',
      'contact': 'اتصل بنا',

      // Absences
      'absence_list': 'الغياب: قائمة الفترات',
      'select_semester': 'اختر الفصل الدراسي',
      'semester': 'الفصل الدراسي',
      'total_hours_charge': 'إجمالي الساعات',
      'weekly_ci_hours': 'ساعات المحاضرات/أسبوع',
      'weekly_tp_hours': 'ساعات التطبيق/أسبوع',
      'weeks': 'الأسابيع',
      'total_absent': 'إجمالي الغياب',
      'absence_percent': 'نسبة الغياب',
      'warning_absence': 'تحذير! أنت تقترب من حد الغياب المسموح.',
      'critical_absence': 'تحذير! لقد تجاوزت حد الغياب الحرج.',
      'eliminated_absence': 'تحذير! تم استبعادك من الجلسة الرئيسية للامتحانات.',

      // Results
      'semester_average': 'معدل الفصل',
      'coefficient': 'المعامل',
      'subject_average': 'معدل المادة',
      'grade_not_available': 'غ/م',
      'grade_not_planned': 'غ/م',

      // Suggestions
      'subject': 'الموضوع',
      'message': 'الرسالة',
      'attachment': 'مرفق',
      'send': 'إرسال',
      'status_sent': 'مرسل',
      'status_read': 'مقروء',
      'status_replied': 'تم الرد',

      // Payments
      'total_amount': 'المبلغ الإجمالي',
      'paid_amount': 'المبلغ المدفوع',
      'remaining_amount': 'المبلغ المتبقي',
      'payment_history': 'سجل الدفعات',
      'payment_date': 'التاريخ',
      'date': 'التاريخ',
      'payment_method': 'طريقة الدفع',
      'payment_status': 'الحالة',
      'payment_pending': 'قيد الانتظار',
      'payment_paid': 'مدفوع',
      'payment_overdue': 'متأخر',

      // Timetable
      'monday': 'الإثنين',
      'tuesday': 'الثلاثاء',
      'wednesday': 'الأربعاء',
      'thursday': 'الخميس',
      'friday': 'الجمعة',
      'saturday': 'السبت',
      'sunday': 'الأحد',
      'room': 'القاعة',
      'teacher': 'الأستاذ',

      // Documents
      'download': 'تحميل',
      'category': 'الفئة',
      'administrative': 'إداري',
      'courses': 'دروس',
      'exams': 'امتحانات',
      'other': 'أخرى',

      // Group
      'class_name': 'الصف',
      'level': 'المستوى',
      'group': 'المجموعة',
      'section': 'الشعبة',

      // Settings
      'language': 'اللغة',
      'theme': 'المظهر',
      'light_theme': 'فاتح',
      'dark_theme': 'داكن',
      'system_theme': 'النظام',
      'notifications': 'الإشعارات',

      // Common
      'loading': 'جاري التحميل...',
      'error': 'خطأ',
      'retry': 'إعادة المحاولة',
      'refresh': 'تحديث',
      'cancel': 'إلغاء',
      'save': 'حفظ',
      'delete': 'حذف',
      'edit': 'تعديل',
      'confirm': 'تأكيد',
      'no_data': 'لا توجد بيانات',
      'search': 'بحث',
      'submit': 'إرسال',
      'field_required': 'هذا الحقل مطلوب',
      'announcements': 'الإعلانات',

      // Absences Extended
      'total_hours': 'إجمالي الساعات',
      'ci_hours': 'ساعات المحاضرات',
      'tp_hours': 'ساعات التطبيق',
      'absences_count': 'غيابات',
      'no_absences': 'لا يوجد غياب مسجل',
      'no_absences_desc': 'سجلك خالٍ تماماً من أي غيابات لهذا الفصل الدراسي.',
      'no_search_results_desc': 'لم يتم العثور على أي مادة مطابقة للبحث.',
      'absence_warning': 'تحذير! أنت تقترب من حد الغياب المسموح.',
      'absence_critical': 'حرج! لقد تجاوزت حد الغياب الحرج.',
      'absence_fail': 'مستبعد! تم استبعادك من الجلسة الرئيسية للامتحانات.',
      'no_classes': 'لا توجد حصص مجدولة',

      // Results Extended
      'component': 'المكون',
      'weight': 'الوزن',
      'grade': 'الدرجة',
      'no_grades_yet': 'لا توجد درجات متاحة حالياً',
      'passed': 'ناجح',
      'failed': 'راسب',

      // Suggestions Extended
      'my_suggestions': 'اقتراحاتي',
      'new_suggestion': 'اقتراح جديد',
      'pending': 'قيد الانتظار',
      'in_review': 'قيد المراجعة',
      'replied': 'تم الرد',
      'closed': 'مغلق',
      'reply': 'رد',
      'submitted_at': 'تم التقديم في',
      'admin_response': 'رد الإدارة',
      'submit_suggestion': 'تقديم اقتراح',
      'suggestion_desc': 'شارك أفكارك وملاحظاتك معنا',
      'enter_subject': 'أدخل الموضوع',
      'your_suggestion': 'اقتراحك',
      'enter_suggestion': 'صف اقتراحك بالتفصيل...',
      'suggestion_min_length': 'يجب أن يحتوي الاقتراح على 20 حرفًا على الأقل',
      'suggestion_submitted': 'تم تقديم الاقتراح بنجاح!',

      // Payments Extended
      'payment_plan': 'خطة الدفع',
      'remaining_balance': 'الرصيد المتبقي',
      'remaining_short': 'المتبقي',
      'paid': 'مدفوع',
      'total': 'الإجمالي',
      'fully_paid': 'مدفوع بالكامل',
      'in_progress': 'قيد التنفيذ',
      'installment': 'القسط',
      'due_date': 'تاريخ الاستحقاق',
      'no_payments': 'لا توجد مدفوعات مسجلة',
      'no_payments_desc': 'لا يوجد جدول دفع أو معاملات مسجلة في الوقت الحالي.',
      'cash': 'نقداً',
      'bank_transfer': 'تحويل بنكي',
      'check': 'شيك',
      'card': 'بطاقة',
      'receipt': 'إيصال',

      // Documents Extended
      'certificates': 'الشهادات',
      'transcripts': 'كشوف الدرجات',
      'id_cards': 'بطاقات الطالب',
      'other_docs': 'مستندات أخرى',
      'no_documents': 'لا توجد مستندات متاحة',
      'downloading': 'جاري التحميل',

      // Group Extended
      'search_students': 'البحث عن طلاب...',

      // Profile
      'personal_info': 'المعلومات الشخصية',
      'academic_info': 'المعلومات الأكاديمية',
      'full_name': 'الاسم الكامل',
      'phone': 'الهاتف',
      'birth_date': 'تاريخ الميلاد',
      'group_name': 'المجموعة',
      'academic_year': 'السنة الدراسية',
      'student_id': 'رقم الطالب',

      // Profile Extended
      'date_of_birth': 'تاريخ الميلاد',
      'address': 'العنوان',
      'student_code': 'رمز الطالب',
      'current_class': 'الصف الحالي',

      // Documents Extended AR
      'documents_description': 'المستندات الرسمية والنماذج',
      'document_administrative': 'إداري',
      'document_exams': 'امتحانات',
      'document_other': 'أخرى',
      'sort_by': 'ترتيب حسب',
      'all_types': 'جميع الأنواع',
      'no_docs_for_semester': 'لا توجد وثائق للسداسي {sem}',
      'no_matching_documents': 'لا توجد وثائق مطابقة',
      'try_select_another_type': 'جرب تحديد نوع آخر',
      'doc_type_administrative': 'إداري',
      'doc_type_attestation': 'شهادة مدرسية',
      'doc_type_releve_notes': 'كشف الأعداد',
      'doc_type_certificat': 'شهادة ترسيم',
      'doc_type_carte_etudiant': 'بطاقة طالب',
      'doc_type_exams': 'امتحانات وتقييمات',
      'doc_type_planning': 'جدول الأوقات والتخطيط',
      'doc_type_courses': 'دروس ومناهج تعليمية',
      'doc_type_stage_pfe': 'اتفاقية تدريب / تخرج',
      'doc_type_reglement': 'النظام الداخلي',
      'doc_type_other': 'وثيقة أخرى',
      'application_developer': 'مطور التطبيق',
      'visit_portfolio': 'زيارة معرض الأعمال',
      'report_a_bug': 'الإبلاغ عن خلل أو عطل',
      'report_bug_subtitle': 'ساعدنا في الإصلاح',
      'bug_title_label': 'عنوان المشكلة',
      'bug_title_hint': 'مثال: الزر لا يستجيب في جدول الأوقات',
      'bug_desc_label': 'تفاصيل المشكلة',
      'bug_desc_hint': 'اشرح ما حدث والخطوات لتكرار هذا العطل...',
      'bug_type_label': 'نوع المشكلة',
      'bug_type_visual': 'مظهر أو تصميم الواجهة',
      'bug_type_functional': 'ميزة لا تعمل بشكل صحيح',
      'bug_type_crash': 'توقف أو تجمد التطبيق',
      'bug_type_other': 'مشكلة أخرى',
      'add_screenshots': 'لقطات الشاشة (اختياري)',
      'bug_screenshot_label': 'لقطة الشاشة',
      'submit_bug_report': 'إرسال تقرير الخلل',
      'bug_report_success': 'تم إرسال التقرير بنجاح! تم تسليمه لفريق التطوير.',

      // Timetable Extended AR
      'no_courses': 'لا توجد حصص مجدولة',

      // Absences Extended AR
      'absence_hours': 'ساعات الغياب',

      // Payments Extended AR
      'payment_schedule': 'جدول الدفع',
      'status_paid': 'مدفوع',
      'status_overdue': 'متأخر',
      'status_pending': 'قيد الانتظار',

      // Contact
      'need_help': 'هل تحتاج مساعدة؟',
      'contact_desc': 'نحن هنا لمساعدتك في أي أسئلة أو استفسارات.',
      'email_us': 'راسلنا',
      'call_us': 'اتصل بنا',
      'visit_us': 'زورنا',
      'office_hours': 'ساعات العمل',
      'office_hours_value': 'الإثنين-الجمعة: 8:00 - 17:00',
      'follow_us': 'تابعنا',

      // About
      'about_desc':
          'بوابة الطالب هي رفيقك الأكاديمي الشامل، مصممة لمساعدتك على البقاء على اتصال بمدرستك وإدارة مسيرتك الأكاديمية بفعالية.',
      'features': 'المميزات',
      'feature_academic_tracking_title': 'متابعة أكاديمية ذكية',
      'feature_academic_tracking_desc':
          'معدلات مباشرة، معاملات تفصيلية وتحليلات شاملة للمستوى الأكاديمي',
      'feature_dynamic_schedule_title': 'جدول دراسي تفاعلي',
      'feature_dynamic_schedule_desc':
          'جدول الحصص الأسبوعي، تعيين القاعات وتحديثات مباشرة في الوقت الفعلي',
      'feature_attendance_title': 'متابعة الحضور والغياب',
      'feature_attendance_desc':
          'احتساب دقيق لساعات الغياب مع تنبيهات استباقية وإدارة التبريرات',
      'feature_documents_title': 'المستندات والوثائق الرقمية',
      'feature_documents_desc':
          'تحميل مباشر للشهادات المدرسية، كشوف الدرجات والمصادر التعليمية',
      'feature_financial_title': 'متابعة الرسوم والمدفوعات',
      'feature_financial_desc':
          'شفافية كاملة للأقساط الدراسية، المواعيد المحددة وإيصالات الدفع',
      'feature_ai_title': 'المساعد الذكي والتواصل المباشر',
      'feature_ai_desc':
          'مساعد ذكي على مدار الساعة وصندوق مقترحات مباشر للتواصل مع الإدارة',
      'feature_announcements': 'إعلانات ورسائل فورية',
      'feature_grades': 'عرض درجاتك وأدائك الأكاديمي',
      'feature_absences': 'تتبع حضورك وغيابك',
      'feature_timetable': 'الوصول إلى جدول حصصك',
      'feature_payments': 'إدارة مدفوعات الرسوم الدراسية',
      'feature_documents': 'تحميل المستندات الرسمية',
      'developed_by': 'تم التطوير بواسطة',
      'all_rights_reserved': 'جميع الحقوق محفوظة.',
      'privacy_policy': 'سياسة الخصوصية',
      'terms_of_service': 'شروط الخدمة',

      // Profile Extended AR
      'etablissement': 'المؤسسة',
      'niveau': 'المستوى',
      'filiere': 'التخصص',
      'enrollment_status': 'حالة التسجيل',
      'enrolled_and_active': 'مسجل ونشط',
      'personal_info_title': 'المعلومات الشخصية',
      'student_code_copied': 'تم نسخ رمز الطالب!',
      'email_copied': 'تم نسخ البريد الإلكتروني!',
      'settings_subtitle': 'التفضيلات والتخصيص',
      'notifications_alerts': 'الإشعارات والتنبيهات',
      'notif_grades_title': 'النقاط والتقييمات',
      'notif_grades_subtitle': 'تنبيه فوري عند نشر نقطة',
      'notif_timetable_title': 'جدول الأوقات والدروس',
      'notif_timetable_subtitle': 'تذكير بالدروس وتغييرات الجدول',
      'notif_absences_title': 'الغيابات والتأخيرات',
      'notif_absences_subtitle': 'إشعار عند تسجيل غياب',
      'notif_announcements_title': 'الإعلانات والرسائل الرسمية',
      'notif_announcements_subtitle': 'مراسلات مهمة من المدرسة',
      'security_access': 'الأمان والوصول',
      'change_password': 'تغيير كلمة المرور',
      'change_password_subtitle': 'تعديل رمز الوصول السري',
      'biometric_lock': 'القفل البيومتري',
      'biometric_lock_subtitle': 'الفتح ببصمة الوجه أو الإصبع',
      'appearance': 'المظهر',
      'theme_subtitle': 'اختر وضع العرض',
      'privacy': 'الخصوصية والبيانات',
      'clear_cache': 'مسح الذاكرة المؤقتة',
      'clear_cache_subtitle': 'تحرير التخزين المحلي',
      'home_subtitle_absences': 'راجع غياباتك',
      'home_subtitle_suggestions': 'شارك أفكارك',
      'home_subtitle_results': 'اطلع على نتائجك',
      'home_subtitle_timetable': 'جدول أسبوعك',
      'home_subtitle_group': 'زملاؤك في الفصل',
      'home_subtitle_solde': 'إدارة مدفوعاتك',
      'home_subtitle_documents': 'الوصول للوثائق',
      'suggestions_subtitle': 'شارك أفكارك',
      'share_ideas': 'شارك أفكارك',
      'join_us_social': 'انضم إلينا على وسائل التواصل',
      'nos_coordonnees': 'معلومات الاتصال',
      'call_us_contact': 'اتصل بنا',
      'visit_us_contact': 'قم بزيارتنا',
      'office_hours_schedule': 'أوقات العمل',
      'mon_profil': 'ملفي الشخصي',
      'profil_subtitle': 'الحساب الشخصي والمعلومات',
      'app_version': 'الإصدار',
      'developed_with_love': 'تطبيق طُوِّر بـ ❤️',
      'student_card_title': 'بطاقة الطالب',
      'card_name': 'الاسم',
      'card_class': 'القسم',
      'card_dob': 'ت.الولادة',
      'card_address': 'العنوان',
      'schedule_title': 'أوقات العمل',
      'open_to_all': 'مفتوح للجميع',
      'location_access': 'الموقع والوصول',
      'directions': 'الاتجاهات',
      'website': 'الموقع الإلكتروني',
      'logout_confirm_msg': 'هل أنت متأكد أنك تريد تسجيل الخروج؟',
      'day_lun': 'الاثنين',
      'day_mar': 'الثلاثاء',
      'day_mer': 'الأربعاء',
      'day_jeu': 'الخميس',
      'day_ven': 'الجمعة',
      'day_sam': 'السبت',
      'day_dim': 'الأحد',
      'about_subtitle': 'تعرف على مؤسستنا',
      'month': 'شهر',
      'week': 'أسبوع',
      'absences_subtitle': 'متابعة الحضور والغياب',
      'overall_absence_rate': 'نسبة الغياب الإجمالية',
      'unknown_subject': 'مادة غير معروفة',
      'critical': 'حرجة',
      'no_absences_month': 'لا توجد غيابات هذا الشهر',
      'no_absences_week': 'لا توجد غيابات هذا الأسبوع',
      'justified_absence': 'غياب مبرر',
      'unjustified_absence': 'غياب غير مبرر',
      'sessions_count': 'حصص',
      'coeff_label': 'المعامل',
      'total_label': 'المجموع',
      'sem_label': 'أسابيع',
      'absent_label': 'غياب',
      'ci_label': 'م.م',
      'error_loading_details': 'تعذر تحميل التفاصيل',
      'academic_subject': 'المادة',
      'emploi_subtitle': 'جدول أوقات القسم',
      'exam_timetable_subtitle': 'جدول أوقات الامتحانات',
      'upcoming_semester': 'الفصل الدراسي القادم',
      'timetable_available_from': 'سيكون جدول الأوقات متاحاً ابتداءً من {date}.',
      'timetable_available_start': 'سيكون جدول الأوقات متاحاً مع بداية الفصل الدراسي.',
      'no_exams_scheduled': 'لا توجد امتحانات مبرمجة',
      'no_exams_desc': 'لم يتم نشر مواعيد الامتحانات لهذا الفصل بعد من قبل الإدارة.',
      'timetable_not_available': 'جدول الأوقات غير متوفر',
      'timetable_not_available_desc': 'لم يتم إنشاء جدول أوقات الفصل بعد من قبل الإدارة.',
      'results_subtitle': 'متابعة نقاطك',
      'solde_subtitle': 'متابعة المدفوعات',
      'suggestion_type': 'نوع الاقتراح',
      'select_type': 'اختر النوع',
      'description_label': 'الوصف',
      'describe_suggestion_hint': 'صف اقتراحك بالتفصيل...',
      'suggestion_submitted_success': 'تم إرسال الاقتراح بنجاح!',
      'please_fill_description': 'يرجى كتابة الوصف',
      'error_selecting_files': 'خطأ أثناء اختيار الملفات',
      'no_suggestions': 'لا توجد اقتراحات',
      'no_results': 'لا توجد نتائج',
      'due_date_label': 'تاريخ الاستحقاق',
      'payment_date_label': 'تاريخ الدفع',
      'delay_label': 'التأخير',
      'amount_label': 'المبلغ',
      'method_label': 'طريقة الدفع',
      'close_label': 'إغلاق',
      'st_reclamation_note': 'اعتراض على نقطة',
      'st_absence': 'الغياب / التبرير',
      'st_emploi_temps': 'جدول الأوقات',
      'st_inscription': 'التسجيل / إعادة التسجيل',
      'st_paiement': 'الدفع / الرسوم الدراسية',
      'st_orientation': 'التوجيه / تغيير التخصص',
      'st_bourse': 'المنحة / المساعدة الاجتماعية',
      'st_transport': 'النقل / السكن',
      'st_restauration': 'المطعم الجامعي',
      'st_bibliotheque': 'المكتبة / المراجع',
      'st_vie_universitaire': 'الحياة الجامعية / الأنشطة',
      'st_infrastructure': 'البنية التحتية / التجهيزات',
      'st_securite': 'الأمن / النظافة',
      'st_stage': 'التربص / مشروع التخرج',
      'st_autre': 'أخرى',
      'st_general': 'عام',
      'st_request': 'طلب / استفسار',
      'st_administrative': 'إداري / شؤون إدارية',
      'st_short_reclamation_note': 'نقطة',
      'st_short_absence': 'غياب',
      'st_short_emploi_temps': 'الجدول',
      'st_short_inscription': 'التسجيل',
      'st_short_paiement': 'الدفع',
      'st_short_stage': 'تربص',
      'st_short_orientation': 'توجيه',
      'st_short_bourse': 'منحة',
      'st_short_transport': 'نقل',
      'st_short_restauration': 'المطعم',
      'st_short_bibliotheque': 'مكتبة',
      'st_short_vie_universitaire': 'حياة جامعية',
      'st_short_infrastructure': 'تجهيزات',
      'st_short_securite': 'الأمن',
      'st_short_autre': 'أخرى',
      'st_short_general': 'عام',
      'st_short_request': 'طلب',
      'st_short_administrative': 'إداري',
      'administration': 'الإدارة',
          'repartition_categorie': 'التوزيع حسب الفئة',
      'hour_unit': 'س',
      'solde_restant': 'الرصيد المتبقي',
      'currency_tnd': 'د.ت',
      'reste': 'المتبقي',
      'completed': 'مكتمل',
      'incomplete': 'غير مكتمل',
      'progress': 'نسبة الدفع',
      'category_details': 'تفاصيل الفئة',
      'cat_scolarite': 'المصاريف المدرسية',
      'cat_transport': 'النقل / الحافلة',
      'cat_inscription': 'التسجيل',
      'cat_uniforme': 'الزي الموحد',
      'cat_cantine': 'المطعم',
      'cat_activites': 'الأنشطة',
      'cat_autres': 'أخرى',
      'badge_current': 'الحالي',
      'badge_upcoming': 'قريباً',
      'weight_label': 'الوزن',
      'progression_semestre': 'تقدم الفصل',
      'matieres_completes': 'المواد المكتملة',
      'details_par_matiere': 'التفاصيل حسب المادة',
      'no_subjects_assigned': 'لا توجد مواد مسندة',
      'exam_control_1': 'فرض مراقبة 1',
      'exam_control_2': 'فرض مراقبة 2',
      'exam_control_3': 'فرض مراقبة 3',
      'exam_synthesis': 'فرض تأليفي',
      'exam_practical': 'أشغال تطبيقية',
      'exam_continuous': 'مراقبة مستمرة',
      'exam_project': 'مشروع',
      'exam_oral': 'شفاهي',
      'exam_generic': 'امتحان',
      'welcome_portal': 'مرحباً بكم في البوابة التعليمية',
      'email_address': 'البريد الإلكتروني',
      'email_hint': 'votre@email.com',
      'email_required': 'الرجاء إدخال البريد الإلكتروني',
      'email_invalid': 'بريد إلكتروني غير صالح',
      'password_required': 'الرجاء إدخال كلمة المرور',
      'forgot_password_q': 'نسيت كلمة المرور؟',
      'forgot_password_title': 'استعادة كلمة المرور',
      'forgot_password_desc': 'أدخل بريدك الإلكتروني لطلب إعادة تعيين كلمة المرور.',
      'admin_process_notice': 'ستقوم الإدارة بمعالجة طلبك في أقرب وقت.',
      'request_sent_title': 'تم إرسال الطلب!',
      'request_sent_desc': 'تم إرسال طلب إعادة تعيين كلمة المرور إلى المسؤول.',
      'request_sent_note': 'ستصلك كلمة مرور جديدة فور الموافقة على طلبك.',
      'btn_understood': 'حسناً',
      'btn_send_request': 'إرسال الطلب',
      'access_denied': 'تم رفض الوصول',
      'access_denied_student_only': 'هذا التطبيق مخصص للطلاب فقط.',
      'access_denied_admin_dashboard': 'إذا كنت مسؤولاً، يرجى استخدام لوحة تحكم المسؤول.',
      'not_assigned': 'غير محدد',
      'file_label': 'الملف',
      'size_label': 'الحجم',
      'downloading_status': 'جاري التحميل...',
      'pinned': 'مثبت',
      'important': 'هام',
      'sent_by': 'مرسل من',
      'delete_conversation': 'حذف المحادثة',
      'change_photo': 'تعديل صورتك',
      'choose_photo_source': 'اختر مصدراً:',
      'take_photo': 'التقاط صورة',
      'take_photo_subtitle': 'استخدام الكاميرا مباشرة',
      'choose_gallery': 'اختيار من المعرض',
      'choose_gallery_subtitle': 'اختيار صورة من هاتفك',
      'current_password': 'كلمة المرور الحالية',
      'new_password': 'كلمة المرور الجديدة',
      'confirm_new_password': 'تأكيد كلمة المرور الجديدة',
      'passwords_mismatch': 'كلمات المرور الجديدة غير متطابقة',
      'password_updated_success': 'تم تحديث كلمة المرور بنجاح!',
      'current_password_required': 'يرجى إدخال كلمة المرور الحالية',
      'password_too_short': 'يجب أن تتكون كلمة المرور من 6 أحرف على الأقل',
      'current_password_incorrect': 'كلمة المرور الحالية غير صحيحة',
      'password_update_failed': 'فشل تحديث كلمة المرور. يرجى المحاولة مرة أخرى',
      'cache_cleared_success': 'تم تفريغ الذاكرة المؤقتة بنجاح! (تم تحرير 14.8 ميغابايت)',
      'photo_updated_success': 'تم تحديث الصورة الشخصية بنجاح!',
      'photo_upload_error': 'فشل تحميل الصورة الشخصية. يرجى المحاولة مرة أخرى',
      'adjust_photo': 'تعديل وتوسيط الصورة',
      'crop_photo_hint': 'اسحب وقرّب للتوسيط',
      'crop_card_shape': 'بطاقة الطالب',
      'crop_avatar_shape': 'صورة الحساب',
      'crop_rotate': 'تدوير',
      'crop_reset': 'إعادة ضبط',
      'crop_center': 'توسيط',
      'crop_done': 'تأكيد',
      'cropping_photo': 'جارٍ القص...',
      'user_not_connected': 'المستخدم غير متصل',
      'base_education': 'التعليم الأساسي',
      'general_branch': 'جذع مشترك',
      'saving': 'جاري الحفظ...',
      'notifications_subtitle': 'ابقَ على اطلاع',
      'messages_subtitle': 'رسائل القسم',
      'no_notifications': 'لا توجد إشعارات',
      'notifications_appear_here': 'ستظهر الإشعارات هنا',
      'no_messages': 'لا توجد رسائل',
      'messages_appear_here': 'ستظهر رسائل القسم هنا',
      'tap_to_download': 'اضغط للتحميل',
      'image_unavailable': 'الصورة غير متوفرة',
      'open_label': 'فتح',
      'cannot_open_file': 'تعذر فتح الملف',
      'attached_file': 'ملف مرفق',
      'doc_pdf': 'مستند PDF',
      'doc_word': 'مستند Word',
      'doc_excel': 'ملف Excel',
      'doc_ppt': 'عرض تقديمي',
      'doc_image': 'صورة',
      'doc_video': 'فيديو',
      'doc_audio': 'ملف صوتي',
      'doc_archive': 'ملف مضغوط',
      'at_teacher_absent': 'غياب أستاذ',
      'at_room_change': 'تغيير القاعة',
      'at_exam': 'امتحان',
      'at_reminder': 'تذكير',
      'at_closure': 'إغلاق',
      'at_trip': 'رحلة / خرجة',
      'at_party': 'فعالية',
      'at_payment': 'دفع',
      'at_retenue': 'احتجاز',
      'at_avertissement': 'إنذار',
      'at_exclusion_classe': 'طرد من القسم',
      'at_exclusion_etablissement': 'رفت مؤقت',
      'at_convocation_parents': 'استدعاء الولي',
      'at_conseil_discipline': 'مجلس التأديب',
      'at_exclusion_definitive': 'رفت نهائي',
      'at_general': 'عام',

      // AI Chat
      'ai_assistant_name': 'نوفا',
      'ai_assistant_role': 'المساعد الأكاديمي الذكي',
      'ai_thinking': 'يفكّر...',
      'ai_welcome_message': 'مرحباً، كيف يمكنني مساعدتك اليوم؟',
      'ask_ai_question_hint': 'اطرح سؤالك هنا...',
      'attached_image': 'صورة مرفقة',
      'attach_title': 'إرفاق',
      'photo_library': 'مكتبة الصور',
      'photo_library_desc': 'مشاركة صورة أو مستند',
      'take_photo_desc': 'تصوير وثيقة أو ملاحظة',
      'chat_history': 'سجل المحادثات',
      'no_conversations': 'لا توجد محادثات سابقة',
      'new_conversation': 'محادثة جديدة',
      'delete_conversation_confirm': 'هل أنت متأكد من حذف هذه المحادثة؟',
      'time_just_now': 'الآن',
      'time_mins_ago': 'منذ {min} دقيقة',
      'time_hours_ago': 'منذ {hours} ساعة',
      'time_days_ago': 'منذ {days} أيام',
    },
  };

  String translate(String key, [Map<String, String>? params]) {
    var text = _localizedValues[locale.languageCode]?[key] ??
        _localizedValues['en']?[key] ??
        key;
    if (params != null) {
      params.forEach((k, v) {
        text = text.replaceAll('{$k}', v);
      });
    }
    return text;
  }

  // Convenience getters
  String get appName => translate('app_name');
  String get welcome => translate('welcome');
  String get logout => translate('logout');
  String get settings => translate('settings');
  String get home => translate('home');
  String get profile => translate('profile');
  String get contactUs => translate('contact_us');
  String get about => translate('about');

  // Auth
  String get login => translate('login');
  String get register => translate('register');
  String get email => translate('email');
  String get password => translate('password');
  String get confirmPassword => translate('confirm_password');
  String get forgotPassword => translate('forgot_password');
  String get noAccount => translate('no_account');
  String get alreadyAccount => translate('already_account');
  String get signIn => translate('sign_in');
  String get signUp => translate('sign_up');

  // Home Menu
  String get noteInfo => translate('note_info');
  String get messages => translate('messages');
  String get suggestions => translate('suggestions');
  String get absences => translate('absences');
  String get resultats => translate('resultats');
  String get emploi => translate('emploi');
  String get monGroupe => translate('mon_groupe');
  String get monSolde => translate('mon_solde');
  String get documents => translate('documents');

  // Bottom Nav
  String get myProfile => translate('my_profile');
  String get contact => translate('contact');

  // Common
  String get loading => translate('loading');
  String get error => translate('error');
  String get retry => translate('retry');
  String get refresh => translate('refresh');
  String get cancel => translate('cancel');
  String get delete => translate('delete');
  String get save => translate('save');
  String get noData => translate('no_data');
  String get search => translate('search');
  String get confirm => translate('confirm');
  String get submit => translate('submit');
  String get fieldRequired => translate('field_required');

  // Settings
  String get language => translate('language');
  String get theme => translate('theme');
  String get lightTheme => translate('light_theme');
  String get darkTheme => translate('dark_theme');
  String get systemTheme => translate('system_theme');
  String get notifications => translate('notifications');
  String get announcements => translate('announcements');

  // Semester/Timetable
  String get semester => translate('semester');
  String get monday => translate('monday');
  String get tuesday => translate('tuesday');
  String get wednesday => translate('wednesday');
  String get thursday => translate('thursday');
  String get friday => translate('friday');
  String get saturday => translate('saturday');
  String get noClasses => translate('no_classes');

  // Absences
  String get totalHours => translate('total_hours');
  String get ciHours => translate('ci_hours');
  String get tpHours => translate('tp_hours');
  String get weeks => translate('weeks');
  String get absencesCount => translate('absences_count');
  String get noAbsences => translate('no_absences');
  String get absenceWarning => translate('absence_warning');
  String get absenceCritical => translate('absence_critical');
  String get absenceFail => translate('absence_fail');

  // Results
  String get semesterAverage => translate('semester_average');
  String get coefficient => translate('coefficient');
  String get component => translate('component');
  String get weight => translate('weight');
  String get grade => translate('grade');
  String get noGradesYet => translate('no_grades_yet');
  String get passed => translate('passed');
  String get failed => translate('failed');

  // Suggestions
  String get mySuggestions => translate('my_suggestions');
  String get newSuggestion => translate('new_suggestion');
  String get pending => translate('pending');
  String get inReview => translate('in_review');
  String get replied => translate('replied');
  String get closed => translate('closed');
  String get reply => translate('reply');
  String get submittedAt => translate('submitted_at');
  String get adminResponse => translate('admin_response');
  String get submitSuggestion => translate('submit_suggestion');
  String get suggestionDesc => translate('suggestion_desc');
  String get subject => translate('subject');
  String get enterSubject => translate('enter_subject');
  String get yourSuggestion => translate('your_suggestion');
  String get enterSuggestion => translate('enter_suggestion');
  String get suggestionMinLength => translate('suggestion_min_length');
  String get suggestionSubmitted => translate('suggestion_submitted');

  // Payments
  String get paymentPlan => translate('payment_plan');
  String get paymentHistory => translate('payment_history');
  String get remainingBalance => translate('remaining_balance');
  String get paid => translate('paid');
  String get total => translate('total');
  String get fullyPaid => translate('fully_paid');
  String get inProgress => translate('in_progress');
  String get installment => translate('installment');
  String get dueDate => translate('due_date');
  String get noPayments => translate('no_payments');
  String get cash => translate('cash');
  String get bankTransfer => translate('bank_transfer');
  String get check => translate('check');
  String get card => translate('card');
  String get receipt => translate('receipt');

  // Documents
  String get certificates => translate('certificates');
  String get transcripts => translate('transcripts');
  String get idCards => translate('id_cards');
  String get otherDocs => translate('other_docs');
  String get noDocuments => translate('no_documents');
  String get download => translate('download');
  String get downloading => translate('downloading');

  // Group
  String get searchStudents => translate('search_students');

  // Profile
  String get personalInfo => translate('personal_info');
  String get academicInfo => translate('academic_info');
  String get fullName => translate('full_name');
  String get phone => translate('phone');
  String get birthDate => translate('birth_date');
  String get className => translate('class_name');
  String get groupName => translate('group_name');
  String get academicYear => translate('academic_year');
  String get studentId => translate('student_id');

  // Profile Extended
  String get monProfil => translate('my_profile');
  String get dateOfBirth => translate('date_of_birth');
  String get address => translate('address');
  String get studentCode => translate('student_code');
  String get currentClass => translate('current_class');
  String get group => translate('group');

  // Documents Extended
  String get documentsDescription => translate('documents_description');
  String get documentAdministrative => translate('document_administrative');
  String get documentExams => translate('document_exams');
  String get documentOther => translate('document_other');
  String get sortBy => translate('sort_by');
  String get allTypes => translate('all_types');
  String noDocsForSemester(int sem) => translate('no_docs_for_semester').replaceAll('{sem}', sem.toString());
  String get noMatchingDocuments => translate('no_matching_documents');
  String get trySelectAnotherType => translate('try_select_another_type');
  String get applicationDeveloper => translate('application_developer');
  String get visitPortfolio => translate('visit_portfolio');
  String get reportABug => translate('report_a_bug');
  String get reportBugSubtitle => translate('report_bug_subtitle');
  String get bugTitleLabel => translate('bug_title_label');
  String get bugTitleHint => translate('bug_title_hint');
  String get bugDescLabel => translate('bug_desc_label');
  String get bugDescHint => translate('bug_desc_hint');
  String get bugTypeLabel => translate('bug_type_label');
  String get bugTypeVisual => translate('bug_type_visual');
  String get bugTypeFunctional => translate('bug_type_functional');
  String get bugTypeCrash => translate('bug_type_crash');
  String get bugTypeOther => translate('bug_type_other');
  String get addScreenshots => translate('add_screenshots');
  String get bugScreenshotLabel => translate('bug_screenshot_label');
  String get submitBugReport => translate('submit_bug_report');
  String get bugReportSuccess => translate('bug_report_success');

  // Timetable Extended
  String get noCourses => translate('no_courses');

  // Absences Extended
  String get absenceHours => translate('absence_hours');

  // Payments Extended
  String get paymentSchedule => translate('payment_schedule');
  String get statusPaid => translate('status_paid');
  String get statusOverdue => translate('status_overdue');
  String get statusPending => translate('status_pending');

  // Contact
  String get needHelp => translate('need_help');
  String get contactDesc => translate('contact_desc');
  String get emailUs => translate('email_us');
  String get callUs => translate('call_us');
  String get visitUs => translate('visit_us');
  String get officeHours => translate('office_hours');
  String get officeHoursValue => translate('office_hours_value');
  String get followUs => translate('follow_us');

  // About
  String get aboutDesc => translate('about_desc');
  String get features => translate('features');
  String get featureAcademicTrackingTitle =>
      translate('feature_academic_tracking_title');
  String get featureAcademicTrackingDesc =>
      translate('feature_academic_tracking_desc');
  String get featureDynamicScheduleTitle =>
      translate('feature_dynamic_schedule_title');
  String get featureDynamicScheduleDesc =>
      translate('feature_dynamic_schedule_desc');
  String get featureAttendanceTitle =>
      translate('feature_attendance_title');
  String get featureAttendanceDesc =>
      translate('feature_attendance_desc');
  String get featureDocumentsTitle =>
      translate('feature_documents_title');
  String get featureDocumentsDesc =>
      translate('feature_documents_desc');
  String get featureFinancialTitle =>
      translate('feature_financial_title');
  String get featureFinancialDesc =>
      translate('feature_financial_desc');
  String get featureAiTitle =>
      translate('feature_ai_title');
  String get featureAiDesc =>
      translate('feature_ai_desc');
  String get featureAnnouncements => translate('feature_announcements');
  String get featureGrades => translate('feature_grades');
  String get featureAbsences => translate('feature_absences');
  String get featureTimetable => translate('feature_timetable');
  String get featurePayments => translate('feature_payments');
  String get featureDocuments => translate('feature_documents');
  String get developedBy => translate('developed_by');
  String get allRightsReserved => translate('all_rights_reserved');
  String get privacyPolicy => translate('privacy_policy');
  String get termsOfService => translate('terms_of_service');

  // Profile new
  String get etablissement => translate('etablissement');
  String get niveau => translate('niveau');
  String get filiere => translate('filiere');
  String get enrollmentStatus => translate('enrollment_status');
  String get enrolledAndActive => translate('enrolled_and_active');
  String get personalInfoTitle => translate('personal_info_title');
  String get studentCodeCopied => translate('student_code_copied');
  String get emailCopied => translate('email_copied');

  // Settings new
  String get settingsSubtitle => translate('settings_subtitle');
  String get notificationsAlerts => translate('notifications_alerts');
  String get notifGradesTitle => translate('notif_grades_title');
  String get notifGradesSubtitle => translate('notif_grades_subtitle');
  String get notifTimetableTitle => translate('notif_timetable_title');
  String get notifTimetableSubtitle => translate('notif_timetable_subtitle');
  String get notifAbsencesTitle => translate('notif_absences_title');
  String get notifAbsencesSubtitle => translate('notif_absences_subtitle');
  String get notifAnnouncementsTitle => translate('notif_announcements_title');
  String get notifAnnouncementsSubtitle => translate('notif_announcements_subtitle');
  String get securityAccess => translate('security_access');
  String get changePasswordLabel => translate('change_password');
  String get changePasswordSubtitle => translate('change_password_subtitle');
  String get biometricLock => translate('biometric_lock');
  String get biometricLockSubtitle => translate('biometric_lock_subtitle');
  String get appearanceLabel => translate('appearance');
  String get themeSubtitle => translate('theme_subtitle');
  String get privacyLabel => translate('privacy');
  String get clearCache => translate('clear_cache');
  String get clearCacheSubtitle => translate('clear_cache_subtitle');

  // Home subtitles
  String get homeSubtitleAbsences => translate('home_subtitle_absences');
  String get homeSubtitleSuggestions => translate('home_subtitle_suggestions');
  String get homeSubtitleResults => translate('home_subtitle_results');
  String get homeSubtitleTimetable => translate('home_subtitle_timetable');
  String get homeSubtitleGroup => translate('home_subtitle_group');
  String get homeSubtitleSolde => translate('home_subtitle_solde');
  String get homeSubtitleDocuments => translate('home_subtitle_documents');

  // Suggestions
  String get suggestionsSubtitle => translate('suggestions_subtitle');
  String get shareIdeas => translate('share_ideas');

  // Contact new
  String get joinUsSocial => translate('join_us_social');
  String get nosCoordonnees => translate('nos_coordonnees');
  String get callUsContact => translate('call_us_contact');
  String get visitUsContact => translate('visit_us_contact');
  String get officeHoursSchedule => translate('office_hours_schedule');

  // Profile header
  String get monProfilLabel => translate('mon_profil');
  String get profilSubtitle => translate('profil_subtitle');

  // About new
  String get appVersion => translate('app_version');
  String get developedWithLove => translate('developed_with_love');


  // Student Card
  
  String get absencesSubtitle => translate('absences_subtitle');
  String get overallAbsenceRate => translate('overall_absence_rate');
  String get unknownSubject => translate('unknown_subject');
  String get critical => translate('critical');
  String get month => translate('month');
  String get week => translate('week');
  String get studentCardTitle => translate('student_card_title');
  String get cardName => translate('card_name');
  String get cardClass => translate('card_class');
  String get cardDob => translate('card_dob');
  String get cardAddress => translate('card_address');

  // Contact schedule & location
  String get scheduleTitle => translate('schedule_title');
  String get openToAll => translate('open_to_all');
  String get locationAccess => translate('location_access');
  String get directions => translate('directions');
  String get website => translate('website');
  String get logoutConfirmMsg => translate('logout_confirm_msg');

  // Days
  String get dayLun => translate('day_lun');
  String get dayMar => translate('day_mar');
  String get dayMer => translate('day_mer');
  String get dayJeu => translate('day_jeu');
  String get dayVen => translate('day_ven');
  String get daySam => translate('day_sam');
  String get dayDim => translate('day_dim');

  String get aboutSubtitle => translate('about_subtitle');
  String get noAbsencesMonth => translate('no_absences_month');
  String get noAbsencesWeek => translate('no_absences_week');
  String get noAbsencesDesc => translate('no_absences_desc');
  String get noSearchResultsDesc => translate('no_search_results_desc');
  String get justifiedAbsence => translate('justified_absence');
  String get unjustifiedAbsence => translate('unjustified_absence');
  String get sessionsCount => translate('sessions_count');
  String get coeffLabel => translate('coeff_label');
  String get totalLabel => translate('total_label');
  String get semLabel => translate('sem_label');
  String get absentLabel => translate('absent_label');
  String get ciLabel => translate('ci_label');
  String get errorLoadingDetails => translate('error_loading_details');
  String get academicSubject => translate('academic_subject');
  String get emploiSubtitle => translate('emploi_subtitle');
  String get examTimetableSubtitle => translate('exam_timetable_subtitle');
  String get remainingShort => translate('remaining_short');
  String get upcomingSemester => translate('upcoming_semester');
  String get noExamsScheduled => translate('no_exams_scheduled');
  String get noExamsDesc => translate('no_exams_desc');
  String get timetableNotAvailable => translate('timetable_not_available');
  String get timetableNotAvailableDesc => translate('timetable_not_available_desc');
  String get resultsSubtitle => translate('results_subtitle');
  String get soldeSubtitle => translate('solde_subtitle');
  String get suggestionTypeLabel => translate('suggestion_type');
  String get selectType => translate('select_type');
  String get descriptionLabel => translate('description_label');
  String get describeSuggestionHint => translate('describe_suggestion_hint');
  String get suggestionSubmittedSuccess => translate('suggestion_submitted_success');
  String get pleaseFillDescription => translate('please_fill_description');
  String get errorSelectingFiles => translate('error_selecting_files');
  String get noSuggestions => translate('no_suggestions');
  String get noResults => translate('no_results');
  String get dueDateLabel => translate('due_date_label');
  String get paymentDateLabel => translate('payment_date_label');
  String get delayLabel => translate('delay_label');
  String get amountLabel => translate('amount_label');
  String get methodLabel => translate('method_label');
  String get closeLabel => translate('close_label');
  String get send => translate('send');
  String get attachment => translate('attachment');
  String get dateLabel => translate('date');
  String get attachments => translate('attachment');

  String normalizeSuggestionType(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return 'general';
    var lower = s.toLowerCase();
    if (lower.startsWith('st_short_')) lower = lower.substring(9);
    if (lower.startsWith('st_')) lower = lower.substring(3);

    if (lower.contains('sécurité') || lower.contains('securite') || lower.contains('hygiène') || lower.contains('hygiene') || lower.contains('الأمن') || lower.contains('نظافة') || lower.contains('security')) {
      return 'securite';
    }
    if (lower.contains('emploi') || lower.contains('temps') || lower.contains('edt') || lower.contains('جدول') || lower.contains('أوقات') || lower.contains('timetable') || lower.contains('schedule')) {
      return 'emploi_temps';
    }
    if (lower.contains('réclamation') || lower.contains('reclamation') || lower.contains('note') || lower.contains('نقطة') || lower.contains('اعتراض') || lower.contains('grade') || lower.contains('claim')) {
      return 'reclamation_note';
    }
    if (lower.contains('absence') || lower.contains('غياب') || lower.contains('justif')) {
      return 'absence';
    }
    if (lower.contains('paiement') || lower.contains('payer') || lower.contains('frais') || lower.contains('دفع') || lower.contains('رسوم') || lower.contains('payment')) {
      return 'paiement';
    }
    if (lower.contains('inscription') || lower.contains('تسجيل') || lower.contains('registration')) {
      return 'inscription';
    }
    if (lower.contains('orientation') || lower.contains('توجيه')) {
      return 'orientation';
    }
    if (lower.contains('bourse') || lower.contains('منحة') || lower.contains('scholarship')) {
      return 'bourse';
    }
    if (lower.contains('transport') || lower.contains('نقل') || lower.contains('hébergement') || lower.contains('سكن')) {
      return 'transport';
    }
    if (lower.contains('resto') || lower.contains('restauration') || lower.contains('مطعم') || lower.contains('dining')) {
      return 'restauration';
    }
    if (lower.contains('biblio') || lower.contains('bibliotheque') || lower.contains('مكتبة') || lower.contains('library')) {
      return 'bibliotheque';
    }
    if (lower.contains('vie') || lower.contains('universitaire') || lower.contains('نشاط') || lower.contains('campus')) {
      return 'vie_universitaire';
    }
    if (lower.contains('infra') || lower.contains('infrastructure') || lower.contains('تجهيزات') || lower.contains('facility')) {
      return 'infrastructure';
    }
    if (lower.contains('stage') || lower.contains('pfe') || lower.contains('تربص') || lower.contains('internship')) {
      return 'stage';
    }
    if (lower.contains('administrat') || lower.contains('admin') || lower.contains('إدار')) {
      return 'administrative';
    }
    if (lower.contains('demande') || lower.contains('request') || lower.contains('طلب')) {
      return 'request';
    }
    if (lower.contains('autre') || lower.contains('other') || lower.contains('أخرى')) {
      return 'autre';
    }
    return lower;
  }

  String getSuggestionType(String type) {
    final norm = normalizeSuggestionType(type);
    final key = 'st_$norm';
    final val = translate(key);
    if (val != key) return val;
    final directVal = translate('st_$type');
    if (directVal != 'st_$type') return directVal;
    return val;
  }

  String getShortSuggestionType(String type) {
    final norm = normalizeSuggestionType(type);
    final key = 'st_short_$norm';
    final val = translate(key);
    if (val != key) return val;
    final full = getSuggestionType(norm);
    if (full != 'st_$norm') return full;
    return type;
  }

  String formatGradeComponentName(String rawName) {
    final lower = rawName.trim().toLowerCase();
    if (lower.contains('synthèse') || lower.contains('synthese') || lower == 'ds') {
      return translate('exam_synthesis');
    }
    if (lower.contains('contrôle 1') || lower.contains('controle 1') || lower == 'dc1') {
      return translate('exam_control_1');
    }
    if (lower.contains('contrôle 2') || lower.contains('controle 2') || lower == 'dc2') {
      return translate('exam_control_2');
    }
    if (lower.contains('contrôle 3') || lower.contains('controle 3') || lower == 'dc3') {
      return translate('exam_control_3');
    }
    if (lower.contains('contrôle') || lower.contains('controle') || lower == 'dc') {
      return translate('exam_control_1');
    }
    if (lower.contains('pratique') || lower == 'tp') {
      return translate('exam_practical');
    }
    if (lower.contains('continu') || lower == 'cc') {
      return translate('exam_continuous');
    }
    if (lower.contains('projet')) {
      return translate('exam_project');
    }
    if (lower.contains('oral')) {
      return translate('exam_oral');
    }
    if (lower.contains('examen')) {
      return translate('exam_generic');
    }
    return rawName;
  }

  Map<String, String> get suggestionTypesList => {
    'reclamation_note': translate('st_reclamation_note'),
    'absence': translate('st_absence'),
    'emploi_temps': translate('st_emploi_temps'),
    'inscription': translate('st_inscription'),
    'paiement': translate('st_paiement'),
    'orientation': translate('st_orientation'),
    'bourse': translate('st_bourse'),
    'transport': translate('st_transport'),
    'restauration': translate('st_restauration'),
    'bibliotheque': translate('st_bibliotheque'),
    'vie_universitaire': translate('st_vie_universitaire'),
    'infrastructure': translate('st_infrastructure'),
    'securite': translate('st_securite'),
    'administrative': translate('st_administrative'),
    'request': translate('st_request'),
    'autre': translate('st_autre'),
  };

  // Notifications & Messages getters
  String get notificationsSubtitle => translate('notifications_subtitle');
  String get messagesSubtitle => translate('messages_subtitle');
  String get noNotifications => translate('no_notifications');
  String get notificationsAppearHere => translate('notifications_appear_here');
  String get noMessages => translate('no_messages');
  String get messagesAppearHere => translate('messages_appear_here');
  String get tapToDownload => translate('tap_to_download');
  String get imageUnavailable => translate('image_unavailable');
  String get openLabel => translate('open_label');
  String get cannotOpenFile => translate('cannot_open_file');
  String get attachedFile => translate('attached_file');
  String get pinnedLabel => translate('pinned');
  String get importantLabel => translate('important');
  String get sentByLabel => translate('sent_by');

  static String normalizeAnnouncementType(String? rawType) {
    if (rawType == null) return 'general';
    final t = rawType.trim().toLowerCase()
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('à', 'a')
        .replaceAll('â', 'a');

    if (t == 'teacher_absent' || t.contains('absence prof') || t.contains('prof absent')) return 'teacher_absent';
    if (t == 'room_change' || t.contains('changement salle') || t.contains('salle')) return 'room_change';
    if (t == 'exam' || t.contains('examen') || t.contains('evaluation') || t.contains('controle')) return 'exam';
    if (t == 'retenue') return 'retenue';
    if (t == 'reminder' || t.contains('rappel')) return 'reminder';
    if (t == 'trip' || t.contains('sortie') || t.contains('voyage')) return 'trip';
    if (t == 'party' || t.contains('evenement') || t.contains('fete')) return 'party';
    if (t == 'payment' || t.contains('paiement') || t.contains('frais')) return 'payment';
    if (t == 'closure' || t.contains('fermeture')) return 'closure';
    if (t == 'avertissement') return 'avertissement';
    if (t == 'exclusion_classe' || t.contains('exclusion classe')) return 'exclusion_classe';
    if (t == 'exclusion_etablissement' || t.contains('exclusion etab')) return 'exclusion_etablissement';
    if (t == 'convocation_parents' || t.contains('convocation')) return 'convocation_parents';
    if (t == 'conseil_discipline' || t.contains('conseil disc')) return 'conseil_discipline';
    if (t == 'exclusion_definitive' || t.contains('exclusion def')) return 'exclusion_definitive';
    if (t == 'general' || t.contains('general')) return 'general';
    return t;
  }

  String getAnnouncementTypeLabel(String? type) {
    final norm = normalizeAnnouncementType(type);
    switch (norm) {
      case 'teacher_absent':
        return translate('at_teacher_absent');
      case 'room_change':
        return translate('at_room_change');
      case 'exam':
        return translate('at_exam');
      case 'reminder':
        return translate('at_reminder');
      case 'closure':
        return translate('at_closure');
      case 'trip':
        return translate('at_trip');
      case 'party':
        return translate('at_party');
      case 'payment':
        return translate('at_payment');
      case 'retenue':
        return translate('at_retenue');
      case 'avertissement':
        return translate('at_avertissement');
      case 'exclusion_classe':
        return translate('at_exclusion_classe');
      case 'exclusion_etablissement':
        return translate('at_exclusion_etablissement');
      case 'convocation_parents':
        return translate('at_convocation_parents');
      case 'conseil_discipline':
        return translate('at_conseil_discipline');
      case 'exclusion_definitive':
        return translate('at_exclusion_definitive');
      case 'general':
      default:
        return translate('at_general');
    }
  }

  String localizeSenderLabel(String? senderLabel) {
    if (senderLabel == null || senderLabel.trim().isEmpty) return '';
    final trimmed = senderLabel.trim();
    final lower = trimmed.toLowerCase();
    if (lower == 'administration' || lower == 'admin') {
      return translate('administration');
    }
    if (lower == 'enseignant' || lower == 'professeur' || lower == 'teacher') {
      return translate('teacher');
    }
    return trimmed;
  }

  String getCleanAttachmentFileName(String? customName, String url) {
    if (customName != null &&
        customName.isNotEmpty &&
        !customName.toLowerCase().contains('whatsapp') &&
        !RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(customName) &&
        !RegExp(
          r'IMG_\d+|DSC_\d+|Screenshot',
          caseSensitive: false,
        ).hasMatch(customName)) {
      return customName;
    }

    final lower = url.toLowerCase();
    if (lower.endsWith('.pdf')) return translate('doc_pdf');
    if (lower.endsWith('.doc') || lower.endsWith('.docx')) {
      return translate('doc_word');
    }
    if (lower.endsWith('.xls') || lower.endsWith('.xlsx')) {
      return translate('doc_excel');
    }
    if (lower.endsWith('.ppt') || lower.endsWith('.pptx')) {
      return translate('doc_ppt');
    }
    if (lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp')) {
      return translate('doc_image');
    }
    if (lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.avi')) {
      return translate('doc_video');
    }
    if (lower.endsWith('.mp3') || lower.endsWith('.wav')) {
      return translate('doc_audio');
    }
    if (lower.endsWith('.zip') || lower.endsWith('.rar')) {
      return translate('doc_archive');
    }

    return translate('attached_file');
  }

  String formatAnnouncementDateTime(DateTime dt) {
    final lang = locale.languageCode;
    final timePart = DateFormat('HH:mm').format(dt);
    if (lang == 'ar') {
      final datePart = ArabicTypography.toLatinDigits(DateFormat('d MMMM yyyy', 'ar').format(dt));
      return '$datePart على الساعة $timePart';
    } else if (lang == 'en') {
      final datePart = DateFormat('d MMMM yyyy', 'en').format(dt);
      return '$datePart at $timePart';
    } else {
      final datePart = DateFormat('d MMMM yyyy', 'fr_FR').format(dt);
      return '$datePart à $timePart';
    }
  }

  String _cleanRoomName(String rawRoom) {
    return rawRoom
        .trim()
        .replaceFirst(
          RegExp(r'^(?:salle|room|قاعة)\s+', caseSensitive: false),
          '',
        )
        .trim();
  }

  String _formatRoom(String rawRoom) {
    final clean = _cleanRoomName(rawRoom);
    if (clean.isEmpty) return '';
    switch (locale.languageCode) {
      case 'ar':
        return 'قاعة $clean';
      case 'en':
        return 'Room $clean';
      default:
        return 'Salle $clean';
    }
  }

  String _localizeSubjectName(String rawSubject) {
    final s = rawSubject.trim();
    if (s.isEmpty || locale.languageCode == 'fr') return s;
    final lower = s.toLowerCase();
    final isAr = locale.languageCode == 'ar';
    if (lower == 'math' ||
        lower == 'maths' ||
        lower == 'mathématiques' ||
        lower == 'mathematiques') {
      return isAr ? 'الرياضيات' : 'Mathematics';
    }
    if (lower == 'physique' || lower == 'sciences physiques') {
      return isAr ? 'الفيزياء' : 'Physics';
    }
    if (lower == 'sciences' ||
        lower == 'svt' ||
        lower == 'sciences naturelles') {
      return isAr ? 'العلوم الطبيعية' : 'Natural Sciences';
    }
    if (lower == 'français' || lower == 'francais') {
      return isAr ? 'الفرنسية' : 'French';
    }
    if (lower == 'anglais') {
      return isAr ? 'الإنجليزية' : 'English';
    }
    if (lower == 'arabe') {
      return isAr ? 'العربية' : 'Arabic';
    }
    if (lower == 'informatique') {
      return isAr ? 'الإعلامية' : 'Computer Science';
    }
    if (lower == 'philosophie') {
      return isAr ? 'الفلسفة' : 'Philosophy';
    }
    if (lower == 'histoire' ||
        lower == 'histoire-géographie' ||
        lower == 'histoire-geographie') {
      return isAr ? 'التاريخ والجغرافيا' : 'History & Geography';
    }
    if (lower == 'sport' ||
        lower == 'eps' ||
        lower == 'éducation physique') {
      return isAr ? 'التربية البدنية' : 'Physical Education';
    }
    return s;
  }

  String _localizeEventName(String rawEvent) {
    final s = rawEvent.trim();
    if (s.isEmpty || locale.languageCode == 'fr') return s;
    final lower = s.toLowerCase();
    final isAr = locale.languageCode == 'ar';
    if (lower == 'fete' || lower == 'fête') {
      return isAr ? 'حفل' : 'Celebration';
    }
    if (lower == 'soirée' || lower == 'soiree') {
      return isAr ? 'أمسية' : 'Evening event';
    }
    if (lower == 'célébration' || lower == 'celebration') {
      return isAr ? 'احتفال' : 'Celebration';
    }
    return s;
  }

  String _localizePaymentType(String rawType) {
    final lower = rawType.trim().toLowerCase();
    final lang = locale.languageCode;
    if (lower.contains('scolarit')) {
      return lang == 'ar'
          ? 'الرسوم الدراسية'
          : (lang == 'en' ? 'Tuition fees' : 'Frais de scolarité');
    }
    if (lower.contains('inscript')) {
      return lang == 'ar'
          ? 'رسوم التسجيل'
          : (lang == 'en' ? 'Registration fees' : 'Frais d\'inscription');
    }
    if (lower.contains('sortie') || lower.contains('voyage')) {
      return lang == 'ar'
          ? 'مصاريف الرحلة'
          : (lang == 'en' ? 'Trip fees' : 'Frais de sortie');
    }
    if (lower.contains('matériel') || lower.contains('materiel')) {
      return lang == 'ar'
          ? 'مصاريف اللوازم'
          : (lang == 'en' ? 'Material fees' : 'Frais de matériel');
    }
    if (lower.contains('cotisation')) {
      return lang == 'ar'
          ? 'مساهمة'
          : (lang == 'en' ? 'Contribution' : 'Cotisation');
    }
    return lang == 'ar'
        ? 'دفعة'
        : (lang == 'en' ? 'Payment' : 'Paiement');
  }

  String _localizePaymentMethod(String rawMethod) {
    final s = rawMethod.trim();
    if (s.isEmpty) return '';
    final lower = s.toLowerCase();
    final lang = locale.languageCode;
    if (lower.contains('espèces') ||
        lower.contains('especes') ||
        lower == 'cash') {
      return lang == 'ar' ? 'نقداً' : (lang == 'en' ? 'Cash' : 'Espèces');
    }
    if (lower.contains('virement') || lower == 'bank_transfer') {
      return lang == 'ar'
          ? 'تحويل بنكي'
          : (lang == 'en' ? 'Bank transfer' : 'Virement bancaire');
    }
    if (lower.contains('chèque') ||
        lower.contains('cheque') ||
        lower == 'check') {
      return lang == 'ar' ? 'شيك' : (lang == 'en' ? 'Check' : 'Chèque');
    }
    if (lower.contains('carte') || lower == 'card') {
      return lang == 'ar'
          ? 'بطاقة بنكية'
          : (lang == 'en' ? 'Bank card' : 'Carte bancaire');
    }
    if (lower.contains('ligne') || lower == 'online') {
      return lang == 'ar'
          ? 'عبر الإنترنت'
          : (lang == 'en' ? 'Online' : 'En ligne');
    }
    return s;
  }

  String extractAnnouncementKeyInfo(
    String? type,
    Map<String, dynamic> payload,
    String body,
  ) {
    final lang = locale.languageCode;
    final arrow = lang == 'ar' ? '←' : '→';

    switch (type) {
      case 'room_change':
        String oldRoom = (payload['old_room'] as String?)?.trim() ?? '';
        String newRoom = (payload['new_room'] as String?)?.trim() ?? '';
        String subject = (payload['subject'] as String?)?.trim() ?? '';

        if (oldRoom.isEmpty || newRoom.isEmpty) {
          final m = RegExp(
            r'Le cours(?:\s+de\s+(.+?))?\s+est déplacé de la salle\s+(.+?)\s+vers la salle\s+([^\s.]+)',
            caseSensitive: false,
          ).firstMatch(body);
          if (m != null) {
            if (subject.isEmpty) subject = m.group(1)?.trim() ?? '';
            if (oldRoom.isEmpty) oldRoom = m.group(2)?.trim() ?? '';
            if (newRoom.isEmpty) newRoom = m.group(3)?.trim() ?? '';
          }
        }

        if (oldRoom.isNotEmpty && newRoom.isNotEmpty) {
          String info = '${_formatRoom(oldRoom)} $arrow ${_formatRoom(newRoom)}';
          if (subject.isNotEmpty) {
            info = '${_localizeSubjectName(subject)}: $info';
          }
          return info;
        }
        break;

      case 'teacher_absent':
        String teacherName = (payload['teacher_name'] as String?)?.trim() ?? '';
        String startDate = (payload['start_date'] as String?)?.trim() ?? '';
        String endDate = (payload['end_date'] as String?)?.trim() ?? '';

        if (teacherName.isEmpty) {
          final m = RegExp(
            r'^(.+?)\s+sera absent(?:e)?(?:\s+(?:du|le)\s+(\d{1,2}/\d{1,2}/\d{2,4}))?(?:.*?\s+au\s+(\d{1,2}/\d{1,2}/\d{2,4}))?',
            caseSensitive: false,
          ).firstMatch(body);
          if (m != null) {
            teacherName = m.group(1)?.trim() ?? '';
            if (startDate.isEmpty) startDate = m.group(2)?.trim() ?? '';
            if (endDate.isEmpty) endDate = m.group(3)?.trim() ?? '';
          }
        }

        if (teacherName.isNotEmpty) {
          final cleanTeacher = teacherName
              .replaceFirst(
                RegExp(r'^(?:prof\.?|أستاذ(?:ة)?)\s*', caseSensitive: false),
                '',
              )
              .trim();
          String info = lang == 'ar'
              ? 'الأستاذ(ة) $cleanTeacher'
              : 'Prof. $cleanTeacher';
          if (startDate.isNotEmpty) {
            if (endDate.isNotEmpty && startDate != endDate) {
              info += ' • $startDate $arrow $endDate';
            } else {
              info += ' • $startDate';
            }
          }
          return info;
        }
        break;

      case 'exam':
        String subject = (payload['subject'] as String?)?.trim() ?? '';
        String dateTime = (payload['date_time'] as String?)?.trim() ?? '';
        String room = (payload['room'] as String?)?.trim() ?? '';

        if (subject.isEmpty && room.isEmpty) {
          final m = RegExp(
            r'Un examen de\s+(.+?)(?:\s+aura lieu le\s+(\d{1,2}/\d{1,2}/\d{2,4}))?(?:\s+à\s+(\d{1,2}:\d{2}))?(?:\s+en salle\s+([^.]+))?\.',
            caseSensitive: false,
          ).firstMatch(body);
          if (m != null) {
            subject = m.group(1)?.trim() ?? '';
            room = m.group(4)?.trim() ?? '';
          }
        }

        final parts = <String>[];
        if (subject.isNotEmpty) parts.add(_localizeSubjectName(subject));
        if (dateTime.isNotEmpty) parts.add(dateTime);
        if (room.isNotEmpty) parts.add(_formatRoom(room));

        if (parts.isNotEmpty) {
          return parts.join(' • ');
        }
        break;

      case 'closure':
        String reason = (payload['reason'] as String?)?.trim() ?? '';
        String closedFrom = (payload['closed_from'] as String?)?.trim() ?? '';
        String closedTo = (payload['closed_to'] as String?)?.trim() ?? '';

        if (reason.isEmpty && closedFrom.isEmpty) {
          final m = RegExp(
            r"L'établissement sera fermé(?:\s+pour\s+(.+?))?(?:\s+(?:du|le)\s+(\d{1,2}/\d{1,2}/\d{2,4}))?(?:\s+au\s+(\d{1,2}/\d{1,2}/\d{2,4}))?\.",
            caseSensitive: false,
          ).firstMatch(body);
          if (m != null) {
            reason = m.group(1)?.trim() ?? '';
            closedFrom = m.group(2)?.trim() ?? '';
            closedTo = m.group(3)?.trim() ?? '';
          }
        }

        final parts = <String>[];
        if (reason.isNotEmpty) {
          parts.add(reason);
        }
        if (closedFrom.isNotEmpty) {
          if (closedTo.isNotEmpty) {
            parts.add('$closedFrom $arrow $closedTo');
          } else {
            parts.add(
              lang == 'ar'
                  ? 'ابتداءً من $closedFrom'
                  : (lang == 'en'
                      ? 'From $closedFrom'
                      : 'À partir du $closedFrom'),
            );
          }
        }

        if (parts.isNotEmpty) {
          return parts.join(' • ');
        }
        break;

      case 'reminder':
        String dueDate = (payload['due_date'] as String?)?.trim() ?? '';
        String actionRequired =
            (payload['action_required'] as String?)?.trim() ?? '';

        if (dueDate.isEmpty) {
          final m = RegExp(
            r'Date limite:\s*(\d{1,2}/\d{1,2}/\d{2,4})',
            caseSensitive: false,
          ).firstMatch(body);
          if (m != null) dueDate = m.group(1)?.trim() ?? '';
        }

        final parts = <String>[];
        if (dueDate.isNotEmpty) {
          parts.add(
            lang == 'ar'
                ? 'قبل $dueDate'
                : (lang == 'en' ? 'Before $dueDate' : 'Avant le $dueDate'),
          );
        }
        if (actionRequired.isNotEmpty) parts.add(actionRequired);

        if (parts.isNotEmpty) {
          return parts.join(' • ');
        }
        break;

      case 'general':
        return '';

      case 'trip':
        String dest = (payload['destination'] as String?)?.trim() ?? '';
        String date = (payload['departure_date'] as String?)?.trim() ?? '';

        if (dest.isEmpty) {
          final destMatch = RegExp(
            r'(?:sortie\s+à|sortie\s+vers|sortie|à|vers|destination)\s+([A-Za-zÀ-ÿ\s]+?)(?:\s+(?:le|est|organis))',
            caseSensitive: false,
          ).firstMatch(body);
          if (destMatch != null) {
            dest = (destMatch.group(1)?.trim() ?? '')
                .replaceFirst(
                  RegExp(r'^(?:à|vers)\s+', caseSensitive: false),
                  '',
                )
                .trim();
          }
        }
        if (date.isEmpty) {
          final dateMatch = RegExp(r'(\d{1,2}/\d{1,2}/\d{2,4})').firstMatch(body);
          if (dateMatch != null) date = dateMatch.group(1)?.trim() ?? '';
        }

        final tripParts = <String>[];
        if (dest.isNotEmpty) {
          tripParts.add(
            lang == 'ar'
                ? 'إلى $dest'
                : (lang == 'en' ? 'To $dest' : 'à $dest'),
          );
        }
        if (date.isNotEmpty) {
          tripParts.add(
            lang == 'ar'
                ? 'يوم $date'
                : (lang == 'en' ? 'On $date' : 'Le $date'),
          );
        }
        if (tripParts.isNotEmpty) return tripParts.join(' • ');
        break;

      case 'party':
        String eventDate = (payload['event_date'] as String?)?.trim() ?? '';
        String location = (payload['location'] as String?)?.trim() ?? '';

        if (eventDate.isEmpty) {
          final eventDateMatch =
              RegExp(r'(\d{1,2}/\d{1,2}/\d{2,4})').firstMatch(body);
          if (eventDateMatch != null) {
            eventDate = eventDateMatch.group(1)?.trim() ?? '';
          }
        }
        if (location.isEmpty) {
          final locationMatch = RegExp(
            r'[Ll]ieu[:\s]+([A-Za-zÀ-ÿ0-9\s]+?)(?:\.|,|$)',
          ).firstMatch(body);
          if (locationMatch != null) {
            location = locationMatch.group(1)?.trim() ?? '';
          }
        }

        final eventParts = <String>[];
        if (eventDate.isNotEmpty) {
          eventParts.add(
            lang == 'ar'
                ? 'يوم $eventDate'
                : (lang == 'en' ? 'On $eventDate' : 'Le $eventDate'),
          );
        }
        if (location.isNotEmpty) eventParts.add(location);
        if (eventParts.isNotEmpty) return eventParts.join(' • ');
        break;

      case 'payment':
        String dueDate = (payload['due_date'] as String?)?.trim() ?? '';
        String mode = (payload['payment_method'] as String?)?.trim() ?? '';

        if (dueDate.isEmpty) {
          final dueDateMatch = RegExp(
            r'avant\s+le\s+(\d{1,2}/\d{1,2}/\d{2,4})',
            caseSensitive: false,
          ).firstMatch(body);
          if (dueDateMatch != null) {
            dueDate = dueDateMatch.group(1)?.trim() ?? '';
          }
        }
        if (mode.isEmpty) {
          final modeMatch = RegExp(
            r'[Mm]ode\s+de\s+paiement[:\s]+([A-Za-zÀ-ÿ0-9\s]+?)(?:\.|,|$)',
          ).firstMatch(body);
          if (modeMatch != null) {
            mode = modeMatch.group(1)?.trim() ?? '';
          }
        }

        final paymentParts = <String>[];
        if (dueDate.isNotEmpty) {
          paymentParts.add(
            lang == 'ar'
                ? 'قبل $dueDate'
                : (lang == 'en' ? 'Before $dueDate' : 'Avant le $dueDate'),
          );
        }
        if (mode.isNotEmpty) paymentParts.add(_localizePaymentMethod(mode));
        if (paymentParts.isNotEmpty) return paymentParts.join(' • ');
        break;

      case 'conseil_discipline':
      case 'convocation_parents':
      case 'retenue':
        String date = (payload['meeting_date'] as String?)?.trim() ?? '';
        String time = (payload['meeting_time'] as String?)?.trim() ?? '';
        if (date.isEmpty) {
          final m = RegExp(
            r'(?:le|يوم)\s+(\d{1,2}/\d{1,2}/\d{2,4})(?:\s+(?:à|الساعة)\s+(\d{1,2}:\d{2}))?',
            caseSensitive: false,
          ).firstMatch(body);
          if (m != null) {
            date = m.group(1)?.trim() ?? '';
            time = m.group(2)?.trim() ?? '';
          }
        }
        if (date.isEmpty) {
          final m = RegExp(r'(\d{1,2}/\d{1,2}/\d{2,4})').firstMatch(body);
          if (m != null) date = m.group(1)?.trim() ?? '';
        }
        if (date.isNotEmpty) {
          final prefix = lang == 'ar' ? 'يوم $date' : (lang == 'en' ? 'On $date' : 'Le $date');
          return time.isNotEmpty ? '$prefix • $time' : prefix;
        }
        break;

      case 'exclusion_classe':
      case 'exclusion_etablissement':
        String startDate = (payload['start_date'] as String?)?.trim() ?? '';
        String endDate = (payload['end_date'] as String?)?.trim() ?? '';
        if (startDate.isEmpty) {
          final m = RegExp(
            r'(\d{1,2}/\d{1,2}/\d{2,4}).*?(\d{1,2}/\d{1,2}/\d{2,4})',
          ).firstMatch(body);
          if (m != null) {
            startDate = m.group(1)?.trim() ?? '';
            endDate = m.group(2)?.trim() ?? '';
          }
        }
        if (startDate.isNotEmpty) {
          if (endDate.isNotEmpty && startDate != endDate) {
            return '$startDate $arrow $endDate';
          }
          return lang == 'ar' ? 'يوم $startDate' : (lang == 'en' ? 'On $startDate' : 'Le $startDate');
        }
        break;

      case 'exclusion_definitive':
      case 'avertissement':
        String date = (payload['sanction_date'] as String?)?.trim() ?? '';
        if (date.isEmpty) {
          final m = RegExp(r'(\d{1,2}/\d{1,2}/\d{2,4})').firstMatch(body);
          if (m != null) date = m.group(1)?.trim() ?? '';
        }
        if (date.isNotEmpty) {
          return lang == 'ar' ? 'يوم $date' : (lang == 'en' ? 'On $date' : 'Le $date');
        }
        break;

      default:
        // Generic date extraction fallback for any announcement with date in text
        final dateMatch = RegExp(
          r'(?:le|avant\s+le|du|يوم|قبل)\s+(\d{1,2}/\d{1,2}/\d{2,4})(?:\s+(?:à|الساعة)\s+(\d{1,2}:\d{2}))?',
          caseSensitive: false,
        ).firstMatch(body);
        if (dateMatch != null) {
          final d = dateMatch.group(1)?.trim() ?? '';
          final t = dateMatch.group(2)?.trim() ?? '';
          if (d.isNotEmpty) {
            final prefix = lang == 'ar' ? 'يوم $d' : (lang == 'en' ? 'On $d' : 'Le $d');
            return t.isNotEmpty ? '$prefix • $t' : prefix;
          }
        }
        break;
    }

    return '';
  }

  String localizeAnnouncementTitle(String? type, String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return '';
    final lang = locale.languageCode;
    if (lang == 'fr') return trimmed;

    final lower = trimmed.toLowerCase();
    // Common seed/template titles
    if (lower == 'rentrée scolaire 2025-2026') {
      return lang == 'ar'
          ? 'العودة المدرسية 2025-2026'
          : 'Back to School 2025-2026';
    }
    if (lower == 'réunion parents-professeurs') {
      return lang == 'ar'
          ? 'اجتماع الأولياء والأساتذة'
          : 'Parent-Teacher Meeting';
    }
    if (lower == "vacances d'hiver" ||
        lower == "calendrier des vacances d'hiver") {
      return lang == 'ar' ? 'عطلة الشتاء' : 'Winter Holidays';
    }
    if (lower == 'compétition de mathématiques') {
      return lang == 'ar' ? 'مسابقة الرياضيات' : 'Mathematics Competition';
    }
    if (lower == 'sortie groupe a') {
      return lang == 'ar' ? 'رحلة الفوج أ' : 'Group A Trip';
    }
    if (lower == 'inscription aux examens du semestre 1') {
      return lang == 'ar'
          ? 'التسجيل في امتحانات السداسي الأول'
          : 'Semester 1 Exam Registration';
    }
    if (lower == 'fermeture exceptionnelle') {
      return lang == 'ar' ? 'إغلاق استثنائي' : 'Exceptional Closure';
    }
    if (lower.startsWith('changement de salle')) {
      return lang == 'ar'
          ? trimmed.replaceFirst(
              RegExp(r'Changement de salle', caseSensitive: false),
              'تغيير القاعة',
            )
          : trimmed.replaceFirst(
              RegExp(r'Changement de salle', caseSensitive: false),
              'Room Change',
            );
    }
    return trimmed;
  }

  String localizeAnnouncementBody(
    String? type,
    Map<String, dynamic> payload,
    String body,
  ) {
    final trimmedBody = body.trim();
    if (trimmedBody.isEmpty) return '';

    final lang = locale.languageCode;
    if (lang == 'fr') {
      return trimmedBody.replaceAll(
        RegExp(r'\bsalle\s+Salle\s+', caseSensitive: false),
        'salle ',
      );
    }

    final isAr = lang == 'ar';

    switch (type) {
      case 'teacher_absent':
        String teacher = (payload['teacher_name'] as String?)?.trim() ?? '';
        String startDate = (payload['start_date'] as String?)?.trim() ?? '';
        String startTime = (payload['start_time'] as String?)?.trim() ?? '';
        String endDate = (payload['end_date'] as String?)?.trim() ?? '';
        String endTime = (payload['end_time'] as String?)?.trim() ?? '';
        String replacement =
            (payload['replacement_note'] as String?)?.trim() ?? '';

        if (teacher.isEmpty) {
          final mRange = RegExp(
            r'^(.+?)\s+sera absent(?:e)?\s+du\s+(\d{1,2}/\d{1,2}/\d{2,4})(?:\s+à\s+(\d{1,2}:\d{2}))?\s+au\s+(\d{1,2}/\d{1,2}/\d{2,4})(?:\s+à\s+(\d{1,2}:\d{2}))?\.(?:\s*(.+?)\.?)?$',
            caseSensitive: false,
          ).firstMatch(trimmedBody);
          if (mRange != null) {
            teacher = mRange.group(1)?.trim() ?? '';
            startDate = mRange.group(2)?.trim() ?? '';
            startTime = mRange.group(3)?.trim() ?? '';
            endDate = mRange.group(4)?.trim() ?? '';
            endTime = mRange.group(5)?.trim() ?? '';
            replacement = mRange.group(6)?.trim() ?? '';
          } else {
            final mSingle = RegExp(
              r'^(.+?)\s+sera absent(?:e)?(?:\s+le\s+(\d{1,2}/\d{1,2}/\d{2,4}))?(?:\s+de\s+(\d{1,2}:\d{2})\s+à\s+(\d{1,2}:\d{2})|\s+à partir de\s+(\d{1,2}:\d{2}))?\.(?:\s*(.+?)\.?)?$',
              caseSensitive: false,
            ).firstMatch(trimmedBody);
            if (mSingle != null) {
              teacher = mSingle.group(1)?.trim() ?? '';
              startDate = mSingle.group(2)?.trim() ?? '';
              startTime =
                  (mSingle.group(3) ?? mSingle.group(5))?.trim() ?? '';
              endTime = mSingle.group(4)?.trim() ?? '';
              replacement = mSingle.group(6)?.trim() ?? '';
            }
          }
        }

        if (teacher.isNotEmpty) {
          final cleanTeacher = teacher
              .replaceFirst(
                RegExp(r'^(?:prof\.?|أستاذ(?:ة)?)\s*', caseSensitive: false),
                '',
              )
              .trim();
          if (isAr) {
            String s = 'سيغيب الأستاذ(ة) $cleanTeacher';
            if (startDate.isNotEmpty) {
              if (endDate.isNotEmpty && startDate != endDate) {
                s += ' من $startDate';
                if (startTime.isNotEmpty) s += ' على الساعة $startTime';
                s += ' إلى $endDate';
                if (endTime.isNotEmpty) s += ' على الساعة $endTime';
              } else {
                s += ' يوم $startDate';
                if (startTime.isNotEmpty && endTime.isNotEmpty) {
                  s += ' من $startTime إلى $endTime';
                } else if (startTime.isNotEmpty) {
                  s += ' ابتداءً من الساعة $startTime';
                }
              }
            }
            s += '.';
            if (replacement.isNotEmpty) s += ' $replacement.';
            return s;
          } else {
            String s = '$cleanTeacher will be absent';
            if (startDate.isNotEmpty) {
              if (endDate.isNotEmpty && startDate != endDate) {
                s += ' from $startDate';
                if (startTime.isNotEmpty) s += ' at $startTime';
                s += ' to $endDate';
                if (endTime.isNotEmpty) s += ' at $endTime';
              } else {
                s += ' on $startDate';
                if (startTime.isNotEmpty && endTime.isNotEmpty) {
                  s += ' from $startTime to $endTime';
                } else if (startTime.isNotEmpty) {
                  s += ' starting at $startTime';
                }
              }
            }
            s += '.';
            if (replacement.isNotEmpty) s += ' $replacement.';
            return s;
          }
        }
        break;

      case 'room_change':
        String subject = (payload['subject'] as String?)?.trim() ?? '';
        String oldRoom = (payload['old_room'] as String?)?.trim() ?? '';
        String newRoom = (payload['new_room'] as String?)?.trim() ?? '';
        String date = (payload['change_date'] as String?)?.trim() ??
            (payload['date_time'] as String?)?.trim() ??
            '';
        String time = (payload['change_time'] as String?)?.trim() ?? '';

        if (oldRoom.isEmpty || newRoom.isEmpty || date.isEmpty) {
          final m = RegExp(
            r'Le cours(?:\s+de\s+(.+?))?\s+est déplacé de la salle\s+(.+?)\s+vers la salle\s+([^\s.]+)(?:\s+le\s+(\d{1,2}/\d{1,2}/\d{2,4}))?(?:\s+à\s+(\d{1,2}:\d{2}))?\.',
            caseSensitive: false,
          ).firstMatch(trimmedBody);
          if (m != null) {
            if (subject.isEmpty) subject = m.group(1)?.trim() ?? '';
            if (oldRoom.isEmpty) oldRoom = m.group(2)?.trim() ?? '';
            if (newRoom.isEmpty) newRoom = m.group(3)?.trim() ?? '';
            if (date.isEmpty) date = m.group(4)?.trim() ?? '';
            if (time.isEmpty) time = m.group(5)?.trim() ?? '';
          }
        }

        final cleanOld = _cleanRoomName(oldRoom);
        final cleanNew = _cleanRoomName(newRoom);
        final locSubject = _localizeSubjectName(subject);

        if (cleanOld.isNotEmpty && cleanNew.isNotEmpty) {
          if (isAr) {
            String s = locSubject.isNotEmpty
                ? 'تم نقل درس $locSubject'
                : 'تم نقل الدرس';
            s += ' من القاعة $cleanOld إلى القاعة $cleanNew';
            if (date.isNotEmpty) {
              s += ' يوم $date';
              if (time.isNotEmpty) s += ' على الساعة $time';
            }
            s += '.';
            return s;
          } else {
            String s = locSubject.isNotEmpty
                ? 'The $locSubject class'
                : 'The class';
            s += ' has been moved from room $cleanOld to room $cleanNew';
            if (date.isNotEmpty) {
              s += ' on $date';
              if (time.isNotEmpty) s += ' at $time';
            }
            s += '.';
            return s;
          }
        }
        break;

      case 'exam':
        String subject = (payload['subject'] as String?)?.trim() ?? '';
        String date = (payload['exam_date'] as String?)?.trim() ??
            (payload['date_time'] as String?)?.trim() ??
            '';
        String time = (payload['exam_time'] as String?)?.trim() ?? '';
        String room = (payload['room'] as String?)?.trim() ?? '';
        String instructions =
            (payload['instructions'] as String?)?.trim() ?? '';

        if (subject.isEmpty || date.isEmpty || room.isEmpty) {
          final m = RegExp(
            r'Un examen de\s+(.+?)(?:\s+aura lieu le\s+(\d{1,2}/\d{1,2}/\d{2,4}))?(?:\s+à\s+(\d{1,2}:\d{2}))?(?:\s+en salle\s+([^.]+))?\.(?:\s*(.+?)\.?)?$',
            caseSensitive: false,
          ).firstMatch(trimmedBody);
          if (m != null) {
            if (subject.isEmpty) subject = m.group(1)?.trim() ?? '';
            if (date.isEmpty) date = m.group(2)?.trim() ?? '';
            if (time.isEmpty) time = m.group(3)?.trim() ?? '';
            if (room.isEmpty) room = m.group(4)?.trim() ?? '';
            if (instructions.isEmpty) instructions = m.group(5)?.trim() ?? '';
          }
        }

        final cleanRoom = _cleanRoomName(room);
        final locSubject = _localizeSubjectName(subject);

        if (locSubject.isNotEmpty) {
          if (isAr) {
            String s = 'سيجرى امتحان في مادة $locSubject';
            if (date.isNotEmpty) {
              s += ' يوم $date';
              if (time.isNotEmpty) s += ' على الساعة $time';
            }
            if (cleanRoom.isNotEmpty) {
              s += ' بالقاعة $cleanRoom';
            }
            s += '.';
            if (instructions.isNotEmpty) s += ' $instructions.';
            return s;
          } else {
            String s = 'An exam in $locSubject';
            if (date.isNotEmpty) {
              s += ' will take place on $date';
              if (time.isNotEmpty) s += ' at $time';
            } else {
              s += ' is scheduled';
            }
            if (cleanRoom.isNotEmpty) {
              s += ' in room $cleanRoom';
            }
            s += '.';
            if (instructions.isNotEmpty) s += ' $instructions.';
            return s;
          }
        }
        break;

      case 'closure':
        String reason = (payload['reason'] as String?)?.trim() ?? '';
        String from = (payload['closed_from'] as String?)?.trim() ?? '';
        String to = (payload['closed_to'] as String?)?.trim() ?? '';
        String reopen = (payload['reopen_date'] as String?)?.trim() ?? '';

        if (reason.isEmpty && from.isEmpty) {
          final m = RegExp(
            r"L'établissement sera fermé(?:\s+pour\s+(.+?))?(?:\s+(?:du|le)\s+(\d{1,2}/\d{1,2}/\d{2,4}))?(?:\s+au\s+(\d{1,2}/\d{1,2}/\d{2,4}))?\.(?:\s*Réouverture prévue le\s*(\d{1,2}/\d{1,2}/\d{2,4})\.?)?",
            caseSensitive: false,
          ).firstMatch(trimmedBody);
          if (m != null) {
            reason = m.group(1)?.trim() ?? '';
            from = m.group(2)?.trim() ?? '';
            to = m.group(3)?.trim() ?? '';
            reopen = m.group(4)?.trim() ?? '';
          }
        }

        if (reason.isNotEmpty || from.isNotEmpty) {
          if (isAr) {
            String s = 'ستكون المؤسسة مغلقة';
            if (reason.isNotEmpty) s += ' بسبب $reason';
            if (from.isNotEmpty) {
              if (to.isNotEmpty) {
                s += ' من $from إلى $to';
              } else {
                s += ' يوم $from';
              }
            }
            s += '.';
            if (reopen.isNotEmpty) s += ' تستأنف الدراسة يوم $reopen.';
            return s;
          } else {
            String s = 'The school will be closed';
            if (reason.isNotEmpty) s += ' for $reason';
            if (from.isNotEmpty) {
              if (to.isNotEmpty) {
                s += ' from $from to $to';
              } else {
                s += ' on $from';
              }
            }
            s += '.';
            if (reopen.isNotEmpty) s += ' Reopening scheduled for $reopen.';
            return s;
          }
        }
        break;

      case 'reminder':
        String dueDate = (payload['due_date'] as String?)?.trim() ?? '';
        String action = (payload['action_required'] as String?)?.trim() ?? '';

        if (dueDate.isEmpty && action.isEmpty) {
          final m1 = RegExp(
            r'^Rappel:\s*(.+?)(?:\.\s*Date limite:\s*(\d{1,2}/\d{1,2}/\d{2,4}))?\.?$',
            caseSensitive: false,
          ).firstMatch(trimmedBody);
          if (m1 != null) {
            action = m1.group(1)?.trim() ?? '';
            dueDate = m1.group(2)?.trim() ?? '';
          } else {
            final m2 = RegExp(
              r'^Date limite:\s*(\d{1,2}/\d{1,2}/\d{2,4})\.?$',
              caseSensitive: false,
            ).firstMatch(trimmedBody);
            if (m2 != null) {
              dueDate = m2.group(1)?.trim() ?? '';
            }
          }
        }

        if (action.isNotEmpty || dueDate.isNotEmpty) {
          if (isAr) {
            if (action.isNotEmpty) {
              String s = 'تذكير: $action';
              if (dueDate.isNotEmpty) s += '. آخر أجل: $dueDate';
              s += '.';
              return s;
            } else {
              return 'آخر أجل: $dueDate.';
            }
          } else {
            if (action.isNotEmpty) {
              String s = 'Reminder: $action';
              if (dueDate.isNotEmpty) s += '. Deadline: $dueDate';
              s += '.';
              return s;
            } else {
              return 'Deadline: $dueDate.';
            }
          }
        }
        break;

      case 'trip':
        String destination = (payload['destination'] as String?)?.trim() ?? '';
        String departDate =
            (payload['departure_date'] as String?)?.trim() ?? '';
        String departTime =
            (payload['departure_time'] as String?)?.trim() ?? '';
        String returnDate = (payload['return_date'] as String?)?.trim() ?? '';
        String returnTime = (payload['return_time'] as String?)?.trim() ?? '';
        String meetingPoint =
            (payload['meeting_point'] as String?)?.trim() ?? '';
        String cost = (payload['cost'] as String?)?.trim() ?? '';
        String notes = (payload['notes'] as String?)?.trim() ?? '';

        if (destination.isEmpty) {
          final mDest = RegExp(
            r'Une sortie à\s+(.+?)\s+est organisée(?:\s+le\s+(\d{1,2}/\d{1,2}/\d{2,4}))?(?:\s+à\s+(\d{1,2}:\d{2}))?\.',
            caseSensitive: false,
          ).firstMatch(trimmedBody);
          if (mDest != null) {
            destination = mDest.group(1)?.trim() ?? '';
            if (departDate.isEmpty) departDate = mDest.group(2)?.trim() ?? '';
            if (departTime.isEmpty) departTime = mDest.group(3)?.trim() ?? '';
          }
          final mRet = RegExp(
            r'Retour prévu le\s+(\d{1,2}/\d{1,2}/\d{2,4})(?:\s+à\s+(\d{1,2}:\d{2}))?\.',
            caseSensitive: false,
          ).firstMatch(trimmedBody);
          if (mRet != null) {
            if (returnDate.isEmpty) returnDate = mRet.group(1)?.trim() ?? '';
            if (returnTime.isEmpty) returnTime = mRet.group(2)?.trim() ?? '';
          }
          final mMeet = RegExp(
            r'Rendez-vous:\s*([^.]+)\.',
            caseSensitive: false,
          ).firstMatch(trimmedBody);
          if (mMeet != null && meetingPoint.isEmpty) {
            meetingPoint = mMeet.group(1)?.trim() ?? '';
          }
          final mCost = RegExp(
            r'Coût:\s*([^.]+)\.',
            caseSensitive: false,
          ).firstMatch(trimmedBody);
          if (mCost != null && cost.isEmpty) {
            cost = mCost.group(1)?.trim() ?? '';
          }
        }

        if (destination.isNotEmpty) {
          if (isAr) {
            String s = 'تم تنظيم رحلة إلى $destination';
            if (departDate.isNotEmpty) {
              s += ' يوم $departDate';
              if (departTime.isNotEmpty) s += ' على الساعة $departTime';
            }
            s += '.';
            if (returnDate.isNotEmpty) {
              s += ' العودة المقررة يوم $returnDate';
              if (returnTime.isNotEmpty) s += ' على الساعة $returnTime';
              s += '.';
            }
            if (meetingPoint.isNotEmpty) {
              s += ' نقطة الالتقاء: $meetingPoint.';
            }
            if (cost.isNotEmpty) s += ' التكلفة: $cost.';
            if (notes.isNotEmpty) s += ' $notes';
            return s;
          } else {
            String s = 'A trip to $destination is organized';
            if (departDate.isNotEmpty) {
              s += ' on $departDate';
              if (departTime.isNotEmpty) s += ' at $departTime';
            }
            s += '.';
            if (returnDate.isNotEmpty) {
              s += ' Expected return on $returnDate';
              if (returnTime.isNotEmpty) s += ' at $returnTime';
              s += '.';
            }
            if (meetingPoint.isNotEmpty) {
              s += ' Meeting point: $meetingPoint.';
            }
            if (cost.isNotEmpty) s += ' Cost: $cost.';
            if (notes.isNotEmpty) s += ' $notes';
            return s;
          }
        }
        break;

      case 'party':
        String eventName = (payload['event_name'] as String?)?.trim() ?? '';
        String eventDate = (payload['event_date'] as String?)?.trim() ?? '';
        String eventTime = (payload['event_time'] as String?)?.trim() ?? '';
        String location = (payload['location'] as String?)?.trim() ?? '';
        String dressCode = (payload['dress_code'] as String?)?.trim() ?? '';
        String notes = (payload['notes'] as String?)?.trim() ?? '';

        if (eventName.isEmpty) {
          final mEv = RegExp(
            r'^(.+?)\s+aura lieu(?:\s+le\s+(\d{1,2}/\d{1,2}/\d{2,4}))?(?:\s+à\s+(\d{1,2}:\d{2}))?\.',
            caseSensitive: false,
          ).firstMatch(trimmedBody);
          if (mEv != null) {
            eventName = mEv.group(1)?.trim() ?? '';
            if (eventDate.isEmpty) eventDate = mEv.group(2)?.trim() ?? '';
            if (eventTime.isEmpty) eventTime = mEv.group(3)?.trim() ?? '';
          }
          final mLoc = RegExp(
            r'Lieu:\s*([^.]+)\.',
            caseSensitive: false,
          ).firstMatch(trimmedBody);
          if (mLoc != null && location.isEmpty) {
            location = mLoc.group(1)?.trim() ?? '';
          }
          final mDress = RegExp(
            r'Tenue:\s*([^.]+)\.',
            caseSensitive: false,
          ).firstMatch(trimmedBody);
          if (mDress != null && dressCode.isEmpty) {
            dressCode = mDress.group(1)?.trim() ?? '';
          }
        }

        if (eventName.isNotEmpty) {
          final locEvent = _localizeEventName(eventName);
          if (isAr) {
            String s = 'سيقام $locEvent';
            if (eventDate.isNotEmpty) {
              s += ' يوم $eventDate';
              if (eventTime.isNotEmpty) s += ' على الساعة $eventTime';
            }
            s += '.';
            if (location.isNotEmpty) s += ' المكان: $location.';
            if (dressCode.isNotEmpty) s += ' اللباس: $dressCode.';
            if (notes.isNotEmpty) s += ' $notes';
            return s;
          } else {
            String s = locEvent;
            if (eventDate.isNotEmpty) {
              s += ' will take place on $eventDate';
              if (eventTime.isNotEmpty) s += ' at $eventTime';
            }
            s += '.';
            if (location.isNotEmpty) s += ' Location: $location.';
            if (dressCode.isNotEmpty) s += ' Dress code: $dressCode.';
            if (notes.isNotEmpty) s += ' $notes';
            return s;
          }
        }
        break;

      case 'payment':
        String paymentType =
            (payload['payment_type'] as String?)?.trim() ?? '';
        String amount = (payload['amount'] as String?)?.trim() ?? '';
        String dueDate = (payload['due_date'] as String?)?.trim() ?? '';
        String method = (payload['payment_method'] as String?)?.trim() ?? '';
        String notes = (payload['notes'] as String?)?.trim() ?? '';

        if (paymentType.isEmpty && amount.isEmpty && dueDate.isEmpty) {
          final mPay = RegExp(
            r'^(Frais de scolarité|Frais d.inscription|Frais de sortie|Frais de matériel|Cotisation|Paiement)(?:\s+de\s+([^\s]+))?\s+à régler(?:\s+avant le\s+(\d{1,2}/\d{1,2}/\d{2,4}))?\.',
            caseSensitive: false,
          ).firstMatch(trimmedBody);
          if (mPay != null) {
            paymentType = mPay.group(1)?.trim() ?? '';
            amount = mPay.group(2)?.trim() ?? '';
            dueDate = mPay.group(3)?.trim() ?? '';
          }
          final mMode = RegExp(
            r'Mode de paiement:\s*([^.]+)\.',
            caseSensitive: false,
          ).firstMatch(trimmedBody);
          if (mMode != null && method.isEmpty) {
            method = mMode.group(1)?.trim() ?? '';
          }
        }

        if (paymentType.isNotEmpty || amount.isNotEmpty || dueDate.isNotEmpty) {
          final locPayType = _localizePaymentType(paymentType);
          final locMethod = _localizePaymentMethod(method);
          if (isAr) {
            String s = locPayType;
            if (amount.isNotEmpty) s += ' بقيمة $amount';
            s += ' مستحقة الدفع';
            if (dueDate.isNotEmpty) s += ' قبل $dueDate';
            s += '.';
            if (locMethod.isNotEmpty) s += ' طريقة الدفع: $locMethod.';
            if (notes.isNotEmpty) s += ' $notes';
            return s;
          } else {
            String s = locPayType;
            if (amount.isNotEmpty) s += ' of $amount';
            s += ' to be paid';
            if (dueDate.isNotEmpty) s += ' before $dueDate';
            s += '.';
            if (locMethod.isNotEmpty) s += ' Payment method: $locMethod.';
            if (notes.isNotEmpty) s += ' $notes';
            return s;
          }
        }
        break;

      case 'retenue':
        String date = (payload['exam_date'] as String?)?.trim() ?? '';
        String time = (payload['exam_time'] as String?)?.trim() ?? '';
        String room = (payload['room'] as String?)?.trim() ?? '';
        String instructions =
            (payload['instructions'] as String?)?.trim() ?? '';
        final cleanRoom = _cleanRoomName(room);
        if (isAr) {
          String s = 'تم تحديد عقوبة احتجاز';
          if (date.isNotEmpty) {
            s += ' يوم $date';
            if (time.isNotEmpty) s += ' على الساعة $time';
          }
          if (cleanRoom.isNotEmpty) s += ' بالقاعة $cleanRoom';
          s += '.';
          if (instructions.isNotEmpty) s += ' $instructions.';
          return s;
        } else {
          String s = 'A detention is scheduled';
          if (date.isNotEmpty) {
            s += ' on $date';
            if (time.isNotEmpty) s += ' at $time';
          }
          if (cleanRoom.isNotEmpty) s += ' in room $cleanRoom';
          s += '.';
          if (instructions.isNotEmpty) s += ' $instructions.';
          return s;
        }

      default:
        break;
    }

    return trimmedBody;
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return ['en', 'fr', 'ar'].contains(locale.languageCode);
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

// Extension for easier access
extension AppLocalizationsExtension on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
