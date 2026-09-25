import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/user_model.dart';
import '../services/material_cache_service.dart';

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
// 관리자 입·출고 종합관리 메인 화면 (증분 캐시 동기화 적용)
// ------------------------------------------------------------
class AdvancedInventoryScreen extends StatefulWidget {
  final UserModel currentUser;

  const AdvancedInventoryScreen({super.key, required this.currentUser});

  @override
  State<AdvancedInventoryScreen> createState() =>
      _AdvancedInventoryScreenState();
}

class _AdvancedInventoryScreenState extends State<AdvancedInventoryScreen> {
  String _mode = 'OUT'; // 'OUT' (출고 - 차감) / 'IN' (입고 - 가산)
  String _selectedWarehouse = '광주';

  final List<AdminInventoryItem> _itemList = [];
  final TextEditingController _memoController = TextEditingController();
  bool _isSubmitting = false;

  // [증분 캐시] 스마트폰 내부 파일에서 관리되는 로컬 자재 리스트
  List<Map<String, dynamic>> _cachedMaterials = [];
  bool _isLoadingMaterials = true;

  int get _totalQuantity =>
      _itemList.fold(0, (sum, item) => sum + item.quantity);

  Color get _themeColor =>
      _mode == 'OUT' ? const Color(0xFFA61C24) : Colors.blue[800]!;

  @override
  void initState() {
    super.initState();
    _initMaterialCache();
  }

  @override
  void dispose() {
    _memoController.dispose();
    super.dispose();
  }

