import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

class StockLookupScreen extends StatefulWidget {
  final UserModel currentUser;
  const StockLookupScreen({super.key, required this.currentUser});

  @override
  State<StockLookupScreen> createState() => _StockLookupScreenState();
}

class _StockLookupScreenState extends State<StockLookupScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  String _formatStock(dynamic val) {
    if (val == null) return '0';
    if (val is int) return '$val';
    if (val is double) {
      if (val == val.roundToDouble()) {
        return '${val.toInt()}';
      }
      return '$val';
    }
    final d = double.tryParse(val.toString());
    if (d != null) {
      if (d == d.roundToDouble()) return '${d.toInt()}';
      return '$d';
    }
    return val.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '재고 확인',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1E88E5),
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: '사급자재 (재고보유)'),
            Tab(text: '지입자재 (재고보유)'),
          ],
        ),
      ),
      body: SafeArea(
        top: false, // 상단은 AppBar가 처리
        bottom: true, // 하단 내비게이션 바 영역 자동 감지 및 보호
        child: Column(
          children: [
            // 상단 검색창
            Container(
              padding: const EdgeInsets.all(14),
              color: Colors.white,
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: '자재코드, 품명 또는 비고 검색...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 0,
                    horizontal: 16,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onChanged: (val) => setState(() => _searchQuery = val.trim()),
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildStockList(itemTypeFilter: '사급'),
                  _buildStockList(itemTypeFilter: '지입'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStockList({required String itemTypeFilter}) {
    final bool isJip = itemTypeFilter == '지입';

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('materials').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final itemType = (data['itemType'] ?? '사급').toString();

          final dynamic rawStock = data['currentStock'];
          double stock = 0.0;
          if (rawStock is num) {
            stock = rawStock.toDouble();
          }

          if (itemType != itemTypeFilter) return false;
          if (stock <= 0) return false;

          final code = (data['materialCode'] ?? doc.id)
              .toString()
              .toLowerCase();
          final name = (data['materialName'] ?? '').toString().toLowerCase();
          final remark = (data['remark'] ?? '').toString().toLowerCase();
          final q = _searchQuery.toLowerCase();
          return code.contains(q) || name.contains(q) || remark.contains(q);
        }).toList();

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                  size: 48,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 12),
                Text(
                  _searchQuery.isEmpty
                      ? '현재 재고가 보유된 [$itemTypeFilter자재]가 없습니다.'
                      : '검색 조건에 맞는 [$itemTypeFilter자재]가 없습니다.',
                  style: const TextStyle(color: Colors.grey, fontSize: 14),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          // [핵심] 하단 여백을 80으로 늘려 내비게이션 바(홈/뒤로가기) 위로 완전히 올라오도록 설정
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (ctx, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final code = data['materialCode'] ?? docs[index].id;
            final name = data['materialName'] ?? '품명 없음';
            final unit = data['unit'] ?? 'EA';
            final remark = (data['remark'] ?? '').toString().trim();
            final stockFormatted = _formatStock(data['currentStock']);
            final category = data['category'] ?? '미분류';
            final requiresSerial = data['requiresSerial'] == true;

            return Card(
              elevation: 1.5,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!isJip) ...[
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFEBEE),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    category,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFFA61C24),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                if (requiresSerial)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFF3E0),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      '시리얼관리',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Color(0xFFEF6C00),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                          ],

                          // 1. 품명 / 규격
                          Text(
                            name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                          const SizedBox(height: 4),

                          // 2. 비고 (지입자재)
                          if (isJip) ...[
                            if (remark.isNotEmpty)
                              Container(
                                margin: const EdgeInsets.only(
                                  top: 2,
                                  bottom: 4,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '비고: $remark',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF475569),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              )
                            else
                              const Text(
                                '비고: (미기재)',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                          ] else ...[
                            Text(
                              '자재코드: $code',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),

                    // 3. 우측 재고 수량
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isJip
                            ? const Color(0xFFEBF5FF)
                            : const Color(0xFFFFF1F2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isJip
                              ? const Color(0xFFBFDBFE)
                              : const Color(0xFFFECDD3),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            '재고',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '$stockFormatted $unit',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isJip
                                  ? const Color(0xFF1E88E5)
                                  : const Color(0xFFA61C24),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
