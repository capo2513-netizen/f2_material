import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';
import 'user_out_scan_screen.dart'; // 곧 만들 사용자 전용 단순 출고 화면
import 'advanced_inventory_screen.dart'; // 곧 만들 운영자/관리자 전용 정밀 입출고 화면
import 'admin_user_manage_screen.dart'; // 곧 만들 관리자 전용 회원관리 화면

class HomeScreen extends StatelessWidget {
  final UserModel user;
  const HomeScreen({super.key, required this.user});

  String _getRoleLabel(String role) {
    switch (role) {
      case 'super_admin':
        return '총괄관리자';
      case 'admin':
        return '관리자';
      case 'operator':
        return '운영자';
      default:
        return '현장작업자';
    }
  }

  Color _getRoleBadgeColor(String role) {
    switch (role) {
      case 'super_admin':
      case 'admin':
        return const Color(0xFFA61C24); // 버건디
      case 'operator':
        return const Color(0xFFF39800); // 주황
      default:
        return const Color(0xFF4A90E2); // 파랑
    }
  }

  @override
  Widget build(BuildContext context) {
    // 권한 확인
    final bool isOperatorOrAdmin =
        user.role == 'operator' ||
        user.role == 'admin' ||
        user.role == 'super_admin';
    final bool isAdmin = user.role == 'admin' || user.role == 'super_admin';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(
        title: const Text(
          'F2자재 시스템',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFFA61C24),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: '로그아웃',
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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. 내 정보 프로필 카드
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20.0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: const Color(0xFFA61C24).withOpacity(0.1),
                      child: const Icon(
                        Icons.person,
                        size: 32,
                        color: Color(0xFFA61C24),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                user.name,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: _getRoleBadgeColor(user.role),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  _getRoleLabel(user.role),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            user.team,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF666666),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            user.phone,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF999999),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              const Text(
                '현장 작업 메뉴',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF333333),
                ),
              ),
              const SizedBox(height: 12),

              // 2. [사용자 / 운영자 / 관리자 공통] 일반 출고 버튼
              _buildMenuCard(
                context,
                title: '자재 출고 등록',
                subtitle: 'QR코드 스캔 후 바로 수량/시리얼 출고',
                icon: Icons.qr_code_scanner_rounded,
                color: const Color(0xFFA61C24),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => UserOutScanScreen(currentUser: user),
                    ),
                  );
                },
              ),
              const SizedBox(height: 14),

              // 3. [운영자 / 관리자 전용] 정밀 입출고 메뉴
              if (isOperatorOrAdmin) ...[
                _buildMenuCard(
                  context,
                  title: '정밀 입고 / 출고 관리',
                  subtitle: '신품·구품 입고 및 상태별 출고 상세 처리',
                  icon: Icons.swap_horizontal_circle_outlined,
                  color: const Color(0xFFF39800),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            AdvancedInventoryScreen(currentUser: user),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 14),
              ],

              // 4. [관리자 / 최고관리자 전용] 회원 승인 및 정보 수정 메뉴
              if (isAdmin) ...[
                _buildMenuCard(
                  context,
                  title: '회원 승인 및 팀 관리',
                  subtitle: '신규 가입 승인, 팀명 수정, 기기 초기화, 권한 관리',
                  icon: Icons.manage_accounts_rounded,
                  color: const Color(0xFF2C3E50),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            AdminUserManageScreen(currentUser: user),
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.2), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF222222),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF777777),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: Colors.grey,
            ),
          ],
        ),
      ),
    );
  }
}
