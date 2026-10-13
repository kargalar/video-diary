package app.videodiary

import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val recordingExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            RECORDING_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                AVAILABLE_CAMERA_LENSES -> {
                    try {
                        result.success(availableCameraLenses())
                    } catch (error: Exception) {
                        result.error(
                            "CAMERA_LENS_QUERY_FAILED",
                            error.message ?: "Available camera lenses could not be queried",
                            null,
                        )
                    }
                }
                MERGE_VIDEO_SEGMENTS -> mergeVideoSegments(call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun mergeVideoSegments(
        call: io.flutter.plugin.common.MethodCall,
        result: MethodChannel.Result,
    ) {
        val inputPaths = call.argument<List<String>>("inputs")
        val outputPath = call.argument<String>("outputPath")
        recordingExecutor.execute {
            try {
                requireNotNull(inputPaths) { "inputs are required" }
                requireNotNull(outputPath) { "outputPath is required" }
                VideoSegmentMerger().merge(inputPaths.map(::File), File(outputPath))
                mainHandler.post { result.success(null) }
            } catch (error: IllegalArgumentException) {
                mainHandler.post {
                    result.error(
                        "VIDEO_MERGE_INVALID_INPUT",
                        error.message,
                        null,
                    )
                }
            } catch (error: Exception) {
                mainHandler.post {
                    result.error(
                        "VIDEO_MERGE_FAILED",
                        error.message ?: "Video segments could not be merged",
                        null,
                    )
                }
            }
        }
    }

    private fun availableCameraLenses(): List<String> {
        val cameraManager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
        val lenses = linkedSetOf<String>()
        cameraManager.cameraIdList.forEach { cameraId ->
            when (
                cameraManager
                    .getCameraCharacteristics(cameraId)
                    .get(CameraCharacteristics.LENS_FACING)
            ) {
                CameraCharacteristics.LENS_FACING_FRONT -> lenses.add("front")
                CameraCharacteristics.LENS_FACING_BACK -> lenses.add("back")
            }
        }
        return lenses.toList()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        recordingExecutor.shutdown()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private companion object {
        const val RECORDING_CHANNEL = "app.videodiary/recording"
        const val MERGE_VIDEO_SEGMENTS = "mergeVideoSegments"
        const val AVAILABLE_CAMERA_LENSES = "availableCameraLenses"
    }
}
