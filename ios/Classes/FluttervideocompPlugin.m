#import "FluttervideocompPlugin.h"

#import <fluttervideocomp/fluttervideocomp-Swift.h>

@implementation FluttervideocompPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftFluttervideocompPlugin registerWithRegistrar:registrar];
}
@end
