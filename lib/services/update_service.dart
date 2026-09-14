import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:permission_handler/permission_handler.dart';

class UpdateService {
  /// 버전 체크 및 업데이트 다이얼로그 호출
  static Future<void> checkVersionAndShowDialog(BuildContext context) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('app_config').doc('version').get();
      if (!doc.exists || doc.data() == null) return;

      final data = doc.data()!;
      final int serverVersionCode = (data['latestVersionCode'] ?? 1) as int;
      final String versionName = (data['latestVersionName'] ?? '1.0.0').toString();
      final String apkUrl = (data['apkDownloadUrl'] ?? '').toString();
      final String releaseNotes = (data['releaseNotes'] ?? '안정성 개선 및 버그 수정').toString();

      // 현재 설치된 앱의 빌드 번호 확인 (pubspec.yaml의 +뒤의 숫자)
      final packageInfo = await PackageInfo.fromPlatform();
      final int currentVersionCode = int.tryParse(packageInfo.buildNumber) ?? 1;

      // 서버 버전이 더 높으면 강제 업데이트 팝업 표시
      if (serverVersionCode > currentVersionCode && apkUrl.isNotEmpty) {
        if (!context.mounted) return;
        _showForceUpdateDialog(context, versionName, releaseNotes, apkUrl);
      }
    } catch (e) {
      debugPrint('버전 체크 오류: $e');
    }
  }

  /// 강제 업데이트 팝업 (바깥 터치 및 뒤로가기 차단)
  static void _showForceUpdateDialog(
    BuildContext context,
    String versionName,
    String releaseNotes,
    String apkUrl,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return PopScope(
          canPop: false,
          child: _UpdateProgressDialog(
            versionName: versionName,
            releaseNotes: releaseNotes,
            apkUrl: apkUrl,
          ),
        );
      },
    );
  }
}

class _UpdateProgressDialog extends StatefulWidget {
  final String versionName;
  final String releaseNotes;
  final String apkUrl;

  const _UpdateProgressDialog({
    required this.versionName,
    required this.releaseNotes,
    required this.apkUrl,
  });

  @override
  State<_UpdateProgressDialog> createState() => _UpdateProgressDialogState();
}

class _UpdateProgressDialogState extends State<_UpdateProgressDialog> with WidgetsBindingObserver {
  bool _isDownloading = false;
  double _progress = 0.0;
  String _statusText = '';
  String? _downloadedApkPath; // 다운로드 완료된 APK 경로 저장
  bool _isWaitingInstall = false; // 설치 승인 대기 플래그

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // 앱 라이프사이클 관찰 시작
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // 사용자가 스마트폰 시스템 설정(보안 해제 등)을 하고 앱으로 다시 돌아왔을 때 자동 감지
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isWaitingInstall) {
      // 앱 복귀 시 멈춤을 풀고 버튼을 다시 활성화
      setState(() {
        _isDownloading = false;
        _statusText = '보안 설정을 완료하셨다면 아래 버튼을 눌러 설치를 완료해 주세요.';
      });
    }
  }

  /// 다운로드 및 설치 실행 함수
  Future<void> _startDownloadAndInstall() async {
    // 1. 이미 받아둔 파일이 온전히 존재하는 경우 재다운로드 생략하고 설치 창 호출
    if (_downloadedApkPath != null && await File(_downloadedApkPath!).exists()) {
      await _launchInstaller(_downloadedApkPath!);
      return;
    }

    // 2. 알 수 없는 앱 설치 권한 확인
    if (Platform.isAndroid) {
      final status = await Permission.requestInstallPackages.status;
      if (!status.isGranted) {
        setState(() {
          _statusText = '안내: 설치 권한 또는 갤럭시 [보안 위험 자동 차단]을 해제해야 설치가 가능합니다.';
          _isWaitingInstall = true;
        });
        await Permission.requestInstallPackages.request();
      }
    }

    setState(() {
      _isDownloading = true;
      _isWaitingInstall = false;
      _progress = 0.0;
      _statusText = '최신 업데이트 파일 다운로드 중...';
    });

    try {
      final dir = await getTemporaryDirectory();
      final savePath = '${dir.path}/app-update.apk';

      final existingFile = File(savePath);
      if (await existingFile.exists()) {
        await existingFile.delete();
      }

      final dio = Dio();
      await dio.download(
        widget.apkUrl,
        savePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            setState(() {
              _progress = received / total;
              _statusText = '다운로드 중... ${(_progress * 100).toStringAsFixed(0)}%';
            });
          }
        },
      );

      _downloadedApkPath = savePath;
      await _launchInstaller(savePath);
    } catch (e) {
      setState(() {
        _statusText = '다운로드 실패: 네트워크를 확인해 주세요.';
        _isDownloading = false;
        _isWaitingInstall = false;
      });
    }
  }

  /// 패키지 인스톨러 호출 함수
  Future<void> _launchInstaller(String path) async {
    setState(() {
      _isDownloading = false;
      _isWaitingInstall = true; // 설치 화면으로 나갔음을 표시
      _statusText = '설치 관리자 실행 중...';
    });

    final result = await OpenFilex.open(path, type: "application/vnd.android.package-archive");
    
    if (result.type != ResultType.done) {
      setState(() {
        _statusText = '설치가 중단되었습니다. 보안 해제 후 아래 버튼을 다시 눌러주세요.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.system_update_rounded, color: Color(0xFFA61C24), size: 28),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'v${widget.versionName} 업데이트 안내',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '현장 자재 관리 시스템의 최신 버전이 출시되었습니다.\n안정적인 작업을 위해 반드시 업데이트가 필요합니다.',
            style: TextStyle(fontSize: 13, color: Colors.black87),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F6F8),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '[주요 개선 내용]',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFFA61C24)),
                ),
                const SizedBox(height: 4),
                Text(widget.releaseNotes, style: const TextStyle(fontSize: 12, color: Colors.black87)),
              ],
            ),
          ),

          // 갤럭시 보안 자동 차단 주의 문구 상시 안내
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.security, size: 16, color: Color(0xFFD97706)),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '갤럭시 기기는 [설정 > 보안 및 개인정보 보호 > 보안 위험 자동 차단]을 "사용 안함"으로 해제해야 설치됩니다.',
                    style: TextStyle(fontSize: 11, color: Color(0xFF92400E)),
                  ),
                ),
              ],
            ),
          ),

          if (_isDownloading) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: _progress > 0 ? _progress : null,
              color: const Color(0xFFA61C24),
              backgroundColor: Colors.grey[200],
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                _statusText,
                style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold),
              ),
            ),
          ] else if (_statusText.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              _statusText,
              style: TextStyle(
                fontSize: 12,
                color: _downloadedApkPath != null ? const Color(0xFF1E88E5) : Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ],
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: _isDownloading ? null : _startDownloadAndInstall,
            style: ElevatedButton.styleFrom(
              backgroundColor: _downloadedApkPath != null ? const Color(0xFFF39800) : const Color(0xFFA61C24),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(
              _isDownloading
                  ? '다운로드 진행 중...'
                  : (_downloadedApkPath != null ? '보안 설정 완료 후 설치 계속하기' : '지금 바로 업데이트'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
        ),
      ],
    );
  }
}