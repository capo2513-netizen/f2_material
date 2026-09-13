import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

class AdvancedItem {
  final String materialCode;
  final String materialName;
  int quantity;
  final String actionType; // 'IN' (입고) 또는 'OUT' (출고)
  final String condition; // '신품', '구품', '불량'

  AdvancedItem({
    required this.materialCode,
    required this.materialName,
    required this.quantity,
    required this.actionType,
    required this.condition,
  });
}

class AdvancedInventoryScreen extends StatefulWidget {
  final UserModel currentUser;
  const AdvancedInventoryScreen({super.key, required this.currentUser});

  @override
  State<AdvancedInventoryScreen> createState() =>
      _AdvancedInventoryScreenState();
}

class _AdvancedInventoryScreenState extends State<AdvancedInventoryScreen> {
  final MobileScannerController _cameraController = MobileScannerController();
  final List<AdvancedItem> _cart = [];

  // 기본 작업 모드: 출고(OUT) / 입고(IN)
  String _currentAction = 'OUT';
  // 기본 상태: 신품
  String _currentCondition = '신품';

  bool _isProcessing = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_isProcessing || _isSubmitting) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    final rawValue = barcode.rawValue!.trim();
    if (rawValue.isEmpty) return;

    _isProcessing = true;

    // #SN 같은 태그가 있다면 제거
    String cleanCode = rawValue.split('#')[0].trim();

    String fetchedName = '조회 중...';
    try {
      final doc = await FirebaseFirestore.instance
          .collection('materials')
          .doc(cleanCode)
          .get();

      if (doc.exists && doc.data() != null) {
        fetchedName = doc.data()!['materialName'] ?? '품명 없음';
      } else {
        fetchedName = '미등록 자재코드 ($cleanCode)';
      }
    } catch (e) {
      fetchedName = '조회 실패 ($cleanCode)';
    }

    setState(() {
      // 동일한 자재코드 + 동일한 구분 + 동일한 상태가 있으면 수량만 증가
      final index = _cart.indexWhere(
        (item) =>
            item.materialCode == cleanCode &&
            item.actionType == _currentAction &&
            item.condition == _currentCondition,
      );

      if (index != -1) {
        _cart[index].quantity += 1;
      } else {
        _cart.add(
          AdvancedItem(
            materialCode: cleanCode,
            materialName: fetchedName,
            quantity: 1,
            actionType: _currentAction,
            condition: _currentCondition,
          ),
        );
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '[$_currentCondition ${_currentAction == 'IN' ? '입고' : '출고'}] $fetchedName 1개 추가',
        ),
        duration: const Duration(milliseconds: 700),
      ),
    );

    await Future.delayed(const Duration(milliseconds: 900));
    _isProcessing = false;
  }

  void _submit() async {
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('스캔된 내역이 없습니다.')));
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          '정밀 입출고 전송 확인',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text('총 ${_cart.length}건의 입출고 내역을 동기화 서버로 전송하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF39800),
            ),
            child: const Text('전송', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isSubmitting = true);

    try {
      final batch = FirebaseFirestore.instance.batch();
      final collection = FirebaseFirestore.instance.collection(
        'advanced_inventory_logs',
      );
      final now = DateTime.now();

      for (var item in _cart) {
        final docRef = collection.doc();
        batch.set(docRef, {
          'timestamp': FieldValue.serverTimestamp(),
          'displayTime': now.toIso8601String(),
          'actionType': item.actionType, // IN, OUT
          'condition': item.condition, // 신품, 구품, 불량
          'materialCode': item.materialCode,
          'materialName': item.materialName,
          'quantity': item.quantity,
          'team': widget.currentUser.team,
          'userName': widget.currentUser.name,
          'userPhone': widget.currentUser.phone,
          'syncedToExcel': false,
        });
      }

      await batch.commit();

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('전송 완료'),
          content: const Text(
            '정밀 입출고 내역이 파이어베이스에 저장되었습니다.\n엑셀 동기화 시 재고현황에 즉시 반영됩니다.',
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF39800),
              ),
              child: const Text('확인', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('전송 실패: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '정밀 입·출고 관리',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFFF39800),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => _cameraController.toggleTorch(),
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. 입고 / 출고 전환 탭바
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                    label: const Text(
                      '출고 모드',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: () {
                      setState(() {
                        _currentAction = 'OUT';
                        _currentCondition = '신품';
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _currentAction == 'OUT'
                          ? const Color(0xFFA61C24)
                          : Colors.grey[200],
                      foregroundColor: _currentAction == 'OUT'
                          ? Colors.white
                          : Colors.black87,
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.arrow_downward_rounded, size: 18),
                    label: const Text(
                      '입고 모드',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: () {
                      setState(() {
                        _currentAction = 'IN';
                        _currentCondition = '신품';
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _currentAction == 'IN'
                          ? const Color(0xFF2E7D32)
                          : Colors.grey[200],
                      foregroundColor: _currentAction == 'IN'
                          ? Colors.white
                          : Colors.black87,
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 2. 세부 상태 선택 칩 (신품 / 구품 / 불량)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
            child: Row(
              children: [
                const Text(
                  '상태 구분: ',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('신품'),
                  selected: _currentCondition == '신품',
                  selectedColor: const Color(0xFFE8F5E9),
                  labelStyle: TextStyle(
                    color: _currentCondition == '신품'
                        ? const Color(0xFF2E7D32)
                        : Colors.black87,
                    fontWeight: FontWeight.bold,
                  ),
                  onSelected: (val) {
                    if (val) setState(() => _currentCondition = '신품');
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('구품'),
                  selected: _currentCondition == '구품',
                  selectedColor: const Color(0xFFFFF3E0),
                  labelStyle: TextStyle(
                    color: _currentCondition == '구품'
                        ? const Color(0xFFEF6C00)
                        : Colors.black87,
                    fontWeight: FontWeight.bold,
                  ),
                  onSelected: (val) {
                    if (val) setState(() => _currentCondition = '구품');
                  },
                ),
                // 입고 모드일 때는 불량 입고 제외 (출고일 때만 불량 선택 가능)
                if (_currentAction == 'OUT') ...[
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('불량'),
                    selected: _currentCondition == '불량',
                    selectedColor: const Color(0xFFFFEBEE),
                    labelStyle: TextStyle(
                      color: _currentCondition == '불량'
                          ? Colors.red
                          : Colors.black87,
                      fontWeight: FontWeight.bold,
                    ),
                    onSelected: (val) {
                      if (val) setState(() => _currentCondition = '불량');
                    },
                  ),
                ],
              ],
            ),
          ),

          // 3. 카메라 프리뷰 (30% 높이)
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.30,
            child: Stack(
              alignment: Alignment.center,
              children: [
                MobileScanner(
                  controller: _cameraController,
                  onDetect: _onDetect,
                ),
                Container(
                  width: 220,
                  height: 130,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                Positioned(
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      '현재: [$_currentCondition ${_currentAction == 'IN' ? '입고' : '출고'}] 스캔 중',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 4. 담긴 목록 리스트
          Expanded(
            child: Container(
              color: const Color(0xFFF5F6F8),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '작업 목록 (${_cart.length}건)',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        if (_cart.isNotEmpty)
                          TextButton(
                            onPressed: () => setState(() => _cart.clear()),
                            child: const Text(
                              '전체 비우기',
                              style: TextStyle(color: Colors.red, fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _cart.isEmpty
                        ? const Center(
                            child: Text(
                              '스캔된 항목이 없습니다.',
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _cart.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (ctx, index) {
                              final item = _cart[index];
                              final isOut = item.actionType == 'OUT';
                              return Card(
                                elevation: 1,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isOut
                                              ? const Color(0xFFFFEBEE)
                                              : const Color(0xFFE8F5E9),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Text(
                                          '${item.condition} ${isOut ? '출고' : '입고'}',
                                          style: TextStyle(
                                            color: isOut
                                                ? Colors.red[800]
                                                : Colors.green[800],
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.materialName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            Text(
                                              '코드: ${item.materialCode}',
                                              style: const TextStyle(
                                                color: Colors.grey,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.remove_circle_outline,
                                          size: 18,
                                        ),
                                        onPressed: () {
                                          if (item.quantity > 1) {
                                            setState(() => item.quantity -= 1);
                                          } else {
                                            setState(
                                              () => _cart.removeAt(index),
                                            );
                                          }
                                        },
                                      ),
                                      Text(
                                        '${item.quantity}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.add_circle_outline,
                                          size: 18,
                                        ),
                                        onPressed: () =>
                                            setState(() => item.quantity += 1),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),

                  // 5. 전송 버튼
                  Container(
                    padding: const EdgeInsets.all(16),
                    color: Colors.white,
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _isSubmitting || _cart.isEmpty
                            ? null
                            : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF39800),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: _isSubmitting
                            ? const CircularProgressIndicator(
                                color: Colors.white,
                              )
                            : Text(
                                '정밀 데이터 전송 완료 (${_cart.length}건)',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
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
