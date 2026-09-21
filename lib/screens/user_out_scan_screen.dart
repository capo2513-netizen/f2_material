import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/user_model.dart';

// ------------------------------------------------------------
// 출고 품목 데이터 모델
// ------------------------------------------------------------
class OutItem {
  final String materialCode;
  final String materialName;
  int quantity;

  OutItem({
    required this.materialCode,
    required this.materialName,
    required this.quantity,
  });
}

// ------------------------------------------------------------
// 사용자 자재 출고 등록 메인 화면
// ------------------------------------------------------------
class UserOutScanScreen extends StatefulWidget {
  final UserModel currentUser;

  const UserOutScanScreen({super.key, required this.currentUser});

  @override
  State<UserOutScanScreen> createState() => _UserOutScanScreenState();
}

class _UserOutScanScreenState extends State<UserOutScanScreen> {
  String _selectedWarehouse = '광주';
  final List<OutItem> _cart = [];
  bool _isSubmitting = false;

  // [성능 개선] 화면 생명주기 동안 단 1회만 유지되는 자재 스트림 (로컬 캐시 활용)
  late final Stream<QuerySnapshot> _materialsStream;

  int get _totalItemCount => _cart.fold(0, (sum, item) => sum + item.quantity);

  @override
  void initState() {
    super.initState();
    _materialsStream =
        FirebaseFirestore.instance.collection('materials').snapshots();
  }

  // 장바구니에 품목 추가/합산 공통 함수
  void _addOrUpdateItem(String code, String name, int qty) {
    setState(() {
      final existingIndex =
          _cart.indexWhere((item) => item.materialCode == code);
      if (existingIndex >= 0) {
        _cart[existingIndex].quantity += qty;
      } else {
        _cart.add(OutItem(
          materialCode: code,
          materialName: name,
          quantity: qty,
        ));
      }
    });
  }

