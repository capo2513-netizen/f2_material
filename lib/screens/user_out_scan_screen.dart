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
  final bool requiresSerial;
  List<String> sktSerials;
  bool isConfirmed;

  OutItem({
    required this.materialCode,
    required this.materialName,
    required this.quantity,
    required this.requiresSerial,
    List<String>? sktSerials,
    this.isConfirmed = false,
  }) : sktSerials = sktSerials ?? [];
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
  String _selectedWarehouse = '광주'; // 기본 광주
  final List<OutItem> _cart = [];
  bool _isSubmitting = false;

  // 장바구니 총 품목 수
  int get _totalItemCount => _cart.fold(0, (sum, item) => sum + item.quantity);

  // 품목 목록 모달 열기 (대분류/소분류/규격 선택 및 메시지 전송)
  void _openItemListModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CategoryItemSelectModal(
        selectedWarehouse: _selectedWarehouse,
        currentUser: widget.currentUser,
        onItemsAdded: (newItems) {
          setState(() {
            for (var newItem in newItems) {
              final existingIndex = _cart.indexWhere(
                (item) => item.materialCode == newItem.materialCode,
              );
              if (existingIndex >= 0) {
                _cart[existingIndex].quantity += newItem.quantity;
              } else {
                _cart.add(newItem);
              }
            }
          });
        },
      ),
    );
  }

  // QR 바코드 스캐너 모달 열기
  void _openScannerModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ScannerModalSheet(
        selectedWarehouse: _selectedWarehouse,
        existingSerials: _cart.expand((item) => item.sktSerials).toList(),
        onItemsScanned: (scannedItems) {
          setState(() {
            for (var scanned in scannedItems) {
              final existingIndex = _cart.indexWhere(
                (item) => item.materialCode == scanned.materialCode,
              );
              if (existingIndex >= 0) {
                if (scanned.requiresSerial) {
                  _cart[existingIndex].sktSerials.addAll(scanned.sktSerials);
                  _cart[existingIndex].quantity =
                      _cart[existingIndex].sktSerials.length;
                } else {
                  _cart[existingIndex].quantity += scanned.quantity;
                }
              } else {
                _cart.add(scanned);
              }
            }
          });
        },
      ),
    );
  }

  // 출고 최종 전송 (Firebase 이력 등록 + materials currentStock 즉시 차감)
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
        if (item.requiresSerial) {
          // 시리얼 자재
          for (var serial in item.sktSerials) {
            final docRef = logCollection.doc();
            batch.set(docRef, {
              'timestamp': FieldValue.serverTimestamp(),
              'outDate': dateStr,
              'outTime': timeStr,
              'warehouse': _selectedWarehouse,
              'team': widget.currentUser.team,
              'userName': widget.currentUser.name,
              'userPhone': widget.currentUser.phone,
              'materialCode': item.materialCode,
              'materialName': item.materialName,
              'quantity': 1,
              'sktSerial': serial,
              'syncedToExcel': false,
            });
          }

          // 재고 실시간 차감
          final matDocRef = matCollection.doc(item.materialCode);
          batch.update(matDocRef, {
            'currentStock': FieldValue.increment(-item.sktSerials.length),
          });
        } else {
          // 일반 자재
          final docRef = logCollection.doc();
          batch.set(docRef, {
            'timestamp': FieldValue.serverTimestamp(),
            'outDate': dateStr,
            'outTime': timeStr,
            'warehouse': _selectedWarehouse,
            'team': widget.currentUser.team,
            'userName': widget.currentUser.name,
            'userPhone': widget.currentUser.phone,
            'materialCode': item.materialCode,
            'materialName': item.materialName,
            'quantity': item.quantity,
            'sktSerial': '',
            'syncedToExcel': false,
          });

          // 재고 실시간 차감
          final matDocRef = matCollection.doc(item.materialCode);
          batch.update(matDocRef, {
            'currentStock': FieldValue.increment(-item.quantity),
          });
        }
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
          content: const Text('정상적으로 출고 등록 및 재고 차감이 완료되었습니다.'),
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
          // 상단: 거점 선택 (광주 / 본사)
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

          // 진입 버튼 영역 (목록 선택 / 바코드 스캔)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _openItemListModal,
                    icon: const Icon(Icons.list_alt, size: 20),
                    label: const Text('목록 선택',
                        style: TextStyle(fontWeight: FontWeight.bold)),
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

          // 출고 장바구니 리스트 헤더
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

          // 장바구니 목록
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
                          '[$_selectedWarehouse 창고] 담긴 출고 자재가 없습니다.\n위의 [목록 선택] 또는 [QR 스캔]을 눌러 추가하세요.',
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
                                    if (item.requiresSerial) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        'S/N: ${item.sktSerials.join(', ')}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFFA61C24),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              Row(
                                children: [
                                  if (!item.requiresSerial) ...[
                                    IconButton(
                                      icon: const Icon(
                                          Icons.remove_circle_outline,
                                          size: 20),
                                      onPressed: () {
                                        setState(() {
                                          if (item.quantity > 1) {
                                            item.quantity--;
                                          } else {
                                            _cart.removeAt(index);
                                          }
                                        });
                                      },
                                    ),
                                    Text(
                                      '${item.quantity}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.add_circle_outline,
                                          size: 20),
                                      onPressed: () {
                                        setState(() => item.quantity++);
                                      },
                                    ),
                                  ] else ...[
                                    Text(
                                      '${item.quantity}대',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: Color(0xFFA61C24),
                                      ),
                                    ),
                                  ],
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

          // 하단: 출고 전송 완료 버튼
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
// 대분류/소분류/규격 선택 및 관리자 메모 바텀시트 모달
// ------------------------------------------------------------
class _CategoryItemSelectModal extends StatefulWidget {
  final String selectedWarehouse;
  final UserModel currentUser;
  final Function(List<OutItem>) onItemsAdded;