  // 1단계: 로컬 캐시 즉시 로드(0초/읽기0회) ➡️ 2단계: 변경분만 증분 동기화
  Future<void> _initMaterialCache() async {
    setState(() => _isLoadingMaterials = true);

    // 1) 기기 내부 파일에서 즉각 로드 (Firestore 읽기 0회)
    final localData = await MaterialCacheService.loadLocalMaterials();
    if (localData.isNotEmpty && mounted) {
      setState(() {
        _cachedMaterials = localData;
        _isLoadingMaterials = false;
      });
    }

    // 2) 백그라운드에서 변경된 문서만 증분 동기화 (읽기 극소량)
    try {
      final updatedList = await MaterialCacheService.syncIncrementalMaterials();
      if (mounted) {
        setState(() {
          _cachedMaterials = updatedList;
          _isLoadingMaterials = false;
        });
      }
    } catch (e) {
      if (mounted && _cachedMaterials.isEmpty) {
        setState(() => _isLoadingMaterials = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('자재 동기화 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }

  // 강제 전체 새로고침
  Future<void> _forceRefresh() async {
    setState(() => _isLoadingMaterials = true);
    try {
      final list = await MaterialCacheService.forceFullRefresh();
      if (mounted) {
        setState(() {
          _cachedMaterials = list;
          _isLoadingMaterials = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('전체 자재 목록이 새로고침되었습니다.')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingMaterials = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('새로고침 실패: $e')),
        );
      }
    }
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

  // 메인 리스트에서 숫자 터치 시 직접 수량 입력 다이얼로그
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
              backgroundColor: _themeColor,
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
    if (_isLoadingMaterials && _cachedMaterials.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('자재 정보를 불러오는 중입니다. 잠시만 기다려주세요.')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AdminCategorySelectModal(
        selectedWarehouse: _selectedWarehouse,
        mode: _mode,
        cachedMaterials: _cachedMaterials,
        onItemsAdded: (newItems) {
          for (var newItem in newItems) {
            _addOrUpdateItem(
                newItem.materialCode, newItem.materialName, newItem.quantity);
          }
        },
      ),
    );
  }

  // 2. QR 바코드 스캐너 모달 열기
  void _openScannerModal() {
    if (_isLoadingMaterials && _cachedMaterials.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('자재 정보를 불러오는 중입니다. 잠시만 기다려주세요.')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AdminScannerModal(
        selectedWarehouse: _selectedWarehouse,
        mode: _mode,
        cachedMaterials: _cachedMaterials,
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

  // 3. 최종 처리 전송
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
              backgroundColor: _themeColor,
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

      final deltaMultiplier = isOut ? -1 : 1;

      for (var item in _itemList) {
        // 1. 로그 기록
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
          'memo': memo,
          'syncedToExcel': false,
        });

        // 2. 실시간 재고 가감 처리 + 증분 동기화용 타임스탬프 업데이트
        final deltaStock = item.quantity * deltaMultiplier;
        final matDocRef =
            matCollection.doc('${_selectedWarehouse}_${item.materialCode}');
        batch.update(matDocRef, {
          'currentStock': FieldValue.increment(deltaStock),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();

      // [핵심] 로컬 파일 캐시에도 변경 품목의 현재고를 즉시 갱신
      for (var targetItem in _itemList) {
        await MaterialCacheService.updateLocalStock(
          _cachedMaterials,
          _selectedWarehouse,
          targetItem.materialCode,
          targetItem.quantity * deltaMultiplier,
        );
      }

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
                backgroundColor: _themeColor,
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
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '자재 목록 동기화',
            onPressed: _isLoadingMaterials ? null : _forceRefresh,
          ),
        ],
      ),
      body: (_isLoadingMaterials && _cachedMaterials.isEmpty)
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('자재 목록을 불러오는 중입니다...',
                      style: TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
            )
          : Column(
              children: [
                // 작업 모드 선택 (출고 vs 입고)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: Colors.white,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('관리 거점 선택',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.bold)),
                      Row(
                        children: ['광주', '본사'].map((wh) {
                          final isSel = _selectedWarehouse == wh;
                          return Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: ChoiceChip(
                              label: Text(wh),
                              selected: isSel,
                              selectedColor: _themeColor,
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
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
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
                            backgroundColor: _themeColor,
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
                              style:
                                  TextStyle(color: Colors.red, fontSize: 12)),
                        ),
                    ],
                  ),
                ),

                // 선택된 품목 리스트
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
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
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
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
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
                                        InkWell(
                                          onTap: () =>
                                              _editQuantityDirectly(item),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF1F5F9),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                  color:
                                                      const Color(0xFFCBD5E1)),
                                            ),
                                            child: Text(
                                              '${item.quantity}',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: _themeColor,
                                              ),
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                              Icons.add_circle_outline,
                                              size: 22),
                                          onPressed: () {
                                            setState(() => item.quantity++);
                                          },
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline,
                                              color: Colors.grey, size: 20),
                                          onPressed: () => setState(
                                              () => _itemList.removeAt(idx)),
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
                    boxShadow: [
                      BoxShadow(color: Colors.black12, blurRadius: 4)
                    ],
                  ),
                  child: SafeArea(
                    child: Column(
                      children: [
                        TextField(
                          controller: _memoController,
                          decoration: InputDecoration(
                            hintText: isOut
                                ? '출고 비고 입력 (선택사항, 예: 국소명, OOO팀 현장수령 등)'
                                : '입고 비고 입력 (선택사항, 예: 국소 철거 반납, 신규 구매 등)',
                            hintStyle: TextStyle(
                                fontSize: 13, color: Colors.grey[400]),
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
                              backgroundColor: _themeColor,
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
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16),
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
// 관리자 규격 목록 선택 및 실시간 검색 바텀시트
// ------------------------------------------------------------
class _AdminCategorySelectModal extends StatefulWidget {
  final String selectedWarehouse;
  final String mode;
  final List<Map<String, dynamic>> cachedMaterials;
  final Function(List<AdminInventoryItem>) onItemsAdded;

  const _AdminCategorySelectModal({
    required this.selectedWarehouse,
    required this.mode,
    required this.cachedMaterials,
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

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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
    final materials = widget.cachedMaterials.where((m) {
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
      final code = (m['materialCode'] ?? m['F2자재코드'] ?? m['docId'] ?? '')
          .toString()
          .toLowerCase();
      final name =
          (m['materialName'] ?? m['품명'] ?? '').toString().toLowerCase();
      final spec = (m['spec'] ?? m['규격'] ?? '').toString().toLowerCase();

      if (_searchQuery.isNotEmpty) {
        return code.contains(_searchQuery) ||
            name.contains(_searchQuery) ||
            spec.contains(_searchQuery);
      }

      final c1 = (m['category1'] ?? m['분류1'] ?? '').toString().trim();
      final c2 = (m['category2'] ?? m['분류2'] ?? '').toString().trim();
      if (cat2List.isNotEmpty) {
        return c1 == _selectedCat1 && c2 == _selectedCat2;
      }
      return c1 == _selectedCat1;
    }).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Padding(
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

            // 실시간 검색창
            TextField(
              controller: _searchController,
              onChanged: (val) {
                setState(() {
                  _searchQuery = val.trim().toLowerCase();
                });
              },
              decoration: InputDecoration(
                hintText: '자재명, 규격, 자재코드 실시간 검색...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                filled: true,
                fillColor: const Color(0xFFF1F5F9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 10),

            if (_searchQuery.isEmpty)
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
            if (_searchQuery.isEmpty) const SizedBox(height: 10),

            Expanded(
              child: filteredMaterials.isEmpty
                  ? Center(
                      child: Text(
                        _searchQuery.isNotEmpty
                            ? '검색 결과가 없습니다.'
                            : '[$widget.selectedWarehouse] 자재가 존재하지 않습니다.',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: filteredMaterials.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, idx) {
                        final mat = filteredMaterials[idx];
                        final code = (mat['materialCode'] ??
                                mat['F2자재코드'] ??
                                mat['docId'])
                            .toString();
                        final name =
                            (mat['materialName'] ?? mat['품명'] ?? '').toString();
                        final spec =
                            (mat['spec'] ?? mat['규격'] ?? '').toString();

                        final rawStock = mat['currentStock'] ?? mat['현재고'] ?? 0;
                        final int stock = rawStock is num
                            ? rawStock.toInt()
                            : (int.tryParse(rawStock.toString()) ?? 0);

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: stock > 0
                                                ? const Color(0xFFE8F5E9)
                                                : (stock < 0
                                                    ? const Color(0xFFFFEBEE)
                                                    : const Color(0xFFF1F5F9)),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text('현재고: $stock',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: stock > 0
                                                      ? const Color(0xFF2E7D32)
                                                      : (stock < 0
                                                          ? const Color(
                                                              0xFFD32F2F)
                                                          : Colors.grey[600]))),
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
                                  final currentQty = _quantities[code] ?? 0;
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
                                      InkWell(
                                        onTap: () async {
                                          await _editQuantityInList(code,
                                              name.isNotEmpty ? name : spec);
                                          setLocalQty(() {});
                                        },
                                        child: Container(
                                          alignment: Alignment.center,
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 4),
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
                                          setLocalQty(() => _quantities[code] =
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
                                  final spec =
                                      (target['spec'] ?? target['규격'] ?? '')
                                          .toString();

                                  String displayName = matName;
                                  if (spec.isNotEmpty && spec != matName) {
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
      ),
    );
  }
}

// ------------------------------------------------------------
// 관리자 QR 스캐너 바텀시트
// ------------------------------------------------------------
class _AdminScannerModal extends StatefulWidget {
  final String selectedWarehouse;
  final String mode;
  final List<Map<String, dynamic>> cachedMaterials;
  final Function(String code, String name, int qty) onItemScanned;

  const _AdminScannerModal({
    required this.selectedWarehouse,
    required this.mode,
    required this.cachedMaterials,
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
    _scannerController.stop();

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

      Map<String, dynamic> target = widget.cachedMaterials.firstWhere(
        (m) {
          final wh = (m['warehouse'] ?? '').toString().trim();
          final code = (m['materialCode'] ?? m['F2자재코드'] ?? m['docId'] ?? '')
              .toString()
              .trim();
          return wh == targetWarehouse && code == materialCode;
        },
        orElse: () => {},
      );

      if (target.isEmpty) {
        target = widget.cachedMaterials.firstWhere(
          (m) {
            final wh = (m['warehouse'] ?? '').toString().trim();
            final code = (m['materialCode'] ?? m['F2자재코드'] ?? m['docId'] ?? '')
                .toString()
                .trim();
            return wh == '광주' && code == materialCode;
          },
          orElse: () => {},
        );
      }

      if (target.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('등록되지 않은 자재코드입니다: $materialCode')),
        );
        await Future.delayed(const Duration(seconds: 1));
        _scannerController.start();
        setState(() => _isProcessing = false);
        return;
      }

      final matName = (target['materialName'] ?? target['품명'] ?? '').toString();
      final spec = (target['spec'] ?? target['규격'] ?? '').toString();

      String displayName = matName;
      if (spec.isNotEmpty && spec != matName) {
        displayName = matName.isNotEmpty ? '$matName ($spec)' : spec;
      }
      if (displayName.isEmpty) displayName = materialCode;

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
                title: Text('${widget.mode == 'OUT' ? '출고' : '입고'} 자재 수량 지정',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
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
                        style:
                            TextStyle(color: Colors.grey[600], fontSize: 12)),
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

      if (selectedQty != null && selectedQty > 0) {
        widget.onItemScanned(materialCode, displayName, selectedQty);
        if (mounted) {
          Navigator.pop(context);
        }
      } else {
        _scannerController.start();
        setState(() => _isProcessing = false);
      }
    } catch (e) {
      if (mounted) {
        _scannerController.start();
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.65,
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
                Text('관리자 ${widget.mode == 'OUT' ? '출고' : '입고'} QR 스캔',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 17)),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: AspectRatio(
              aspectRatio: 1.2,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: MobileScanner(
                  controller: _scannerController,
                  onDetect: _onDetect,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'QR코드를 사각형 영역 중앙에 비춰주세요.\n스캔 후 수량을 입력하면 즉시 처리 목록으로 이동합니다.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
        ],
      ),
    );
  }
}
