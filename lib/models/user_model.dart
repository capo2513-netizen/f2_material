import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String name;
  final String phone;
  final String team;
  final String role; // user, operator, admin, super_admin
  final String status; // pending, approved, dormant, rejected
  final String deviceId; // 1인 1단말기 고유값
  final DateTime lastActiveAt; // 수정 완료

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
    DateTime parseDate(dynamic value) {
      if (value is Timestamp) {
        return value.toDate();
      } else if (value is String) {
        return DateTime.tryParse(value) ?? DateTime.now();
      }
      return DateTime.now();
    }

    return UserModel(
      uid: documentId,
      name: data['name'] ?? '',
      phone: data['phone'] ?? '',
      team: data['team'] ?? '',
      role: data['role'] ?? 'user',
      status: data['status'] ?? 'pending',
      deviceId: data['deviceId'] ?? '',
      lastActiveAt: parseDate(data['lastActiveAt']),
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
