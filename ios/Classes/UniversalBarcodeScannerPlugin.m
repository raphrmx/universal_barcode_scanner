#import "UniversalBarcodeScannerPlugin.h"
#import <universal_barcode_scanner/universal_barcode_scanner-Swift.h>

@implementation UniversalBarcodeScannerPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftUniversalBarcodeScannerPlugin registerWithRegistrar:registrar];
}
@end
