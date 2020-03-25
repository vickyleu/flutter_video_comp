#import "FluttervideocompPlugin.h"

#import <flutter_video_comp/flutter_video_comp-Swift.h>

@implementation FluttervideocompPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftFluttervideocompPlugin registerWithRegistrar:registrar];
}
@end
