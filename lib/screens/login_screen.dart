import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import '../services/auth_service.dart';
import 'register_screen.dart';
import 'pending_screen.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  final _storage = const FlutterSecureStorage();
  final _localAuth = LocalAuthentication();

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // 화면 빌드 완료 후 3일 이내 생체인식 자동 로그인 시도
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkBiometricAutoLogin();
    });
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// [핵심] 3일(72시간) 이내 접속 이력 확인 후 생체인증 자동 로그인
  Future<void> _checkBiometricAutoLogin() async {
    try {
      final lastLoginStr = await _storage.read(key: 'last_login_time');
      final savedPhone = await _storage.read(key: 'saved_phone');
      final savedPassword = await _storage.read(key: 'saved_password');

      // 저장된 로그인 정보가 없으면 일반 로그인 유지
      if (lastLoginStr == null || savedPhone == null || savedPassword == null) {
        return;
      }

      final lastLoginTime = DateTime.parse(lastLoginStr);
      final difference = DateTime.now().difference(lastLoginTime);

      // 마지막 로그인 후 3일(72시간) 초과 시 자동 로그인 만료
      if (difference.inHours >= 72) {
        return;
      }

      // 기기에서 생체인식(지문 센서 등) 지원 여부 확인
      final canAuth = await _localAuth.canCheckBiometrics ||
          await _localAuth.isDeviceSupported();
      if (!canAuth) return;

      // 안드로이드 지문/생체인식 팝업 호출
      final didAuthenticate = await _localAuth.authenticate(
        localizedReason: 'F2자재 빠른 로그인을 위해 생체인증을 진행합니다.',
        options: const AuthenticationOptions(
          biometricOnly: true, // 지문/얼굴인식 우선
          stickyAuth: true,
        ),
      );

      // 생체인증 성공 시 자동 로그인 진행
      if (didAuthenticate && mounted) {
        setState(() => _isLoading = true);
        final result = await _authService.login(
          phone: savedPhone,
          password: savedPassword,
        );
        setState(() => _isLoading = false);

        if (!mounted) return;

        if (result['success'] == true) {
          // 성공 시 최신 로그인 시각 갱신
          await _storage.write(
            key: 'last_login_time',
            value: DateTime.now().toIso8601String(),
          );

          if (result['status'] == 'pending') {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                  builder: (_) => PendingScreen(user: result['user'])),
            );
          } else {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                  builder: (_) => HomeScreen(user: result['user'])),
            );
          }
        }
      }
    } catch (e) {
      // 생체인증 취소 또는 실패 시 조용히 넘어가고 수동 로그인 폼 유지
      debugPrint('생체인식 자동 로그인 스킵: $e');
    }
  }

  /// [일반 로그인] 버튼 클릭 시 처리
  void _handleLogin() async {
    final phone = _phoneController.text.trim();
    final password = _passwordController.text.trim();

    if (phone.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('전화번호와 비밀번호를 모두 입력해주세요.')),
      );
      return;
    }

    setState(() => _isLoading = true);
    final result = await _authService.login(phone: phone, password: password);
    setState(() => _isLoading = false);

    if (!mounted) return;

    if (result['success'] == true) {
      // ★ 로그인 성공 시 3일 생체인증용 정보 안전 저장
      await _storage.write(key: 'saved_phone', value: phone);
      await _storage.write(key: 'saved_password', value: password);
      await _storage.write(
        key: 'last_login_time',
        value: DateTime.now().toIso8601String(),
      );

      if (result['status'] == 'pending') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => PendingScreen(user: result['user']),
          ),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => HomeScreen(user: result['user'])),
        );
      }
    } else {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text(
            '접속 제한 / 안내',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Text(result['message'] ?? '로그인에 실패했습니다.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('확인'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // F2 로고 영역
                Image.asset('assets/icon/app_icon.png', width: 90, height: 90),
                const SizedBox(height: 12),
                const Text(
                  'F2자재 관리시스템',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF222222),
                    letterSpacing: -0.5,
                  ),
                ),
                const Text(
                  '에프투텔레콤 현장 자재/장비 관리',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 36),

                // 전화번호 입력창
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(
                      Icons.phone_android,
                      color: Color(0xFFA61C24),
                    ),
                    labelText: '전화번호',
                    hintText: '01012345678 (- 없이 입력)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 비밀번호 입력창
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(
                      Icons.lock_outline,
                      color: Color(0xFFA61C24),
                    ),
                    labelText: '비밀번호',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // 로그인 버튼
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFA61C24),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 2,
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            '로그인',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 16),

                // 회원가입 페이지 이동
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      '처음 접속하시나요? ',
                      style: TextStyle(color: Colors.grey),
                    ),
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const RegisterScreen(),
                          ),
                        );
                      },
                      child: const Text(
                        '가입신청',
                        style: TextStyle(
                          color: Color(0xFFF39800),
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.underline,
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
