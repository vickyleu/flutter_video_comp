package com.bond520.fluttervideocomp

import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

public class FluttervideocompPlugin : FlutterPlugin, ActivityAware, MethodCallHandler {
    private var binding: ActivityPluginBinding? = null
    private var binding2: FlutterPlugin.FlutterPluginBinding? = null
    private var channel: MethodChannel? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        Log.e("FluttervideocompPlugin","onAttachedToEngine")
        if(this.binding2==null){
            this.binding2 = flutterPluginBinding
            this.channel = MethodChannel(flutterPluginBinding.binaryMessenger, channelName)
            this.channel?.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(plugin: FlutterPlugin.FlutterPluginBinding) {
        Log.e("FluttervideocompPlugin","onDetachedFromEngine")
        if(this.channel!=null){
            this.channel?.setMethodCallHandler(null)
        }
        this.channel = null
        this.binding2 = null
    }

    override fun onDetachedFromActivity() {
    }

    override fun onReattachedToActivityForConfigChanges(plugin: ActivityPluginBinding) {
        onAttachedToActivity(plugin)
    }

    override fun onAttachedToActivity(plugin: ActivityPluginBinding) {
        Log.e("FluttervideocompPlugin","onAttachedToActivity")
        if(this.binding==null){
            this.binding = plugin
        }
    }

    override fun onDetachedFromActivityForConfigChanges() {
        Log.e("FluttervideocompPlugin","onDetachedFromActivityForConfigChanges")
        this.binding = null
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


    override fun onMethodCall(call: MethodCall, result: Result) {
        Log.e("FluttervideocompPlugin","onMethodCall")
        if (binding == null || binding2 == null) {
            android.util.Log.e("pathpath", "binding==>${binding}  ${binding2}")
            result.success("")
            return
        }
        val binding = this.binding!!
        val binding2 = this.binding2!!
        initFfmpegCommanderIfNeeded(binding)
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
                ThumbnailUtility(channelName).getThumbnailWithFile(binding.activity, path, quality,
                        position, result)
            }
            "getMediaInfo" -> {
                val path = call.argument<String>("path")!!
                val provider = call.argument<String>("provider")
                result.success(utility.getMediaInfoJson(binding.activity, path, provider).toString())
            }
            "compressVideo" -> {
                val path = call.argument<String>("path")!!
                val quality = call.argument<Int>("quality")!!
                val deleteOrigin = call.argument<Boolean>("deleteOrigin")!!
                val startTime = call.argument<Int>("startTime")
                val duration = call.argument<Int>("duration")
                val includeAudio = call.argument<Boolean>("includeAudio")
                val frameRate = call.argument<Int>("frameRate")
                val provider = call.argument<String>("provider")

                ffmpegCommander?.compressVideo(path, VideoQuality.from(quality), deleteOrigin,
                        startTime, duration, includeAudio, frameRate, result, binding2.binaryMessenger, provider)
            }
            "cancelCompression" -> {
                ffmpegCommander?.cancelCompression()
                result.success("")
            }
            "deleteAllCache" -> {
                utility.deleteAllCache(binding.activity, result)
            }
            else -> result.notImplemented()
        }
    }

    private fun initFfmpegCommanderIfNeeded(binding: ActivityPluginBinding) {
        if (ffmpegCommander == null) {
            ffmpegCommander = FFmpegCommander(binding.activity, channelName)
        }
    }


}
