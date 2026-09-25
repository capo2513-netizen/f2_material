import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/user_model.dart';
import '../services/material_cache_service.dart';

// ------------------------------------------------------------
// 입출고 품목 데이터 모델
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
// 사용자 자재 입출고 등록 메인 화면 (증분 캐시 동기화 적용)
// ------------------------------------------------------------
class UserOutScanScreen extends StatefulWidget {
  final UserModel currentUser;

  const UserOutScanScreen({super.key, required this.currentUser});

  @override
  State<UserOutScanScreen> createState() => _UserOutScanScreenState();
}

class _UserOutScanScreenState extends State<UserOutScanScreen> {
  String _selectedWarehouse = '광주';
  String _tradeType = '출고'; // '출고' 또는 '입고(반납)'
  final TextEditingController _memoController = TextEditingController();
  final List<OutItem> _cart = [];
  bool _isSubmitting = false;

  // [증분 캐시] 스마트폰 내부 파일에서 관리되는 로컬 자재 리스트
  List<Map<String, dynamic>> _cachedMaterials = [];
  bool _isLoadingMaterials = true;

  int get _totalItemCount => _cart.fold(0, (sum, item) => sum + item.quantity);

  Color get _themeColor => _tradeType == '출고'
      ? const Color(0xFFA61C24)
      : const Color(0xFF1E88E5); // 입고(반납) 시 파란색 계열

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

