import 'package:flutter/material.dart';
import 'package:universal_barcode_scanner/src/barcode_app_bar.dart';
import 'package:universal_barcode_scanner/src/constants.dart';
import 'package:universal_barcode_scanner/src/enums.dart';
import 'package:webview_all/webview_all.dart';

/// Name of the JavaScript channel the bundled page posts scans on. It has to
/// match the `CHANNEL` constant in `assets/barcode.html`.
const String _channelName = 'UniversalBarcodeScanner';

/// Scanner for the desktop platforms that have no native scanner: Windows and
/// Linux.
///
/// Both run the same bundled `html5-qrcode` page in a webview, WebView2 on
/// Windows and WebKitGTK on Linux, and both need the host to answer the
/// page's camera permission request.
class DesktopBarcodeScannerPage extends StatefulWidget {
  /// Creates the desktop scanner page.
  const DesktopBarcodeScannerPage({
    super.key,
    required this.onScanned,
    this.lineColor = kDefaultLineColor,
    this.cancelButtonText = 'Cancel',
    this.isShowFlashIcon = false,
    this.scanType = ScanType.barcode,
    this.cameraFace = CameraFace.back,
    this.child,
    this.barcodeAppBar,
    this.scanDelay,
    this.flip = false,
    this.onClose,
    this.scanFormat = ScanFormat.all,
  });

  /// Colour of the sweeping scan line.
  final Color lineColor;

  /// Label of the cancel button. Unused here.
  final String cancelButtonText;

  /// Whether the torch toggle is shown. Unused here.
  final bool isShowFlashIcon;

  /// What the scanner looks for. Unused here, the page reads every format.
  final ScanType scanType;

  /// Which camera to open. Unused here.
  final CameraFace cameraFace;

  /// Called with every code read.
  final ValueChanged<String> onScanned;

  /// Drawn over the scanner.
  final Widget? child;

  /// App bar shown above the scanner, or null for none.
  final BarcodeAppBar? barcodeAppBar;

  /// Pause between two reads in continuous mode. Unused here.
  final Duration? scanDelay;

  /// Whether the preview is mirrored.
  final bool flip;

  /// Called when the scanner closes.
  final VoidCallback? onClose;

  /// Symbologies to accept. Unused here.
  final ScanFormat scanFormat;

  @override
  State<DesktopBarcodeScannerPage> createState() =>
      _DesktopBarcodeScannerPageState();
}

class _DesktopBarcodeScannerPageState extends State<DesktopBarcodeScannerPage> {
  late final WebViewController _controller;
  String? _barcode;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController(onPermissionRequest: _onPermissionRequest)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(_channelName, onMessageReceived: _onMessage)
      // The page is loaded from a file, so there is no query string to carry
      // the colour the way the web host does. It is set once the page is up.
      ..setNavigationDelegate(
        NavigationDelegate(onPageFinished: (String _) => _applyLineColor()),
      )
      ..loadFlutterAsset(ScannerAsset.desktopPath);
  }

  @override
  void dispose() {
    // Releases the camera even when the route is left without going through
    // the app bar, a system gesture for instance.
    _controller.runJavaScript('stopScanner()');
    super.dispose();
  }

  void _applyLineColor() {
    final String css = colorToCssHex(widget.lineColor);
    _controller.runJavaScript("setScanLineColor('$css')");
  }

  /// The page we load is our own and asks for exactly one thing, so granting
  /// the camera here is not a blanket allow.
  void _onPermissionRequest(WebViewPermissionRequest request) {
    if (request.types.contains(WebViewPermissionResourceType.camera)) {
      request.grant();
    } else {
      request.deny();
    }
  }

  void _onMessage(JavaScriptMessage message) {
    final String code = message.message;
    if (code.isEmpty || _barcode != null) return;

    _barcode = code;
    widget.onScanned(code);
  }

  void _close() {
    _controller.runJavaScript('stopScanner()');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(context),
      body: Stack(
        children: <Widget>[
          // Left to fill the window, the webview stretches the camera across
          // the whole screen. Capped against the space actually available, not
          // against the window: the host may well embed the scanner in a
          // panel narrower than the window itself.
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double width = constraints.maxWidth > kMaxScannerWidth
                  ? kMaxScannerWidth
                  : constraints.maxWidth;
              final double height = constraints.maxHeight > kMaxScannerHeight
                  ? kMaxScannerHeight
                  : constraints.maxHeight;

              return Center(
                child: SizedBox(
                  width: width,
                  height: height,
                  child: Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..rotateY(widget.flip ? 3.1416 : 0),
                    child: WebViewWidget(controller: _controller),
                  ),
                ),
              );
            },
          ),
          if (widget.child != null) widget.child!,
        ],
      ),
    );
  }

  AppBar? _buildAppBar(BuildContext context) {
    final BarcodeAppBar? bar = widget.barcodeAppBar;
    if (bar == null) return null;

    return AppBar(
      title: bar.appBarTitle != null ? Text(bar.appBarTitle!) : null,
      centerTitle: bar.centerTitle ?? false,
      leading: bar.enableBackButton == true
          ? IconButton(
              onPressed: _close,
              icon: bar.backButtonIcon ?? const Icon(Icons.arrow_back_ios),
            )
          : null,
      automaticallyImplyLeading: false,
    );
  }
}
