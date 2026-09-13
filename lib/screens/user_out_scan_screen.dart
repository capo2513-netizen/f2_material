import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

// 출고 대기 장바구니 아이템 모델
class OutItem {
  final String materialCode;
  final String materialName;
  int quantity;
  String? sktSerial;
  final bool requiresSerial;

  OutItem({
    required this.materialCode,
    required this.materialName,
    required this.quantity,
    this.sktSerial,
    required this.requiresSerial,
  });
}

class UserOutScanScreen extends StatefulWidget {
  final UserModel currentUser;
  const UserOutScanScreen({super.key, required this.currentUser});

  @override
  State<UserOutScanScreen> createState() => _UserOutScanScreenState();
}

class _UserOutScanScreenState extends State<UserOutScanScreen> {
  final MobileScannerController _cameraController = MobileScannerController();
  final List<OutItem> _cart = [];

  // 현재 스캔 진행 중인 임시 자재 정보
  String? _scannedMatCode;
  String? _scannedMatName;
  bool _waitingForSktSerial = false;
  bool _isProcessing = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  // QR 스캔 감지 처리 로직
  void _onDetect(BarcodeCapture capture) async {
    if (_isProcessing || _isSubmitting) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    final rawValue = barcode.rawValue!.trim();
    if (rawValue.isEmpty) return;

    // 1. [2단계 상태] SKT 시리얼 QR 스캔 대기 중일 때
    if (_waitingForSktSerial) {
      _isProcessing = true;
      setState(() {
        _cart.add(
          OutItem(
            materialCode: _scannedMatCode!,
            materialName: _scannedMatName!,
            quantity: 1, // 시리얼 장비는 1개 단위
            sktSerial: rawValue,
            requiresSerial: true,
          ),
        );
        _waitingForSktSerial = false;
        _scannedMatCode = null;
        _scannedMatName = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('SKT 시리얼($rawValue) 등록 완료!'),
          backgroundColor: const Color(0xFFF39800),
          duration: const Duration(seconds: 1),
        ),
      );

      await Future.delayed(const Duration(milliseconds: 1200));
      _isProcessing = false;
      return;
    }

    // 2. [1단계 상태] 일반 자재코드 QR 스캔일 때
    _isProcessing = true;

    // 자재코드 파싱 (#SN 플래그가 붙어있는지 확인)
    bool isSerialItem = false;
    String cleanMatCode = rawValue;
    if (rawValue.contains('#SN')) {
      isSerialItem = true;
      cleanMatCode = rawValue.replaceAll('#SN', '').trim();
    }

    // Firestore materials 컬렉션에서 품명 조회
    String fetchedName = '확인되지 않은 자재';
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
      } else {
        fetchedName = '신규/미등록 코드 ($cleanMatCode)';
      }
    } catch (e) {
      fetchedName = '조회 실패 ($cleanMatCode)';
    }

    if (isSerialItem) {
      // SKT QR 추가 스캔 모드로 진입
      setState(() {
        _scannedMatCode = cleanMatCode;
        _scannedMatName = fetchedName;
        _waitingForSktSerial = true;
      });
      await Future.delayed(const Duration(milliseconds: 1000));
      _isProcessing = false;
    } else {
      // 일반 자재인 경우 바로 1개 추가 (수량 조정 가능)
      setState(() {
        final existingIndex = _cart.indexWhere(
          (i) => i.materialCode == cleanMatCode && !i.requiresSerial,
        );
        if (existingIndex != -1) {
          _cart[existingIndex].quantity += 1;
        } else {
          _cart.add(
            OutItem(
              materialCode: cleanMatCode,
              materialName: fetchedName,
              quantity: 1,
              requiresSerial: false,
            ),
          );
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$fetchedName (1개) 추가됨'),
          duration: const Duration(milliseconds: 800),
        ),
      );

      await Future.delayed(const Duration(milliseconds: 1000));
      _isProcessing = false;
    }
  }

  // 최종 출고 전송 로직
  void _submitOut() async {
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('스캔하여 담은 자재가 없습니다.')));
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          '출고 전송 확인',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          '총 ${_cart.length}종의 자재를 출고 전송하시겠습니까?\n작업자: [${widget.currentUser.team}] ${widget.currentUser.name}',
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
          'syncedToExcel': false, // 엑셀에서 읽어간 후 true로 갱신할 플래그
        });
      }

      await batch.commit();

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('출고 완료'),
          content: const Text(
            '출고 내역이 정상 전송되었습니다.\n사무실 엑셀 [일반출고] 시트에 실시간 반영됩니다.',
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context); // 홈 화면으로 복귀
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFA61C24),
              ),
              child: const Text('확인', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('전송 중 오류가 발생했습니다: $e')));
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
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => _cameraController.toggleTorch(),
          ),
        ],
      ),
      body: Column(
        children: [
          // 상단: 카메라 스캐너 프리뷰 (35% 높이)
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.35,
            child: Stack(
              alignment: Alignment.center,
              children: [
                MobileScanner(
                  controller: _cameraController,
                  onDetect: _onDetect,
                ),
                // 조준 사각 프레임
                Container(
                  width: 220,
                  height: 140,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _waitingForSktSerial
                          ? const Color(0xFFF39800)
                          : Colors.white,
                      width: 2.5,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                // 안내 텍스트 바
                Positioned(
                  bottom: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _waitingForSktSerial
                          ? const Color(0xFFF39800)
                          : Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _waitingForSktSerial
                          ? '📢 장비의 SKT QR코드(시리얼)를 스캔하세요!'
                          : '자재 QR코드를 조준창에 비추세요',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 중간/하단: 출고 장바구니 리스트
          Expanded(
            child: Container(
              color: const Color(0xFFF5F6F8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '스캔된 출고 목록 (${_cart.length}건)',
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
                              '스캔된 자재가 없습니다.\n위 카메라로 QR을 비추면 담깁니다.',
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
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (ctx, index) {
                              final item = _cart[index];
                              return Card(
                                elevation: 1,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              item.requiresSerial
                                                  ? '시리얼관리'
                                                  : '일반자재',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              item.materialName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(
                                              Icons.close,
                                              size: 18,
                                              color: Colors.grey,
                                            ),
                                            onPressed: () => setState(
                                              () => _cart.removeAt(index),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '코드: ${item.materialCode}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey,
                                        ),
                                      ),
                                      if (item.sktSerial != null) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          'SKT S/N: ${item.sktSerial}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFFF39800),
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                      const Divider(height: 16),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          const Text(
                                            '출고 수량: ',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          if (!item.requiresSerial) ...[
                                            IconButton(
                                              icon: const Icon(
                                                Icons.remove_circle_outline,
                                                size: 20,
                                              ),
                                              onPressed: () {
                                                if (item.quantity > 1) {
                                                  setState(
                                                    () => item.quantity -= 1,
                                                  );
                                                }
                                              },
                                            ),
                                            Text(
                                              '${item.quantity}',
                                              style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            IconButton(
                                              icon: const Icon(
                                                Icons.add_circle_outline,
                                                size: 20,
                                              ),
                                              onPressed: () => setState(
                                                () => item.quantity += 1,
                                              ),
                                            ),
                                          ] else ...[
                                            Text(
                                              '${item.quantity} EA (고정)',
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
                                ),
                              );
                            },
                          ),
                  ),

                  // 하단 최종 전송 버튼 바
                  Container(
                    padding: const EdgeInsets.all(16.0),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isSubmitting || _cart.isEmpty
                            ? null
                            : _submitOut,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFA61C24),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: _isSubmitting
                            ? const CircularProgressIndicator(
                                color: Colors.white,
                              )
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
