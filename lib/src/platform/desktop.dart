import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:universal_barcode_scanner/src/barcode_app_bar.dart';
import 'package:universal_barcode_scanner/src/constants.dart';
import 'package:universal_barcode_scanner/src/enums.dart';
import 'package:universal_barcode_scanner/src/scanner_chrome.dart';
import 'package:webview_all/webview_all.dart';

/// Name of the JavaScript channel the bundled page posts scans on. It has to
/// match the `CHANNEL` constant in `assets/barcode.html`.
const String _channelName = 'UniversalBarcodeScanner';

/// How long an idle webview is kept before it is let go.
const Duration _idleBeforeRelease = Duration(minutes: 1);

/// The webview kept between two scans, and what it costs to build it again:
/// starting the engine, loading the page and its script, and asking the user
/// for the camera. Reopening the scanner within [_idleBeforeRelease] reuses it
/// and only has to resume the page.
WebViewController? _kept;

/// Whether a page is currently showing [_kept]. A second scanner opened at the
/// same time builds its own rather than fighting over this one.
bool _keptInUse = false;

/// Where a scan read by [_kept] is delivered. The channel belongs to the
/// controller, so it outlives the page that opened it and has to be routed
/// rather than bound once.
void Function(String)? _keptListener;

/// Releases [_kept] once it has been idle long enough.
Timer? _keptRelease;

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
    this.backgroundColor,
  });

  /// Colour behind the camera. Black when null, which suits a scanner; pass
  /// your own when the page sits inside a lighter application.
  final Color? backgroundColor;

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

  /// Whether [_controller] is the shared one, and so has to be handed back
  /// rather than dropped.
  late final bool _shared;

  String? _barcode;

  @override
  void initState() {
    super.initState();

    _keptRelease?.cancel();
    _keptRelease = null;

    final WebViewController? kept = _kept;
    if (kept != null && !_keptInUse) {
      _controller = kept;
      _shared = true;
      _keptInUse = true;
      _keptListener = _onCode;
      // The page is still loaded, so `onPageFinished` will not fire again:
      // everything it would have done is done here instead.
      _applyColours();
      _controller.runJavaScript('resumeScanner()');
      return;
    }

    _controller = WebViewController(onPermissionRequest: _onPermissionRequest)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(_channelName, onMessageReceived: _onMessage)
      // The page is loaded from a file, so there is no query string to carry
      // the colour the way the web host does. It is set once the page is up.
      ..setNavigationDelegate(
        NavigationDelegate(onPageFinished: (String _) => _applyColours()),
      )
      ..loadFlutterAsset(ScannerAsset.desktopPath);

    _shared = kept == null;
    if (_shared) {
      _kept = _controller;
      _keptInUse = true;
      _keptListener = _onCode;
    }
  }

  @override
  void dispose() {
    // Releases the camera even when the route is left without going through
    // the app bar, a system gesture for instance.
    _controller.runJavaScript('stopScanner()');
    if (_shared) {
      _keptListener = null;
      _keptInUse = false;
      _keptRelease?.cancel();
      _keptRelease = Timer(_idleBeforeRelease, () {
        // `webview_all` exposes no way to dispose a controller, so dropping the
        // reference is all the host can do. Loading a blank page first at least
        // lets go of the scanner page and its script rather than leaving them
        // resident until the platform decides otherwise.
        _kept?.loadHtmlString('<!doctype html><title>.</title>');
        _kept = null;
        _keptRelease = null;
      });
    }
    super.dispose();
  }

  /// Delivers a code read by the shared controller to whichever page is open.
  void _onCode(String code) {
    if (code.isEmpty || _barcode != null) return;
    _barcode = code;
    widget.onScanned(code);
  }

  void _applyColours() {
    final String css = colorToCssHex(widget.lineColor);
    _controller.runJavaScript("setScanLineColor('$css')");
    final Color? background = widget.backgroundColor;
    if (background != null) {
      _controller.runJavaScript(
        "setBackgroundColor('${colorToCssHex(background)}')",
      );
    }
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

  /// Routed rather than bound: the channel belongs to the controller, which
  /// outlives the page that created it.
  void _onMessage(JavaScriptMessage message) {
    final void Function(String)? listener = _shared ? _keptListener : _onCode;
    listener?.call(message.message);
  }

  void _close() {
    _controller.runJavaScript('stopScanner()');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return ScannerChrome(
      backgroundColor: widget.backgroundColor,
      bar: widget.barcodeAppBar,
      onClose: _close,
      body: Stack(
        children: <Widget>[
          // Fills the space it is given. The framing is the page's job: sizing
          // the view to a box the page did not lay out for stretches its whole
          // overlay, since the library derives every dimension from the width
          // it measured itself.
          Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()..rotateY(widget.flip ? 3.1416 : 0),
            child: WebViewWidget(controller: _controller),
          ),
          if (widget.child != null) widget.child!,
        ],
      ),
    );
  }
}
