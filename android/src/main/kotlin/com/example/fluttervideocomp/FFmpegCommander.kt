package com.example.fluttervideocomp

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import nl.bravobit.ffmpeg.ExecuteBinaryResponseHandler
import nl.bravobit.ffmpeg.FFmpeg
import nl.bravobit.ffmpeg.FFtask
import java.io.File

class FFmpegCommander(private val context: Context, private val channelName: String) {
    private var stopCommand = false
    private var ffTask: FFtask? = null
    private val utility = Utility(channelName)
    private var totalTime: Long = 0


    fun compressVideo(path: String, quality: VideoQuality, deleteOrigin: Boolean,
                      startTime: Int?, duration: Int? = null, includeAudio: Boolean?,
                      frameRate: Int?, result: MethodChannel.Result,
                      messenger: BinaryMessenger, provider: String?) {

        val ffmpeg = FFmpeg.getInstance(context)

        if (!ffmpeg.isSupported) {
            android.util.Log.e("pathpath", "ffmpeg.isSupported==>" + ffmpeg.isSupported)
            return result.error(channelName, "FlutterVideoCompress Error",
                    "ffmpeg isn't supported this platform")
        }

        val dir = context.getExternalFilesDir("flutter_video_compress")
        if (dir != null && !dir.exists()) dir.mkdirs()

        val file = File(dir, path.substring(path.lastIndexOf("/")))
        utility.deleteFile(file)


        val scale = quality.getScaleString()
        val dm = context.resources.displayMetrics
        android.util.Log.e("pathpath", "path==>" + path + "  file.path=>" + file.path + "   dir=>" + dir?.path)
        val cmdArray = mutableListOf("-noautorotate", "-i", path, "-vcodec", "libx264", "-preset", "slow", "-crf", "28", "-y", "-movflags", "+faststart", "-vf",
                "scale=$scale:-2", "-b:v", "1000k")

//        ffmpeg -i MVI_7274.MOV -vcodec libx264 -preset fast -crf 20 -y -vf "scale=1920:-1" -acodec libmp3lame -ab 128k a.mp4

        //"ultrafast",
//        val cmdArray = mutableListOf("-noautorotate", "-i", path, "-vcodec", "h264", "-crf", "28", "-movflags", "+faststart", "-vf", "scale=$scale:-2", "-preset:v", "ultrafast", "-b:v", "1000k")

        // Add high bitrate for the highest quality
//        if (quality.isHighQuality()) {
//            cmdArray.addAll(listOf("-preset:v", "ultrafast", "-b:v", "1000k"))
//        }

        if (startTime != null) {
            cmdArray.add("-ss")
            cmdArray.add(startTime.toString())

            if (duration != null) {
                cmdArray.add("-t")
                cmdArray.add(duration.toString())
            }
        }

        if (includeAudio != null && !includeAudio) {
            cmdArray.add("-an")
        }

        if (frameRate != null) {
            cmdArray.add("-r")
            cmdArray.add(frameRate.toString())
        }

        cmdArray.add(" ${file.absolutePath}")

        this.ffTask = ffmpeg.execute(cmdArray.toTypedArray(),
                object : ExecuteBinaryResponseHandler() {
                    override fun onProgress(message: String) {
                        notifyProgress(message, messenger)

                        if (stopCommand) {
                            print("FlutterVideoCompress: Video compression has stopped")
                            stopCommand = false
                            val json = utility.getMediaInfoJson(context, path, provider)
                            json.put("isCancel", true)
                            result.success(json.toString())
                            totalTime = 0
                            ffTask?.killRunningProcess()
                        }
                    }

                    override fun onFinish() {
                        if(!file.exists()){
                            val json = utility.getMediaInfoJson(context, path, provider)
                            json.put("isCancel", false)
                            result.success(json.toString())
                        }else{
                            val json = utility.getMediaInfoJson(context, file.absolutePath, provider)
                            json.put("isCancel", false)
                            result.success(json.toString())
                            if (deleteOrigin) {
                                File(path).delete()
                            }
                        }

                        totalTime = 0
                    }
                })
    }

    private fun isLandscapeImage(orientation: Int) = orientation != 90 && orientation != 270


    private fun notifyProgress(message: String, messenger: BinaryMessenger) {
        if ("Duration" in message) {
            val reg = Regex("""Duration: ((\d{2}:){2}\d{2}\.\d{2}).*""")
            val totalTimeStr = message.replace(reg, "$1")
            totalTime = utility.timeStrToTimestamp(totalTimeStr.trim())
        }

        if ("frame=" in message) {
            try {
                val reg = Regex("""frame.*time=((\d{2}:){2}\d{2}\.\d{2}).*""")
                val totalTimeStr = message.replace(reg, "$1")
                val time = utility.timeStrToTimestamp(totalTimeStr.trim())
                MethodChannel(messenger, channelName)
                        .invokeMethod("updateProgress", ((time / totalTime) * 100).toString())
            } catch (e: Exception) {
                print(e.stackTrace)
            }
        }

        MethodChannel(messenger, channelName).invokeMethod("updateProgress", message)
    }

    fun cancelCompression() {
        if (ffTask != null && !ffTask!!.isProcessCompleted) {
            stopCommand = true
        }
    }
}