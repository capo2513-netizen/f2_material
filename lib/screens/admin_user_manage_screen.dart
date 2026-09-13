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
                    const DropdownMenuItem(
                      value: 'user',
                      child: Text('사용자 (출고 전용)'),
                    ),
                    const DropdownMenuItem(
                      value: 'operator',
                      child: Text('운영자 (입/출고)'),
                    ),
                    if (isSuperAdmin) ...[
                      const DropdownMenuItem(
                        value: 'admin',
                        child: Text('관리자 (회원/자재관리)'),
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
              if (!snapshot.hasData)
                return const Center(child: CircularProgressIndicator());
              final docs = snapshot.data!.docs;

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
              if (!snapshot.hasData)
                return const Center(child: CircularProgressIndicator());
              final docs = snapshot.data!.docs;

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (ctx, index) {
                  final user = UserModel.fromMap(
                    docs[index].data() as Map<String, dynamic>,
                    docs[index].id,
                  );
                  final bool isTargetAdmin =
                      user.role == 'admin' || user.role == 'super_admin';
                  final bool isMe = user.uid == widget.currentUser.uid;

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
                          if (user.status == 'dormant')
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
                              icon: const Icon(
                                Icons.lock_open,
                                color: Colors.orange,
                              ),
                              tooltip: '휴면 해제',
                              onPressed: () => _unlockDormantUser(user),
                            ),
                          // 단말기 초기화 버튼
                          IconButton(
                            icon: const Icon(
                              Icons.phonelink_erase,
                              color: Colors.blueGrey,
                            ),
                            tooltip: '단말기 초기화',
                            onPressed: () => _resetDeviceId(user),
                          ),
                          // 정보 수정 버튼
                          IconButton(
                            icon: const Icon(
                              Icons.edit,
                              color: Colors.blueGrey,
                            ),
                            tooltip: '정보/등급 수정',
                            onPressed: () => _showEditUserDialog(user),
                          ),
                          // 최고관리자만 볼 수 있는 관리자/회원 영구 탈퇴/삭제 버튼
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
