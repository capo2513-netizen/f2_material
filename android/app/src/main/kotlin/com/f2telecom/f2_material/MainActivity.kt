package com.f2telecom.f2_material // 본인의 실제 패키지명 유지

import android.media.AudioManager
import android.media.ToneGenerator
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "f2_material/beep"
    private var toneGen: ToneGenerator? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 미디어/알림 스트림으로 최대 볼륨(100) 비프음 엔진 생성
        try {
            toneGen = ToneGenerator(AudioManager.STREAM_MUSIC, 100)
        } catch (e: Exception) {
            toneGen = ToneGenerator(AudioManager.STREAM_SYSTEM, 100)
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "playBeep") {
                try {
                    // TONE_PROP_BEEP: 물류/바코드 스캐너 표준 비프음 (0.15초)
                    toneGen?.startTone(ToneGenerator.TONE_PROP_BEEP, 150)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("UNAVAILABLE", "Tone generation failed", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}