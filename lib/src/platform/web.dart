import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:universal_barcode_scanner/src/constants.dart';
import 'package:universal_barcode_scanner/src/embedded_page.dart';
import 'package:universal_barcode_scanner/src/scanner_bar.dart';
import 'package:universal_barcode_scanner/src/scanner_chrome.dart';
import 'package:universal_barcode_scanner/src/scanner_config.dart';
import 'package:universal_barcode_scanner/src/scanner_controller.dart';
import 'package:universal_barcode_scanner/src/scanner_exception.dart';
import 'package:web/web.dart' as html;

/// Barcode scanner for web, running the bundled page in an iframe.
class ScannerPage extends StatefulWidget {
  /// Creates the web scanner page.
  const ScannerPage({
    super.key,
    required this.config,
    required this.onScanned,
    required this.onClose,
    this.onError,
    this.child,
    this.bar,
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
  final ScannerBar? bar;

  /// Whether the preview is mirrored.
  final bool flip;

  /// Colour behind the camera. Black when null.
  final Color? backgroundColor;

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
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
      // The page says itself why the camera did not start, and has no torch
      // button to answer.
      case PageError():
      case PageTorch():
      case PageReady():
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
      bar: widget.bar,
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

/// Embedded scanner view on web: the bundled page in an iframe the size of
/// the widget, the camera filling it.
///
/// What to scan is read once, when the frame is created: give the widget a
/// new key to apply a different configuration. The callbacks are always the
/// current widget's.
class EmbeddedScanner extends StatefulWidget {
  /// Creates the web embedded view.
  const EmbeddedScanner({
    super.key,
    required this.config,
    required this.onCreated,
    this.onScanned,
    this.onError,
    this.scanWindowSize,
    this.child,
    this.flip = false,
  });

  /// What to scan and how.
  final ScannerConfig config;

  /// Called once the view exists.
  final ScannerCreatedCallback onCreated;

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
  State<EmbeddedScanner> createState() => _EmbeddedScannerState();
}

class _EmbeddedScannerState extends State<EmbeddedScanner> {
  late final PageScannerController _controller = PageScannerController(
    (PageCall call) => _post(<String, Object>{'call': call.name}),
  );

  html.HTMLIFrameElement? _iframe;
  StreamSubscription<html.MessageEvent>? _messages;

  /// The scan window, as the last layout measured it.
  Size? _window;

  /// The scan window the page was last told about.
  Size? _pageWindow;

  /// Whether the page listens: before, a message would be dropped.
  bool _pageReady = false;

  /// Whether the camera did not start, which the page explains itself.
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller
      ..onScanned = widget.onScanned
      ..onError = widget.onError;
    _messages = html.window.onMessage.listen(_onMessage);
    // After the frame, so a callback that sets state does not do it during
    // this build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onCreated(_controller);
    });
  }

  @override
  void didUpdateWidget(EmbeddedScanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller
      ..onScanned = widget.onScanned
      ..onError = widget.onError;
  }

  @override
  void dispose() {
    _messages?.cancel();
    // A code or an error still in flight must not reach a widget that is
    // gone. The camera stops with the frame.
    _controller.dispose();
    super.dispose();
  }

  void _post(Map<String, Object> message) {
    _iframe?.contentWindow?.postMessage(
      jsonEncode(message).toJS,
      html.window.location.origin.toJS,
    );
  }

  /// Called during the build, before the frame exists the first time.
  void _onWindow(Size window) {
    _window = window;
    _sendWindow();
  }

  /// Tells the page about a scan window it does not have yet.
  void _sendWindow() {
    final Size? window = _window;
    if (!_pageReady || window == null || window == _pageWindow) return;
    _pageWindow = window;
    _post(<String, Object>{
      'call': 'setWindow',
      'width': window.width.round(),
      'height': window.height.round(),
    });
  }

  void _onElementCreated(Object element) {
    final html.HTMLIFrameElement iframe = element as html.HTMLIFrameElement;
    final Size window = _pageWindow = _window ?? Size.zero;
    final Uri page = Uri(
      path: ScannerAsset.webPath,
      queryParameters: <String, String>{
        ...widget.config.toEmbeddedPage(host: 'web', window: window),
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
    // Only our own frame speaks for this view: every embedded scanner, and
    // any other window of the same origin, posts to the same window.
    final html.HTMLIFrameElement? iframe = _iframe;
    if (iframe == null || event.origin != html.window.location.origin) return;
    if (!event.source.strictEquals(iframe.contentWindow).toDart) return;
    final PageMessage? message = PageMessage.parse(event.data.dartify());
    if (message is PageError && !_failed) setState(() => _failed = true);
    if (message is PageReady) {
      _pageReady = true;
      // A layout that changed while the page was loading.
      _sendWindow();
    }
    _controller.handle(message);
  }

  @override
  Widget build(BuildContext context) => EmbeddedPageFrame(
    view: HtmlElementView.fromTagName(
      tagName: 'iframe',
      onElementCreated: _onElementCreated,
    ),
    config: widget.config,
    scanWindowSize: widget.scanWindowSize,
    onWindow: _onWindow,
    flip: widget.flip,
    failed: _failed,
    child: widget.child,
  );
}
