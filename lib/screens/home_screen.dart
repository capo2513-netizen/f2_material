import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';
import 'user_out_scan_screen.dart';
import 'advanced_inventory_screen.dart';
import 'admin_user_manage_screen.dart';
import 'stock_lookup_screen.dart'; // 신규 추가

class HomeScreen extends StatefulWidget {
  final UserModel user;
  const HomeScreen({super.key, required this.user});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AuthService _authService = AuthService();

  void _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('로그아웃'),
        content: const Text('로그아웃 하시겠습니까?'),
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
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = widget.user.role;
    final bool canAccessAdvanced =
        role == 'operator' || role == 'admin' || role == 'super_admin';
    final bool canAccessAdmin = role == 'admin' || role == 'super_admin';

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'F2자재 관리 시스템',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFFA61C24),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: '로그아웃',
            onPressed: _handleLogout,
          ),
        ],
      ),
      body: Container(
        color: const Color(0xFFF5F6F8),
        child: Column(
          children: [
            // 상단 사용자 프로필 카드
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: const Color(0xFFA61C24).withOpacity(0.1),
                    child: const Icon(
                      Icons.person,
                      color: Color(0xFFA61C24),
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              widget.user.name,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: role == 'super_admin'
                                    ? Colors.purple[100]
                                    : role == 'admin'
                                    ? Colors.blue[100]
                                    : Colors.grey[200],
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                role == 'super_admin'
                                    ? '총괄관리자'
                                    : role == 'admin'
                                    ? '관리자'
                                    : '일반사용자',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: role == 'super_admin'
                                      ? Colors.purple[800]
                                      : role == 'admin'
                                      ? Colors.blue[800]
                                      : Colors.black87,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '소속: ${widget.user.team} | ${widget.user.phone}',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // 메인 메뉴 그리드/리스트
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  // 1. 자재 출고 등록 (모든 사용자)
                  _buildMenuCard(
                    title: '자재 출고 등록',
                    subtitle: '현장 사용 자재 출고 스캔 및 전송',
                    icon: Icons.qr_code_scanner,
                    color: const Color(0xFFA61C24),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              UserOutScanScreen(currentUser: widget.user),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),

                  // 2. 입고 관리 / 출고 관리 (운영자, 관리자 전용)
                  if (canAccessAdvanced) ...[
                    _buildMenuCard(
                      title: '입고 관리 / 출고 관리',
                      subtitle: '신품 / 구품 / 불량 자재 입·출고',
                      icon: Icons.inventory_2_rounded,
                      color: const Color(0xFFF39800),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AdvancedInventoryScreen(
                              currentUser: widget.user,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                  ],

                  // 3. 재고 확인 (모든 사용자 또는 필요 시 권한 부여)
                  _buildMenuCard(
                    title: '재고 확인',
                    subtitle: '자재별 현재 재고 및 코드 조회',
                    icon: Icons.search_rounded,
                    color: const Color(0xFF1E88E5), // 블루
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              StockLookupScreen(currentUser: widget.user),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),

                  // 4. 사용자 승인 및 관리 (관리자, 총괄관리자 전용)
                  if (canAccessAdmin) ...[
                    _buildMenuCard(
                      title: '사용자 승인 및 관리',
                      subtitle: '신규 가입 승인, 팀명/정보 수정, 기기 초기화',
                      icon: Icons.admin_panel_settings_rounded,
                      color: const Color(0xFF2C3E50),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                AdminUserManageScreen(currentUser: widget.user),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
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
