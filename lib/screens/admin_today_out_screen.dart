import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AdminTodayOutScreen extends StatefulWidget {
  const AdminTodayOutScreen({super.key});

  @override
  State<AdminTodayOutScreen> createState() => _AdminTodayOutScreenState();
}

class _AdminTodayOutScreenState extends State<AdminTodayOutScreen> {
  String _selectedWarehouse = '전체'; // 전체, 광주, 본사
  String _selectedTradeType = '전체'; // 전체, 출고, 입고(반납)
  DateTime _selectedDate = DateTime.now(); // 기본 오늘 날짜

  static const String _prefWarehouseKey = 'admin_last_selected_warehouse';

  @override
  void initState() {
    super.initState();
    _loadLastWarehouse();
  }

  // 마지막으로 선택했던 거점 불러오기
  Future<void> _loadLastWarehouse() async {
    final prefs = await SharedPreferences.getInstance();
    final savedWh = prefs.getString(_prefWarehouseKey);
    if (savedWh != null && mounted) {
      setState(() {
        _selectedWarehouse = savedWh;
      });
    }
  }

  // 거점 선택 시 기기에 영구 저장
  Future<void> _onWarehouseChanged(String wh) async {
    setState(() => _selectedWarehouse = wh);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefWarehouseKey, wh);
  }

  // 날짜 포맷 변환 (YYYY-MM-DD)
  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  // 달력 팝업 띄우기
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2023, 1, 1),
      lastDate: DateTime(2030, 12, 31),
      locale: const Locale('ko', 'KR'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF2C3E50),
              onPrimary: Colors.white,
              onSurface: Colors.black87,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = _formatDate(_selectedDate);
    final isToday = _formatDate(DateTime.now()) == dateStr;

    return Scaffold(
      appBar: AppBar(
        title: const Text('입출고내역 검수',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF2C3E50),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // 상단: 날짜 선택 & 거점 / 구분 필터
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            color: Colors.white,
            child: Column(
              children: [
                // 1) 날짜 선택 줄 (달력 터치 및 좌우 날짜 이동)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left, size: 22),
                          onPressed: () {
                            setState(() {
                              _selectedDate = _selectedDate
                                  .subtract(const Duration(days: 1));
                            });
                          },
                          tooltip: '하루 전',
                        ),
                        InkWell(
                          onTap: _pickDate,
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 4),
                            child: Row(
                              children: [
                                const Icon(Icons.calendar_month,
                                    size: 20, color: Color(0xFFA61C24)),
                                const SizedBox(width: 6),
                                Text(
                                  dateStr,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16),
                                ),
                                if (isToday) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE8F5E9),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      '오늘',
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: Color(0xFF2E7D32),
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right, size: 22),
                          onPressed: () {
                            setState(() {
                              _selectedDate =
                                  _selectedDate.add(const Duration(days: 1));
                            });
                          },
                          tooltip: '다음 날',
                        ),
                      ],
                    ),
                    if (!isToday)
                      TextButton(
                        onPressed: () =>
                            setState(() => _selectedDate = DateTime.now()),
                        child: const Text('오늘로',
                            style: TextStyle(
                                fontSize: 12, color: Color(0xFFA61C24))),
                      ),
                  ],
                ),
                const SizedBox(height: 6),

                // 2) 거점 선택 ChoiceChips
                Row(
                  children: [
                    const Text('거점: ',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey)),
                    ...['전체', '광주', '본사'].map((wh) {
                      final isSelected = _selectedWarehouse == wh;
                      return Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: ChoiceChip(
                          label: Text(wh),
                          selected: isSelected,
                          selectedColor: const Color(0xFF2C3E50),
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : Colors.black87,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                          onSelected: (val) {
                            if (val) _onWarehouseChanged(wh);
                          },
                        ),
                      );
                    }).toList(),
                  ],
                ),
                const SizedBox(height: 6),

                // 3) 구분 선택 ChoiceChips (전체 / 출고 / 입고·반납)
                Row(
                  children: [
                    const Text('구분: ',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey)),
                    ...['전체', '출고', '입고(반납)'].map((type) {
                      final isSelected = _selectedTradeType == type;
                      return Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: ChoiceChip(
                          label: Text(type),
                          selected: isSelected,
                          selectedColor: type == '출고'
                              ? const Color(0xFFA61C24)
                              : (type == '입고(반납)'
                                  ? const Color(0xFF1E88E5)
                                  : const Color(0xFF2C3E50)),
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : Colors.black87,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                          onSelected: (val) {
                            if (val) {
                              setState(() => _selectedTradeType = type);
                            }
                          },
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Firestore 실시간 구독: 단일 필터 쿼리 유지 (복합 인덱스 요구 차단)
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('normal_out_logs')
                  .where('outDate', isEqualTo: dateStr)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.assignment_turned_in_outlined,
                            size: 50, color: Colors.grey[400]),
                        const SizedBox(height: 10),
                        Text(
                          '[$dateStr]\n해당 일자의 입출고 내역이 없습니다.',
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(color: Colors.grey[600], fontSize: 14),
                        ),
                      ],
                    ),
                  );
                }

                var docs = snapshot.data!.docs;

                // 1) 거점 필터링
                if (_selectedWarehouse != '전체') {
                  docs = docs.where((d) {
                    final data = d.data() as Map<String, dynamic>;
                    return (data['warehouse'] ?? '') == _selectedWarehouse;
                  }).toList();
                }

                // 2) 구분 필터링 (출고 vs 입고/반납)
                if (_selectedTradeType != '전체') {
                  docs = docs.where((d) {
                    final data = d.data() as Map<String, dynamic>;
                    final t = (data['type'] ?? '출고').toString();
                    if (_selectedTradeType == '입고(반납)') {
                      return t.contains('입고');
                    } else {
                      return t == '출고';
                    }
                  }).toList();
                }

                if (docs.isEmpty) {
                  return Center(
                    child: Text(
                        '[$dateStr] [$_selectedWarehouse / $_selectedTradeType] 조건의 내역이 없습니다.'),
                  );
                }

                // 3) 클라이언트 메모리 정렬 (최신 시간순)
                final logList = docs.map((d) {
                  final data = d.data() as Map<String, dynamic>;
                  data['docId'] = d.id;
                  return data;
                }).toList();

                logList.sort((a, b) => (b['outTime'] ?? '')
                    .toString()
                    .compareTo((a['outTime'] ?? '').toString()));

                // 4) 작업자별 그룹화
                final Map<String, List<Map<String, dynamic>>> groupedByUser =
                    {};

                for (var data in logList) {
                  final team = data['team'] ?? '미지정';
                  final userName = data['userName'] ?? '작업자';
                  final userKey = '[$team] $userName';

                  groupedByUser.putIfAbsent(userKey, () => []).add(data);
                }

                final userKeys = groupedByUser.keys.toList();

                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: userKeys.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final userKey = userKeys[index];
                    final userLogs = groupedByUser[userKey]!;

                    int totalOutQty = 0;
                    int totalInQty = 0;

                    for (var log in userLogs) {
                      final q = (log['quantity'] as num? ?? 1).toInt();
                      final t = (log['type'] ?? '출고').toString();
                      if (t.contains('입고')) {
                        totalInQty += q;
                      } else {
                        totalOutQty += q;
                      }
                    }

                    final phone = userLogs.first['userPhone'] ?? '';
                    final warehouse = userLogs.first['warehouse'] ?? '';

                    return Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          _showUserDetailModal(
                              context, userKey, warehouse, phone, userLogs);
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: warehouse == '광주'
                                    ? const Color(0xFFA61C24)
                                    : const Color(0xFF2C3E50),
                                foregroundColor: Colors.white,
                                child: Text(
                                  warehouse.isNotEmpty ? warehouse[0] : '물',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
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
                                          userKey,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.grey[200],
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            warehouse,
                                            style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '연락처: $phone | 총 ${userLogs.length}건 기록',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600]),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  if (totalOutQty > 0)
                                    Text(
                                      '출고: -${totalOutQty}개',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFA61C24),
                                      ),
                                    ),
                                  if (totalInQty > 0)
                                    Text(
                                      '입고: +${totalInQty}개',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF1E88E5),
                                      ),
                                    ),
                                  const SizedBox(height: 2),
                                  const Text('상세보기 >',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.blueGrey)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // 작업자 입출고 상세 모달
  void _showUserDetailModal(
    BuildContext context,
    String userTitle,
    String warehouse,
    String phone,
    List<Map<String, dynamic>> logs,
  ) {
    logs.sort((a, b) => (b['outTime'] ?? '')
        .toString()
        .compareTo((a['outTime'] ?? '').toString()));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userTitle,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '거점: $warehouse | 연락처: $phone',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(height: 16),
              Text(
                '상세 내역 (${logs.length}건)',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.separated(
                  itemCount: logs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (c, idx) {
                    final item = logs[idx];
                    final time = item['outTime'] ?? '';
                    final name = item['materialName'] ?? '품명 없음';
                    final code = item['materialCode'] ?? '';
                    final qty = item['quantity'] ?? 1;
                    final serial = item['sktSerial'] ?? '';
                    final type = (item['type'] ?? '출고').toString();
                    final memo = (item['memo'] ?? '').toString().trim();
                    final isReturn = type.contains('입고');

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isReturn
                                      ? const Color(0xFFE3F2FD)
                                      : const Color(0xFFFFEBEE),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: isReturn
                                        ? const Color(0xFF90CAF9)
                                        : const Color(0xFFFFCDD2),
                                  ),
                                ),
                                child: Text(
                                  type,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isReturn
                                        ? const Color(0xFF1E88E5)
                                        : const Color(0xFFA61C24),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                time,
                                style: TextStyle(
                                    fontSize: 10, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '코드: $code ${serial.isNotEmpty ? '| S/N: $serial' : ''}',
                                  style: TextStyle(
                                      fontSize: 11, color: Colors.grey[600]),
                                ),
                                if (memo.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                          color: const Color(0xFFE2E8F0)),
                                    ),
                                    child: Text(
                                      '메모: $memo',
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF334155)),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isReturn ? '+$qty개' : '-$qty개',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isReturn
                                  ? const Color(0xFF1E88E5)
                                  : const Color(0xFFA61C24),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
