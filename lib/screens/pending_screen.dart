import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';

class PendingScreen extends StatelessWidget {
  final UserModel user;
  const PendingScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('승인 대기 중'),
        backgroundColor: const Color(0xFFA61C24),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await AuthService().logout();
              if (context.mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              }
            },
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.hourglass_top_rounded,
                size: 70,
                color: Color(0xFFF39800),
              ),
              const SizedBox(height: 24),
              Text(
                '${user.team} ${user.name} 님',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '현재 관리자 승인 대기 중입니다.\n관리자가 승인 및 팀명을 확인한 후\n자재 출고 기능을 이용하실 수 있습니다.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey, height: 1.5),
              ),
              const SizedBox(height: 32),
              OutlinedButton.icon(
                onPressed: () async {
                  // 새로고침 시 다시 로그인 시도하여 승인 여부 갱신
                  await AuthService().logout();
                  if (context.mounted) {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    );
                  }
                },
                icon: const Icon(Icons.refresh),
                label: const Text('상태 다시 확인하기'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