    // 1) 스마트폰 로컬 파일에서 먼저 즉각 로드 (Firestore 읽기 0회)
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
          decoration: InputDecoration(
            labelText: '$_tradeType 수량',
            suffixText: '개',
            border: const OutlineInputBorder(),
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

  // 1. 목록 선택 모달 열기 (로컬 캐시 리스트 전달)
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
      builder: (ctx) => _CategoryItemSelectModal(
        selectedWarehouse: _selectedWarehouse,
        currentUser: widget.currentUser,
        cachedMaterials: _cachedMaterials,
        tradeType: _tradeType,
        onItemsAdded: (newItems) {
          for (var newItem in newItems) {
            _addOrUpdateItem(
                newItem.materialCode, newItem.materialName, newItem.quantity);
          }
        },
      ),
    );
  }

  // 2. QR 바코드 스캐너 모달 열기 (로컬 캐시 검색)
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
      builder: (ctx) => _ScannerModalSheet(
        selectedWarehouse: _selectedWarehouse,
        tradeType: _tradeType,
        cachedMaterials: _cachedMaterials,
        onItemScanned: (code, name, qty) {
          _addOrUpdateItem(code, name, qty);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$name ($qty개) $_tradeType 담기 목록에 추가됨'),
              duration: const Duration(milliseconds: 1500),
            ),
          );
        },
      ),
    );
  }

  // 3. 최종 입출고 전송
  Future<void> _submitTrade() async {
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('담긴 $_tradeType 자재가 없습니다.')),
      );
      return;
    }

    final memoText = _memoController.text.trim();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$_tradeType 전송 확인',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(
          '선택 구분: [$_tradeType]\n'
          '선택 거점: [$_selectedWarehouse 창고]\n'
          '국소명/메모: ${memoText.isEmpty ? "(없음)" : memoText}\n'
          '총 ${_cart.length}개 품목 (${_totalItemCount}개)\n\n'
          '$_tradeType 내역을 확정 전송하시겠습니까?',
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
            child: Text('$_tradeType 확정'),
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

      // 입고(반납)이면 재고 가산(+), 출고이면 재고 차감(-)
      final int stockMultiplier = _tradeType == '출고' ? -1 : 1;

      for (var item in _cart) {
        final docRef = logCollection.doc();
        batch.set(docRef, {
          'timestamp': FieldValue.serverTimestamp(),
          'type': _tradeType,
          'outDate': dateStr,
          'outTime': timeStr,
          'warehouse': _selectedWarehouse,
          'team': widget.currentUser.team,
          'userName': widget.currentUser.name,
          'userPhone': widget.currentUser.phone,
          'materialCode': item.materialCode,
          'materialName': item.materialName,
          'quantity': item.quantity,
          'memo': memoText,
          'syncedToExcel': false,
        });

        String docKey = '${_selectedWarehouse}_${item.materialCode}';
        final matDocRef = matCollection.doc(docKey);
        batch.update(matDocRef, {
          'currentStock': FieldValue.increment(item.quantity * stockMultiplier),
          'updatedAt': FieldValue.serverTimestamp(), // 증분 동기화용 타임스탬프
        });
      }

      await batch.commit();

      // [핵심] 로컬 파일 캐시에도 변경 품목의 현재고를 즉시 갱신
      for (var cartItem in _cart) {
        await MaterialCacheService.updateLocalStock(
          _cachedMaterials,
          _selectedWarehouse,
          cartItem.materialCode,
          cartItem.quantity * stockMultiplier,
        );
      }

      if (!mounted) return;
      setState(() {
        _cart.clear();
        _memoController.clear();
        _isSubmitting = false;
      });

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('$_tradeType 완료',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          content:
              Text('[$_selectedWarehouse] $_tradeType 등록 및 재고 수량이 정상 반영되었습니다.'),
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
        SnackBar(content: Text('$_tradeType 전송 중 오류가 발생했습니다: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('자재 입출고 등록',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: _themeColor,
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
                // 구분(출고 vs 입고/반납) 및 거점 선택 카드
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  color: Colors.white,
                  child: Column(
                    children: [
                      // 1) 출고 / 입고(반납) 선택 세그먼트 토글
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                if (_tradeType != '출고') {
                                  setState(() => _tradeType = '출고');
                                }
                              },
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 9),
                                decoration: BoxDecoration(
                                  color: _tradeType == '출고'
                                      ? const Color(0xFFA61C24)
                                      : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  '자재 출고 (-)',
                                  style: TextStyle(
                                    color: _tradeType == '출고'
                                        ? Colors.white
                                        : Colors.black87,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                if (_tradeType != '입고(반납)') {
                                  setState(() => _tradeType = '입고(반납)');
                                }
                              },
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 9),
                                decoration: BoxDecoration(
                                  color: _tradeType == '입고(반납)'
                                      ? const Color(0xFF1E88E5)
                                      : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  '자재 입고/반납 (+)',
                                  style: TextStyle(
                                    color: _tradeType == '입고(반납)'
                                        ? Colors.white
                                        : Colors.black87,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // 2) 거점 선택
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '$_tradeType 거점 선택',
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                          Row(
                            children: ['광주', '본사'].map((wh) {
                              final isSelected = _selectedWarehouse == wh;
                              return Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: ChoiceChip(
                                  label: Text(wh),
                                  selected: isSelected,
                                  selectedColor: _themeColor,
                                  labelStyle: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.black87,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  onSelected: (val) {
                                    if (val && _selectedWarehouse != wh) {
                                      if (_cart.isNotEmpty) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content:
                                                Text('장바구니가 초기화된 후 거점이 변경됩니다.'),
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
                    ],
                  ),
                ),
                const Divider(height: 1),

                // 국소명 / 메모 입력란
                Container(
                  color: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: TextField(
                    controller: _memoController,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.edit_note, size: 20),
                      hintText: '국소명/메모 (예: 천남리 기지국 보수, 남은 자재 반납 등)',
                      hintStyle:
                          TextStyle(color: Colors.grey[400], fontSize: 13),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                    ),
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

                // 담기 목록 헤더
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '$_tradeType 담기 목록 (${_cart.length}종 / 총 $_totalItemCount개)',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      if (_cart.isNotEmpty)
                        TextButton(
                          onPressed: () => setState(() => _cart.clear()),
                          child: const Text('전체 비우기',
                              style:
                                  TextStyle(color: Colors.red, fontSize: 12)),
                        ),
                    ],
                  ),
                ),

                // 담기 리스트
                Expanded(
                  child: _cart.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.inventory_2_outlined,
                                  size: 54, color: Colors.grey[400]),
                              const SizedBox(height: 12),
                              Text(
                                '[$_selectedWarehouse 창고] 담긴 $_tradeType 자재가 없습니다.\n위의 [목록 선택] 또는 [QR 스캔]으로 자재를 담아주세요.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Colors.grey[600], fontSize: 13),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _cart.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
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
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
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
                                        IconButton(
                                          icon: const Icon(
                                              Icons.remove_circle_outline,
                                              size: 22),
                                          onPressed: () {
                                            if (item.quantity > 1) {
                                              setState(() => item.quantity--);
                                            } else {
                                              setState(
                                                  () => _cart.removeAt(index));
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
                                              () => _cart.removeAt(index)),
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    color: Colors.white,
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: (_cart.isEmpty || _isSubmitting)
                            ? null
                            : _submitTrade,
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
                                _cart.isEmpty
                                    ? '$_tradeType 할 자재를 담아주세요'
                                    : '$_tradeType 전송 완료 ($_totalItemCount개 확정)',
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
// 자재 규격 목록 선택 및 실시간 검색, 관리자 문의 바텀시트
// ------------------------------------------------------------
class _CategoryItemSelectModal extends StatefulWidget {
  final String selectedWarehouse;
  final UserModel currentUser;
  final List<Map<String, dynamic>> cachedMaterials;
  final String tradeType;
  final Function(List<OutItem>) onItemsAdded;

  const _CategoryItemSelectModal({
    required this.selectedWarehouse,
    required this.currentUser,
    required this.cachedMaterials,
    required this.tradeType,
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

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  int _tabIndex = 0; // 0: 규격 선택, 1: 관리자 문의
  final TextEditingController _msgController = TextEditingController();
  bool _isSendingMsg = false;

  String _inquiryCategory = '건의';
  final List<String> _inquiryCategoryList = ['건의', '추가요청', '기타'];

  @override
  void dispose() {
    _searchController.dispose();
    _msgController.dispose();
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
          decoration: InputDecoration(
            labelText: '담을 수량',
            suffixText: '개',
            border: const OutlineInputBorder(),
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

            // 탭 바
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
                          '자재 규격 선택 / 검색',
                          style: TextStyle(
                            color:
                                _tabIndex == 0 ? Colors.white : Colors.black87,
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
                          labelText: '대분류 (분류1)',
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
                          labelText: '소분류 (분류2)',
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
                              : '[$widget.selectedWarehouse] 해당 분류의 등록 자재가 없습니다.\n엑셀에서 [목록업로드]를 실행해 주세요.',
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(color: Colors.grey[600], fontSize: 13),
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
                          final name = (mat['materialName'] ?? mat['품명'] ?? '')
                              .toString();
                          final spec =
                              (mat['spec'] ?? mat['규격'] ?? '').toString();

                          final rawStock =
                              mat['currentStock'] ?? mat['현재고'] ?? 0;
                          final int stock = rawStock is num
                              ? rawStock.toInt()
                              : (int.tryParse(rawStock.toString()) ?? 0);

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
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
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: stock > 0
                                                  ? const Color(0xFFE8F5E9)
                                                  : (stock < 0
                                                      ? const Color(0xFFFFEBEE)
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
                                                    ? const Color(0xFF2E7D32)
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
                                                  fontWeight: FontWeight.w500,
                                                ),
                                                overflow: TextOverflow.ellipsis,
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
                                                  setLocalQty(() {
                                                    _quantities[code] =
                                                        currentQty - 1;
                                                  });
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
                                color:
                                    isSelected ? Colors.white : Colors.black87,
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
                          hintStyle:
                              TextStyle(color: Colors.grey[400], fontSize: 13),
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
                        onPressed: _isSendingMsg ? null : _sendAdminMessage,
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
                          final totalSelectedCount =
                              _quantities.values.fold(0, (sum, q) => sum + q);
                          return ElevatedButton(
                            onPressed: totalSelectedCount == 0
                                ? null
                                : () {
                                    List<OutItem> itemsToAdd = [];
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
      ),
    );
  }
}

// ------------------------------------------------------------
// 모달 카메라 스캐너 위젯
// ------------------------------------------------------------
class _ScannerModalSheet extends StatefulWidget {
  final String selectedWarehouse;
  final String tradeType;
  final List<Map<String, dynamic>> cachedMaterials;
  final Function(String code, String name, int qty) onItemScanned;

  const _ScannerModalSheet({
    required this.selectedWarehouse,
    required this.tradeType,
    required this.cachedMaterials,
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
                title: Text('${widget.tradeType} 자재 수량 지정',
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
                      backgroundColor: widget.tradeType == '출고'
                          ? const Color(0xFFA61C24)
                          : const Color(0xFF1E88E5),
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
                Text('${widget.tradeType} QR/바코드 스캔',
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
            'QR코드를 사각형 영역 중앙에 비춰주세요.\n스캔 후 수량을 입력하면 즉시 담기 목록으로 이동합니다.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
        ],
      ),
    );
  }
}
