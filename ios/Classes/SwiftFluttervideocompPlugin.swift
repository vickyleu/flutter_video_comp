import Flutter
import UIKit
import AVFoundation
import Regift

public class SwiftFluttervideocompPlugin: NSObject, FlutterPlugin {
    private let channelName = "fluttervideocomp"
    //    private var exporter: AVAssetExportSession? = nil
    private var stopCommand = false
    private let channel: FlutterMethodChannel
    private let avController = AvController()
    
    private var  lastSamplePresentationTime:CMTime?=nil
    
    private var reader:AVAssetReader?=nil
    private var videoOutput:AVAssetReaderVideoCompositionOutput?=nil
    private var audioOutput:AVAssetReaderAudioMixOutput?=nil
    private var writer:AVAssetWriter?=nil
    private var videoInput:AVAssetWriterInput?=nil
    private var videoPixelBufferAdaptor:AVAssetWriterInputPixelBufferAdaptor?=nil
    private var audioInput:AVAssetWriterInput?=nil
    private var  inputQueue:DispatchQueue?=nil
    
    init(channel: FlutterMethodChannel) {
        self.channel = channel
    }
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "fluttervideocomp", binaryMessenger: registrar.messenger())
        let instance = SwiftFluttervideocompPlugin(channel: channel)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? Dictionary<String, Any>
        switch call.method {
            case "getThumbnail":
                let path = args!["path"] as! String
                let quality = args!["quality"] as! NSNumber
                let position = args!["position"] as! NSNumber
                getThumbnail(path, quality, position, result)
            case "getThumbnailWithFile":
                let path = args!["path"] as! String
                let quality = args!["quality"] as! NSNumber
                let position = args!["position"] as! NSNumber
                getThumbnailWithFile(path, quality, position, result)
            case "getMediaInfo":
                let path = args!["path"] as! String
                getMediaInfo(path, result)
            case "compressVideo":
                let path = args!["path"] as! String
                let quality = args!["quality"] as! NSNumber
                let deleteOrigin = args!["deleteOrigin"] as! Bool
                let startTime = args!["startTime"] as? Double
                let duration = args!["duration"] as? Double
                let includeAudio = args!["includeAudio"] as? Bool
                let frameRate = args!["frameRate"] as? Int
                compressVideo(path, quality, deleteOrigin, startTime, duration, includeAudio,
                              frameRate, result)
            case "cancelCompression":
                cancelCompression(result)
            case "convertVideoToGif":
                let path = args!["path"] as! String
                let startTime = args!["startTime"] as! NSNumber
                let endTime = args!["endTime"] as! NSNumber
                let duration = args!["duration"] as! NSNumber
                convertVideoToGif(path, startTime, endTime, duration, result)
            case "deleteAllCache":
                Utility.deleteFile(Utility.basePath(), clear: true)
                result(true)
            default:
                result(FlutterMethodNotImplemented)
        }
    }
    
    private func getBitMap(_ path: String,_ quality: NSNumber,_ position: NSNumber,_ result: FlutterResult)-> Data?  {
        let url = Utility.getPathUrl(path)
        let asset = avController.getVideoAsset(url)
        guard let track = avController.getTrack(asset) else { return nil }
        
        let assetImgGenerate = AVAssetImageGenerator(asset: asset)
        assetImgGenerate.appliesPreferredTrackTransform = true
        
        let timeScale = CMTimeScale(track.nominalFrameRate)
        let time = CMTimeMakeWithSeconds(Float64(truncating: position),preferredTimescale: timeScale)
        guard let img = try? assetImgGenerate.copyCGImage(at:time, actualTime: nil) else {
            return nil
        }
        let thumbnail = UIImage(cgImage: img)
        let compressionQuality = CGFloat(0.01 * Double(truncating: quality))
        return thumbnail.jpegData(compressionQuality: compressionQuality)
    }
    
    private func getThumbnail(_ path: String,_ quality: NSNumber,_ position: NSNumber,_ result: FlutterResult) {
        if let bitmap = getBitMap(path,quality,position,result) {
            result(bitmap)
        }
    }
    
    private func getThumbnailWithFile(_ path: String,_ quality: NSNumber,_ position: NSNumber,_ result: FlutterResult) {
        let fileName = Utility.getFileName(path)
        let url = Utility.getPathUrl("\(Utility.basePath())/\(fileName).jpg")
        Utility.deleteFile(path)
        if let bitmap = getBitMap(path,quality,position,result) {
            guard (try? bitmap.write(to: url)) != nil else {
                return result(FlutterError(code: channelName,message: "getThumbnailWithFile error",details: "getThumbnailWithFile error"))
            }
            result(Utility.excludeFileProtocol(url.absoluteString))
        }
    }
    
    public func getMediaInfoJson(_ path: String)->[String : Any?] {
        let url = Utility.getPathUrl(path)
        let asset = avController.getVideoAsset(url)
        guard let track = avController.getTrack(asset) else { return [:] }
        
        let playerItem = AVPlayerItem(url: url)
        let metadataAsset = playerItem.asset
        
        let orientation = avController.getVideoOrientation(path)
        
        let title = avController.getMetaDataByTag(metadataAsset,key: "title")
        let author = avController.getMetaDataByTag(metadataAsset,key: "author")
        
        let duration = asset.duration.seconds * 1000
        let filesize = track.totalSampleDataLength
        
        let size = track.naturalSize.applying(track.preferredTransform)
        
        let width = abs(size.width)
        let height = abs(size.height)
        
        let dictionary = [
            "path":Utility.excludeFileProtocol(path),
            "title":title,
            "author":author,
            "width":width,
            "height":height,
            "duration":duration,
            "filesize":filesize,
            "orientation":orientation
            ] as [String : Any?]
        return dictionary
    }
    
    private func getMediaInfo(_ path: String,_ result: FlutterResult) {
        let json = getMediaInfoJson(path)
        let string = Utility.keyValueToJson(json)
        result(string)
    }
    
    
    @objc private func updateProgress(progress:Double) {
        if(!stopCommand) {
            channel.invokeMethod("updateProgress", arguments: "\(String(describing: progress * 100))")
        }
    }
    
    private func getExportPreset(_ quality: NSNumber)->String {
        switch(quality) {
            case 2:
                return AVAssetExportPresetMediumQuality
            case 3:
                //           return AVAssetExportPreset1280x720
                return AVAssetExportPresetHighestQuality
            default:
                return AVAssetExportPresetLowQuality
        }
    }
    
    private func getComposition(_ isIncludeAudio: Bool,_ timeRange: CMTimeRange, _ sourceVideoTrack: AVAssetTrack)->AVAsset {
        let composition = AVMutableComposition()
        if !isIncludeAudio {
            let compressionVideoTrack = composition.addMutableTrack(withMediaType: AVMediaType.video, preferredTrackID: kCMPersistentTrackID_Invalid)
            compressionVideoTrack!.preferredTransform = sourceVideoTrack.preferredTransform
            try? compressionVideoTrack!.insertTimeRange(timeRange, of: sourceVideoTrack, at: CMTime.zero)
        } else {
            return sourceVideoTrack.asset!
        }
        
        return composition
    }
    
    private func compressVideo(_ path: String,_ quality: NSNumber,_ deleteOrigin: Bool,_ startTime: Double?,
                               _ duration: Double?,_ includeAudio: Bool?,_ frameRate: Int?,
                               _ result: @escaping FlutterResult) {
        let sourceVideoUrl = Utility.getPathUrl(path)
        let sourceVideoType = sourceVideoUrl.pathExtension
        
        let compressionUrl =
            Utility.getPathUrl("\(Utility.basePath())/\(Utility.getFileName(path)).\(sourceVideoType)")
        
        let sourceVideoAsset = avController.getVideoAsset(sourceVideoUrl)
        //        let sourceVideoTrack = avController.getTrack(sourceVideoAsset)
        
        let videoSettings = [AVVideoCodecKey:AVVideoCodecH264,AVVideoCompressionPropertiesKey:[
            AVVideoAverageBitRateKey:6000000,
            AVVideoHeightKey:1920,
            AVVideoWidthKey:1080,
            AVVideoProfileLevelKey:AVVideoProfileLevelH264High40
            ]as [String : Any]] as [String : Any]
        let audioSettings = [AVFormatIDKey:kAudioFormatMPEG4AAC, AVNumberOfChannelsKey:2,
                             AVSampleRateKey:44100,
                             AVEncoderBitRateKey:128000
        ]
        
        
        let timescale = sourceVideoAsset.duration.timescale
        let minStartTime = Double(startTime ?? 0)
        
        let videoDuration = sourceVideoAsset.duration.seconds
        let minDuration = Double(duration ?? videoDuration)
        let maxDurationTime = minStartTime + minDuration < videoDuration ? minDuration : videoDuration
        
        let cmStartTime = CMTimeMakeWithSeconds(minStartTime, preferredTimescale: timescale)
        let cmDurationTime = CMTimeMakeWithSeconds(maxDurationTime, preferredTimescale: timescale)
        let timeRange: CMTimeRange = CMTimeRangeMake(start: cmStartTime, duration: cmDurationTime)
        
        let isIncludeAudio = includeAudio != nil ? includeAudio! : false
        
        let asset=AVAsset(url: sourceVideoUrl)
        
        do{
            self.reader=try AVAssetReader (asset: asset)
            
            self.writer=try AVAssetWriter(url: compressionUrl, fileType:.mp4)
            
            if !isIncludeAudio {
                self.reader?.timeRange = timeRange
            }else{
                self.reader?.timeRange = CMTimeRangeMake(start: CMTime.zero, duration: asset.duration)
            }
            
            self.writer?.shouldOptimizeForNetworkUse = true;
            let videoTracks=asset.tracks(withMediaType: .video)
            
            
            if (videoTracks.count > 0) {
                self.videoOutput = try AVAssetReaderVideoCompositionOutput(videoTracks: videoTracks, videoSettings:nil)
                self.videoOutput!.alwaysCopiesSampleData = false
                self.videoOutput!.videoComposition = buildDefaultVideoComposition(asset:asset,settings:videoSettings,frameRate:frameRate);
                if ((self.reader?.canAdd(self.videoOutput!)) != nil){
                    self.reader?.add(self.videoOutput!)
                }
                
                //
                // Video input
                //
                self.videoInput =  AVAssetWriterInput(mediaType: .video, outputSettings:videoSettings)
                
                self.videoInput?.expectsMediaDataInRealTime = false
                
                
                if (self.writer?.canAdd(self.videoInput!) != nil)
                {
                    self.writer?.add(self.audioInput!)
                }
                
                
                self.videoPixelBufferAdaptor=AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: self.audioInput!, sourcePixelBufferAttributes:[
                    kCVPixelBufferPixelFormatTypeKey: (kCVPixelFormatType_32BGRA),
                    kCVPixelBufferWidthKey: self.videoOutput!.videoComposition!.renderSize.width,
                    kCVPixelBufferHeightKey: self.videoOutput!.videoComposition!.renderSize.height,
                    "IOSurfaceOpenGLESTextureCompatibility": true,
                    "IOSurfaceOpenGLESFBOCompatibility": true] as! [String : Any])
                
                
            }
            
            if frameRate != nil {
                let videoComposition = AVMutableVideoComposition(propertiesOf: sourceVideoAsset)
                videoComposition.frameDuration = CMTimeMake(value: 1, timescale: Int32(frameRate!))
                self.videoOutput?.videoComposition = videoComposition
            }
            
            //
            //Audio output
            //
            let audioTracks = asset.tracks(withMediaType: .audio)
            if(audioTracks.count>0){
                self.audioOutput = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: nil)
                self.audioOutput?.alwaysCopiesSampleData=false
                self.audioOutput?.audioMix=nil
                if(self.reader?.canAdd(self.audioOutput!) != nil){
                    self.reader?.add(self.audioOutput!)
                }
            }else{
                self.audioOutput=nil
            }
            
            //
            // Audio input
            //
            if(self.audioOutput != nil){
                self.audioInput=AVAssetWriterInput(mediaType: .audio, outputSettings:audioSettings)
                self.audioInput?.expectsMediaDataInRealTime=false
                if(self.writer?.canAdd(self.audioInput!) != nil){
                    self.writer?.add(self.audioInput!)
                }
            }
            Utility.deleteFile(compressionUrl.absoluteString)
            self.writer?.startWriting()
            self.reader?.startReading()
            self.writer?.startSession(atSourceTime: timeRange.start)
            
            var videoCompleted = false;
            var audioCompleted = false;
            
            
            let completeBlock = {
                
                let fileManager = FileManager.default
                
                if(self.stopCommand) {
                    self.stopCommand = false
                    var json = self.getMediaInfoJson(path)
                    json["isCancel"] = true
                    let jsonString = Utility.keyValueToJson(json)
                    result(jsonString)
                    self.reader?.cancelReading()
                    self.writer?.cancelWriting()
                    return
                }
                if deleteOrigin {
                    do {
                        if fileManager.fileExists(atPath: path) {
                            try fileManager.removeItem(atPath: path)
                        }
                        
                        self.stopCommand = false
                    }
                    catch let error as NSError {
                        print(error)
                    }
                }
                
                
                var json = self.getMediaInfoJson(compressionUrl.absoluteString)
                json["isCancel"] = false
                
                print("视频压缩后大小",((fileManager.contents(atPath: compressionUrl.absoluteString))?.count ?? 0) / 1024 / 1024)
                
                let jsonString = Utility.keyValueToJson(json)
                result(jsonString)
                self.reader?.cancelReading()
                self.writer?.cancelWriting()
            }
            
            let finishBlock = {
                // Synchronized block to ensure we never cancel the writer before calling finishWritingWithCompletionHandler
                if (self.reader?.status == AVAssetReader.Status.cancelled || self.writer?.status == AVAssetWriter.Status.cancelled)
                {
                    return;
                }
                
                if (self.writer?.status == AVAssetWriter.Status.failed)
                {
                    completeBlock()
                }
                else if (self.reader?.status == AVAssetReader.Status.failed) {
                    
                    self.writer?.cancelWriting()
                    completeBlock()
                }
                else
                {
                    self.writer?.finishWriting(completionHandler: {
                        completeBlock()
                    })
                }
            }
            self.inputQueue = DispatchQueue(label: "VideoEncoderInputQueue", attributes: .concurrent)
            if (videoTracks.count > 0) {
                self.videoInput?.requestMediaDataWhenReady(on: self.inputQueue!, using: {
                    if (!(self.encodeReadySamplesFromOutput(output: self.videoOutput!, input: self.videoInput!, timeRange: self.reader!.timeRange)))
                    {
                        videoCompleted = true;
                        if (audioCompleted)
                        {
                            finishBlock()
                        }
                        
                    }
                })
                
            }
            else {
                videoCompleted = true;
            }
            
            if (self.audioOutput==nil) {
                audioCompleted = true;
            } else {
                self.audioInput?.requestMediaDataWhenReady(on: self.inputQueue!, using: {
                    if(self.encodeReadySamplesFromOutput(output: self.audioOutput!, input: self.audioInput!, timeRange: self.reader!.timeRange)){
                        audioCompleted = true;
                        if (videoCompleted)
                        {
                            finishBlock()
                        }
                    }
                    
                })
                
            }
        }catch let error as NSError{
            self.stopCommand = false
            var json = self.getMediaInfoJson(path)
            json["isCancel"] = true
            let jsonString = Utility.keyValueToJson(json)
            return result(jsonString)
        }
    }
    
    private func cancelCompression(_ result: FlutterResult) {
        self.reader?.cancelReading()
        self.writer?.cancelWriting()
        stopCommand = true
        result("")
    }
    
    private func convertVideoToGif(_ path: String,_ startTime: NSNumber,_ endTime: NSNumber, _ duration:NSNumber,
                                   _ result: FlutterResult) {
        let gifStartTime = Float(truncating: startTime)
        var gifDuration = Float(truncating: 0)
        
        if endTime as! Int > 0 {
            if startTime.intValue > endTime.intValue {
                result(FlutterError(code: channelName, message: "startTime should preceed endTime",
                                    details: nil))
            } else {
                gifDuration  = Float(Float(truncating: endTime) - gifStartTime)
            }
        } else {
            gifDuration = Float(truncating: duration)
        }
        
        let frameRate = Int(15)
        let loopCount = Int(0)
        
        let sourceFileURL = Utility.getPathUrl(path)
        let destinationUrl = Utility.getPathUrl("\(Utility.basePath())/\(Utility.getFileName(path)).gif")
        
        let trimmedRegift = Regift(sourceFileURL: sourceFileURL, destinationFileURL: destinationUrl,
                                   startTime: gifStartTime, duration: gifDuration, frameRate: frameRate,
                                   loopCount: loopCount, size: nil)
        
        let destinationPath = trimmedRegift.createGif();
        
        result(Utility.excludeFileProtocol(destinationPath!.absoluteString))
    }
    
    
    private func encodeReadySamplesFromOutput(output:AVAssetReaderOutput,input:AVAssetWriterInput,timeRange:CMTimeRange) -> Bool
    {
        while (input.isReadyForMoreMediaData)
        {
            var sampleBuffer=output.copyNextSampleBuffer()
            
            if (sampleBuffer != nil)
            {
                var handled = false;
                var error = false;
                if(self.reader?.status != AVAssetReader.Status.reading ||
                    self.writer?.status != AVAssetWriter.Status.writing
                    ){
                    handled = true;
                    error = true;
                }
                
                
                if (!handled && self.videoOutput == output)
                {
                    // update the video progress
                    lastSamplePresentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer!);
                    lastSamplePresentationTime = CMTimeSubtract(lastSamplePresentationTime!, timeRange.start);
                    
                    
                    let progress = CMTimeCompare(timeRange.duration, CMTime.zero)==0 ? 1 : CMTimeGetSeconds(lastSamplePresentationTime!).binade / CMTimeGetSeconds(timeRange.duration)
                    
                    
                    let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer!);
                    var renderBuffer:CVPixelBuffer? = nil;
                    CVPixelBufferPoolCreatePixelBuffer(nil, self.videoPixelBufferAdaptor!.pixelBufferPool!, &renderBuffer)
                    
                    updateProgress(progress: lastSamplePresentationTime!.seconds/timeRange.duration.seconds)
                    
                    if(!(self.videoPixelBufferAdaptor?.append(renderBuffer!, withPresentationTime: lastSamplePresentationTime!) ?? false)){
                        error = true;
                    }
                    
                    handled = true;
                    
                    
                }
                
                if (!handled && !input.append(sampleBuffer!))
                {
                    error = true;
                }
                if (error)
                {
                    return false;
                }
            }
            else
            {
                input.markAsFinished()
                return false;
            }
        }
        
        return true;
    }
    
    
    
    
    private func buildDefaultVideoComposition(asset:AVAsset,settings : [String:Any]? ,frameRate:Int?) -> AVMutableVideoComposition
    {
        
        let videoComposition = AVMutableVideoComposition();
        let videoTrack:AVAssetTrack =  asset.tracks(withMediaType: .video)[0]
        
        
        
        if(frameRate != nil){
            videoComposition.frameDuration = CMTimeMake(value: 1, timescale: Int32(frameRate!));
        }else{
            // get the frame rate from videoSettings, if not set then try to get it from the video track,
            // if not set (mainly when asset is AVComposition) then use the default frame rate of 30
            var trackFrameRate:Float = 0.0;
            
            if (settings != nil)
            {
                let videoCompressionProperties: [String:Any]? = settings?[AVVideoCompressionPropertiesKey] as! [String : Any]
                
                if (videoCompressionProperties != nil)
                {
                    let frameRate:Double? = videoCompressionProperties?[AVVideoAverageNonDroppableFrameRateKey] as? Double ;
                    
                    
                    if (frameRate != nil)
                    {
                        trackFrameRate = Float(frameRate ?? 0);
                    }
                }
            }
            else
            {
                trackFrameRate = videoTrack.nominalFrameRate
            }
            
            if (trackFrameRate == 0)
            {
                trackFrameRate = 30;
            }
            
            videoComposition.frameDuration = CMTimeMake(value: 1, timescale: Int32(trackFrameRate));
        }
       
        let targetSize = CGSize(width:CGFloat(settings?[AVVideoWidthKey] as? Float ?? 0), height: CGFloat(settings?[AVVideoHeightKey] as? Float ?? 0));
        
        
        
        var naturalSize = videoTrack.naturalSize
        var transform = videoTrack.preferredTransform;
        // Workaround radar 31928389, see https://github.com/rs/SDAVAssetExportSession/pull/70 for more info
        if (transform.ty == -560) {
            transform.ty = 0.0;
        }
        
        if (transform.tx == -560) {
            transform.tx = 0.0;
        }
        
        let videoAngleInDegree  = Float(atan2(transform.b, transform.a)) * 180.0 / .pi;
        if (videoAngleInDegree == 90 || videoAngleInDegree == -90) {
            let width = naturalSize.width;
            naturalSize.width = naturalSize.height;
            naturalSize.height = width;
        }
        videoComposition.renderSize = naturalSize;
        // center inside
        var ratio=0.0;
        let xratio = targetSize.width / naturalSize.width;
        let yratio = targetSize.height / naturalSize.height;
        ratio = Double(min(xratio, yratio));
        
        let postWidth = Float(naturalSize.width) * Float(ratio)
        let postHeight = Float(naturalSize.height) * Float(ratio)
        let transx = (Float(targetSize.width) - postWidth) / 2;
        let transy = (Float(targetSize.height) - postHeight) / 2;
        
        var matrix = CGAffineTransform(translationX: CGFloat(transx) / xratio, y: CGFloat(transy) / yratio);
        matrix = matrix.scaledBy(x: CGFloat(ratio) / xratio, y: CGFloat(ratio) / yratio);
        transform = transform.concatenating(matrix);
        
        
        
        // Make a "pass through video track" video composition.
        let passThroughInstruction = AVMutableVideoCompositionInstruction()
        
        passThroughInstruction.timeRange = CMTimeRangeMake(start: CMTime.zero, duration: asset.duration);
        
        let passThroughLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        passThroughLayer.setTransform(transform, at: CMTime.zero)
        
        passThroughInstruction.layerInstructions = [passThroughLayer];
        videoComposition.instructions = [passThroughInstruction];
        
        return videoComposition;
    }
    
    
    
    
    
    
}
