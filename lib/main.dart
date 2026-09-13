import 'dart:async'; // unawaited 사용을 위해 추가
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'firebase_options.dart';
import 'models/user_model.dart';
import 'services/auth_service.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/pending_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const F2MaterialApp());
}

class F2MaterialApp extends StatelessWidget {
  const F2MaterialApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'F2자재',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFA61C24),
          primary: const Color(0xFFA61C24),
          secondary: const Color(0xFFF39800),
        ),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final AuthService _authService = AuthService();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _checkAutoLogin(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFFA61C24)),
            ),
          );
        }
        // 에러 발생 시 안전하게 로그인 화면으로 이동
        if (snapshot.hasError) {
          return const LoginScreen();
        }
        return snapshot.data ?? const LoginScreen();
      },
    );
  }

  /// 자동 로그인 및 보안 검증 로직
  Future<Widget> _checkAutoLogin() async {
    final user = FirebaseAuth.instance.currentUser;
    // 1. 파이어베이스 세션 자체가 없으면 로그인행
    if (user == null) return const LoginScreen();

    // 2. 앱 자체 7일 세션 만료 여부 확인
    final isExpired = await _authService.isSessionExpired();
    if (isExpired) {
      await _forceLogout(); // 로컬 데이터까지 지우는 안전한 로그아웃
      return const LoginScreen();
    }

    // 3. 최신 유저 정보 DB 조회 및 기기 잠금/상태 검증
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      // DB에 유저 정보가 없으면 로그인행
      if (!doc.exists || doc.data() == null) {
        await _forceLogout();
        return const LoginScreen();
      }

      final userModel = UserModel.fromMap(doc.data()!, user.uid);
      final currentDeviceId = await _authService.getDeviceId();

      // [보안] 단말기 고유 ID 불일치 시 차단 (중복 로그인 방지)
      if (userModel.deviceId.isNotEmpty &&
          userModel.deviceId != currentDeviceId) {
        await _forceLogout();
        return const LoginScreen();
      }

      // [보안] 휴면(21일) 또는 거절된 계정 체크
      final daysInactive = DateTime.now()
          .difference(userModel.lastActiveAt)
          .inDays;
      if (daysInactive >= 21 ||
          userModel.status == 'dormant' ||
          userModel.status == 'rejected') {
        await _forceLogout();
        return const LoginScreen();
      }

      // 4. 승인 대기 계정 처리
      if (userModel.status == 'pending') {
        return PendingScreen(user: userModel);
      }

      // 5. [정상 유저] - 홈 화면으로 직행하되, 세션 갱신은 백그라운드에서 처리 (UX 향상)

      // 파이어베이스 접속일자 갱신 (기다리지 않음)
      unawaited(
        FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({'lastActiveAt': FieldValue.serverTimestamp()})
            .catchError((_) => null),
      ); // 에러 발생해도 무시 (다음 접속 때 갱신됨)

      // 로컬 세션 시작일자 갱신 (기다리지 않음)
      unawaited(
        _storage.write(
          key: 'last_login_date',
          value: DateTime.now().toIso8601String(),
        ),
      );

      // 갱신 완료를 기다리지 않고 바로 홈 화면 위젯 반환
      return HomeScreen(user: userModel);
    } catch (e) {
      // 네트워크 오류 등 예외 발생 시 로그인 화면으로 안전하게 복귀
      return const LoginScreen();
    }
  }

  /// 파이어베이스 로그아웃 및 로컬 세션 데이터까지 완벽히 삭제
  Future<void> _forceLogout() async {
    await _authService.logout(); // 파이어베이스 로그아웃
    await _storage.delete(key: 'last_login_date'); // 로컬 세션 날짜 삭제
  }
}