  // 숫자 터치 시 직접 수량 입력 다이얼로그 (100개 등 대량 입력 지원)
  Future<void> _editQuantityDirectly(OutItem item) async {
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
            labelText: '출고 수량',
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
              backgroundColor: const Color(0xFFA61C24),
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
      builder: (ctx) => _CategoryItemSelectModal(
        selectedWarehouse: _selectedWarehouse,
        currentUser: widget.currentUser,
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

  // 2. QR 바코드 스캐너 모달 열기 (스캔 시 메인 _cart로 즉시 통합)
  void _openScannerModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ScannerModalSheet(
        selectedWarehouse: _selectedWarehouse,
        onItemScanned: (code, name, qty) {
          _addOrUpdateItem(code, name, qty);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$name ($qty개) 출고 목록에 추가됨'),
              duration: const Duration(milliseconds: 1500),
            ),
          );
        },
      ),
    );
  }

  // 3. 최종 출고 전송
  Future<void> _submitOut() async {
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('장바구니에 담긴 출고 자재가 없습니다.')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('출고 전송 확인',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(
          '선택 거점: [$_selectedWarehouse 창고]\n'
          '총 ${_cart.length}개 품목 (${_totalItemCount}개)\n\n'
          '출고를 확정 전송하시겠습니까?',
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
              foregroundColor: Colors.white,
            ),
            child: const Text('출고 확정'),
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
      final logCollection = firestore.collection('normal_out_logs');
      final matCollection = firestore.collection('materials');

      for (var item in _cart) {
        final docRef = logCollection.doc();
        batch.set(docRef, {
          'timestamp': FieldValue.serverTimestamp(),
          'type': '출고',
          'outDate': dateStr,
          'outTime': timeStr,
          'warehouse': _selectedWarehouse,
          'team': widget.currentUser.team,
          'userName': widget.currentUser.name,
          'userPhone': widget.currentUser.phone,
          'materialCode': item.materialCode,
          'materialName': item.materialName,
          'quantity': item.quantity,
          'memo': '',
          'syncedToExcel': false,
        });

        String docKey = '${_selectedWarehouse}_${item.materialCode}';
        final matDocRef = matCollection.doc(docKey);
        batch.update(matDocRef, {
          'currentStock': FieldValue.increment(-item.quantity),
        });
      }

      await batch.commit();

      if (!mounted) return;
      setState(() {
        _cart.clear();
        _isSubmitting = false;
      });

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('출고 완료',
              style: TextStyle(fontWeight: FontWeight.bold)),
          content: Text('[$_selectedWarehouse] 출고 등록 및 재고 차감이 완료되었습니다.'),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFA61C24),
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
        SnackBar(content: Text('출고 전송 중 오류가 발생했습니다: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('자재 출고 등록',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFFA61C24),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // 거점 선택
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.white,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '출고 거점 선택',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                Row(
                  children: ['광주', '본사'].map((wh) {
                    final isSelected = _selectedWarehouse == wh;
                    return Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: ChoiceChip(
                        label: Text(wh),
                        selected: isSelected,
                        selectedColor: const Color(0xFFA61C24),
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.bold,
                        ),
                        onSelected: (val) {
                          if (val && _selectedWarehouse != wh) {
                            if (_cart.isNotEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('장바구니가 초기화된 후 거점이 변경됩니다.'),
                                ),
                              );
                              setState(() {
                                _cart.clear();
                                _selectedWarehouse = wh;
                              });
                            } else {
                              setState(() => _selectedWarehouse = wh);
                            }
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

          // 진입 버튼 (목록 선택 / QR 스캔)
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
                      backgroundColor: const Color(0xFFA61C24),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 출고 담기 목록 헤더
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '출고 담기 목록 (${_cart.length}종 / 총 $_totalItemCount개)',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14),
                ),
                if (_cart.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() => _cart.clear()),
                    child: const Text('전체 비우기',
                        style: TextStyle(color: Colors.red, fontSize: 12)),
                  ),
              ],
            ),
          ),

          // 출고 담기 리스트 (목록 선택 + QR 스캔 자재 모두 통합 표시)
          Expanded(
            child: _cart.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.shopping_cart_outlined,
                            size: 54, color: Colors.grey[400]),
                        const SizedBox(height: 12),
                        Text(
                          '[$_selectedWarehouse 창고] 담긴 출고 자재가 없습니다.\n위의 [목록 선택] 또는 [QR 스캔]으로 자재를 담아주세요.',
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(color: Colors.grey[600], fontSize: 13),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _cart.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (ctx, index) {
                      final item = _cart[index];
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
                                    Text(
                                      item.materialName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '코드: ${item.materialCode}',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[600]),
                                    ),
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
                                        setState(() => _cart.removeAt(index));
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
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFFA61C24),
                                        ),
                                      ),
                                    ),
                                  ),

                                  // [+] 버튼
                                  IconButton(
                                    icon: const Icon(Icons.add_circle_outline,
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
                                        setState(() => _cart.removeAt(index)),
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

          // 하단 확정 버튼
          SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: Colors.white,
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed:
                      (_cart.isEmpty || _isSubmitting) ? null : _submitOut,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFA61C24),
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
                          _cart.isEmpty
                              ? '출고할 자재를 담아주세요'
                              : '출고 전송 완료 ($_totalItemCount개 확정)',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------
// 자재 규격 목록 선택 및 관리자 문의 바텀시트
// ------------------------------------------------------------
class _CategoryItemSelectModal extends StatefulWidget {
  final String selectedWarehouse;
  final UserModel currentUser;
  final Stream<QuerySnapshot> materialsStream;
  final Function(List<OutItem>) onItemsAdded;

  const _CategoryItemSelectModal({
    required this.selectedWarehouse,
    required this.currentUser,
    required this.materialsStream,
    required this.onItemsAdded,
  });

  @override
  State<_CategoryItemSelectModal> createState() =>
      _CategoryItemSelectModalState();
}

class _CategoryItemSelectModalState extends State<_CategoryItemSelectModal> {
  String? _selectedCat1;
  String? _selectedCat2;
  final Map<String, int> _quantities = {};

  int _tabIndex = 0; // 0: 규격 선택, 1: 관리자 문의
  final TextEditingController _msgController = TextEditingController();
  bool _isSendingMsg = false;

  String _inquiryCategory = '건의';
  final List<String> _inquiryCategoryList = ['건의', '추가요청', '기타'];

  @override
  void dispose() {
    _msgController.dispose();
    super.dispose();
  }

  // 목록 선택 화면 내에서도 숫자 터치 시 직접 수량 입력 지원
  Future<void> _editQuantityInList(String code, String name) async {
    final currentVal = _quantities[code] ?? 0;
    final textController =
        TextEditingController(text: currentVal > 0 ? currentVal.toString() : '');
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
              backgroundColor: const Color(0xFFA61C24),
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

  Future<void> _sendAdminMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('문의 내용을 입력하세요.')),
      );
      return;
    }

    setState(() => _isSendingMsg = true);
    try {
      final now = DateTime.now();
      final dateStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final timeStr =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

      await FirebaseFirestore.instance.collection('user_requests').add({
        'timestamp': FieldValue.serverTimestamp(),
        'reqDate': dateStr,
        'reqTime': timeStr,
        'warehouse': widget.selectedWarehouse,
        'team': widget.currentUser.team,
        'userName': widget.currentUser.name,
        'userPhone': widget.currentUser.phone,
        'reqCategory': _inquiryCategory,
        'content': text,
        'isConfirmed': false,
      });

      if (!mounted) return;
      setState(() {
        _isSendingMsg = false;
        _msgController.clear();
        _inquiryCategory = '건의';
        _tabIndex = 0;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('관리자 [요청사항] 시트로 문의가 접수되었습니다.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSendingMsg = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('전송 중 오류: $e')),
      );
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
                      '자재 목록 선택 [${widget.selectedWarehouse} 거점]',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 17),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // 탭 바 (자재 선택 vs 관리자 문의)
                Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _tabIndex = 0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: _tabIndex == 0
                                  ? const Color(0xFFA61C24)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '자재 규격 선택',
                              style: TextStyle(
                                color: _tabIndex == 0
                                    ? Colors.white
                                    : Colors.black87,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _tabIndex = 1),
                          child: Container(
                            decoration: BoxDecoration(
                              color: _tabIndex == 1
                                  ? const Color(0xFF2C3E50)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.edit_note,
                                    size: 16,
                                    color: _tabIndex == 1
                                        ? Colors.white
                                        : Colors.black87),
                                const SizedBox(width: 4),
                                Text(
                                  '관리자 문의/요청',
                                  style: TextStyle(
                                    color: _tabIndex == 1
                                        ? Colors.white
                                        : Colors.black87,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                if (_tabIndex == 0) ...[
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _selectedCat1,
                          isExpanded: true,
                          menuMaxHeight: 450,
                          itemHeight: kMinInteractiveDimension,
                          decoration: const InputDecoration(
                            labelText: '대분류 (분류1)',
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(),
                          ),
                          items: cat1List.map((c) {
                            return DropdownMenuItem(
                                value: c,
                                child:
                                    Text(c, overflow: TextOverflow.ellipsis));
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
                            labelText: '소분류 (분류2)',
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(),
                          ),
                          items: cat2List.map((c) {
                            return DropdownMenuItem(
                                value: c,
                                child:
                                    Text(c, overflow: TextOverflow.ellipsis));
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
                              '[$widget.selectedWarehouse] 해당 분류의 등록 자재가 없습니다.\n엑셀에서 [목록업로드]를 실행해 주세요.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.grey[600], fontSize: 13),
                            ),
                          )
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
                                                    fontSize: 14,
                                                    color: Color(0xFF1E293B),
                                                  ),
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
                                                child: Text(
                                                  '현재고: $stock',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    color: stock > 0
                                                        ? const Color(
                                                            0xFF2E7D32)
                                                        : (stock < 0
                                                            ? const Color(
                                                                0xFFD32F2F)
                                                            : Colors.grey[600]),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 3),
                                          Row(
                                            children: [
                                              if (spec.isNotEmpty) ...[
                                                Flexible(
                                                  child: Text(
                                                    spec,
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.black87,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                              ],
                                              Text(
                                                '코드: $code',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                            ],
                                          ),
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
                                                      setLocalQty(() {
                                                        _quantities[code] =
                                                            currentQty - 1;
                                                      });
                                                      setState(() {});
                                                    }
                                                  : null,
                                            ),
                                            // 숫자 터치 시 직접 입력 다이얼로그
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
                                                        ? const Color(
                                                            0xFFA61C24)
                                                        : Colors.black,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            IconButton(
                                              icon: const Icon(
                                                  Icons.add_circle_outline,
                                                  size: 22),
                                              color: const Color(0xFFA61C24),
                                              onPressed: () {
                                                setLocalQty(() {
                                                  _quantities[code] =
                                                      currentQty + 1;
                                                });
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
                ] else ...[
                  // 관리자 문의 탭
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.info_outline,
                                    size: 18, color: Color(0xFF475569)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '작성하신 문의 및 요청사항은 엑셀 [요청사항] 시트로 자동 연동되어 관리자에게 실시간 알림이 전송됩니다.',
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.grey[800]),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            '문의 분류',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: _inquiryCategoryList.map((cat) {
                              final isSelected = _inquiryCategory == cat;
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(cat),
                                  selected: isSelected,
                                  selectedColor: const Color(0xFF2C3E50),
                                  labelStyle: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.black87,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  onSelected: (val) {
                                    if (val) {
                                      setState(() => _inquiryCategory = cat);
                                    }
                                  },
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            '문의/요청 내용',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _msgController,
                            maxLines: 5,
                            decoration: InputDecoration(
                              hintText:
                                  '예: 본사 창고에 RF케이블 2M 수량이 부족합니다. 추가 입고 부탁드립니다.\n(자재코드, 수량, 현장 필요 사유 등)',
                              hintStyle: TextStyle(
                                  color: Colors.grey[400], fontSize: 13),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                SafeArea(
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: _tabIndex == 1
                        ? ElevatedButton.icon(
                            onPressed:
                                _isSendingMsg ? null : _sendAdminMessage,
                            icon: const Icon(Icons.send, size: 18),
                            label: _isSendingMsg
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text(
                                    '관리자에게 문의사항 전송',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2C3E50),
                              foregroundColor: Colors.white,
                            ),
                          )
                        : Builder(
                            builder: (context) {
                              final totalSelectedCount = _quantities.values
                                  .fold(0, (sum, q) => sum + q);
                              return ElevatedButton(
                                onPressed: totalSelectedCount == 0
                                    ? null
                                    : () {
                                        List<OutItem> itemsToAdd = [];
                                        _quantities.forEach((code, qty) {
                                          if (qty > 0) {
                                            final target =
                                                materials.firstWhere(
                                              (m) =>
                                                  (m['materialCode'] ??
                                                      m['F2자재코드'] ??
                                                      m['docId']) ==
                                                  code,
                                              orElse: () => {},
                                            );

                                            final matName =
                                                (target['materialName'] ??
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

                                            itemsToAdd.add(OutItem(
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
                                  backgroundColor: const Color(0xFFA61C24),
                                  foregroundColor: Colors.white,
                                ),
                                child: Text(
                                  totalSelectedCount == 0
                                      ? '수량을 선택하세요'
                                      : '선택한 자재 담기 (총 $totalSelectedCount개 품목)',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
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
// 모달 카메라 스캐너 위젯 (QR 스캔 후 수량 입력 ➡️ 메인 장바구니로 즉시 전송)
// ------------------------------------------------------------
class _ScannerModalSheet extends StatefulWidget {
  final String selectedWarehouse;
  final Function(String code, String name, int qty) onItemScanned;

  const _ScannerModalSheet({
    required this.selectedWarehouse,
    required this.onItemScanned,
  });

  @override
  State<_ScannerModalSheet> createState() => _ScannerModalSheetState();
}

class _ScannerModalSheetState extends State<_ScannerModalSheet> {
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
    _scannerController.stop(); // 팝업 동안 스캔 중지

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

      if (targetWarehouse != widget.selectedWarehouse) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('[$targetWarehouse 창고] QR이 감지되었습니다. 거점을 확인하세요.'),
            backgroundColor: const Color(0xFFA61C24),
            duration: const Duration(seconds: 2),
          ),
        );
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

      // QR 스캔 즉시 수량 조절 다이얼로그 (직접 타이핑 입력창 포함)
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
                    // + / - 버튼 및 직접 입력란 결합
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
                      backgroundColor: const Color(0xFFA61C24),
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

      // 선택된 자재를 메인 출고 담기 목록으로 즉시 추가
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
                const Text('QR/바코드 스캔',
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