import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:universal_barcode_scanner/src/barcode_app_bar.dart';
import 'package:universal_barcode_scanner/src/barcode_view_controller.dart';
import 'package:universal_barcode_scanner/src/constants.dart';
import 'package:universal_barcode_scanner/src/scanner_chrome.dart';
import 'package:universal_barcode_scanner/src/scanner_config.dart';
import 'package:universal_barcode_scanner/src/scanner_exception.dart';
import 'package:web/web.dart' as html;

/// Barcode scanner for web, running the bundled page in an iframe.
class BarcodeScannerPage extends StatefulWidget {
  /// Creates the web scanner page.
  const BarcodeScannerPage({
    super.key,
    required this.config,
    required this.onScanned,
    required this.onClose,
    this.onError,
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

  /// Unused on web: the page says itself why the camera did not start.
  final ValueChanged<ScannerException>? onError;

  /// Drawn over the scanner.
  final Widget? child;

  /// App bar shown above the scanner, or null for none.
  final BarcodeAppBar? barcodeAppBar;

  /// Whether the preview is mirrored.
  final bool flip;

  /// Colour behind the camera. Black when null.
  final Color? backgroundColor;

  @override
  State<BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<BarcodeScannerPage> {
  /// The frame, once Flutter has created it.
  html.HTMLIFrameElement? _iframe;

  StreamSubscription<html.MessageEvent>? _messages;
  bool _delivered = false;

  @override
  void initState() {
    super.initState();
    _messages = html.window.onMessage.listen(_onMessage);
  }

  @override
  void dispose() {
    _messages?.cancel();
    super.dispose();
  }

  /// Sets the frame up. No cross-frame call is possible before it loads, so
  /// the settings ride in the query string; `start` tells the page not to
  /// wait for `configure`.
  ///
  /// Created through the element callback rather than a view factory: a
  /// factory is registered for good, and one per scan kept every page it had
  /// built alive.
  void _onElementCreated(Object element) {
    final html.HTMLIFrameElement iframe = element as html.HTMLIFrameElement;
    final Uri page = Uri(
      path: ScannerAsset.webPath,
      queryParameters: <String, String>{
        ...widget.config.toPage(
          host: 'web',
          background: widget.backgroundColor,
        ),
        'start': '1',
      },
    );
    iframe
      ..src = page.toString()
      ..allow = 'camera'
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%';
    _iframe = iframe;
  }

  void _onMessage(html.MessageEvent event) {
    // Only our own frame speaks for the scanner: any other window of the same
    // origin, or the app itself, may post messages too.
    final html.HTMLIFrameElement? iframe = _iframe;
    if (iframe == null || event.origin != html.window.location.origin) return;
    if (!event.source.strictEquals(iframe.contentWindow).toDart) return;

    switch (PageMessage.parse(event.data.dartify())) {
      case PageCode(:final String code):
        if (!widget.config.continuous) {
          if (_delivered) return;
          _delivered = true;
        }
        widget.onScanned(code);
      case PageClose():
        widget.onClose();
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget view = HtmlElementView.fromTagName(
      tagName: 'iframe',
      onElementCreated: _onElementCreated,
    );
    return ScannerChrome(
      backgroundColor: widget.backgroundColor,
      bar: widget.barcodeAppBar,
      onClose: widget.onClose,
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

/// Embedded scanner view on web.
///
/// Not implemented: the web scanner runs in an iframe, which only makes sense
/// as a whole page. Use `UniversalBarcodeScanner.scan` there.
class BarcodeScannerView extends StatelessWidget {
  /// Creates the web embedded view.
  const BarcodeScannerView({
    super.key,
    required this.config,
    required this.onBarcodeViewCreated,
    this.onScanned,
    this.onError,
    this.scanWindowSize,
    this.child,
    this.flip = false,
  });

  /// What to scan and how.
  final ScannerConfig config;

  /// Called once the view exists.
  final BarcodeScannerViewCreated onBarcodeViewCreated;

  /// Called with every code read.
  final ValueChanged<String>? onScanned;

  /// Called when the camera cannot be used.
  final ValueChanged<ScannerException>? onError;

  /// Size of the scan window.
  final Size? scanWindowSize;

  /// Drawn over the camera.
  final Widget? child;

  /// Whether the preview is mirrored.
  final bool flip;

  @override
  Widget build(BuildContext context) =>
      const Center(child: Text('The embedded view is not available on web'));
}
