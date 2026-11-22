class SchoolModel {
  final String id;
  final String name;
  final String? logoUrl;
  final String? address;
  final String? phone;
  final String? email;
  final String? code;
  final String? primaryColor;
  final String? secondaryColor;
  final String? bio;
  final DateTime createdAt;
  final bool isActive;
  final bool isSuspended;

  SchoolModel({
    required this.id,
    required this.name,
    this.logoUrl,
    this.address,
    this.phone,
    this.email,
    this.code,
    this.primaryColor,
    this.secondaryColor,
    this.bio,
    required this.createdAt,
    this.isActive = true,
    this.isSuspended = false,
  });

  factory SchoolModel.fromJson(Map<String, dynamic> json) {
    final bool active = (json['is_active'] as bool?) ?? true;
    final bool suspended = (json['is_suspended'] as bool?) ?? !active;
    return SchoolModel(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      logoUrl: json['logo_url'] as String?,
      address: json['address'] as String?,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      code: json['code'] as String?,
      primaryColor: json['primary_color'] as String?,
      secondaryColor: json['secondary_color'] as String?,
      bio: json['bio'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      isActive: active,
      isSuspended: suspended,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'logo_url': logoUrl,
      'address': address,
      'phone': phone,
      'email': email,
      'code': code,
      'primary_color': primaryColor,
      'secondary_color': secondaryColor,
      'bio': bio,
      'created_at': createdAt.toIso8601String(),
      'is_active': isActive,
      'is_suspended': isSuspended,
    };
  }
}
