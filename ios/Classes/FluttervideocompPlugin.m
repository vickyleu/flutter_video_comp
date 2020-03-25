#import "FluttervideocompPlugin.h"

#import <flutter_video_comp/fluttervideocomp-Swift.h>

@implementation FluttervideocompPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftFluttervideocompPlugin registerWithRegistrar:registrar];
}
@end
