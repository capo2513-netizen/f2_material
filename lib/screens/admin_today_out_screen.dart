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
  String _selectedTradeType = '전체'; // 전체, 출고, 입고(반납), SKT바코드
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
                // 1) 날짜 선택 줄
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

                // 3) 구분 선택 ChoiceChips (전체 / 출고 / 입고·반납 / SKT바코드)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      const Text('구분: ',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey)),
                      ...['전체', '출고', '입고(반납)', 'SKT바코드'].map((type) {
                        final isSelected = _selectedTradeType == type;
                        Color selColor = const Color(0xFF2C3E50);
                        if (type == '출고') selColor = const Color(0xFFA61C24);
                        if (type == '입고(반납)')
                          selColor = const Color(0xFF1E88E5);
                        if (type == 'SKT바코드')
                          selColor = const Color(0xFFE65100);

                        return Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: ChoiceChip(
                            label: Text(type),
                            selected: isSelected,
                            selectedColor: selColor,
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
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // ★ [핵심] 일반 입출고 로그(normal_out_logs) 실시간 구독
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('normal_out_logs')
                  .where('outDate', isEqualTo: dateStr)
                  .snapshots(),
              builder: (context, outSnap) {
                // ★ [핵심] SKT 바코드 로그(skt_barcodes) 실시간 동시 구독
                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('skt_barcodes')
                      .where('regDate', isEqualTo: dateStr)
                      .snapshots(),
                  builder: (context, sktSnap) {
                    if (outSnap.connectionState == ConnectionState.waiting &&
                        sktSnap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    // 1) 두 컬렉션 데이터 병합
                    final List<Map<String, dynamic>> combinedLogs = [];

                    // 일반 자재 로그 추가
                    if (outSnap.hasData) {
                      for (var doc in outSnap.data!.docs) {
                        final d = doc.data() as Map<String, dynamic>;
                        d['docId'] = doc.id;
                        d['isSktBarcode'] = false;
                        combinedLogs.add(d);
                      }
                    }

                    // SKT 바코드 로그 추가
                    if (sktSnap.hasData) {
                      for (var doc in sktSnap.data!.docs) {
                        final d = doc.data() as Map<String, dynamic>;
                        d['docId'] = doc.id;
                        d['isSktBarcode'] = true;
                        d['type'] = 'SKT바코드';
                        d['outTime'] = d['regTime'] ?? '';
                        d['materialName'] = 'SKT 장비 바코드';
                        d['materialCode'] = d['barcode'] ?? '';
                        d['quantity'] = 1;
                        if ((d['warehouse'] ?? '').toString().isEmpty) {
                          d['warehouse'] = '현장'; // 미지정 시 기본 표기
                        }
                        combinedLogs.add(d);
                      }
                    }

                    if (combinedLogs.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.assignment_turned_in_outlined,
                                size: 50, color: Colors.grey[400]),
                            const SizedBox(height: 10),
                            Text(
                              '[$dateStr]\n해당 일자의 입출고 및 바코드 내역이 없습니다.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.grey[600], fontSize: 14),
                            ),
                          ],
                        ),
                      );
                    }

                    var filteredLogs = combinedLogs;

                    // 2) 거점 필터링
                    if (_selectedWarehouse != '전체') {
                      filteredLogs = filteredLogs.where((data) {
                        final wh = (data['warehouse'] ?? '').toString();
                        return wh == _selectedWarehouse;
                      }).toList();
                    }

                    // 3) 구분 필터링
                    if (_selectedTradeType != '전체') {
                      filteredLogs = filteredLogs.where((data) {
                        final t = (data['type'] ?? '출고').toString();
                        if (_selectedTradeType == '입고(반납)') {
                          return t.contains('입고');
                        } else if (_selectedTradeType == '출고') {
                          return t == '출고';
                        } else if (_selectedTradeType == 'SKT바코드') {
                          return data['isSktBarcode'] == true;
                        }
                        return true;
                      }).toList();
                    }

                    if (filteredLogs.isEmpty) {
                      return Center(
                        child: Text(
                            '[$dateStr] [$_selectedWarehouse / $_selectedTradeType] 조건의 내역이 없습니다.'),
                      );
                    }

                    // 4) 시간순 정렬 (최신 시간순)
                    filteredLogs.sort((a, b) => (b['outTime'] ?? '')
                        .toString()
                        .compareTo((a['outTime'] ?? '').toString()));

                    // ★ [2단계 핵심] "작업자 + 거점" 복합 키로 그룹핑 (광주/본사 출고 분리)
                    final Map<String, List<Map<String, dynamic>>> groupedData =
                        {};

                    for (var data in filteredLogs) {
                      final team = data['team'] ?? '미지정';
                      final userName = data['userName'] ?? '작업자';
                      final wh = (data['warehouse'] ?? '').toString();

                      // 복합 고유 키 생성: [팀명] 작업자명|거점
                      final groupKey = '[$team] $userName|$wh';
                      groupedData.putIfAbsent(groupKey, () => []).add(data);
                    }

                    final groupKeys = groupedData.keys.toList();

                    return ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: groupKeys.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final gKey = groupKeys[index];
                        final userLogs = groupedData[gKey]!;

                        // 키에서 작업자 타이틀과 거점 분리
                        final parts = gKey.split('|');
                        final userTitle = parts[0];
                        final cardWarehouse = parts.length > 1 ? parts[1] : '';

                        int totalOutQty = 0;
                        int totalInQty = 0;
                        int totalSktCount = 0;

                        for (var log in userLogs) {
                          final q = (log['quantity'] as num? ?? 1).toInt();
                          final t = (log['type'] ?? '출고').toString();
                          if (log['isSktBarcode'] == true) {
                            totalSktCount += 1;
                          } else if (t.contains('입고')) {
                            totalInQty += q;
                          } else {
                            totalOutQty += q;
                          }
                        }

                        final phone = userLogs.first['userPhone'] ?? '';

                        return Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              _showUserDetailModal(context, userTitle,
                                  cardWarehouse, phone, userLogs);
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  // 거점별 아바타 색상 구분
                                  CircleAvatar(
                                    backgroundColor: cardWarehouse == '광주'
                                        ? const Color(0xFFA61C24)
                                        : (cardWarehouse == '본사'
                                            ? const Color(0xFF2C3E50)
                                            : const Color(0xFFE65100)),
                                    foregroundColor: Colors.white,
                                    child: Text(
                                      cardWarehouse.isNotEmpty
                                          ? cardWarehouse[0]
                                          : '물',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                userTitle,
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            // 거점 뱃지
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2),
                                              decoration: BoxDecoration(
                                                color: cardWarehouse == '광주'
                                                    ? const Color(0xFFFFEBEE)
                                                    : (cardWarehouse == '본사'
                                                        ? const Color(
                                                            0xFFECEFF1)
                                                        : const Color(
                                                            0xFFFFF3E0)),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                cardWarehouse.isNotEmpty
                                                    ? '$cardWarehouse 창고'
                                                    : '미지정',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: cardWarehouse == '광주'
                                                      ? const Color(0xFFA61C24)
                                                      : (cardWarehouse == '본사'
                                                          ? const Color(
                                                              0xFF2C3E50)
                                                          : const Color(
                                                              0xFFE65100)),
                                                ),
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
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFFA61C24),
                                          ),
                                        ),
                                      if (totalInQty > 0)
                                        Text(
                                          '입고: +${totalInQty}개',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF1E88E5),
                                          ),
                                        ),
                                      if (totalSktCount > 0)
                                        Text(
                                          'SKT: ${totalSktCount}건',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFFE65100),
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
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // 작업자 입출고 및 SKT 바코드 상세 모달
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
                        '거점: ${warehouse.isNotEmpty ? warehouse : '미지정'} | 연락처: $phone',
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
                    final isSkt = item['isSktBarcode'] == true;
                    final type = (item['type'] ?? '출고').toString();
                    final memo = (item['memo'] ?? '').toString().trim();
                    final isReturn = type.contains('입고');

                    // 라벨 디자인 색상 결정
                    Color badgeBg = const Color(0xFFFFEBEE);
                    Color badgeBorder = const Color(0xFFFFCDD2);
                    Color badgeText = const Color(0xFFA61C24);

                    if (isSkt) {
                      badgeBg = const Color(0xFFFFF3E0);
                      badgeBorder = const Color(0xFFFFCC80);
                      badgeText = const Color(0xFFE65100);
                    } else if (isReturn) {
                      badgeBg = const Color(0xFFE3F2FD);
                      badgeBorder = const Color(0xFF90CAF9);
                      badgeText = const Color(0xFF1E88E5);
                    }

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
                                  color: badgeBg,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: badgeBorder),
                                ),
                                child: Text(
                                  type,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: badgeText,
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
                                  isSkt ? '바코드: $code' : '코드: $code',
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
                            isSkt ? '1건' : (isReturn ? '+$qty개' : '-$qty개'),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: badgeText,
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
