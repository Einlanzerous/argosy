package dev.dodson.argosy

import android.Manifest
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.app.UiModeManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.drawable.Icon
import android.media.MediaCodecList
import android.media.MediaFormat
import android.os.Build
import android.os.Bundle
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

    // Mirrors the player's play/pause state so the PiP action shows the right
    // icon. Pushed from Dart via `setPlaying`.
    private var isPlaying = true
    private var pip: MethodChannel? = null

    // Receives taps on the PiP play/pause RemoteAction and forwards them to Dart.
    private val pipReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == ACTION_PIP_TOGGLE) {
                pip?.invokeMethod("pipAction", "toggle")
            }
        }
    }

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
                    // Is this a TV / leanback device? Drives the 10-foot UI +
                    // D-pad shell (ARGY-51). Primary signal is the UI mode; the
                    // leanback/television features are a belt-and-suspenders
                    // fallback for boxes that under-report the mode.
                    "isTelevision" -> result.success(isTelevision())
                    else -> result.notImplemented()
                }
            }

        pip = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, pipChannel)
        pip!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> result.success(isPipSupported())
                "setActive" -> {
                    playbackActive = call.arguments == true
                    // Arm (or disarm) auto-enter PiP now, so the system floats the
                    // video when the user leaves — including the swipe-up-to-home
                    // gesture, which doesn't reliably fire onUserLeaveHint.
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        runCatching { setPictureInPictureParams(buildPipParams()) }
                    }
                    result.success(null)
                }
                "setPlaying" -> {
                    isPlaying = call.arguments == true
                    // Refresh the PiP action icon (play <-> pause) live while floating.
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                        isInPictureInPictureMode
                    ) {
                        runCatching { setPictureInPictureParams(buildPipParams()) }
                    }
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

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val filter = IntentFilter(ACTION_PIP_TOGGLE)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(pipReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            // Android 13+ gates the media-playback foreground-service notification
            // (lock-screen / shade transport controls) behind this runtime grant.
            if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED
            ) {
                requestPermissions(
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    REQUEST_NOTIFICATIONS,
                )
            }
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(pipReceiver, filter)
        }
    }

    override fun onDestroy() {
        runCatching { unregisterReceiver(pipReceiver) }
        super.onDestroy()
    }

    private fun isPipSupported(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    private fun enterPip() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            enterPictureInPictureMode(buildPipParams())
        } catch (_: Exception) {
            // Some OEMs reject PiP (e.g. disabled by user/policy); ignore.
        }
    }

    // 16:9 window with a single play/pause RemoteAction. The system PiP UI adds
    // the expand-to-fullscreen and close affordances itself, giving the expected
    // three controls (ARGY-50). On Android 12+ auto-enter floats the video when
    // the app is backgrounded (reliable under gesture nav, unlike onUserLeaveHint).
    private fun buildPipParams(): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder().setAspectRatio(Rational(16, 9))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            builder.setActions(listOf(playPauseAction()))
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(playbackActive)
            builder.setSeamlessResizeEnabled(true)
        }
        return builder.build()
    }

    private fun playPauseAction(): RemoteAction {
        val iconRes =
            if (isPlaying) android.R.drawable.ic_media_pause
            else android.R.drawable.ic_media_play
        val label = if (isPlaying) "Pause" else "Play"
        val intent = Intent(ACTION_PIP_TOGGLE).setPackage(packageName)
        val pending = PendingIntent.getBroadcast(
            this,
            REQUEST_PIP_TOGGLE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return RemoteAction(Icon.createWithResource(this, iconRes), label, label, pending)
    }

    // Pre-Android-12 fallback: float the video on home/recents. On 12+ the
    // auto-enter param handles this (and covers the swipe-up-to-home gesture).
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S &&
            playbackActive && isPipSupported()
        ) {
            enterPip()
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pip?.invokeMethod("pipChanged", isInPictureInPictureMode)
    }

    private fun isTelevision(): Boolean {
        val uiMode = getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
        if (uiMode?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION) return true
        return packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK) ||
            packageManager.hasSystemFeature(PackageManager.FEATURE_TELEVISION)
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

    companion object {
        private const val ACTION_PIP_TOGGLE = "dev.dodson.argosy.PIP_TOGGLE"
        private const val REQUEST_PIP_TOGGLE = 1001
        private const val REQUEST_NOTIFICATIONS = 1002
    }
}