  const _CategoryItemSelectModal({
    required this.selectedWarehouse,
    required this.currentUser,
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

  bool _isMessageMode = false;
  final TextEditingController _msgController = TextEditingController();
  bool _isSendingMsg = false;

  @override
  void dispose() {
    _msgController.dispose();
    super.dispose();
  }

  // 관리자에게 요청/건의 메시지 전송 (Firebase user_requests에 등록)
  Future<void> _sendAdminMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('메시지 내용을 입력하세요.')),
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
        'date': dateStr,
        'time': timeStr,
        'warehouse': widget.selectedWarehouse,
        'userName': widget.currentUser.name,
        'team': widget.currentUser.team,
        'phone': widget.currentUser.phone,
        'category1': _selectedCat1 ?? '',
        'category2': _selectedCat2 ?? '',
        'message': text,
        'status': '미확인',
      });

      if (!mounted) return;
      setState(() {
        _isSendingMsg = false;
        _msgController.clear();
        _isMessageMode = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('관리자에게 메시지가 성공적으로 전송되었습니다.')),
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
    final totalSelectedCount = _quantities.values.fold(0, (sum, q) => sum + q);

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('materials').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('등록된 자재 목록이 없습니다.'));
          }

          // 해당 거점 자재 필터링
          final materials = snapshot.data!.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            data['docId'] = doc.id;
            return data;
          }).where((m) {
            final wh = (m['warehouse'] ?? '').toString();
            return wh.isEmpty || wh == widget.selectedWarehouse;
          }).toList();

          // 대분류 목록 추출
          final cat1Set = <String>{};
          for (var m in materials) {
            final c1 = (m['category1'] ?? m['분류1'] ?? '').toString().trim();
            if (c1.isNotEmpty) cat1Set.add(c1);
          }
          final cat1List = cat1Set.toList()..sort();

          if (_selectedCat1 == null && cat1List.isNotEmpty) {
            _selectedCat1 = cat1List.first;
          }

          // 소분류 목록 추출
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

          // 선택된 대/소분류에 속한 자재 리스트
          final filteredMaterials = materials.where((m) {
            final c1 = (m['category1'] ?? m['분류1'] ?? '').toString().trim();
            final c2 = (m['category2'] ?? m['분류2'] ?? '').toString().trim();
            return c1 == _selectedCat1 && c2 == _selectedCat2;
          }).toList();

          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 모달 상단 타이틀 & 닫기
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '자재 규격 선택 (${widget.selectedWarehouse})',
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

                // 대분류 / 소분류 선택 드롭다운
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedCat1,
                        isExpanded: true,
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
                const SizedBox(height: 10),

                // 관리자 메시지 모드 토글 바
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _isMessageMode ? '관리자 건의/요청 작성 모드' : '규격별 수량 선택',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      TextButton.icon(
                        icon: Icon(
                            _isMessageMode ? Icons.list : Icons.edit_note,
                            size: 18),
                        label: Text(_isMessageMode ? '목록으로' : '관리자에게 건의'),
                        onPressed: () {
                          setState(() => _isMessageMode = !_isMessageMode);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // 중앙 콘텐츠 (규격 목록 vs 메시지 입력창)
                Expanded(
                  child: _isMessageMode
                      ? SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '자재 요청 및 관리자 건의사항',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              const SizedBox(height: 6),
                              TextField(
                                controller: _msgController,
                                maxLines: 5,
                                decoration: InputDecoration(
                                  hintText:
                                      '필요한 자재 품명, 규격, 요청 수량 및 전달사항을 적어주시면 엑셀 [요청사항] 시트로 자동 전달됩니다.',
                                  hintStyle: TextStyle(
                                      color: Colors.grey[400], fontSize: 13),
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ],
                          ),
                        )
                      : filteredMaterials.isEmpty
                          ? const Center(child: Text('해당 분류에 속한 자재가 없습니다.'))
                          : ListView.separated(
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
                                final currentQty = _quantities[code] ?? 0;

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
                                            // 1행: 품명(D열) + 재고 뱃지
                                            Row(
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    name.isNotEmpty
                                                        ? name
                                                        : spec,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 14,
                                                      color: Color(0xFF1E293B),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 6,
                                                      vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: stock > 0
                                                        ? const Color(
                                                            0xFFE8F5E9)
                                                        : const Color(
                                                            0xFFFFEBEE),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            4),
                                                  ),
                                                  child: Text(
                                                    '재고: $stock',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: stock > 0
                                                          ? const Color(
                                                              0xFF2E7D32)
                                                          : Colors.red,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 3),
                                            // 2행: 규격(E열) + 회색 자재코드
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
                                      // 수량 증감 버튼
                                      Row(
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
                                                    setState(() {
                                                      _quantities[code] =
                                                          currentQty - 1;
                                                    });
                                                  }
                                                : null,
                                          ),
                                          Container(
                                            alignment: Alignment.center,
                                            width: 32,
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
                                          IconButton(
                                            icon: const Icon(
                                                Icons.add_circle_outline,
                                                size: 22),
                                            color: const Color(0xFFA61C24),
                                            onPressed: () {
                                              setState(() {
                                                _quantities[code] =
                                                    currentQty + 1;
                                              });
                                            },
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                ),

                // 하단 버튼부
                SafeArea(
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: _isMessageMode
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
                                    '관리자에게 메시지 전송',
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
                        : ElevatedButton(
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
                                          requiresSerial: false,
                                          isConfirmed: true,
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
                                  : '선택한 자재 장바구니에 담기 (총 $totalSelectedCount개 품목)',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
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
// 모달 카메라 스캐너 위젯
// ------------------------------------------------------------
class _ScannerModalSheet extends StatefulWidget {
  final String selectedWarehouse;
  final List<String> existingSerials;
  final Function(List<OutItem>) onItemsScanned;

  const _ScannerModalSheet({
    required this.selectedWarehouse,
    required this.existingSerials,
    required this.onItemsScanned,
  });

  @override
  State<_ScannerModalSheet> createState() => _ScannerModalSheetState();
}

class _ScannerModalSheetState extends State<_ScannerModalSheet> {
  final MobileScannerController _scannerController = MobileScannerController();
  final List<OutItem> _scannedList = [];
  bool _isProcessing = false;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;
    final barcode = capture.barcodes.firstOrNull?.rawValue?.trim();
    if (barcode == null || barcode.isEmpty) return;

    setState(() => _isProcessing = true);

    try {
      // Firebase materials 조회
      final snap = await FirebaseFirestore.instance
          .collection('materials')
          .doc(barcode)
          .get();

      if (!snap.exists) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('등록되지 않은 자재코드입니다: $barcode')),
        );
        await Future.delayed(const Duration(seconds: 1));
        setState(() => _isProcessing = false);
        return;
      }

      final data = snap.data()!;
      final name = (data['materialName'] ?? data['품명'] ?? barcode).toString();
      final reqSerial = data['requiresSerial'] == true;

      final existingIdx =
          _scannedList.indexWhere((it) => it.materialCode == barcode);
      if (existingIdx >= 0) {
        _scannedList[existingIdx].quantity++;
      } else {
        _scannedList.add(OutItem(
          materialCode: barcode,
          materialName: name,
          quantity: 1,
          requiresSerial: reqSerial,
          isConfirmed: true,
        ));
      }

      setState(() {});
      await Future.delayed(const Duration(milliseconds: 800));
    } catch (e) {
      // ignore
    } finally {
      if (mounted) setState(() => _isProcessing = false);
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
          SizedBox(
            height: 220,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: MobileScanner(
                controller: _scannerController,
                onDetect: _onDetect,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '스캔된 품목 (${_scannedList.length}건)',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13),
                ),
                if (_scannedList.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() => _scannedList.clear()),
                    child: const Text('비우기',
                        style: TextStyle(color: Colors.red, fontSize: 12)),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _scannedList.isEmpty
                ? Center(
                    child: Text('카메라에 QR코드를 비춰주세요.',
                        style: TextStyle(color: Colors.grey[500])),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _scannedList.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, idx) {
                      final item = _scannedList[idx];
                      return ListTile(
                        dense: true,
                        title: Text(item.materialName,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('코드: ${item.materialCode}'),
                        trailing: Text('${item.quantity}개',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFA61C24))),
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _scannedList.isEmpty
                      ? null
                      : () {
                          widget.onItemsScanned(_scannedList);
                          Navigator.pop(context);
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFA61C24),
                    foregroundColor: Colors.white,
                  ),
                  child: Text('스캔 완료 (${_scannedList.length}건 담기)',
                      style: const TextStyle(
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
