package com.example.educational_platform

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Context
import android.app.Activity
import android.content.Intent
import android.media.MediaRecorder
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.hardware.display.VirtualDisplay
import android.os.Environment
import android.util.DisplayMetrics
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class MainActivity : FlutterActivity() {

    private val CHANNEL = "local_recording"
    private val REQUEST_CODE_SCREEN_CAPTURE = 1001

    private var methodResult: MethodChannel.Result? = null

    private var mediaProjectionManager: MediaProjectionManager? = null
    private var mediaProjection: MediaProjection? = null
    private var mediaRecorder: MediaRecorder? = null
    private var virtualDisplay: VirtualDisplay? = null

    private var videoWidth = 720
    private var videoHeight = 1280
    private var videoDpi = 320
    private var outputPath: String? = null
    private var isRecording: Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startLocalRecording" -> {
                    if (isRecording) {
                        result.error("already_recording", "Recording already in progress", null)
                        return@setMethodCallHandler
                    }
                    methodResult = result
                    startScreenCaptureRequest()
                }
                "stopLocalRecording" -> {
                    val path = stopRecordingInternal()
                    result.success(path ?: "")
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startScreenCaptureRequest() {
        mediaProjectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager

        // Determine screen metrics for proper sizing
        val metrics: DisplayMetrics = resources.displayMetrics
        videoWidth = metrics.widthPixels
        videoHeight = metrics.heightPixels
        videoDpi = metrics.densityDpi

        val intent = mediaProjectionManager?.createScreenCaptureIntent()
        @Suppress("DEPRECATION")
        run {
            startActivityForResult(intent, REQUEST_CODE_SCREEN_CAPTURE)
        }
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_CODE_SCREEN_CAPTURE) {
            if (resultCode == Activity.RESULT_OK && data != null) {
                mediaProjection = mediaProjectionManager?.getMediaProjection(resultCode, data)
                try {
                    startRecordingInternal()
                    methodResult?.success(true)
                } catch (e: Exception) {
                    methodResult?.error("start_failed", e.message, null)
                } finally {
                    methodResult = null
                }
            } else {
                methodResult?.error("user_cancelled", "User cancelled screen capture permission", null)
                methodResult = null
            }
        }
    }

    private fun buildOutputFilePath(): String {
        val dir = getExternalFilesDir(Environment.DIRECTORY_MOVIES) ?: filesDir
        val sdf = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.getDefault())
        val name = "local_recording_${sdf.format(Date())}.mp4"
        return File(dir, name).absolutePath
    }

    private fun initMediaRecorder() {
        val recorder = MediaRecorder()
        // Microphone only for audio per user request
        recorder.setAudioSource(MediaRecorder.AudioSource.MIC)
        recorder.setVideoSource(MediaRecorder.VideoSource.SURFACE)
        recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
        outputPath = buildOutputFilePath()
        recorder.setOutputFile(outputPath)
        recorder.setVideoEncoder(MediaRecorder.VideoEncoder.H264)
        recorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
        recorder.setVideoEncodingBitRate(5_000_000)
        recorder.setVideoFrameRate(30)
        recorder.setVideoSize(videoWidth, videoHeight)
        recorder.prepare()
        mediaRecorder = recorder
    }

    private fun startRecordingInternal() {
        if (mediaProjection == null) throw IllegalStateException("MediaProjection is null")
        initMediaRecorder()
        val surface = mediaRecorder!!.surface
        virtualDisplay = mediaProjection!!.createVirtualDisplay(
            "LocalScreenRecord",
            videoWidth,
            videoHeight,
            videoDpi,
            0,
            surface,
            null,
            null
        )
        mediaRecorder!!.start()
        isRecording = true
    }

    private fun stopRecordingInternal(): String? {
        return try {
            if (isRecording) {
                try { mediaRecorder?.stop() } catch (_: Exception) {}
                mediaRecorder?.reset()
            }
            mediaRecorder?.release()
            mediaRecorder = null
            virtualDisplay?.release()
            virtualDisplay = null
            mediaProjection?.stop()
            mediaProjection = null
            val path = outputPath
            outputPath = null
            isRecording = false
            path
        } catch (e: Exception) {
            isRecording = false
            outputPath = null
            null
        }
    }
}
