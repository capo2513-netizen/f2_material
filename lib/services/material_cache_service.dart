import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MaterialCacheService {
  static const String _syncKey = 'last_materials_sync_timestamp';
  static const String _fileName = 'materials_cache.json';

  // 1. 로컬 캐시 파일 경로 획득
  static Future<File> _getLocalFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  // 2. 스마트폰 로컬 저장소에서 자재 목록 즉시 로드 (읽기 비용: 0회)
  static Future<List<Map<String, dynamic>>> loadLocalMaterials() async {
    try {
      final file = await _getLocalFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          final List<dynamic> decoded = jsonDecode(content);
          return decoded.map((e) => Map<String, dynamic>.from(e)).toList();
        }
      }
    } catch (e) {
      // 로컬 파일 읽기 실패 시 빈 리스트 반환
    }
    return [];
  }

  // 3. 자재 목록을 로컬 파일에 영구 저장
  static Future<void> saveLocalMaterials(
      List<Map<String, dynamic>> materials) async {
    try {
      final file = await _getLocalFile();
      await file.writeAsString(jsonEncode(materials));
    } catch (_) {}
  }

  // 4. [증분 동기화 코어] 변경된 자재 문서만 Firestore에서 가져오기
  // - 로컬 데이터가 없으면: 최초 1회 전체 로드
  // - 로컬 데이터가 있으면: 마지막 동기화 시간 이후에 '수정된 문서'만 로드 (읽기 2~3회 수준)
  static Future<List<Map<String, dynamic>>> syncIncrementalMaterials() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSyncMillis = prefs.getInt(_syncKey) ?? 0;

    List<Map<String, dynamic>> localList = await loadLocalMaterials();
    final materialsRef = FirebaseFirestore.instance.collection('materials');

    final nowSyncMillis = DateTime.now().millisecondsSinceEpoch;

    if (localList.isEmpty || lastSyncMillis == 0) {
      // 최초 실행: 전체 문서 1회 수신
      final snap = await materialsRef.get();
      localList = snap.docs.map((doc) {
        final data = doc.data();
        data['docId'] = doc.id;
        return data;
      }).toList();
    } else {
      // 2회차 이후: 마지막 동기화 이후 변경된 자재만 읽기 (읽기 극소량 발생)
      final lastSyncDate = DateTime.fromMillisecondsSinceEpoch(lastSyncMillis);
      final lastTimestamp = Timestamp.fromDate(lastSyncDate);

      final snap = await materialsRef
          .where('updatedAt', isGreaterThan: lastTimestamp)
          .get();

      if (snap.docs.isNotEmpty) {
        for (var doc in snap.docs) {
          final updatedData = doc.data();
          updatedData['docId'] = doc.id;

          final idx = localList.indexWhere((m) => m['docId'] == doc.id);
          if (idx >= 0) {
            localList[idx] = updatedData; // 기존 자재 최신화
          } else {
            localList.add(updatedData); // 신규 자재 추가
          }
        }
      }
    }

    // 최신 데이터를 로컬 파일에 저장하고 동기화 시간 갱신
    await saveLocalMaterials(localList);
    await prefs.setInt(_syncKey, nowSyncMillis);

    return localList;
  }

  // 5. 사용자가 입출고/반납 확정한 품목만 로컬 재고에 즉시 증감 반영
  static Future<void> updateLocalStock(List<Map<String, dynamic>> currentList,
      String warehouse, String materialCode, int deltaQty) async {
    final idx = currentList.indexWhere((m) {
      final wh = (m['warehouse'] ?? '').toString().trim();
      final code = (m['materialCode'] ?? m['F2자재코드'] ?? m['docId'] ?? '')
          .toString()
          .trim();
      return wh == warehouse && code == materialCode;
    });

    if (idx >= 0) {
      final rawStock =
          currentList[idx]['currentStock'] ?? currentList[idx]['현재고'] ?? 0;
      final int cur = rawStock is num
          ? rawStock.toInt()
          : (int.tryParse(rawStock.toString()) ?? 0);
      currentList[idx]['currentStock'] = cur + deltaQty;
      currentList[idx]['현재고'] = cur + deltaQty;
      await saveLocalMaterials(currentList);
    }
  }

  // 6. 강제 전체 초기화 동기화 (필요 시 전체 재다운로드)
  static Future<List<Map<String, dynamic>>> forceFullRefresh() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_syncKey);
    return await syncIncrementalMaterials();
  }
}
