import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateService {
  /// 버전 체크 및 업데이트 다이얼로그 호출
  static Future<void> checkVersionAndShowDialog(BuildContext context) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('version')
          .get();
      if (!doc.exists || doc.data() == null) return;

      final data = doc.data()!;
      final int serverVersionCode = (data['latestVersionCode'] ?? 1) as int;
      final String versionName =
          (data['latestVersionName'] ?? '1.0.0').toString();
      final String apkUrl = (data['apkDownloadUrl'] ?? '').toString();
      final String releaseNotes =
          (data['releaseNotes'] ?? '안정성 개선 및 버그 수정').toString();

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

class _UpdateProgressDialogState extends State<_UpdateProgressDialog>
    with WidgetsBindingObserver {
  bool _isDownloading = false;
  double _progress = 0.0;
  String _statusText = '';
  String? _downloadedApkPath;
  bool _isWaitingInstall = false;

  // 스토어 URL인지 일반 APK 다운로드 URL인지 판별
  bool get _isStoreUrl {
    final url = widget.apkUrl.trim().toLowerCase();
    return url.contains('play.google.com') || url.startsWith('market://');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isWaitingInstall) {
      setState(() {
        _isDownloading = false;
        _statusText = '보안 설정을 완료하셨다면 아래 버튼을 눌러 설치를 완료해 주세요.';
      });
    }
  }

  /// 구글 플레이스토어로 이동하는 함수
  Future<void> _launchStore() async {
    try {
      final uri = Uri.parse(widget.apkUrl.trim());
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        // 대체 market 스킴 시도
        final fallbackUri =
            Uri.parse('market://details?id=com.f2telecom.f2_material');
        await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      setState(() {
        _statusText = '스토어 이동 실패: 구글 플레이스토어 앱을 확인해 주세요.';
      });
    }
  }

  /// APK 저장 가능한 최적의 외부 공개 경로 탐색
  Future<String> _getApkSavePath() async {
    Directory? targetDir;
    if (Platform.isAndroid) {
      targetDir = await getExternalStorageDirectory();
    }
    targetDir ??= await getTemporaryDirectory();
    return '${targetDir.path}/F2자재_update.apk';
  }

  /// 다운로드 및 설치 실행 함수 (스토어 URL이면 스토어 실행, APK URL이면 기존 다운로드 실행)
  Future<void> _startDownloadAndInstall() async {
    if (_isStoreUrl) {
      await _launchStore();
      return;
    }

    final savePath = await _getApkSavePath();

    // 1. 이미 받아둔 파일이 온전히 존재하는 경우 재다운로드 없이 바로 설치 창 호출
    if (_downloadedApkPath != null &&
        await File(_downloadedApkPath!).exists()) {
      await _launchInstaller(_downloadedApkPath!);
      return;
    }

    // 2. 알 수 없는 앱 설치 권한 선제적 확인/요청
    if (Platform.isAndroid) {
      final status = await Permission.requestInstallPackages.status;
      if (!status.isGranted) {
        final reqResult = await Permission.requestInstallPackages.request();
        if (!reqResult.isGranted) {
          setState(() {
            _statusText = '안내: [출처를 알 수 없는 앱 설치] 권한을 허용해야 업데이트가 진행됩니다.';
            _isWaitingInstall = true;
          });
        }
      }
    }

    setState(() {
      _isDownloading = true;
      _isWaitingInstall = false;
      _progress = 0.0;
      _statusText = '최신 업데이트 파일 다운로드 중...';
    });

    try {
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
              _statusText =
                  '다운로드 중... ${(_progress * 100).toStringAsFixed(0)}%';
            });
          }
        },
      );

      _downloadedApkPath = savePath;
      await _launchInstaller(savePath);
    } catch (e) {
      setState(() {
        _statusText = '다운로드 실패: 네트워크 또는 저장공간을 확인해 주세요.';
        _isDownloading = false;
        _isWaitingInstall = false;
      });
    }
  }

  /// 패키지 인스톨러 호출 함수
  Future<void> _launchInstaller(String path) async {
    setState(() {
      _isDownloading = false;
      _isWaitingInstall = true;
      _statusText = '설치 관리자 실행 중...';
    });

    final file = File(path);
    if (!await file.exists()) {
      setState(() {
        _downloadedApkPath = null;
        _statusText = '파일을 찾을 수 없습니다. 다시 다운로드해 주세요.';
      });
      return;
    }

    final result = await OpenFilex.open(
      path,
      type: "application/vnd.android.package-archive",
    );

    if (result.type != ResultType.done) {
      setState(() {
        _statusText = '설치 창이 열리지 않을 경우, 갤럭시 [보안 위험 자동 차단]을 해제 후 다시 시도해 주세요.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.system_update_rounded,
              color: Color(0xFFA61C24), size: 28),
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
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Color(0xFFA61C24)),
                ),
                const SizedBox(height: 4),
                Text(widget.releaseNotes,
                    style:
                        const TextStyle(fontSize: 12, color: Colors.black87)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // 스토어 URL일 때는 번거로운 갤럭시 보안 차단 해제 안내 박스를 숨김 (스토어 설치는 보안 차단에 안 걸림)
          if (!_isStoreUrl)
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
                style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ] else if (_statusText.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              _statusText,
              style: TextStyle(
                fontSize: 12,
                color: _downloadedApkPath != null
                    ? const Color(0xFF1E88E5)
                    : Colors.red,
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
              backgroundColor: _downloadedApkPath != null
                  ? const Color(0xFFF39800)
                  : const Color(0xFFA61C24),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(
              _isDownloading
                  ? '다운로드 진행 중...'
                  : (_downloadedApkPath != null
                      ? '보안 설정 완료 후 설치 계속하기'
                      : (_isStoreUrl ? '스토어에서 업데이트' : '지금 바로 업데이트')),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
        ),
      ],
    );
  }
}
