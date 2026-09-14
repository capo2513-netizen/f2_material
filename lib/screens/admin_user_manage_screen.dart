import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

class AdminUserManageScreen extends StatefulWidget {
  final UserModel currentUser;
  const AdminUserManageScreen({super.key, required this.currentUser});

  @override
  State<AdminUserManageScreen> createState() => _AdminUserManageScreenState();
}

class _AdminUserManageScreenState extends State<AdminUserManageScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // 가입 승인 처리
  void _approveUser(UserModel user) async {
    await _firestore.collection('users').doc(user.uid).update({
      'status': 'approved',
    });
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${user.name} 님이 승인되었습니다.')));
    }
  }

  // 가입 반려 처리
  void _rejectUser(UserModel user) async {
    await _firestore.collection('users').doc(user.uid).update({
      'status': 'rejected',
    });
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${user.name} 님의 가입이 반려되었습니다.')));
    }
  }

  // 단말기 초기화 (기기 변경 시)
  void _resetDeviceId(UserModel user) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('단말기 초기화'),
        content: Text(
          '${user.name} 님의 등록 단말기 정보를 초기화하시겠습니까?\n초기화 후 새 단말기에서 로그인하면 새 기기로 등록됩니다.',
        ),
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
            child: const Text('초기화', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _firestore.collection('users').doc(user.uid).update({
        'deviceId': '',
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('단말기 고유 ID가 초기화되었습니다.')));
      }
    }
  }

  // 휴면 계정 잠금 해제
  void _unlockDormantUser(UserModel user) async {
    await _firestore.collection('users').doc(user.uid).update({
      'status': 'approved',
      'lastActiveAt': FieldValue.serverTimestamp(),
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${user.name} 님의 휴면 상태가 해제되었습니다.')),
      );
    }
  }

  // 사용자 정보 (이름, 팀명, 등급) 수정 다이얼로그
  void _showEditUserDialog(UserModel user) {
    final nameController = TextEditingController(text: user.name);
    final teamController = TextEditingController(text: user.team);
    String selectedRole = user.role;

    final bool isSuperAdmin = widget.currentUser.role == 'super_admin';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            '${user.name} 정보 수정',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: '이름',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: teamController,
                  decoration: const InputDecoration(
                    labelText: '소속 팀명',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedRole,
                  decoration: const InputDecoration(
                    labelText: '권한 등급',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    // 일반 admin은 작업자 등급만 부여 가능
                    const DropdownMenuItem(
                      value: 'user',
                      child: Text('사용자 (출고 전용)'),
                    ),
                    const DropdownMenuItem(
                      value: 'operator',
                      child: Text('운영자 (입/출고)'),
                    ),
                    // 최고관리자만 관리자 및 총괄관리자 지정 가능
                    if (isSuperAdmin) ...[
                      const DropdownMenuItem(
                        value: 'admin',
                        child: Text('관리자 (일반 회원관리)'),
                      ),
                      const DropdownMenuItem(
                        value: 'super_admin',
                        child: Text('총괄관리자'),
                      ),
                    ],
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() => selectedRole = val);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () async {
                await _firestore.collection('users').doc(user.uid).update({
                  'name': nameController.text.trim(),
                  'team': teamController.text.trim(),
                  'role': selectedRole,
                });
                if (mounted) Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2C3E50),
              ),
              child: const Text('수정 저장', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // 최고관리자만 가능한 계정 완전 삭제/탈퇴
  void _deleteUser(UserModel user) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          '계정 영구 삭제 / 탈퇴',
          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
        ),
        content: Text(
          '[경고] ${user.team} ${user.name} 님의 계정을 완전히 삭제하시겠습니까?\n삭제 후 복구할 수 없습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('영구 삭제', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _firestore.collection('users').doc(user.uid).delete();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('계정이 완전히 삭제되었습니다.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isSuperAdmin = widget.currentUser.role == 'super_admin';

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '사용자 승인 및 관리',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF2C3E50),
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFF39800),
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(text: '가입 승인 대기'),
            Tab(text: '전체 회원 목록'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // 탭 1: 가입 승인 대기 목록
          StreamBuilder<QuerySnapshot>(
            stream: _firestore
                .collection('users')
                .where('status', isEqualTo: 'pending')
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              // [핵심 필터링] 일반 admin인 경우 super_admin 계정은 아예 안 보이게 배제
              final docs = snapshot.data!.docs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                if (!isSuperAdmin && data['role'] == 'super_admin') {
                  return false;
                }
                return true;
              }).toList();

              if (docs.isEmpty) {
                return const Center(
                  child: Text(
                    '승인 대기 중인 신규 가입자가 없습니다.',
                    style: TextStyle(color: Colors.grey),
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (ctx, index) {
                  final user = UserModel.fromMap(
                    docs[index].data() as Map<String, dynamic>,
                    docs[index].id,
                  );

                  return Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${user.name} (${user.team})',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.edit,
                                  size: 20,
                                  color: Colors.blueGrey,
                                ),
                                tooltip: '팀명/이름 수정',
                                onPressed: () => _showEditUserDialog(user),
                              ),
                            ],
                          ),
                          Text(
                            '연락처: ${user.phone}',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            '단말기 ID: ${user.deviceId.isEmpty ? '미등록' : user.deviceId}',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 11,
                            ),
                          ),
                          const Divider(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              OutlinedButton(
                                onPressed: () => _rejectUser(user),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red,
                                ),
                                child: const Text('반려'),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: () => _approveUser(user),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFA61C24),
                                ),
                                child: const Text(
                                  '가입 승인',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),

          // 탭 2: 전체 회원 목록
          StreamBuilder<QuerySnapshot>(
            stream: _firestore.collection('users').snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              // [핵심 필터링] 일반 admin이 볼 때는 super_admin 데이터를 아예 리스트에서 배제
              final docs = snapshot.data!.docs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                if (!isSuperAdmin && data['role'] == 'super_admin') {
                  return false; // 일반 관리자 화면에선 super_admin 존재 자체를 숨김
                }
                return true;
              }).toList();

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (ctx, index) {
                  final user = UserModel.fromMap(
                    docs[index].data() as Map<String, dynamic>,
                    docs[index].id,
                  );
                  final bool isMe = user.uid == widget.currentUser.uid;
                  // 일반 admin은 동급 admin의 정보를 건드릴 수 없도록 보호
                  final bool isOtherAdmin = !isSuperAdmin && user.role == 'admin' && !isMe;

                  return Card(
                    elevation: 1,
                    child: ListTile(
                      title: Row(
                        children: [
                          Text(
                            user.name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '[${user.team}]',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(width: 6),
                          // 오직 super_admin 본인이 볼 때만 최고관리자 뱃지 표시
                          if (user.role == 'super_admin')
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.purple.shade50,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.purple.shade200),
                              ),
                              child: Text(
                                '총괄관리자',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.purple.shade700,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          if (user.status == 'dormant') ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange[100],
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                '휴면',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.orange,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('권한: ${user.role} | 번호: ${user.phone}'),
                          Text(
                            '단말기: ${user.deviceId.isEmpty ? '초기화됨' : '등록완료'}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 휴면 계정이면 해제 버튼
                          if (user.status == 'dormant')
                            IconButton(
                              icon: Icon(
                                Icons.lock_open,
                                color: isOtherAdmin ? Colors.grey[300] : Colors.orange,
                              ),
                              tooltip: isOtherAdmin ? '수정 불가' : '휴면 해제',
                              onPressed: isOtherAdmin ? null : () => _unlockDormantUser(user),
                            ),

                          // 단말기 초기화 버튼
                          IconButton(
                            icon: Icon(
                              Icons.phonelink_erase,
                              color: isOtherAdmin ? Colors.grey[300] : Colors.blueGrey,
                            ),
                            tooltip: isOtherAdmin ? '동급 관리자 초기화 불가' : '단말기 초기화',
                            onPressed: isOtherAdmin ? null : () => _resetDeviceId(user),
                          ),

                          // 정보/등급 수정 버튼
                          IconButton(
                            icon: Icon(
                              Icons.edit,
                              color: isOtherAdmin ? Colors.grey[300] : Colors.blueGrey,
                            ),
                            tooltip: isOtherAdmin ? '동급 관리자 수정 불가' : '정보/등급 수정',
                            onPressed: isOtherAdmin ? null : () => _showEditUserDialog(user),
                          ),

                          // 최고관리자만 가능한 계정 영구 삭제 버튼
                          if (isSuperAdmin && !isMe)
                            IconButton(
                              icon: const Icon(
                                Icons.delete_forever,
                                color: Colors.red,
                              ),
                              tooltip: '영구 삭제/탈퇴',
                              onPressed: () => _deleteUser(user),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}