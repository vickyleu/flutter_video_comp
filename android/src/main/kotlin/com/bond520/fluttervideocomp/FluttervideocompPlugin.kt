package com.bond520.fluttervideocomp

import androidx.annotation.NonNull;
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry.Registrar

/** FluttervideocompPlugin */
public class FluttervideocompPlugin: FlutterPlugin, MethodCallHandler {
  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    val channel = MethodChannel(flutterPluginBinding.getFlutterEngine().getDartExecutor(), "fluttervideocomp")
    channel.setMethodCallHandler(FluttervideocompPlugin());
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {

  }

  // This static function is optional and equivalent to onAttachedToEngine. It supports the old
  // pre-Flutter-1.12 Android projects. You are encouraged to continue supporting
  // plugin registration via this function while apps migrate to use the new Android APIs
  // post-flutter-1.12 via https://flutter.dev/go/android-project-migration.
  //
  // It is encouraged to share logic between onAttachedToEngine and registerWith to keep
  // them functionally equivalent. Only one of onAttachedToEngine or registerWith will be called
  // depending on the user's project. onAttachedToEngine or registerWith must both be defined
  // in the same class.

  private val channelName = "fluttervideocomp"
  private val utility = Utility(channelName)
  private var ffmpegCommander: FFmpegCommander? = null

  companion object {
    private lateinit var reg: Registrar
    @JvmStatic
    fun registerWith(registrar: Registrar) {
      val channel = MethodChannel(registrar.messenger(), "fluttervideocomp")
      channel.setMethodCallHandler(FluttervideocompPlugin())
      reg = registrar
    }
  }
  override fun onMethodCall(call: MethodCall, result: Result) {
    initFfmpegCommanderIfNeeded()
    when (call.method) {
      "getThumbnail" -> {
        val path = call.argument<String>("path")!!
        val quality = call.argument<Int>("quality")!!
        val position = call.argument<Int>("position")!!.toLong()
        ThumbnailUtility(channelName).getThumbnail(path, quality, position, result)
      }
      "getThumbnailWithFile" -> {
        val path = call.argument<String>("path")!!
        val quality = call.argument<Int>("quality")!!
        val position = call.argument<Int>("position")!!.toLong()
        val provider = call.argument<String>("provider")!!
        ThumbnailUtility(channelName).getThumbnailWithFile(FluttervideocompPlugin.reg.context(), path, quality,
                position, result)
      }
      "getMediaInfo" -> {
        val path = call.argument<String>("path")!!
        val provider = call.argument<String>("provider")
        result.success(utility.getMediaInfoJson(FluttervideocompPlugin.reg.context(), path, provider).toString())
      }
      "compressVideo" -> {
        val path = call.argument<String>("path")!!
        val quality = call.argument<Int>("quality")!!
        val deleteOrigin = call.argument<Boolean>("deleteOrigin")!!
        val startTime = call.argument<Int>("startTime")
        val duration = call.argument<Int>("duration")
        val includeAudio = call.argument<Boolean>("includeAudio")
        val frameRate = call.argument<Int>("frameRate")
        val provider = call.argument<String>("frameRate")

        ffmpegCommander?.compressVideo(path, VideoQuality.from(quality), deleteOrigin,
                startTime, duration, includeAudio, frameRate, result, FluttervideocompPlugin.reg.messenger(), provider)
      }
      "cancelCompression" -> {
        ffmpegCommander?.cancelCompression()
        result.success("")
      }
      "convertVideoToGif" -> {
        val path = call.argument<String>("path")!!
        val startTime = call.argument<Int>("startTime")!!.toLong()
        val endTime = call.argument<Int>("endTime")!!.toLong()
        val duration = call.argument<Int>("duration")!!.toLong()

        ffmpegCommander?.convertVideoToGif(path, startTime, endTime, duration, result,
                FluttervideocompPlugin.reg.messenger())
      }
      "deleteAllCache" -> {
        utility.deleteAllCache(FluttervideocompPlugin.reg.context(), result)
      }
      else -> result.notImplemented()
    }
  }

  private fun initFfmpegCommanderIfNeeded() {
    if (ffmpegCommander == null) {
      ffmpegCommander = FFmpegCommander(FluttervideocompPlugin.reg.context(), channelName)
    }
  }
}
