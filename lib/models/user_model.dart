class User {
  final String id;
  final String email;
  final String role;
  final String name;
  final List<String>? permissions;

  User({
    required this.id,
    required this.email,
    required this.role,
    required this.name,
    this.permissions,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      email: json['email'] as String,
      role: json['role'] as String,
      name: json['name'] as String,
      permissions: json['permissions'] != null
          ? List<String>.from(json['permissions'] as List)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'role': role,
      'name': name,
      if (permissions != null) 'permissions': permissions,
    };
  }
}
