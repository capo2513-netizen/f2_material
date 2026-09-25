import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/update_service.dart';
import 'login_screen.dart';
import 'user_out_scan_screen.dart';
import 'stock_lookup_screen.dart';
import 'advanced_inventory_screen.dart';
import 'admin_user_manage_screen.dart';
import 'admin_today_out_screen.dart';

class HomeScreen extends StatefulWidget {
  final UserModel user;
  const HomeScreen({super.key, required this.user});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();

    // 홈 화면 진입 시 최신 버전 여부 자동 검사
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdateService.checkVersionAndShowDialog(context);
    });
  }

  void _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title:
            const Text('로그아웃', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('정말 로그아웃 하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFA61C24),
            ),
            child: const Text('로그아웃', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _authService.logout();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text(
          'F2 자재 관리 시스템',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: const Color(0xFFA61C24),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: '로그아웃',
            onPressed: _handleLogout,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. 사용자 프로필 정보 카드
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor:
                            const Color(0xFFA61C24).withOpacity(0.1),
                        child: const Icon(Icons.person,
                            size: 34, color: Color(0xFFA61C24)),
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
                                    color: Color(0xFF1E293B),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE2E8F0),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    user.role == 'super_admin'
                                        ? '최고관리자'
                                        : (user.role == 'admin'
                                            ? '관리자'
                                            : '작업자'),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF475569),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '소속: ${user.team} | 연락처: ${user.phone}',
                              style: const TextStyle(
                                  fontSize: 13, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),
              const Text(
                '현장 작업 메뉴',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF334155)),
              ),
              const SizedBox(height: 12),

              // 2. 자재 입출고 등록 (모든 사용자 공통)
              _buildMenuCard(
                title: '자재 입출고 등록',
                subtitle: 'QR 코드 스캔 및 규격 리스트를 통한 출고 및 반납',
                icon: Icons.swap_horiz_rounded,
                accentColor: const Color(0xFFA61C24),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => UserOutScanScreen(currentUser: user),
                    ),
                  );
                },
              ),

              // 3. 관리자 전용 메뉴 영역 (admin 또는 super_admin 만 노출)
              if (user.role == 'admin' || user.role == 'super_admin') ...[
                const SizedBox(height: 12),
                // 1) 입출고내역 검수
                _buildMenuCard(
                  title: '입출고내역 검수',
                  subtitle: '작업자별 일자별 입·출고 내역 및 수량 실시간 검수',
                  icon: Icons.assignment_turned_in_outlined,
                  accentColor: const Color(0xFF2C3E50),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AdminTodayOutScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                // 2) 입·출고 종합 관리
                _buildMenuCard(
                  title: '입·출고 종합 관리 (관리자)',
                  subtitle: '자재 직접 입고/출고 및 재고 조정',
                  icon: Icons.admin_panel_settings_outlined,
                  accentColor: const Color(0xFFF39800),
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
                const SizedBox(height: 12),
                // 3) 사용자 승인 및 권한 관리
                _buildMenuCard(
                  title: '사용자 승인 및 권한 관리',
                  subtitle: '신규 가입자 승인, 팀 배정 및 권한 설정',
                  icon: Icons.manage_accounts_outlined,
                  accentColor: const Color(0xFF1B5E20),
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

  Widget _buildMenuCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accentColor, size: 28),
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
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
