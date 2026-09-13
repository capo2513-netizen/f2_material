import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/user_model.dart';

class AdvancedItem {
  final String materialCode;
  final String materialName;
  int quantity;
  final String actionType; // 'IN' or 'OUT'
  final String condition; // '신품', '구품', '불량'
  final String itemType; // '사급' or '지입'
  String? sktSerial;
  final bool requiresSerial;
  bool isConfirmed;

  AdvancedItem({
    required this.materialCode,
    required this.materialName,
    required this.quantity,
    required this.actionType,
    required this.condition,
    required this.itemType,
    this.sktSerial,
    required this.requiresSerial,
    this.isConfirmed = false,
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
  final List<AdvancedItem> _cart = [];
  String _currentAction = 'OUT';
  String _currentCondition = '신품';
  bool _isSubmitting = false;

  void _openScannerModal() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('카메라 사용 권한이 필요합니다.')));
      }
      return;
    }

    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.fromLTRB(16, 40, 16, 20),
        alignment: Alignment.topCenter,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.65,
          child: _AdvancedScannerView(
            currentAction: _currentAction,
            currentCondition: _currentCondition,
            existingSerials: _cart
                .where((i) => i.sktSerial != null)
                .map((i) => i.sktSerial!)
                .toList(),
            onItemsScanned: (newItems) {
              setState(() {
                _cart.addAll(newItems);
              });
            },
          ),
        ),
      ),
    );
  }

  void _openManualListModal() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Container(
        height: 350,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '자재 목록 선택',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const Divider(),
            const Expanded(
              child: Center(
                child: Text(
                  '대분류 / 중분류 / 소분류 기반 자재 목록이 이곳에 연결됩니다.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showQuantityInputDialog(AdvancedItem item) {
    if (item.isConfirmed || item.requiresSerial) return;
    final controller = TextEditingController(text: '${item.quantity}');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          '${item.materialName}\n수량 직접 입력',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '수량 (개)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () {
              final val = int.tryParse(controller.text.trim());
              if (val != null && val > 0) {
                setState(() => item.quantity = val);
              }
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF39800),
            ),
            child: const Text('적용', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _submit() async {
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('등록된 입·출고 항목이 없습니다.')));
      return;
    }

    final unconfirmedCount = _cart
        .where((item) => !item.isConfirmed && !item.requiresSerial)
        .length;
    if (unconfirmedCount > 0) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text(
            '수량 미확정 알림',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Text(
            '수량 확정을 누르지 않은 일반자재가 $unconfirmedCount건 있습니다.\n현재 수량 그대로 전송하시겠습니까?',
          ),
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
              child: const Text(
                '그대로 전송',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          '입·출고 전송 확인',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text('총 ${_cart.length}건의 데이터를 전송하시겠습니까?'),
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
          'actionType': item.actionType,
          'condition': item.condition,
          'itemType': item.itemType, // '사급' or '지입'
          'materialCode': item.materialCode,
          'materialName': item.materialName,
          'quantity': item.quantity,
          'sktSerial': item.sktSerial ?? '',
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
          content: const Text('입·출고 내역이 성공적으로 저장되었습니다.\n엑셀에서 동기화하세요.'),
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
          '입고 관리 / 출고 관리',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFFF39800),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
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
                    onPressed: () => setState(() {
                      _currentAction = 'OUT';
                      _currentCondition = '신품';
                    }),
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
                    onPressed: () => setState(() {
                      _currentAction = 'IN';
                      _currentCondition = '신품';
                    }),
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: const Color(0xFFFAFAFA),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _openScannerModal,
                    icon: const Icon(Icons.qr_code_scanner, size: 20),
                    label: Text(
                      '[$_currentCondition ${_currentAction == 'IN' ? '입고' : '출고'}] QR 스캔',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF39800),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _openManualListModal,
                    icon: const Icon(Icons.list_alt, size: 20),
                    label: const Text(
                      '목록 선택',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF2C3E50),
                      side: const BorderSide(
                        color: Color(0xFF2C3E50),
                        width: 1.5,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '입·출고 대기 목록 (${_cart.length}건)',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
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
            child: Container(
              color: const Color(0xFFF5F6F8),
              child: _cart.isEmpty
                  ? const Center(
                      child: Text(
                        '등록된 항목이 없습니다.\n상단의 [QR 스캔] 또는 [목록 선택]을 누르세요.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      itemCount: _cart.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (ctx, index) {
                        final item = _cart[index];
                        final isOut = item.actionType == 'OUT';
                        return Card(
                          elevation: 1.5,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color: item.isConfirmed
                                  ? const Color(0xFF2E7D32)
                                  : Colors.transparent,
                              width: 1.2,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              children: [
                                Row(
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
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '${item.condition} ${isOut ? '출고' : '입고'} [${item.itemType}]',
                                        style: TextStyle(
                                          color: isOut
                                              ? Colors.red[800]
                                              : Colors.green[800],
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    if (item.requiresSerial)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFF3E0),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: const Text(
                                          'SKT시리얼',
                                          style: TextStyle(
                                            color: Color(0xFFEF6C00),
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    const Spacer(),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.close,
                                        size: 18,
                                        color: Colors.grey,
                                      ),
                                      onPressed: () =>
                                          setState(() => _cart.removeAt(index)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
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
                                          if (item.sktSerial != null &&
                                              item.sktSerial!.isNotEmpty)
                                            Text(
                                              'SKT S/N: ${item.sktSerial}',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Color(0xFFEF6C00),
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(height: 16),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    if (!item.requiresSerial)
                                      item.isConfirmed
                                          ? OutlinedButton.icon(
                                              onPressed: () => setState(
                                                () => item.isConfirmed = false,
                                              ),
                                              icon: const Icon(
                                                Icons.edit,
                                                size: 14,
                                              ),
                                              label: const Text(
                                                '수량 수정',
                                                style: TextStyle(fontSize: 12),
                                              ),
                                            )
                                          : ElevatedButton.icon(
                                              onPressed: () => setState(
                                                () => item.isConfirmed = true,
                                              ),
                                              icon: const Icon(
                                                Icons.check,
                                                size: 14,
                                              ),
                                              label: const Text(
                                                '수량 확정',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: const Color(
                                                  0xFF2E7D32,
                                                ),
                                                foregroundColor: Colors.white,
                                              ),
                                            )
                                    else
                                      const Text(
                                        '1 EA (단일 시리얼)',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    Row(
                                      children: [
                                        const Text(
                                          '수량: ',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        if (!item.requiresSerial) ...[
                                          IconButton(
                                            icon: Icon(
                                              Icons.remove_circle_outline,
                                              size: 20,
                                              color: item.isConfirmed
                                                  ? Colors.grey[300]
                                                  : Colors.black87,
                                            ),
                                            onPressed: item.isConfirmed
                                                ? null
                                                : () => setState(() {
                                                    if (item.quantity > 1)
                                                      item.quantity -= 1;
                                                  }),
                                          ),
                                          InkWell(
                                            onTap: () =>
                                                _showQuantityInputDialog(item),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.grey[100],
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                                border: Border.all(
                                                  color: Colors.grey[300]!,
                                                ),
                                              ),
                                              child: Text(
                                                '${item.quantity}',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                  color: item.isConfirmed
                                                      ? const Color(0xFF2E7D32)
                                                      : const Color(0xFFF39800),
                                                ),
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            icon: Icon(
                                              Icons.add_circle_outline,
                                              size: 20,
                                              color: item.isConfirmed
                                                  ? Colors.grey[300]
                                                  : Colors.black87,
                                            ),
                                            onPressed: item.isConfirmed
                                                ? null
                                                : () => setState(
                                                    () => item.quantity += 1,
                                                  ),
                                          ),
                                        ] else ...[
                                          const Text(
                                            '1 EA',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFFF39800),
                                            ),
                                          ),
                                        ],
                                      ],
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
          ),
          SafeArea(
            top: false,
            // bottom: true 로 내비게이션 바 영역 자동 보호
            bottom: true,
            child: Container(
              // 하단 여백을 16pt 주어 내비게이션 바 위로 올림
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
              ),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isSubmitting || _cart.isEmpty ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF39800),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isSubmitting
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          '전송 완료 (총 ${_cart.length}건)',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
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

// 상단 모달 스캐너 위젯 (시각적 번쩍임 피드백 + SKT 시리얼 연속 스캔 내장)
class _AdvancedScannerView extends StatefulWidget {
  final String currentAction;
  final String currentCondition;
  final List<String> existingSerials;
  final Function(List<AdvancedItem>) onItemsScanned;

  const _AdvancedScannerView({
    required this.currentAction,
    required this.currentCondition,
    required this.existingSerials,
    required this.onItemsScanned,
  });

  @override
  State<_AdvancedScannerView> createState() => _AdvancedScannerViewState();
}

class _AdvancedScannerViewState extends State<_AdvancedScannerView> {
  final MobileScannerController _controller = MobileScannerController();
  final List<AdvancedItem> _sessionItems = [];

  bool _isProcessing = false;
  bool _showFlashEffect = false; // 플래시 애니메이션 플래그

  bool _isWaitingSktSerial = false;
  String? _activeMatCode;
  String? _activeMatName;
  String _activeItemType = '사급';
  int _activeSerialCount = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _triggerFlash() {
    setState(() => _showFlashEffect = true);
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _showFlashEffect = false);
    });
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    final rawValue = barcode.rawValue!.trim();
    if (rawValue.isEmpty) return;

    // SKT 시리얼 스캔 대기 모드
    if (_isWaitingSktSerial) {
      if (rawValue.contains('#SN')) {
        _isProcessing = true;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ SKT 시리얼을 스캔하세요. 종료는 [스캔 완료]를 누르세요.'),
            backgroundColor: Colors.red,
          ),
        );
        await Future.delayed(const Duration(milliseconds: 1200));
        _isProcessing = false;
        return;
      }

      if (widget.existingSerials.contains(rawValue) ||
          _sessionItems.any((i) => i.sktSerial == rawValue)) {
        _isProcessing = true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ 이미 등록된 SKT 시리얼입니다: $rawValue'),
            backgroundColor: Colors.red,
          ),
        );
        await Future.delayed(const Duration(milliseconds: 1000));
        _isProcessing = false;
        return;
      }

      _isProcessing = true;
      _triggerFlash(); // 인식 번쩍임 피드백

      setState(() {
        _activeSerialCount += 1;
        _sessionItems.add(
          AdvancedItem(
            materialCode: _activeMatCode!,
            materialName: _activeMatName!,
            quantity: 1,
            actionType: widget.currentAction,
            condition: widget.currentCondition,
            itemType: _activeItemType,
            sktSerial: rawValue,
            requiresSerial: true,
            isConfirmed: true,
          ),
        );
      });

      await Future.delayed(const Duration(milliseconds: 1000));
      _isProcessing = false;
      return;
    }

    // F2 자재 QR 인식 모드
    _isProcessing = true;
    bool isSerial = false;
    String cleanCode = rawValue;
    if (rawValue.contains('#SN')) {
      isSerial = true;
      cleanCode = rawValue.replaceAll('#SN', '').trim();
    }

    String? fetchedName;
    String fetchedItemType = '사급';

    try {
      final doc = await FirebaseFirestore.instance
          .collection('materials')
          .doc(cleanCode)
          .get();
      if (doc.exists && doc.data() != null) {
        fetchedName = doc.data()!['materialName'] ?? '품명 없음';
        fetchedItemType = doc.data()!['itemType'] ?? '사급';
        if (doc.data()!['requiresSerial'] == true) isSerial = true;
      }
    } catch (_) {}

    if (fetchedName == null && !rawValue.contains('#SN')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ 미등록 코드: $rawValue\n반드시 F2 자재 QR을 먼저 스캔하세요.'),
          backgroundColor: Colors.red,
        ),
      );
      await Future.delayed(const Duration(milliseconds: 1500));
      _isProcessing = false;
      return;
    }

    _triggerFlash(); // 인식 성공 시 번쩍임
    final finalName = fetchedName ?? cleanCode;

    if (isSerial) {
      setState(() {
        _activeMatCode = cleanCode;
        _activeMatName = finalName;
        _activeItemType = fetchedItemType;
        _activeSerialCount = 0;
        _isWaitingSktSerial = true;
      });
      await Future.delayed(const Duration(milliseconds: 1000));
      _isProcessing = false;
    } else {
      widget.onItemsScanned([
        AdvancedItem(
          materialCode: cleanCode,
          materialName: finalName,
          quantity: 1,
          actionType: widget.currentAction,
          condition: widget.currentCondition,
          itemType: fetchedItemType,
          requiresSerial: false,
          isConfirmed: false,
        ),
      ]);
      Navigator.pop(context); // 일반자재는 즉시 닫고 리스트로 복귀
    }
  }

  void _finishSerial() {
    widget.onItemsScanned(_sessionItems);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Container(
            width: 250,
            height: 160,
            decoration: BoxDecoration(
              border: Border.all(
                color: _isWaitingSktSerial
                    ? const Color(0xFFF39800)
                    : Colors.white,
                width: 2.5,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          // 촬영 성공 시 녹색/흰색 플래시 효과
          if (_showFlashEffect) Container(color: Colors.white.withOpacity(0.4)),
          Positioned(
            top: 10,
            left: 10,
            right: 10,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.flash_on, color: Colors.white),
                  onPressed: () => _controller.toggleTorch(),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                  onPressed: () {
                    if (_sessionItems.isNotEmpty)
                      widget.onItemsScanned(_sessionItems);
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ),
          Positioned(
            top: 55,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: _isWaitingSktSerial
                    ? const Color(0xFFF39800)
                    : Colors.black87,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _isWaitingSktSerial
                    ? '[$_activeMatName]\nSKT 시리얼 QR/바코드를 비추세요 (${_activeSerialCount}대 등록)'
                    : '[${widget.currentCondition} ${widget.currentAction == 'IN' ? '입고' : '출고'}] F2 자재 QR을 비추세요',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 20,
            child: _isWaitingSktSerial
                ? ElevatedButton.icon(
                    onPressed: _finishSerial,
                    icon: const Icon(Icons.check_circle, color: Colors.white),
                    label: Text(
                      '스캔 완료 (${_activeSerialCount}대 등록)',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
