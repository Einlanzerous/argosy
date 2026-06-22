package dev.dodson.argosy

import android.app.PictureInPictureParams
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.media.MediaCodecList
import android.media.MediaFormat
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channel = "dev.dodson.argosy/capabilities"
    private val pipChannel = "dev.dodson.argosy/pip"

    // Set by Dart while a player screen is foregrounded with active playback;
    // gates auto-enter-PiP on leave so we never shrink the browse UI.
    private var playbackActive = false
    private var pip: MethodChannel? = null

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

        pip = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, pipChannel)
        pip!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> result.success(isPipSupported())
                "setActive" -> {
                    playbackActive = call.arguments == true
                    result.success(null)
                }
                "enter" -> {
                    enterPip()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isPipSupported(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    private fun enterPip() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(Rational(16, 9))
                .build()
            enterPictureInPictureMode(params)
        } catch (_: Exception) {
            // Some OEMs reject PiP (e.g. disabled by user/policy); ignore.
        }
    }

    // Press-home / recents while playing → float the video instead of pausing.
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (playbackActive && isPipSupported()) enterPip()
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pip?.invokeMethod("pipChanged", isInPictureInPictureMode)
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
