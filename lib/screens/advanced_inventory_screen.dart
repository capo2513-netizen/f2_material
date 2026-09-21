import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/user_model.dart';

// ------------------------------------------------------------
// 관리자 입·출고 항목 모델
// ------------------------------------------------------------
class AdminInventoryItem {
  final String materialCode;
  final String materialName;
  int quantity;

  AdminInventoryItem({
    required this.materialCode,
    required this.materialName,
    required this.quantity,
  });
}

// ------------------------------------------------------------
// 관리자 입·출고 종합관리 메인 화면
// ------------------------------------------------------------
class AdvancedInventoryScreen extends StatefulWidget {
  final UserModel currentUser;

  const AdvancedInventoryScreen({super.key, required this.currentUser});

  @override
  State<AdvancedInventoryScreen> createState() =>
      _AdvancedInventoryScreenState();
}

class _AdvancedInventoryScreenState extends State<AdvancedInventoryScreen> {
  // 모드: 'OUT' (관리자 출고 - 차감) / 'IN' (관리자 입고 - 가산)
  String _mode = 'OUT';
  // 거점: '광주' / '본사'
  String _selectedWarehouse = '광주';

  final List<AdminInventoryItem> _itemList = [];
  final TextEditingController _memoController = TextEditingController();
  bool _isSubmitting = false;

  // [성능 개선] 화면 생명주기 동안 단 1회만 유지되는 자재 스트림 (Firestore 로컬 캐시 활용)
  late final Stream<QuerySnapshot> _materialsStream;

  int get _totalQuantity =>
      _itemList.fold(0, (sum, item) => sum + item.quantity);

  @override
  void initState() {
    super.initState();
    _materialsStream =
        FirebaseFirestore.instance.collection('materials').snapshots();
  }

  @override
  void dispose() {
    _memoController.dispose();
    super.dispose();
  }

  // 자재 추가/합산 공통 함수
  void _addOrUpdateItem(String code, String name, int qty) {
    setState(() {
      final idx = _itemList.indexWhere((it) => it.materialCode == code);
      if (idx >= 0) {
        _itemList[idx].quantity += qty;
      } else {
        _itemList.add(AdminInventoryItem(
          materialCode: code,
          materialName: name,
          quantity: qty,
        ));
      }
    });
  }

