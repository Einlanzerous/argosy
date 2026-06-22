package dev.dodson.argosy

import android.media.MediaCodecList
import android.media.MediaFormat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channel = "dev.dodson.argosy/capabilities"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Does this device have an HEVC (H.265) decoder that can
                    // handle true 4K? The server only hands back HEVC (vs. a
                    // re-encode to H.264 1080p) when the client advertises this,
                    // so it gates the 4K remux-copy path (ARGY-79).
                    "hevc4k" -> result.success(hasHevc4kDecoder())
                    else -> result.notImplemented()
                }
            }
    }

    private fun hasHevc4kDecoder(): Boolean {
        return try {
            val codecs = MediaCodecList(MediaCodecList.REGULAR_CODECS)
            codecs.codecInfos.any { info ->
                if (info.isEncoder) return@any false
                info.supportedTypes.any types@{ type ->
                    if (!type.equals(MediaFormat.MIMETYPE_VIDEO_HEVC, ignoreCase = true)) {
                        return@types false
                    }
                    val caps = info.getCapabilitiesForType(type)
                    val video = caps.videoCapabilities ?: return@types false
                    video.isSizeSupported(3840, 2160)
                }
            }
        } catch (_: Exception) {
            false
        }
    }
}
