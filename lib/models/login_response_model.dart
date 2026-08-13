import 'package:inspector_app/models/user_model.dart';

class LoginResponse {
  final bool status;
  final List<String> errors;
  final String? message;
  final String token;
  final User user;

  LoginResponse({
    required this.status,
    required this.errors,
    this.message,
    required this.token,
    required this.user,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>;
    return LoginResponse(
      status: json['status'] as bool? ?? true,
      errors: json['errors'] != null
          ? List<String>.from(json['errors'] as List)
          : [],
      message: json['message'] as String?,
      token: data['token'] as String,
      user: User.fromJson(data['user'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status,
      'errors': errors,
      if (message != null) 'message': message,
      'data': {'token': token, 'user': user.toJson()},
    };
  }
}
