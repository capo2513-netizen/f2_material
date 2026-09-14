import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 햅틱 진동 엔진
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/user_model.dart';

/// 출고 아이템 모델: F2 코드 1건당 SKT 시리얼들을 묶음(List<String>)으로 보관
class OutItem {
  final String materialCode;
  final String materialName;
  int quantity;
  List<String> sktSerials; // 묶음 시리얼 리스트
  final bool requiresSerial;
  bool isConfirmed;

  OutItem({
    required this.materialCode,
    required this.materialName,
    required this.quantity,
    List<String>? sktSerials,
    required this.requiresSerial,
    this.isConfirmed = false,
  }) : sktSerials = sktSerials ?? [];
}

class UserOutScanScreen extends StatefulWidget {
  final UserModel currentUser;
  const UserOutScanScreen({super.key, required this.currentUser});

  @override
  State<UserOutScanScreen> createState() => _UserOutScanScreenState();
}

class _UserOutScanScreenState extends State<UserOutScanScreen> {
  final ScrollController _listScrollController = ScrollController();
  final List<OutItem> _cart = [];
  bool _isSubmitting = false;

  @override
  void dispose() {
    _listScrollController.dispose();
    super.dispose();
  }

  // 자재 추가 시 목록 맨 아래(최신 입력 항목)로 자동 스크롤
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_listScrollController.hasClients) {
        _listScrollController.animateTo(
          _listScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

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

    final existingSerials = _cart.expand((item) => item.sktSerials).toList();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ScannerModalSheet(
        onItemsScanned: (List<OutItem> newItems) {
          setState(() {
            _cart.addAll(newItems);
          });
          // 새 자재가 목록에 추가된 후 최하단으로 자동 스크롤
          _scrollToBottom();
        },
        existingSerials: existingSerials,
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

    final unconfirmedCount =
        _cart.where((item) => !item.isConfirmed && !item.requiresSerial).length;
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

    int totalCount = 0;
    for (var item in _cart) {
      totalCount +=
          item.requiresSerial ? item.sktSerials.length : item.quantity;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          '출고 전송 확인',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          '총 ${_cart.length}개 항목 (총 $totalCount개 수량)의 출고 데이터를 전송하시겠습니까?\n작업자: [${widget.currentUser.team}] ${widget.currentUser.name}',
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
        if (item.requiresSerial) {
          for (var serial in item.sktSerials) {
            final docRef = collection.doc();
            batch.set(docRef, {
              'timestamp': FieldValue.serverTimestamp(),
              'displayTime': now.toIso8601String(),
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
        } else {
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
            'sktSerial': '',
            'syncedToExcel': false,
          });
        }
      }

      await batch.commit();

      if (!mounted) return;

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
                  '출고 대기 목록 (${_cart.length}개 항목)',
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
                      controller: _listScrollController, // 컨트롤러 연결 완료
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
                                          borderRadius:
                                              BorderRadius.circular(4),
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
                                if (item.requiresSerial &&
                                    item.sktSerials.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFF8E1),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                          color: const Color(0xFFFFE082)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            const Text(
                                              '등록된 SKT 시리얼 목록',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFFE65100),
                                              ),
                                            ),
                                            Text(
                                              '총 ${item.sktSerials.length}대',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFFE65100),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 6,
                                          children: item.sktSerials
                                              .asMap()
                                              .entries
                                              .map((entry) {
                                            final idx = entry.key;
                                            final serial = entry.value;
                                            return Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 3),
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                border: Border.all(
                                                    color:
                                                        Colors.grey.shade300),
                                              ),
                                              child: Text(
                                                '${idx + 1}. $serial',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.black87,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            );
                                          }).toList(),
                                        ),
                                      ],
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
                                      Text(
                                        '총 ${item.sktSerials.length}대 묶음 등록',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFFE65100),
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
                                                    if (item.quantity > 1) {
                                                      setState(
                                                        () =>
                                                            item.quantity -= 1,
                                                      );
                                                    }
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
                                          Text(
                                            '${item.sktSerials.length} EA',
                                            style: const TextStyle(
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
                          '출고 전송 완료 (총 ${_cart.length}개 항목)',
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
  final List<String> _sessionSerials = [];

  bool _isWaitingSktSerial = false;
  String? _activeMatCode;
  String? _activeMatName;
  bool _isProcessing = false;

  // 조준창 크기 (정사각형 280 x 280)
  final double _scanWindowSize = 280.0;
  final double _scanWindowTop = 70.0;

  @override
  void dispose() {
    _controller.dispose(); // 카메라 컨트롤러만 정리 (불필요한 _listScrollController 제거)
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

    // 1. SKT 시리얼 스캔 대기 모드
    if (_isWaitingSktSerial) {
      if (rawValue.contains('#SN') || rawValue == _activeMatCode) {
        return;
      }

      try {
        final checkDoc = await FirebaseFirestore.instance
            .collection('materials')
            .doc(rawValue)
            .get();
        if (checkDoc.exists) {
          return;
        }
      } catch (_) {}

      if (widget.existingSerials.contains(rawValue) ||
          _sessionSerials.contains(rawValue)) {
        return;
      }

      _vibrate();
      _isProcessing = true;

      setState(() {
        _sessionSerials.add(rawValue);
      });

      await Future.delayed(const Duration(milliseconds: 900));
      _isProcessing = false;
      return;
    }

    // 2. F2 자재 QR 스캔 모드
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
    if (_activeMatCode != null && _sessionSerials.isNotEmpty) {
      widget.onItemsScanned([
        OutItem(
          materialCode: _activeMatCode!,
          materialName: _activeMatName!,
          quantity: _sessionSerials.length,
          sktSerials: List<String>.from(_sessionSerials),
          requiresSerial: true,
          isConfirmed: true,
        ),
      ]);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final modalHeight = MediaQuery.of(context).size.height * 0.88;

    final scanWindow = Rect.fromLTWH(
      (screenWidth - _scanWindowSize) / 2,
      _scanWindowTop,
      _scanWindowSize,
      _scanWindowSize,
    );

    return Container(
      height: modalHeight,
      decoration: const BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(
            controller: _controller,
            scanWindow: scanWindow,
            onDetect: _onDetect,
          ),
          Positioned(
            top: _scanWindowTop,
            child: Container(
              width: _scanWindowSize,
              height: _scanWindowSize,
              decoration: BoxDecoration(
                border: Border.all(
                  color: _isWaitingSktSerial
                      ? const Color(0xFFF39800)
                      : Colors.white,
                  width: 3.0,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
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
                    _finishSerialSession();
                  },
                ),
              ],
            ),
          ),
          Positioned(
            top: _scanWindowTop + _scanWindowSize + 16,
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
                    ? '[$_activeMatName]\n장비의 SKT 시리얼 QR/바코드를 사각형 안에 맞추세요'
                    : 'F2 자재 QR코드를 사각형 안에 맞추세요',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          if (_isWaitingSktSerial)
            Positioned(
              top: _scanWindowTop + _scanWindowSize + 76,
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
                            '총 ${_sessionSerials.length}대',
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
                      child: _sessionSerials.isEmpty
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
                              itemCount: _sessionSerials.length,
                              itemBuilder: (context, idx) {
                                final serial = _sessionSerials[idx];
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
                                      InkWell(
                                        onTap: () {
                                          setState(() {
                                            _sessionSerials.removeAt(idx);
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
                    '스캔 완료 (${_sessionSerials.length}대 묶음 저장)',
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
