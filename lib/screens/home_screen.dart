import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/update_service.dart';
import 'login_screen.dart';
import 'user_out_scan_screen.dart';
import 'stock_lookup_screen.dart';
import 'advanced_inventory_screen.dart';
import 'admin_user_manage_screen.dart'; // [수정] 실제 파일명으로 정확하게 임포트

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
        title: const Text('로그아웃', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('정말 로그아웃 하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFA61C24)),
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
              // 사용자 프로필 정보 카드
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: const Color(0xFFA61C24).withOpacity(0.1),
                        child: const Icon(Icons.person, size: 34, color: Color(0xFFA61C24)),
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
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE2E8F0),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    user.role == 'super_admin'
                                        ? '최고관리자'
                                        : (user.role == 'admin' ? '관리자' : '작업자'),
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
                              style: const TextStyle(fontSize: 13, color: Colors.grey),
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
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
              ),
              const SizedBox(height: 12),

              // 1. 자재 출고 등록 메뉴 (작업자 / 관리자 공통)
              _buildMenuCard(
                title: '자재 출고 등록',
                subtitle: 'QR코드 스캔 및 SKT 시리얼 연속 등록',
                icon: Icons.qr_code_scanner,
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

              const SizedBox(height: 12),

              // 2. 재고 확인 메뉴
              _buildMenuCard(
                title: '재고 확인',
                subtitle: '보유 중인 사급자재 및 지입자재 목록/비고 조회',
                icon: Icons.inventory_2_outlined,
                accentColor: const Color(0xFF1E88E5),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => StockLookupScreen(currentUser: user),
                    ),
                  );
                },
              ),

              // 3. 관리자 전용 메뉴 영역 (admin 또는 super_admin)
              if (user.role == 'admin' || user.role == 'super_admin') ...[
                const SizedBox(height: 12),
                _buildMenuCard(
                  title: '입·출고 종합 관리 (관리자)',
                  subtitle: '자재 직접 입고/출고 및 재고 조정',
                  icon: Icons.admin_panel_settings_outlined,
                  accentColor: const Color(0xFFF39800),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AdvancedInventoryScreen(currentUser: user),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 12),
                // 4. 인원/사용자 관리 (신규 추가)
                _buildMenuCard(
                  title: '인원 및 승인 관리 (관리자)',
                  subtitle: '신규 사용자 승인 대기 목록 확인 및 직급/소속 관리',
                  icon: Icons.manage_accounts_outlined,
                  accentColor: const Color(0xFF10B981),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AdminUserManageScreen(currentUser: user),
                      ),
                    );
                  },
                ),
              ],

              const SizedBox(height: 30),
              // 하단 버전 정보 표시
              const Center(
                child: Text(
                  'F2 Material System\n정상 접속 중',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.4),
                ),
              ),
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