import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase 초기화
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
        fontFamily: 'Pretendard', // 기본 시스템 폰트
      ),
      home: const LoginScreen(),
    );
  }
}
