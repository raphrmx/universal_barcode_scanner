import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:universal_barcode_scanner/src/barcode_app_bar.dart';
import 'package:universal_barcode_scanner/src/constants.dart';
import 'package:universal_barcode_scanner/src/scanner_chrome.dart';
import 'package:universal_barcode_scanner/src/scanner_config.dart';
import 'package:webview_all/webview_all.dart';

/// Name of the JavaScript channel the bundled page posts scans on. It has to
/// match the `CHANNEL` constant in `assets/barcode.html`.
const String _channelName = 'UniversalBarcodeScanner';

/// How long an idle webview is kept before it is let go.
const Duration _idleBeforeRelease = Duration(minutes: 1);

/// What an unused webview is left showing: no script, no camera.
const String _blankPage = '<!doctype html><title>.</title>';

/// A webview and the page showing it, if any.
///
/// The page never starts the camera on its own: it waits for `configure`,
/// which only the page on screen sends. A scanner closed before its webview
/// finished loading therefore never lights the camera up behind it.
class _Webview {
  _Webview() {
    controller = WebViewController(onPermissionRequest: _grantCamera)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        _channelName,
        onMessageReceived: (JavaScriptMessage message) =>
            owner?._onMessage(message.message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String _) {
            if (loaded || released) return;
            loaded = true;
            owner?._configure();
          },
        ),
      )
      ..loadFlutterAsset(ScannerAsset.desktopPath);
  }

  late final WebViewController controller;

  /// Whether the scanner page is up and can take `configure`.
  bool loaded = false;

  /// Whether the webview has been let go. It still finishes loading the blank
  /// page it was left with, which must not count as the scanner page.
  bool released = false;

  /// The page currently showing this webview.
  _DesktopBarcodeScannerPageState? owner;

  Timer? release;

  Future<void> run(String script) async {
    try {
      await controller.runJavaScript(script);
    } on Object {
      // The page is not up yet, or has gone: nothing to stop or start.
    }
  }

  void letGo() {
    released = true;
    owner = null;
    unawaited(controller.loadHtmlString(_blankPage));
  }

  /// The page we load is our own and asks for exactly one thing, so granting
  /// the camera here is not a blanket allow.
  static void _grantCamera(WebViewPermissionRequest request) {
    if (request.types.contains(WebViewPermissionResourceType.camera)) {
      request.grant();
    } else {
      request.deny();
    }
  }
}

/// The webview kept between two scans, and what it costs to build it again:
/// starting the engine, loading the page and its script, and asking the user
/// for the camera. Reopening the scanner within [_idleBeforeRelease] reuses it.
_Webview? _kept;

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
    required this.config,
    required this.onScanned,
    required this.onClose,
    this.child,
    this.barcodeAppBar,
    this.flip = false,
    this.backgroundColor,
  });

  /// What to scan and how.
  final ScannerConfig config;

  /// Called with every code read.
  final ValueChanged<String> onScanned;

  /// Called by the back button.
  final VoidCallback onClose;

  /// Drawn over the scanner.
  final Widget? child;

  /// App bar shown above the scanner, or null for none.
  final BarcodeAppBar? barcodeAppBar;

  /// Whether the preview is mirrored.
  final bool flip;

  /// Colour behind the camera. Black when null.
  final Color? backgroundColor;

  @override
  State<DesktopBarcodeScannerPage> createState() =>
      _DesktopBarcodeScannerPageState();
}

class _DesktopBarcodeScannerPageState extends State<DesktopBarcodeScannerPage> {
  late final _Webview _webview;

  /// Whether [_webview] is the kept one, handed back rather than let go.
  late final bool _shared;

  /// Set on the first code of a single scan, so a second one is ignored.
  bool _delivered = false;

  @override
  void initState() {
    super.initState();

    final _Webview kept = _kept ??= _Webview();
    if (kept.owner == null) {
      kept.release?.cancel();
      kept.release = null;
      _webview = kept;
      _shared = true;
    } else {
      // Another scanner is on screen with the kept one.
      _webview = _Webview();
      _shared = false;
    }

    _webview.owner = this;
    if (_webview.loaded) _configure();
  }

  @override
  void dispose() {
    final _Webview webview = _webview;
    webview.owner = null;
    unawaited(webview.run('stopScanner()'));

    if (_shared) {
      webview.release = Timer(_idleBeforeRelease, () {
        if (!identical(_kept, webview) || webview.owner != null) return;
        // `webview_all` cannot dispose a controller, so the page is blanked
        // and the reference dropped.
        webview.letGo();
        _kept = null;
      });
    } else {
      webview.letGo();
    }
    super.dispose();
  }

  /// Hands the page its settings, which also starts the camera.
  void _configure() {
    final Map<String, String> settings = widget.config.toPage(
      host: 'desktop',
      background: widget.backgroundColor,
    );
    unawaited(_webview.run('configure(${jsonEncode(settings)})'));
  }

  void _onMessage(String data) {
    if (!mounted) return;
    switch (PageMessage.parse(data)) {
      case PageCode(:final String code):
        if (!widget.config.continuous) {
          if (_delivered) return;
          _delivered = true;
        }
        widget.onScanned(code);
      case PageClose():
        _close();
      case null:
        break;
    }
  }

  void _close() {
    unawaited(_webview.run('stopScanner()'));
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget view = WebViewWidget(controller: _webview.controller);
    return ScannerChrome(
      backgroundColor: widget.backgroundColor,
      bar: widget.barcodeAppBar,
      onClose: _close,
      body: Stack(
        children: <Widget>[
          // The page sizes its overlay from the width it measures itself, so
          // the view is mirrored and never resized.
          if (widget.flip)
            Transform(
              alignment: Alignment.center,
              transform: Matrix4.diagonal3Values(-1, 1, 1),
              child: view,
            )
          else
            view,
          ?widget.child,
        ],
      ),
    );
  }
}
