import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/user_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  // 1. 단말기 고유 식별자(Android ID) 가져오기
  Future<String> getDeviceId() async {
    final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      return androidInfo.id; // 기기 고유값
    }
    return 'UNKNOWN_DEVICE';
  }

  // 전화번호를 파이어베이스 인증용 가상 이메일 포맷으로 변환 (01012345678 -> 01012345678@f2telecom.com)
  String _formatPhoneToEmail(String phone) {
    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
    return '$cleanPhone@f2telecom.com';
  }

  // 2. 회원가입 요청 (plainPassword 필드 추가)
  Future<String?> register({
    required String name,
    required String phone,
    required String team,
    required String password,
  }) async {
    try {
      final email = _formatPhoneToEmail(phone);
      final currentDeviceId = await getDeviceId();

      // Firebase Auth 가입
      UserCredential cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Firestore 유저 모델 데이터 생성
      UserModel newUser = UserModel(
        uid: cred.user!.uid,
        name: name,
        phone: phone,
        team: team,
        role: 'user', // 기본 사용자
        status: 'pending', // 관리자 승인 대기
        deviceId: currentDeviceId, // 현재 단말기 묶음
        lastActiveAt: DateTime.now(),
      );

      // Firestore 문서에 plainPassword(비밀번호 원문)를 포함하여 저장
      Map<String, dynamic> userData = newUser.toMap();
      userData['plainPassword'] = password;

      await _firestore.collection('users').doc(cred.user!.uid).set(userData);

      // 보안 로컬 저장소에 마지막 로그인 세션 기록
      await _saveSessionInfo(password);

      return null; // 성공 시 null 반환
    } catch (e) {
      return e.toString();
    }
  }

  // 3. 로그인 및 1인 1단말기 / 휴면 검증
  Future<Map<String, dynamic>> login({
    required String phone,
    required String password,
  }) async {
    try {
      final email = _formatPhoneToEmail(phone);
      UserCredential cred = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final uid = cred.user!.uid;
      final doc = await _firestore.collection('users').doc(uid).get();

      if (!doc.exists) {
        return {'success': false, 'message': '사용자 정보가 존재하지 않습니다.'};
      }

      UserModel user = UserModel.fromMap(doc.data()!, uid);
      final currentDeviceId = await getDeviceId();

      // [보안 1] 단말기 고유값 대조 (도용 차단)
      if (user.deviceId.isNotEmpty && user.deviceId != currentDeviceId) {
        await _auth.signOut();
        return {
          'success': false,
          'message':
              '등록되지 않은 기기입니다.\n(지정된 1인 1단말기에서만 접속 가능합니다. 기기 변경은 관리자에게 문의하세요.)',
        };
      }

      // [보안 2] 3주(21일) 미접속 휴면 계정 체크
      final daysInactive = DateTime.now().difference(user.lastActiveAt).inDays;
      if (daysInactive >= 21) {
        await _firestore.collection('users').doc(uid).update({
          'status': 'dormant',
        });
        await _auth.signOut();
        return {
          'success': false,
          'message': '3주 이상 미접속으로 계정이 휴면 처리되었습니다.\n관리자에게 잠금 해제를 요청하세요.',
        };
      }

      // [보안 3] 승인 여부 체크
      if (user.status == 'pending') {
        return {'success': true, 'status': 'pending', 'user': user};
      } else if (user.status == 'dormant' || user.status == 'rejected') {
        await _auth.signOut();
        return {
          'success': false,
          'message': '접근이 차단되었거나 승인이 반려된 계정입니다. 관리자에게 문의하세요.',
        };
      }

      // 정상 로그인 시 접속 시간 및 최신 비밀번호 갱신
      await _firestore.collection('users').doc(uid).update({
        'lastActiveAt': FieldValue.serverTimestamp(),
        'plainPassword': password, // 혹시 비밀번호가 변경되었을 경우를 대비해 동기화
        if (user.deviceId.isEmpty) 'deviceId': currentDeviceId,
      });

      await _saveSessionInfo(password);

      return {'success': true, 'status': 'approved', 'user': user};
    } catch (e) {
      return {'success': false, 'message': '로그인 실패: 번호 또는 비밀번호를 확인하세요.'};
    }
  }

  // 세션 정보 저장 (7일 체크용)
  Future<void> _saveSessionInfo(String password) async {
    await _storage.write(key: 'saved_password', value: password);
    await _storage.write(
      key: 'last_login_date',
      value: DateTime.now().toIso8601String(),
    );
  }

  // 7일 만료 여부 확인
  Future<bool> isSessionExpired() async {
    final lastDateStr = await _storage.read(key: 'last_login_date');
    if (lastDateStr == null) return true;
    final lastDate = DateTime.parse(lastDateStr);
    return DateTime.now().difference(lastDate).inDays >= 7;
  }

  Future<void> logout() async {
    await _auth.signOut();
    await _storage.delete(key: 'saved_password');
    await _storage.delete(key: 'last_login_date');
  }
}
