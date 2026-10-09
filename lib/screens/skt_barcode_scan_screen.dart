import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/user_model.dart';

class SktBarcodeScanScreen extends StatefulWidget {
  final UserModel currentUser;

  const SktBarcodeScanScreen({super.key, required this.currentUser});

  @override
  State<SktBarcodeScanScreen> createState() => _SktBarcodeScanScreenState();
}

class _SktBarcodeScanScreenState extends State<SktBarcodeScanScreen> {
  // ★ Code39 다시 복구! (Code128, Code39, QR, DataMatrix 모두 감지)
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal, // 무차별 프레임 읽기 방지
    formats: const [
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.qrCode,
      BarcodeFormat.dataMatrix,
    ],
  );

  final TextEditingController _memoController = TextEditingController();
  final List<String> _scannedList = [];

  bool _isSubmitting = false;
  DateTime? _lastScanTime;
  double _zoomScale = 0.0; // 0.0: 1x(기본), 0.45: 2x, 0.8: 3x(초소형 바코드 전용)

  void _setZoom(double scale) {
    setState(() {
      _zoomScale = scale;
    });
    _scannerController.setZoomScale(_zoomScale);
  }

  // ★ SKT 주황 테마에 맞춘 세그먼트 칩 위젯
  Widget _buildZoomChip(
      String label, double scale, bool isSelected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFE65100)
              : Colors.transparent, // SKT 주황 포인트
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white70,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scannerController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  // 바코드/QR 감지 처리
  void _onDetect(BarcodeCapture capture) {
    if (_isSubmitting) return;

    final barcode = capture.barcodes.firstOrNull;
    final rawVal = barcode?.rawValue?.trim();
    if (rawVal == null || rawVal.isEmpty) return;

    // ★ [F2 자재 QR 필터링] "거점|코드" 구조의 F2 전용 QR코드는 감지 즉시 무시
    if (rawVal.contains('|') ||
        rawVal.startsWith('광주|') ||
        rawVal.startsWith('본사|')) {
      return;
    }

    // 1. 최소 길이 체크 (통신 장비 바코드는 보통 6자리 이상)
    if (rawVal.length < 6) return;

    // 2. 스캔 쿨타임 (1초 동안은 추가 스캔 잠금)
    final now = DateTime.now();
    if (_lastScanTime != null &&
        now.difference(_lastScanTime!).inMilliseconds < 1000) {
      return;
    }

    // 3. 이미 목록에 있는 바코드면 무시 (중복 스캔 방지)
    if (_scannedList.contains(rawVal)) {
      return;
    }

    _lastScanTime = now;

    // 햅틱 진동 피드백
    HapticFeedback.mediumImpact();

    setState(() {
      _scannedList.insert(0, rawVal); // 최신 스캔 항목이 맨 위로
    });

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('스캔 완료: $rawVal'),
        duration: const Duration(milliseconds: 800),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // 바코드 직접 수동 입력 다이얼로그 (라벨 훼손 대비)
  Future<void> _manualAddBarcode() async {
    final textController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('바코드 직접 입력',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '바코드 / 시리얼 번호',
            hintText: '예: 6265UF090600B',
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
              final val = textController.text.trim();
              if (val.isNotEmpty) {
                Navigator.pop(ctx, val);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE65100),
              foregroundColor: Colors.white,
            ),
            child: const Text('추가'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      setState(() {
        if (!_scannedList.contains(result)) {
          _scannedList.insert(0, result);
        }
      });
    }
  }

  // 최종 서버 일괄 전송
  Future<void> _submitAll() async {
    if (_scannedList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('스캔된 바코드가 없습니다.')),
      );
      return;
    }

    final memo = _memoController.text.trim();

    // ★ [필수 입력 검증] 메모가 비어있으면 전송 차단
    if (memo.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 26),
              SizedBox(width: 8),
              Text('국소명/메모 입력 필수',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: const Text(
            '국소명/메모가 입력되지 않았습니다.\n\n작업 국소명 또는 처리 사유를 반드시 입력한 후 다시 전송해 주세요.',
            style: TextStyle(fontSize: 14),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE65100),
                foregroundColor: Colors.white,
              ),
              child: const Text('확인'),
            ),
          ],
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('SKT 바코드 전송 확인',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(
          '총 ${_scannedList.length}개의 바코드를 전송하시겠습니까?\n\n'
          '국소명/메모: ${memo.isEmpty ? '(없음)' : memo}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE65100),
              foregroundColor: Colors.white,
            ),
            child: const Text('전송'),
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
      final collection = firestore.collection('skt_barcodes');

      for (var code in _scannedList) {
        final docRef = collection.doc();
        batch.set(docRef, {
          'timestamp': FieldValue.serverTimestamp(),
          'regDate': dateStr,
          'regTime': timeStr,
          'team': widget.currentUser.team,
          'userName': widget.currentUser.name,
          'userPhone': widget.currentUser.phone,
          'barcode': code,
          'memo': memo,
          'syncedToExcel': false,
        });
      }

      await batch.commit();

      if (!mounted) return;
      setState(() {
        _scannedList.clear();
        _memoController.clear();
        _isSubmitting = false;
      });

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('전송 완료',
              style: TextStyle(fontWeight: FontWeight.bold)),
          content: const Text('SKT 바코드가 성공적으로 전송되었습니다.\n엑셀에서 동기화할 수 있습니다.'),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE65100),
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
        SnackBar(content: Text('전송 중 오류 발생: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('SKT 바코드 전송',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFFE65100),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.keyboard),
            tooltip: '바코드 수동 입력',
            onPressed: _manualAddBarcode,
          ),
          IconButton(
            icon: const Icon(Icons.flash_on),
            tooltip: '플래시 토글',
            onPressed: () => _scannerController.toggleTorch(),
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. 상단 슬림 카메라 스캐너 영역
          Container(
            color: Colors.black,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  height: 230,
                  width: double.infinity,
                  child: MobileScanner(
                    controller: _scannerController,
                    scanWindow: Rect.fromCenter(
                      center:
                          Offset(MediaQuery.of(context).size.width / 2, 115),
                      width: 300,
                      height: 150,
                    ),
                    onDetect: _onDetect,
                  ),
                ),
                Container(
                  width: 300,
                  height: 150,
                  decoration: BoxDecoration(
                    border:
                        Border.all(color: const Color(0xFFE65100), width: 2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                // ★ [개선] 우측 상단 [ 1x | 2x | 3x ] 세그먼트 줌 버튼 그룹
                Positioned(
                  top: 6,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white24, width: 0.8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildZoomChip(
                            '1x', 0.0, _zoomScale == 0.0, () => _setZoom(0.0)),
                        const SizedBox(width: 2),
                        _buildZoomChip(
                            '2x',
                            0.45,
                            (_zoomScale > 0.0 && _zoomScale < 0.7),
                            () => _setZoom(0.45)),
                        const SizedBox(width: 2),
                        _buildZoomChip(
                            '3x', 0.8, _zoomScale >= 0.7, () => _setZoom(0.8)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 2. 국소명 / 공통 메모 입력란
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Colors.white,
            child: TextField(
              controller: _memoController,
              decoration: InputDecoration(
                hintText: '국소명/메모 (예: 출고 반납사유 등...', // ★ 문구 통일
                hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                prefixIcon: const Icon(Icons.edit_location_alt,
                    color: Color(0xFFE65100), size: 20),
              ),
            ),
          ),
          const Divider(height: 1),

          // 3. 스캔 목록 헤더
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '스캔 목록 (${_scannedList.length}건)',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14),
                ),
                if (_scannedList.isNotEmpty)
                  InkWell(
                    onTap: () => setState(() => _scannedList.clear()),
                    child: const Text('전체 비우기',
                        style: TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          ),

          // 4. 스캔된 바코드 리스트
          Expanded(
            child: _scannedList.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.qr_code_scanner,
                            size: 48, color: Colors.grey[300]),
                        const SizedBox(height: 8),
                        Text(
                          'SKT 장비 바코드나 QR코드를 비춰주세요.\n연속으로 계속 스캔할 수 있습니다.',
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(color: Colors.grey[500], fontSize: 13),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    itemCount: _scannedList.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (ctx, idx) {
                      final code = _scannedList[idx];
                      return Card(
                        margin: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 12,
                                backgroundColor: const Color(0xFFFFF3E0),
                                child: Text('${_scannedList.length - idx}',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFE65100))),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  code,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      letterSpacing: 0.5),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close,
                                    size: 18, color: Colors.grey),
                                onPressed: () {
                                  setState(() => _scannedList.removeAt(idx));
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // 5. 하단 일괄 전송 버튼
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: SafeArea(
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: (_scannedList.isEmpty || _isSubmitting)
                      ? null
                      : _submitAll,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE65100),
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
                          '총 ${_scannedList.length}건 SKT 바코드 전송',
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
