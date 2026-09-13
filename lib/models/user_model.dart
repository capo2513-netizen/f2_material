import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String name;
  final String phone;
  final String team;
  final String role; // user, operator, admin, super_admin
  final String status; // pending, approved, dormant, rejected
  final String deviceId; // 1인 1단말기 고유값
  final DateTime lastActiveAt;

  UserModel({
    required this.uid,
    required this.name,
    required this.phone,
    required this.team,
    required this.role,
    required this.status,
    required this.deviceId,
    required this.lastActiveAt,
  });

  factory UserModel.fromMap(Map<String, dynamic> data, String documentId) {
    return UserModel(
      uid: documentId,
      name: data['name'] ?? '',
      phone: data['phone'] ?? '',
      team: data['team'] ?? '',
      role: data['role'] ?? 'user',
      status: data['status'] ?? 'pending',
      deviceId: data['deviceId'] ?? '',
      lastActiveAt:
          (data['lastActiveAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'phone': phone,
      'team': team,
      'role': role,
      'status': status,
      'deviceId': deviceId,
      'lastActiveAt': FieldValue.serverTimestamp(),
    };
  }
}
