import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:universal_barcode_scanner/src/barcode_app_bar.dart';
import 'package:universal_barcode_scanner/src/constants.dart';
import 'package:universal_barcode_scanner/src/enums.dart';
import 'package:webview_windows/webview_windows.dart';

class WindowsBarcodeScannerPage extends StatefulWidget {
  /// Colour of the scan line.
  final Color lineColor;

  /// Label of the cancel button.
  final String cancelButtonText;

  /// Whether the torch toggle is shown.
  final bool isShowFlashIcon;

  /// What the scanner looks for.
  final ScanType scanType;

  /// Which camera to open.
  final CameraFace cameraFace;

  /// Called with every code read.
  final ValueChanged<String> onScanned;

  /// App bar shown above the scanner, or null for none.
  final BarcodeAppBar? barcodeAppBar;

  /// Pause between two reads in continuous mode.
  final Duration? scanDelay;

  /// Whether the preview is mirrored.
  final bool flip;

  /// Called when the scanner closes.
  final VoidCallback? onClose;

  /// Creates the Windows scanner page.
  const WindowsBarcodeScannerPage({
    super.key,
    required this.lineColor,
    required this.cancelButtonText,
    required this.isShowFlashIcon,
    required this.scanType,
    this.cameraFace = CameraFace.back,
    required this.onScanned,
    this.barcodeAppBar,
    this.scanDelay,
    this.onClose,
    this.flip = false,
  });

  @override
  State<WindowsBarcodeScannerPage> createState() =>
      _WindowsBarcodeScannerPageState();
}

class _WindowsBarcodeScannerPageState extends State<WindowsBarcodeScannerPage> {
  final WebviewController _controller = WebviewController();

  /// Started once, in [initState]. Handing `FutureBuilder` a future built in
  /// `build` would reinitialise the webview and resubscribe to its messages on
  /// every rebuild, which delivers the same scan several times.
  late final Future<void> _ready = _initialise();

  StreamSubscription<dynamic>? _messages;

  /// Whether the viewer already allowed the camera during this scan. WebView2
  /// asks again on every navigation, and asking the user twice for the same
  /// camera is noise.
  bool _permissionGranted = false;
  String? _barcode;

  @override
  void dispose() {
    _messages?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _initialise() async {
    await _controller.initialize();
    await _controller.loadUrl(_assetFileUrl(ScannerAsset.desktopPath));

    _messages = _controller.webMessage.listen(_onWebMessage);
  }

  void _onWebMessage(dynamic event) {
    if (event is! Map) return;
    if (event['methodName'] != 'successCallback') return;

    final Object? data = event['data'];
    if (data is! String || data.isEmpty || _barcode != null) return;

    _barcode = data;
    widget.onScanned(data);
  }

  String _assetFileUrl(String asset) {
    final String path = p.join(
      p.dirname(Platform.resolvedExecutable),
      'data',
      'flutter_assets',
      asset,
    );
    return Uri.file(path).toString();
  }

  Future<WebviewPermissionDecision> _onPermissionRequested({
    required String url,
    required WebviewPermissionKind kind,
    required bool isUserInitiated,
    required BuildContext context,
  }) async {
    if (_permissionGranted) return WebviewPermissionDecision.allow;

    final WebviewPermissionDecision? decision =
        await showDialog<WebviewPermissionDecision>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: const Text('Permission requested'),
            content: Text(
              "'${kind.name}' permission is required to scan a barcode or "
              'QR code',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, WebviewPermissionDecision.deny),
                child: const Text('Deny'),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, WebviewPermissionDecision.allow),
                child: const Text('Allow'),
              ),
            ],
          ),
        );

    // Granting once is enough: the webview asks again on every navigation.
    if (decision == WebviewPermissionDecision.allow) _permissionGranted = true;

    return decision ?? WebviewPermissionDecision.none;
  }

  /// Tells the scanner page to stop the camera before the route goes away.
  void _close() {
    _controller.postWebMessage(json.encode(<String, String>{'event': 'close'}));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(context),
      body: FutureBuilder<void>(
        future: _ready,
        builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return Center(
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()..rotateY(widget.flip ? 3.1416 : 0),
              child: Webview(
                _controller,
                width: 640,
                height: 480,
                filterQuality: FilterQuality.high,
                permissionRequested:
                    (
                      String url,
                      WebviewPermissionKind kind,
                      bool isUserInitiated,
                    ) => _onPermissionRequested(
                      url: url,
                      kind: kind,
                      isUserInitiated: isUserInitiated,
                      context: context,
                    ),
              ),
            ),
          );
        },
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
