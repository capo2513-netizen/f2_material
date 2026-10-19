import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/update_service.dart';
import 'login_screen.dart';
import 'user_out_scan_screen.dart';
import 'skt_barcode_scan_screen.dart'; // ★ SKT 바코드 전송 화면 임포트
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

  /// 1. [내 계정 설정 바텀시트 메뉴]
  void _showAccountSettingsDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Text(
                '내 계정 설정',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading:
                    const Icon(Icons.lock_outline, color: Color(0xFFA61C24)),
                title: const Text('비밀번호 변경'),
                subtitle: const Text('로그인 비밀번호를 새롭게 변경합니다.'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.pop(ctx);
                  _showChangePasswordDialog();
                },
              ),
              const Divider(),
              ListTile(
                leading:
                    const Icon(Icons.email_outlined, color: Color(0xFFA61C24)),
                title: const Text('이메일 주소 변경'),
                subtitle: const Text('비밀번호 분실 시 인증받을 이메일을 변경합니다.'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.pop(ctx);
                  _showChangeEmailDialog();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 2. [비밀번호 변경 팝업]
  void _showChangePasswordDialog() {
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    bool isUpdating = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Text('비밀번호 변경',
              style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: '새 비밀번호',
                  hintText: '6자리 이상 입력',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: '비밀번호 확인',
                  hintText: '비밀번호 다시 입력',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isUpdating ? null : () => Navigator.pop(ctx),
              child: const Text('취소', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: isUpdating
                  ? null
                  : () async {
                      final newPw = passwordController.text.trim();
                      final confirmPw = confirmController.text.trim();

                      if (newPw.length < 6) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('비밀번호는 최소 6자리 이상이어야 합니다.')),
                        );
                        return;
                      }
                      if (newPw != confirmPw) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('비밀번호가 일치하지 않습니다.')),
                        );
                        return;
                      }

                      setDialogState(() => isUpdating = true);
                      final error = await _authService.updateMyPassword(
                          newPassword: newPw);
                      setDialogState(() => isUpdating = false);

                      if (!mounted) return;
                      Navigator.pop(ctx);

                      if (error == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('비밀번호가 성공적으로 변경되었습니다.')),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(error)),
                        );
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFA61C24),
              ),
              child: isUpdating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('변경하기', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  /// 3. [이메일 주소 변경 팝업]
  void _showChangeEmailDialog() {
    final emailController = TextEditingController();
    bool isUpdating = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Text('이메일 주소 변경',
              style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '새로운 이메일 주소를 입력하세요.\n비밀번호 분실 시 해당 메일로 링크가 발송됩니다.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: '새 이메일 주소',
                  hintText: 'example@gmail.com',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isUpdating ? null : () => Navigator.pop(ctx),
              child: const Text('취소', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: isUpdating
                  ? null
                  : () async {
                      final newEmail = emailController.text.trim();
                      if (!newEmail.contains('@') || !newEmail.contains('.')) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('올바른 이메일 주소를 입력해주세요.')),
                        );
                        return;
                      }

                      setDialogState(() => isUpdating = true);
                      final error =
                          await _authService.updateMyEmail(newEmail: newEmail);
                      setDialogState(() => isUpdating = false);

                      if (!mounted) return;
                      Navigator.pop(ctx);

                      if (error == null) {
                        // 성공 시 확인 팝업을 띄워 메일 인증 링크 클릭을 명확히 안내
                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (successCtx) => AlertDialog(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            title: const Row(
                              children: [
                                Icon(Icons.mark_email_read_outlined,
                                    color: Color(0xFFA61C24)),
                                SizedBox(width: 8),
                                Text(
                                  '인증 메일 발송 완료',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 17),
                                ),
                              ],
                            ),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '입력하신 [$newEmail] 주소로\n인증 메일이 발송되었습니다.',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  '보안을 위해 해당 메일함에서 [인증 링크]를 클릭하셔야 계정 이메일 변경이 최종 완료됩니다.\n\n링크 확인 전까지는 이전 정보가 유지될 수 있습니다.',
                                  style: TextStyle(
                                      fontSize: 13, color: Colors.black87),
                                ),
                              ],
                            ),
                            actions: [
                              ElevatedButton(
                                onPressed: () => Navigator.pop(successCtx),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFA61C24),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: const Text('확인',
                                    style: TextStyle(color: Colors.white)),
                              ),
                            ],
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(error)),
                        );
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFA61C24),
              ),
              child: isUpdating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('변경하기', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
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
              // 1. 사용자 프로필 정보 카드 (누르면 내 계정 설정 팝업 호출)
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: InkWell(
                  onTap: _showAccountSettingsDialog,
                  borderRadius: BorderRadius.circular(12),
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
                        // 설정 진입 안내 아이콘
                        const Icon(Icons.settings_outlined,
                            color: Colors.grey, size: 22),
                      ],
                    ),
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

              // 2-1. 자재 입출고 등록 (모든 사용자 공통)
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

              const SizedBox(height: 12),

              // 2-2. SKT 바코드 전송 (신규 추가: 모든 현장 사용자 사용)
              _buildMenuCard(
                title: 'SKT 바코드 전송',
                subtitle: 'SKT 장비 바코드/QR 연속 스캔 및 국소 메모 전송',
                icon: Icons.qr_code_scanner_rounded,
                accentColor: const Color(0xFFE65100), // SKT 오렌지 테마
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SktBarcodeScanScreen(currentUser: user),
                    ),
                  );
                },
              ),

              // 3. 관리자 전용 메뉴 영역 (admin 또는 super_admin 만 노출)
              if (user.role == 'admin' || user.role == 'super_admin') ...[
                const SizedBox(height: 20),
                const Text(
                  '관리자 메뉴',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF334155)),
                ),
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