  // 메인 리스트에서 숫자 터치 시 직접 수량 입력 다이얼로그 (대량 수량용)
  Future<void> _editQuantityDirectly(AdminInventoryItem item) async {
    final textController =
        TextEditingController(text: item.quantity.toString());
    final newQty = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${item.materialName}\n수량 직접 입력',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: textController,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '처리 수량',
            suffixText: '개',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () {
              final val = int.tryParse(textController.text.trim());
              if (val != null && val > 0) {
                Navigator.pop(ctx, val);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('1 이상의 올바른 숫자를 입력하세요.')),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  _mode == 'OUT' ? const Color(0xFFA61C24) : Colors.blue[800],
              foregroundColor: Colors.white,
            ),
            child: const Text('변경'),
          ),
        ],
      ),
    );

    if (newQty != null) {
      setState(() {
        item.quantity = newQty;
      });
    }
  }

  // 1. 목록 선택 모달 열기
  void _openItemListModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AdminCategorySelectModal(
        selectedWarehouse: _selectedWarehouse,
        mode: _mode,
        materialsStream: _materialsStream,
        onItemsAdded: (newItems) {
          for (var newItem in newItems) {
            _addOrUpdateItem(
                newItem.materialCode, newItem.materialName, newItem.quantity);
          }
        },
      ),
    );
  }

  // 2. QR 바코드 스캐너 모달 열기 (스캔 시 메인 _itemList로 즉시 통합)
  void _openScannerModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AdminScannerModal(
        selectedWarehouse: _selectedWarehouse,
        mode: _mode,
        onItemScanned: (code, name, qty) {
          _addOrUpdateItem(code, name, qty);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$name ($qty개) 선택 자재에 추가됨'),
              duration: const Duration(milliseconds: 1500),
            ),
          );
        },
      ),
    );
  }

  // 3. 최종 처리 전송 (출고: 차감 / 입고: 가산 + 메모 선택 허용)
  Future<void> _submitInventory() async {
    if (_itemList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('처리할 자재를 추가해 주세요.')),
      );
      return;
    }

    final memo = _memoController.text.trim();
    final isOut = _mode == 'OUT';
    final actionName = isOut ? '관리자 출고(차감)' : '관리자 입고(증가)';
    final logType = isOut ? '출고' : '입고';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$actionName 확인',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(
          '거점: [$_selectedWarehouse 창고]\n'
          '유형: [$logType]\n'
          '총 ${_itemList.length}종 (${_totalQuantity}개)\n'
          '비고: ${memo.isEmpty ? '(없음)' : memo}\n\n'
          '$actionName 처리를 확정하시겠습니까?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  isOut ? const Color(0xFFA61C24) : Colors.blue[800],
              foregroundColor: Colors.white,
            ),
            child: const Text('확정 실행'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isSubmitting = true);

    try {
      final now = DateTime.now();
      final dateStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final timeStr =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

      final firestore = FirebaseFirestore.instance;
      final batch = firestore.batch();
      final matCollection = firestore.collection('materials');
      final logCollection = firestore.collection('normal_out_logs');

      for (var item in _itemList) {
        // 1. 통합 입출고 로그 등록 (type: '입고' 또는 '출고')
        final docRef = logCollection.doc();
        batch.set(docRef, {
          'timestamp': FieldValue.serverTimestamp(),
          'type': logType,
          'outDate': dateStr,
          'outTime': timeStr,
          'warehouse': _selectedWarehouse,
          'team': '관리자',
          'userName': widget.currentUser.name,
          'userPhone': widget.currentUser.phone,
          'materialCode': item.materialCode,
          'materialName': item.materialName,
          'quantity': item.quantity,
          'memo': memo, // 엑셀 J열 비고 매핑
          'syncedToExcel': false,
        });

        // 2. 실시간 재고 가감 처리 ('거점_자재코드')
        final deltaStock = isOut ? -item.quantity : item.quantity;
        final matDocRef =
            matCollection.doc('${_selectedWarehouse}_${item.materialCode}');
        batch.update(matDocRef, {
          'currentStock': FieldValue.increment(deltaStock),
        });
      }

      await batch.commit();

      if (!mounted) return;
      setState(() {
        _itemList.clear();
        _memoController.clear();
        _isSubmitting = false;
      });

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('처리 완료',
              style: TextStyle(fontWeight: FontWeight.bold)),
          content: Text('[$_selectedWarehouse 창고] $actionName 처리가 완료되었습니다.'),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    isOut ? const Color(0xFFA61C24) : Colors.blue[800],
                foregroundColor: Colors.white,
              ),
              child: const Text('확인'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('처리 중 오류가 발생했습니다: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOut = _mode == 'OUT';

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('관리자 입·출고 종합관리',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // 작업 모드 선택 (출고 vs 입고)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Center(
                      child: Text('출고 모드 (재고 차감)',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    selected: isOut,
                    selectedColor: const Color(0xFFA61C24),
                    labelStyle: TextStyle(
                      color: isOut ? Colors.white : Colors.black87,
                    ),
                    onSelected: (val) {
                      if (val && _mode != 'OUT') {
                        setState(() {
                          _mode = 'OUT';
                          _itemList.clear();
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    label: const Center(
                      child: Text('입고 모드 (재고 증가)',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    selected: !isOut,
                    selectedColor: Colors.blue[800],
                    labelStyle: TextStyle(
                      color: !isOut ? Colors.white : Colors.black87,
                    ),
                    onSelected: (val) {
                      if (val && _mode != 'IN') {
                        setState(() {
                          _mode = 'IN';
                          _itemList.clear();
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // 거점 선택 (광주 vs 본사)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.white,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('관리 거점 선택',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                Row(
                  children: ['광주', '본사'].map((wh) {
                    final isSel = _selectedWarehouse == wh;
                    return Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: ChoiceChip(
                        label: Text(wh),
                        selected: isSel,
                        selectedColor:
                            isOut ? const Color(0xFFA61C24) : Colors.blue[800],
                        labelStyle: TextStyle(
                          color: isSel ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.bold,
                        ),
                        onSelected: (val) {
                          if (val && _selectedWarehouse != wh) {
                            setState(() {
                              _selectedWarehouse = wh;
                              _itemList.clear();
                            });
                          }
                        },
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // 진입 버튼 영역 (목록 선택 / QR 스캔)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _openItemListModal,
                    icon: const Icon(Icons.list_alt, size: 20),
                    label: Text('목록 선택 ($_selectedWarehouse)',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: const Color(0xFF2C3E50),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _openScannerModal,
                    icon: const Icon(Icons.qr_code_scanner, size: 20),
                    label: const Text('QR 스캔',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor:
                          isOut ? const Color(0xFFA61C24) : Colors.blue[800],
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 리스트 헤더
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '선택된 자재 (${_itemList.length}종 / 총 $_totalQuantity개)',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14),
                ),
                if (_itemList.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() => _itemList.clear()),
                    child: const Text('전체 비우기',
                        style: TextStyle(color: Colors.red, fontSize: 12)),
                  ),
              ],
            ),
          ),

          // 선택된 품목 리스트 (목록 선택 + QR 스캔 자재 모두 통합 표시)
          Expanded(
            child: _itemList.isEmpty
                ? Center(
                    child: Text(
                      '[$_selectedWarehouse 창고] 처리할 자재를 담아주세요.',
                      style: TextStyle(color: Colors.grey[500]),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _itemList.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (ctx, idx) {
                      final item = _itemList[idx];
                      return Card(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item.materialName,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14)),
                                    const SizedBox(height: 3),
                                    Text('코드: ${item.materialCode}',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey[600])),
                                  ],
                                ),
                              ),
                              Row(
                                children: [
                                  // [-] 버튼
                                  IconButton(
                                    icon: const Icon(
                                        Icons.remove_circle_outline,
                                        size: 22),
                                    onPressed: () {
                                      if (item.quantity > 1) {
                                        setState(() => item.quantity--);
                                      } else {
                                        setState(() =>
                                            _itemList.removeAt(idx));
                                      }
                                    },
                                  ),

                                  // ★ [숫자 터치 시 직접 수량 입력 팝업 띄우기]
                                  InkWell(
                                    onTap: () => _editQuantityDirectly(item),
                                    borderRadius: BorderRadius.circular(6),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                            color: const Color(0xFFCBD5E1)),
                                      ),
                                      child: Text(
                                        '${item.quantity}',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: isOut
                                              ? const Color(0xFFA61C24)
                                              : Colors.blue[800],
                                        ),
                                      ),
                                    ),
                                  ),

                                  // [+] 버튼
                                  IconButton(
                                    icon: const Icon(
                                        Icons.add_circle_outline,
                                        size: 22),
                                    onPressed: () {
                                      setState(() => item.quantity++);
                                    },
                                  ),

                                  // 삭제 아이콘
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        color: Colors.grey, size: 20),
                                    onPressed: () =>
                                        setState(() => _itemList.removeAt(idx)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // 관리자 메모 입력란 & 하단 확정 버튼
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
            ),
            child: SafeArea(
              child: Column(
                children: [
                  TextField(
                    controller: _memoController,
                    decoration: InputDecoration(
                      hintText: isOut
                          ? '출고 비고 입력 (선택사항, 예: OOO팀 현장수령 등)'
                          : '입고 비고 입력 (선택사항, 예: 신규 구매 입고 등)',
                      hintStyle:
                          TextStyle(fontSize: 13, color: Colors.grey[400]),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      prefixIcon:
                          const Icon(Icons.edit_note, color: Colors.grey),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: (_itemList.isEmpty || _isSubmitting)
                          ? null
                          : _submitInventory,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isOut
                            ? const Color(0xFFA61C24)
                            : Colors.blue[800],
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : Text(
                              isOut
                                  ? '관리자 출고 확정 ($_totalQuantity개 차감)'
                                  : '관리자 입고 확정 ($_totalQuantity개 가산)',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------
// 관리자 규격 목록 선택 바텀시트
// ------------------------------------------------------------
class _AdminCategorySelectModal extends StatefulWidget {
  final String selectedWarehouse;
  final String mode;
  final Stream<QuerySnapshot> materialsStream;
  final Function(List<AdminInventoryItem>) onItemsAdded;

  const _AdminCategorySelectModal({
    required this.selectedWarehouse,
    required this.mode,
    required this.materialsStream,
    required this.onItemsAdded,
  });

  @override
  State<_AdminCategorySelectModal> createState() =>
      _AdminCategorySelectModalState();
}

class _AdminCategorySelectModalState extends State<_AdminCategorySelectModal> {
  String? _selectedCat1;
  String? _selectedCat2;
  final Map<String, int> _quantities = {};

  // 목록 선택 화면 내에서도 숫자 터치 시 직접 수량 입력 지원
  Future<void> _editQuantityInList(String code, String name) async {
    final currentVal = _quantities[code] ?? 0;
    final textController = TextEditingController(
        text: currentVal > 0 ? currentVal.toString() : '');
    final newQty = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$name\n수량 직접 입력',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: textController,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '담을 수량',
            suffixText: '개',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () {
              final val = int.tryParse(textController.text.trim());
              if (val != null && val >= 0) {
                Navigator.pop(ctx, val);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('0 이상의 숫자를 입력하세요.')),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.mode == 'OUT'
                  ? const Color(0xFFA61C24)
                  : Colors.blue[800],
              foregroundColor: Colors.white,
            ),
            child: const Text('확인'),
          ),
        ],
      ),
    );

    if (newQty != null) {
      setState(() {
        _quantities[code] = newQty;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: StreamBuilder<QuerySnapshot>(
        stream: widget.materialsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('등록된 자재 목록이 없습니다.'));
          }

          final materials = snapshot.data!.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            data['docId'] = doc.id;
            return data;
          }).where((m) {
            final wh = (m['warehouse'] ?? '').toString().trim();
            final itemType = (m['itemType'] ?? '').toString().trim();

            if (widget.selectedWarehouse == '광주') {
              return wh == '광주';
            } else {
              return wh == '본사' && itemType != '사급';
            }
          }).toList();

          final cat1Set = <String>{};
          for (var m in materials) {
            final c1 = (m['category1'] ?? m['분류1'] ?? '').toString().trim();
            if (c1.isNotEmpty) cat1Set.add(c1);
          }
          final cat1List = cat1Set.toList()..sort();

          if ((_selectedCat1 == null || !cat1List.contains(_selectedCat1)) &&
              cat1List.isNotEmpty) {
            _selectedCat1 = cat1List.first;
          }

          final cat2Set = <String>{};
          for (var m in materials) {
            final c1 = (m['category1'] ?? m['분류1'] ?? '').toString().trim();
            final c2 = (m['category2'] ?? m['분류2'] ?? '').toString().trim();
            if (c1 == _selectedCat1 && c2.isNotEmpty) {
              cat2Set.add(c2);
            }
          }
          final cat2List = cat2Set.toList()..sort();

          if ((_selectedCat2 == null || !cat2List.contains(_selectedCat2)) &&
              cat2List.isNotEmpty) {
            _selectedCat2 = cat2List.first;
          }

          final filteredMaterials = materials.where((m) {
            final c1 = (m['category1'] ?? m['분류1'] ?? '').toString().trim();
            final c2 = (m['category2'] ?? m['분류2'] ?? '').toString().trim();
            if (cat2List.isNotEmpty) {
              return c1 == _selectedCat1 && c2 == _selectedCat2;
            }
            return c1 == _selectedCat1;
          }).toList();

          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '관리자 품목 선택 [${widget.selectedWarehouse} 창고]',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedCat1,
                        isExpanded: true,
                        menuMaxHeight: 450,
                        itemHeight: kMinInteractiveDimension,
                        decoration: const InputDecoration(
                          labelText: '대분류',
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(),
                        ),
                        items: cat1List.map((c) {
                          return DropdownMenuItem(
                              value: c,
                              child: Text(c, overflow: TextOverflow.ellipsis));
                        }).toList(),
                        onChanged: (val) {
                          setState(() {
                            _selectedCat1 = val;
                            _selectedCat2 = null;
                            _quantities.clear();
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedCat2,
                        isExpanded: true,
                        menuMaxHeight: 450,
                        itemHeight: kMinInteractiveDimension,
                        decoration: const InputDecoration(
                          labelText: '소분류',
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(),
                        ),
                        items: cat2List.map((c) {
                          return DropdownMenuItem(
                              value: c,
                              child: Text(c, overflow: TextOverflow.ellipsis));
                        }).toList(),
                        onChanged: (val) {
                          setState(() {
                            _selectedCat2 = val;
                            _quantities.clear();
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: filteredMaterials.isEmpty
                      ? Center(
                          child: Text(
                              '[$widget.selectedWarehouse] 자재가 존재하지 않습니다.',
                              style: TextStyle(color: Colors.grey[600])))
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: filteredMaterials.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1),
                          itemBuilder: (context, idx) {
                            final mat = filteredMaterials[idx];
                            final code = (mat['materialCode'] ??
                                    mat['F2자재코드'] ??
                                    mat['docId'])
                                .toString();
                            final name =
                                (mat['materialName'] ?? mat['품명'] ?? '')
                                    .toString();
                            final spec =
                                (mat['spec'] ?? mat['규격'] ?? '').toString();

                            final rawStock =
                                mat['currentStock'] ?? mat['현재고'] ?? 0;
                            final int stock = rawStock is num
                                ? rawStock.toInt()
                                : (int.tryParse(rawStock.toString()) ?? 0);

                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                name.isNotEmpty ? name : spec,
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2),
                                              decoration: BoxDecoration(
                                                color: stock > 0
                                                    ? const Color(0xFFE8F5E9)
                                                    : (stock < 0
                                                        ? const Color(
                                                            0xFFFFEBEE)
                                                        : const Color(
                                                            0xFFF1F5F9)),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text('현재고: $stock',
                                                  style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: stock > 0
                                                          ? const Color(
                                                              0xFF2E7D32)
                                                          : (stock < 0
                                                              ? const Color(
                                                                  0xFFD32F2F)
                                                              : Colors
                                                                  .grey[600]))),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                            spec.isNotEmpty
                                                ? '$spec  |  코드: $code'
                                                : '코드: $code',
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey[600])),
                                      ],
                                    ),
                                  ),
                                  StatefulBuilder(
                                    builder: (ctx, setLocalQty) {
                                      final currentQty =
                                          _quantities[code] ?? 0;
                                      return Row(
                                        children: [
                                          IconButton(
                                            icon: const Icon(
                                                Icons.remove_circle_outline,
                                                size: 22),
                                            color: currentQty > 0
                                                ? Colors.red
                                                : Colors.grey[300],
                                            onPressed: currentQty > 0
                                                ? () {
                                                    setLocalQty(() =>
                                                        _quantities[code] =
                                                            currentQty - 1);
                                                    setState(() {});
                                                  }
                                                : null,
                                          ),
                                          // 숫자 터치 시 직접 입력 창
                                          InkWell(
                                            onTap: () async {
                                              await _editQuantityInList(
                                                  code,
                                                  name.isNotEmpty
                                                      ? name
                                                      : spec);
                                              setLocalQty(() {});
                                            },
                                            child: Container(
                                              alignment: Alignment.center,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 4),
                                              decoration: BoxDecoration(
                                                color: currentQty > 0
                                                    ? const Color(0xFFFFEBEE)
                                                    : Colors.transparent,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                '$currentQty',
                                                style: TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.bold,
                                                  color: currentQty > 0
                                                      ? const Color(0xFFA61C24)
                                                      : Colors.black,
                                                ),
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(
                                                Icons.add_circle_outline,
                                                size: 22),
                                            color: const Color(0xFF1E293B),
                                            onPressed: () {
                                              setLocalQty(() =>
                                                  _quantities[code] =
                                                      currentQty + 1);
                                              setState(() {});
                                            },
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                SafeArea(
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: Builder(
                      builder: (context) {
                        final totalSelectedCount =
                            _quantities.values.fold(0, (sum, q) => sum + q);
                        return ElevatedButton(
                          onPressed: totalSelectedCount == 0
                              ? null
                              : () {
                                  List<AdminInventoryItem> itemsToAdd = [];
                                  _quantities.forEach((code, qty) {
                                    if (qty > 0) {
                                      final target = materials.firstWhere(
                                        (m) =>
                                            (m['materialCode'] ??
                                                m['F2자재코드'] ??
                                                m['docId']) ==
                                            code,
                                        orElse: () => {},
                                      );

                                      final matName = (target['materialName'] ??
                                              target['품명'] ??
                                              '')
                                          .toString();
                                      final spec = (target['spec'] ??
                                              target['규격'] ??
                                              '')
                                          .toString();

                                      String displayName = matName;
                                      if (spec.isNotEmpty &&
                                          spec != matName) {
                                        displayName = matName.isNotEmpty
                                            ? '$matName ($spec)'
                                            : spec;
                                      }
                                      if (displayName.isEmpty) {
                                        displayName = code;
                                      }

                                      itemsToAdd.add(AdminInventoryItem(
                                        materialCode: code,
                                        materialName: displayName,
                                        quantity: qty,
                                      ));
                                    }
                                  });

                                  widget.onItemsAdded(itemsToAdd);
                                  Navigator.pop(context);
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E293B),
                            foregroundColor: Colors.white,
                          ),
                          child: Text('선택한 자재 담기 ($totalSelectedCount개)'),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ------------------------------------------------------------
// 관리자 QR 스캐너 바텀시트 (스캔 후 수량 입력 ➡️ 메인 리스트로 즉시 전송)
// ------------------------------------------------------------
class _AdminScannerModal extends StatefulWidget {
  final String selectedWarehouse;
  final String mode;
  final Function(String code, String name, int qty) onItemScanned;

  const _AdminScannerModal({
    required this.selectedWarehouse,
    required this.mode,
    required this.onItemScanned,
  });

  @override
  State<_AdminScannerModal> createState() => _AdminScannerModalState();
}

class _AdminScannerModalState extends State<_AdminScannerModal> {
  final MobileScannerController _scannerController = MobileScannerController();
  bool _isProcessing = false;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;
    final rawVal = capture.barcodes.firstOrNull?.rawValue?.trim();
    if (rawVal == null || rawVal.isEmpty) return;

    setState(() => _isProcessing = true);
    _scannerController.stop(); // 팝업 띄우는 동안 스캔 일시 중지

    try {
      String targetWarehouse = widget.selectedWarehouse;
      String materialCode = rawVal;

      if (rawVal.contains('|')) {
        final parts = rawVal.split('|');
        if (parts.length >= 2) {
          targetWarehouse = parts[0].trim();
          materialCode = parts[1].trim();
        }
      }

      String matDocId = '${targetWarehouse}_$materialCode';
      var snap = await FirebaseFirestore.instance
          .collection('materials')
          .doc(matDocId)
          .get();

      if (!snap.exists) {
        snap = await FirebaseFirestore.instance
            .collection('materials')
            .doc('광주_$materialCode')
            .get();
      }

      if (!snap.exists) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('등록되지 않은 자재코드입니다: $materialCode')),
        );
        await Future.delayed(const Duration(seconds: 1));
        _scannerController.start();
        setState(() => _isProcessing = false);
        return;
      }

      final data = snap.data()!;
      final matName = (data['materialName'] ?? data['품명'] ?? '').toString();
      final spec = (data['spec'] ?? data['규격'] ?? '').toString();

      String displayName = matName;
      if (spec.isNotEmpty && spec != matName) {
        displayName = matName.isNotEmpty ? '$matName ($spec)' : spec;
      }
      if (displayName.isEmpty) displayName = materialCode;

      // QR 스캔 즉시 수량 조절 다이얼로그 (+ / - 및 직접 입력창 포함)
      if (!mounted) return;
      final textController = TextEditingController(text: '1');
      int tempQty = 1;

      final int? selectedQty = await showDialog<int>(
        context: context,
        barrierDismissible: false,
        builder: (dlgCtx) {
          return StatefulBuilder(
            builder: (context, setDlgState) {
              return AlertDialog(
                title: const Text('자재 수량 지정',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('거점: [$targetWarehouse 창고]',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blueGrey)),
                    const SizedBox(height: 6),
                    Text(displayName,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text('코드: $materialCode',
                        style: TextStyle(
                            color: Colors.grey[600], fontSize: 12)),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline,
                              size: 32, color: Colors.red),
                          onPressed: tempQty > 1
                              ? () {
                                  setDlgState(() {
                                    tempQty--;
                                    textController.text = tempQty.toString();
                                  });
                                }
                              : null,
                        ),
                        SizedBox(
                          width: 80,
                          child: TextField(
                            controller: textController,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                            decoration: const InputDecoration(
                              contentPadding: EdgeInsets.symmetric(vertical: 8),
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (val) {
                              final parsed = int.tryParse(val);
                              if (parsed != null && parsed > 0) {
                                tempQty = parsed;
                              }
                            },
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline,
                              size: 32, color: Colors.blue),
                          onPressed: () {
                            setDlgState(() {
                              tempQty++;
                              textController.text = tempQty.toString();
                            });
                          },
                        ),
                      ],
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dlgCtx, null),
                    child: const Text('취소'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      final finalVal =
                          int.tryParse(textController.text.trim()) ?? tempQty;
                      Navigator.pop(dlgCtx, finalVal > 0 ? finalVal : 1);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.mode == 'OUT'
                          ? const Color(0xFFA61C24)
                          : Colors.blue[800],
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('담기'),
                  ),
                ],
              );
            },
          );
        },
      );

      // 선택된 자재를 메인 [선택된 자재] 리스트로 즉시 추가
      if (selectedQty != null && selectedQty > 0) {
        widget.onItemScanned(materialCode, displayName, selectedQty);
      }
    } catch (e) {
      // ignore
    } finally {
      if (mounted) {
        _scannerController.start();
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('관리자 QR 스캔',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: MobileScanner(
                  controller: _scannerController,
                  onDetect: _onDetect,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E293B),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('스캔 완료하고 목록 보기',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}