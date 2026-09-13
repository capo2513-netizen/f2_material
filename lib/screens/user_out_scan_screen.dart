import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 햅틱 진동 엔진
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/user_model.dart';

class OutItem {
  final String materialCode;
  final String materialName;
  int quantity;
  String? sktSerial;
  final bool requiresSerial;
  bool isConfirmed;

  OutItem({
    required this.materialCode,
    required this.materialName,
    required this.quantity,
    this.sktSerial,
    required this.requiresSerial,
    this.isConfirmed = false,
  });
}

class UserOutScanScreen extends StatefulWidget {
  final UserModel currentUser;
  const UserOutScanScreen({super.key, required this.currentUser});

  @override
  State<UserOutScanScreen> createState() => _UserOutScanScreenState();
}

class _UserOutScanScreenState extends State<UserOutScanScreen> {
  final List<OutItem> _cart = [];
  bool _isSubmitting = false;

  void _openScannerModal() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('카메라 사용 권한이 필요합니다. 설정에서 허용해주세요.')),
        );
      }
      return;
    }

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ScannerModalSheet(
        onItemsScanned: (List<OutItem> newItems) {
          setState(() {
            _cart.addAll(newItems);
          });
        },
        existingSerials: _cart
            .where((i) => i.sktSerial != null)
            .map((i) => i.sktSerial!)
            .toList(),
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

  void _showQuantityInputDialog(OutItem item) {
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
            labelText: '출고 수량 (개)',
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
              backgroundColor: const Color(0xFFA61C24),
            ),
            child: const Text('적용', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _submitOut() async {
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('등록된 출고 자재가 없습니다.')));
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
                backgroundColor: const Color(0xFFA61C24),
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
          '출고 전송 확인',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          '총 ${_cart.length}건의 출고 데이터를 전송하시겠습니까?\n작업자: [${widget.currentUser.team}] ${widget.currentUser.name}',
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
        'normal_out_logs',
      );
      final now = DateTime.now();

      for (var item in _cart) {
        final docRef = collection.doc();
        batch.set(docRef, {
          'timestamp': FieldValue.serverTimestamp(),
          'displayTime': now.toIso8601String(),
          'team': widget.currentUser.team,
          'userName': widget.currentUser.name,
          'userPhone': widget.currentUser.phone,
          'materialCode': item.materialCode,
          'materialName': item.materialName,
          'quantity': item.quantity,
          'sktSerial': item.sktSerial ?? '',
          'syncedToExcel': false,
        });
      }

      await batch.commit();

      if (!mounted) return;

      // 0.5초 자동 닫힘 팝업
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (ctx.mounted) {
              Navigator.pop(ctx);
              Navigator.pop(context);
            }
          });
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            content: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle, color: Color(0xFF2E7D32), size: 28),
                  SizedBox(width: 10),
                  Text(
                    '정상적으로 전송되었습니다.',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('전송 중 오류 발생: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '자재 출고 등록',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFFA61C24),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _openScannerModal,
                    icon: const Icon(Icons.qr_code_scanner, size: 22),
                    label: const Text(
                      'QR 스캔',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFA61C24),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _openManualListModal,
                    icon: const Icon(Icons.list_alt, size: 22),
                    label: const Text(
                      '목록 선택',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF2C3E50),
                      side: const BorderSide(
                        color: Color(0xFF2C3E50),
                        width: 1.5,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
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
                  '출고 대기 목록 (${_cart.length}건)',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                if (_cart.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() => _cart.clear()),
                    child: const Text(
                      '전체 비우기',
                      style: TextStyle(color: Colors.red, fontSize: 13),
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
                        '등록된 자재가 없습니다.\n상단의 [QR 스캔] 또는 [목록 선택]을 누르세요.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontSize: 14),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      itemCount: _cart.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (ctx, index) {
                        final item = _cart[index];
                        return Card(
                          elevation: 1.5,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                              color: item.isConfirmed
                                  ? const Color(0xFF2E7D32)
                                  : Colors.transparent,
                              width: 1.2,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: item.requiresSerial
                                            ? const Color(0xFFF39800)
                                            : const Color(0xFFA61C24),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        item.requiresSerial ? 'SKT시리얼' : '일반자재',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    if (item.isConfirmed &&
                                        !item.requiresSerial)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFE8F5E9),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: const Text(
                                          '수량확정됨',
                                          style: TextStyle(
                                            color: Color(0xFF2E7D32),
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    const Spacer(),
                                    // 메인 리스트 개별 삭제 버튼
                                    IconButton(
                                      icon: const Icon(
                                        Icons.close,
                                        size: 20,
                                        color: Colors.grey,
                                      ),
                                      onPressed: () =>
                                          setState(() => _cart.removeAt(index)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  item.materialName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  '자재코드: ${item.materialCode}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                                if (item.sktSerial != null &&
                                    item.sktSerial!.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFF3E0),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'SKT S/N: ${item.sktSerial}',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFFE65100),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
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
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor:
                                                    Colors.blueGrey,
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
                                        '단일 개별 시리얼 (1개)',
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
                                                : () {
                                                    if (item.quantity > 1)
                                                      setState(
                                                        () =>
                                                            item.quantity -= 1,
                                                      );
                                                  },
                                          ),
                                          InkWell(
                                            onTap: () =>
                                                _showQuantityInputDialog(item),
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
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
                                                      : const Color(0xFFA61C24),
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
            bottom: true,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
              ),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isSubmitting || _cart.isEmpty ? null : _submitOut,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFA61C24),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 3,
                  ),
                  child: _isSubmitting
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          '출고 전송 완료 (총 ${_cart.length}건)',
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

// ------------------------------------------------------------
// 모달 카메라 스캐너 위젯
// ------------------------------------------------------------
class _ScannerModalSheet extends StatefulWidget {
  final Function(List<OutItem>) onItemsScanned;
  final List<String> existingSerials;

  const _ScannerModalSheet({
    required this.onItemsScanned,
    required this.existingSerials,
  });

  @override
  State<_ScannerModalSheet> createState() => _ScannerModalSheetState();
}

class _ScannerModalSheetState extends State<_ScannerModalSheet> {
  final MobileScannerController _controller = MobileScannerController();
  final List<OutItem> _sessionItems = [];

  bool _isWaitingSktSerial = false;
  String? _activeMatCode;
  String? _activeMatName;
  bool _isProcessing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _vibrate() {
    HapticFeedback.heavyImpact();
    HapticFeedback.vibrate();
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    final rawValue = barcode.rawValue!.trim();
    if (rawValue.isEmpty) return;

    // ------------------------------------------------------------
    // 1. SKT 시리얼 스캔 대기 모드 (F2 코드 스캔 원천 차단)
    // ------------------------------------------------------------
    if (_isWaitingSktSerial) {
      // (1) #SN 태그가 있거나, 현재 선택된 자재코드와 일치하면 무조건 F2 자재코드로 판별하여 완전 차단
      if (rawValue.contains('#SN') || rawValue == _activeMatCode) {
        return; // 아무것도 하지 않고 조용히 무시 (오등록 차단)
      }

      // (2) 혹시 다른 F2 자재 QR을 스쳤는지 DB 확인하여 F2 코드면 시리얼 등록 차단
      try {
        final checkDoc = await FirebaseFirestore.instance
            .collection('materials')
            .doc(rawValue)
            .get();
        if (checkDoc.exists) {
          return; // F2 자재코드이므로 SKT 시리얼로 들어가지 않게 차단
        }
      } catch (_) {}

      // (3) 이미 찍힌 시리얼이면 중복 등록 방지
      if (widget.existingSerials.contains(rawValue) ||
          _sessionItems.any((i) => i.sktSerial == rawValue)) {
        return;
      }

      // [정상 SKT 시리얼 인식]
      _vibrate();
      _isProcessing = true;

      setState(() {
        _sessionItems.add(
          OutItem(
            materialCode: _activeMatCode!,
            materialName: _activeMatName!,
            quantity: 1,
            sktSerial: rawValue,
            requiresSerial: true,
            isConfirmed: true,
          ),
        );
      });

      await Future.delayed(const Duration(milliseconds: 900));
      _isProcessing = false;
      return;
    }

    // ------------------------------------------------------------
    // 2. F2 자재 QR 스캔 모드
    // ------------------------------------------------------------
    _isProcessing = true;

    bool isSerialItem = false;
    String cleanMatCode = rawValue;
    if (rawValue.contains('#SN')) {
      isSerialItem = true;
      cleanMatCode = rawValue.replaceAll('#SN', '').trim();
    }

    String? fetchedName;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('materials')
          .doc(cleanMatCode)
          .get();
      if (doc.exists && doc.data() != null) {
        fetchedName = doc.data()!['materialName'] ?? '품명 없음';
        if (doc.data()!['requiresSerial'] == true) {
          isSerialItem = true;
        }
      }
    } catch (_) {}

    if (fetchedName == null && !rawValue.contains('#SN')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ 미등록 코드: $rawValue\n반드시 F2 자재 QR코드를 먼저 스캔하세요.'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
      await Future.delayed(const Duration(milliseconds: 1500));
      _isProcessing = false;
      return;
    }

    _vibrate();
    final finalMatName = fetchedName ?? cleanMatCode;

    if (isSerialItem) {
      setState(() {
        _activeMatCode = cleanMatCode;
        _activeMatName = finalMatName;
        _isWaitingSktSerial = true;
      });
      await Future.delayed(const Duration(milliseconds: 1000));
      _isProcessing = false;
    } else {
      widget.onItemsScanned([
        OutItem(
          materialCode: cleanMatCode,
          materialName: finalMatName,
          quantity: 1,
          requiresSerial: false,
          isConfirmed: false,
        ),
      ]);
      Navigator.pop(context);
    }
  }

  void _finishSerialSession() {
    widget.onItemsScanned(_sessionItems);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),

          // 조준 사각 프레임
          Positioned(
            top: 70,
            child: Container(
              width: 260,
              height: 150,
              decoration: BoxDecoration(
                border: Border.all(
                  color: _isWaitingSktSerial
                      ? const Color(0xFFF39800)
                      : Colors.white,
                  width: 2.5,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),

          // 상단 바
          Positioned(
            top: 14,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.flash_on,
                    color: Colors.white,
                    size: 28,
                  ),
                  onPressed: () => _controller.toggleTorch(),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 30),
                  onPressed: () {
                    if (_sessionItems.isNotEmpty) {
                      widget.onItemsScanned(_sessionItems);
                    }
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ),

          // 안내 타이틀 뱃지
          Positioned(
            top: 235,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: _isWaitingSktSerial
                    ? const Color(0xFFF39800)
                    : Colors.black.withOpacity(0.75),
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(color: Colors.black38, blurRadius: 6),
                ],
              ),
              child: Text(
                _isWaitingSktSerial
                    ? '[$_activeMatName]\n장비의 SKT 시리얼 QR/바코드를 비추세요'
                    : 'F2 자재 QR코드를 조준창에 비추세요',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ),

          // [핵심 개선] 스캔 화면 내 실시간 시리얼 목록 + '개별 삭제(X) 버튼'
          if (_isWaitingSktSerial)
            Positioned(
              top: 295,
              bottom: 150,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.75),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white24, width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '📷 등록된 SKT 시리얼 목록',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF39800),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '총 ${_sessionItems.length}대',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white24, height: 10),
                    Expanded(
                      child: _sessionItems.isEmpty
                          ? const Center(
                              child: Text(
                                '아직 스캔된 시리얼이 없습니다.\n카메라로 SKT 바코드를 비추세요.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white60,
                                  fontSize: 12,
                                ),
                              ),
                            )
                          : ListView.builder(
                              padding: EdgeInsets.zero,
                              itemCount: _sessionItems.length,
                              itemBuilder: (context, idx) {
                                final serial =
                                    _sessionItems[idx].sktSerial ?? '';
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 2.0,
                                  ),
                                  child: Row(
                                    children: [
                                      Text(
                                        '${idx + 1}. ',
                                        style: const TextStyle(
                                          color: Color(0xFFF39800),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          serial,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      // [실시간 개별 삭제 버튼]
                                      InkWell(
                                        onTap: () {
                                          setState(() {
                                            _sessionItems.removeAt(idx);
                                          });
                                        },
                                        borderRadius: BorderRadius.circular(12),
                                        child: const Padding(
                                          padding: EdgeInsets.all(4.0),
                                          child: Icon(
                                            Icons.close,
                                            color: Colors.redAccent,
                                            size: 18,
                                          ),
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
              ),
            ),

          // 하단 스캔 완료 버튼
          if (_isWaitingSktSerial)
            Positioned(
              bottom: 85,
              left: 24,
              right: 24,
              child: SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _finishSerialSession,
                  icon: const Icon(
                    Icons.check_circle,
                    color: Colors.white,
                    size: 20,
                  ),
                  label: Text(
                    '스캔 완료 (${_sessionItems.length}대 저장)',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 15,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    elevation: 5,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
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
