import 'dart:async';
import 'dart:ui_web' as ui;

import 'package:flutter/material.dart';
import 'package:universal_barcode_scanner/src/barcode_app_bar.dart';
import 'package:universal_barcode_scanner/src/barcode_view_controller.dart';
import 'package:universal_barcode_scanner/src/constants.dart';
import 'package:universal_barcode_scanner/src/enums.dart';
// ignore: avoid_web_libraries_in_flutter
import 'package:web/web.dart' as html;

/// Largest size the scanner iframe is given, in logical pixels. Below that it
/// takes the whole viewport.
const double _maxScannerWidth = 640;
const double _maxScannerHeight = 480;

/// Barcode scanner for web using iframe
class BarcodeScannerPage extends StatefulWidget {
  /// Colour of the scan line. Unused on web, the page draws its own.
  final Color lineColor;

  /// Label of the cancel button. Unused on web.
  final String cancelButtonText;

  /// Whether the torch toggle is shown. Unused on web.
  final bool isShowFlashIcon;

  /// What the scanner looks for. Unused on web, the page reads all formats.
  final ScanType scanType;

  /// Which camera to open. Unused on web.
  final CameraFace cameraFace;

  /// Called with every code read.
  final ValueChanged<String> onScanned;

  /// Drawn over the scanner.
  final Widget? child;

  /// App bar shown above the scanner, or null for none.
  final BarcodeAppBar? barcodeAppBar;

  /// Pause between two reads in continuous mode. Unused on web.
  final Duration? scanDelay;

  /// Whether the preview is mirrored.
  final bool flip;

  /// Called when the scanner closes.
  final VoidCallback? onClose;

  /// Symbologies to accept. Unused on web.
  final ScanFormat scanFormat;

  /// Creates the web scanner page.
  const BarcodeScannerPage({
    super.key,
    required this.lineColor,
    required this.cancelButtonText,
    required this.isShowFlashIcon,
    required this.scanType,
    this.cameraFace = CameraFace.back,
    required this.onScanned,
    this.child,
    this.barcodeAppBar,
    this.scanDelay,
    this.onClose,
    this.flip = false,
    this.scanFormat = ScanFormat.all,
  });

  @override
  State<BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<BarcodeScannerPage> {
  /// Registered once, in [initState]. Building it in `build` would register a
  /// new view factory and leak an iframe on every rebuild.
  late final String _viewId;
  late final html.HTMLIFrameElement _iframe;

  StreamSubscription<html.MessageEvent>? _messages;
  String? _barcode;

  @override
  void initState() {
    super.initState();

    _viewId =
        'universal_barcode_scanner_${DateTime.now().microsecondsSinceEpoch}';
    _iframe = html.HTMLIFrameElement()
      ..src = ScannerAsset.webPath
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%';

    ui.platformViewRegistry.registerViewFactory(
      _viewId,
      (int viewId) => _iframe,
    );

    _messages = html.window.onMessage.listen(_onMessage);
  }

  @override
  void dispose() {
    _messages?.cancel();
    super.dispose();
  }

  void _onMessage(html.MessageEvent event) {
    // The scanner page is served from our own origin, so anything posted from
    // elsewhere - another embedded frame, a browser extension - is not ours and
    // must not be taken for a scan.
    if (event.origin != html.window.location.origin) return;
    if (_barcode != null) return;

    final String data = event.data.toString();
    if (data.isEmpty) return;

    _barcode = data;
    widget.onScanned(data);
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.sizeOf(context);

    return Scaffold(
      appBar: _buildAppBar(context),
      body: Stack(
        children: <Widget>[
          Center(
            child: SizedBox(
              width: size.width > _maxScannerWidth
                  ? _maxScannerWidth
                  : size.width,
              height: size.height > _maxScannerHeight
                  ? _maxScannerHeight
                  : size.height,
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..rotateY(widget.flip ? 3.1416 : 0),
                child: HtmlElementView(viewType: _viewId),
              ),
            ),
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
      title: bar.appBarTitle != null
          ? Text(bar.appBarTitle!, style: const TextStyle(color: Colors.white))
          : null,
      centerTitle: bar.centerTitle ?? false,
      leading: bar.enableBackButton == true
          ? IconButton(
              onPressed: () => Navigator.pop(context),
              icon: bar.backButtonIcon ?? const Icon(Icons.arrow_back_ios),
            )
          : null,
      automaticallyImplyLeading: false,
    );
  }
}

/// Embedded scanner view on web.
///
/// Not implemented: the web scanner runs in an iframe, which only makes sense
/// as a whole page. Use [BarcodeScannerPage] there.
class BarcodeScannerView extends StatelessWidget {
  /// Creates the web embedded view.
  const BarcodeScannerView({
    super.key,
    required this.onBarcodeViewCreated,
    required this.onScanned,
    this.scannerWidth,
    this.scannerHeight,
    this.scanType = ScanType.barcode,
    this.cameraFace = CameraFace.back,
    this.continuous = false,
    this.child,
    this.scanDelay,
    this.flip = false,
    this.onClose,
    this.scanFormat = ScanFormat.all,
  });

  /// Called once the view exists.
  final BarcodeScannerViewCreated onBarcodeViewCreated;

  /// Width of the view.
  final double? scannerWidth;

  /// Height of the view.
  final double? scannerHeight;

  /// What the scanner looks for.
  final ScanType scanType;

  /// Which camera to open.
  final CameraFace cameraFace;

  /// Called with every code read.
  final ValueChanged<String>? onScanned;

  /// Drawn over the scanner.
  final Widget? child;

  /// Pause between two reads in continuous mode.
  final Duration? scanDelay;

  /// Whether the preview is mirrored.
  final bool flip;

  /// Called when the scanner closes.
  final VoidCallback? onClose;

  /// Whether reading continues after the first code.
  final bool continuous;

  /// Symbologies to accept.
  final ScanFormat scanFormat;

  @override
  Widget build(BuildContext context) =>
      const Center(child: Text('The embedded view is not available on web'));
}
