import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:universal_barcode_scanner/src/constants.dart';
import 'package:universal_barcode_scanner/src/embedded_page.dart';
import 'package:universal_barcode_scanner/src/enums.dart';
import 'package:universal_barcode_scanner/src/scanner_bar.dart';
import 'package:universal_barcode_scanner/src/scanner_buttons.dart';
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
    this.backgroundColor,
    this.buttons = const <ScannerButton>{},
    this.buttonsAlignment = Alignment.centerRight,
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

  /// Colour behind the camera. Black when null.
  final Color? backgroundColor;

  /// The buttons over the camera.
  final Set<ScannerButton> buttons;

  /// Where [buttons] sit.
  final AlignmentGeometry buttonsAlignment;

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  /// The frame, once Flutter has created it.
  html.HTMLIFrameElement? _iframe;

  StreamSubscription<html.MessageEvent>? _messages;
  bool _delivered = false;

  /// Drives the page for the buttons: pause and torch.
  late final PageScannerController _controller = PageScannerController(
    (PageCall call) => _post(<String, Object>{'call': call.name}),
    continuous: widget.config.continuous,
  );

  late final ScannerButtons _buttons = ScannerButtons(
    flipHorizontal: widget.config.flipHorizontal,
    flipVertical: widget.config.flipVertical,
    onFlip: _sendFlip,
  )..controller = _controller;

  /// Whether the page listens: a call before then is lost.
  bool _pageReady = false;

  @override
  void initState() {
    super.initState();
    _messages = html.window.onMessage.listen(_onMessage);
  }

  @override
  void dispose() {
    _messages?.cancel();
    _controller.dispose();
    _buttons.dispose();
    super.dispose();
  }

  void _post(Map<String, Object> message) {
    _iframe?.contentWindow?.postMessage(
      jsonEncode(message).toJS,
      html.window.location.origin.toJS,
    );
  }

  /// Sent once the page listens; until then the query string still says it.
  void _sendFlip(bool horizontal, bool vertical) {
    if (!_pageReady) return;
    _post(<String, Object>{'call': 'setFlip', 'x': horizontal, 'y': vertical});
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

    final PageMessage? message = PageMessage.parse(event.data.dartify());
    switch (message) {
      case PageCode(:final String code):
        if (!widget.config.continuous) {
          if (_delivered) return;
          _delivered = true;
        }
        widget.onScanned(code);
      case PageClose():
        widget.onClose();
      case PageTorch():
        _controller.handle(message);
      case PageReady():
        _pageReady = true;
        // Buttons pressed while the page was loading.
        if (_buttons.flipHorizontal != widget.config.flipHorizontal ||
            _buttons.flipVertical != widget.config.flipVertical) {
          _sendFlip(_buttons.flipHorizontal, _buttons.flipVertical);
        }
        _controller.pageReady();
      // The page says itself why the camera did not start.
      case PageError():
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
      buttons: widget.buttons.isEmpty
          ? null
          : ScannerButtonGroup(state: _buttons, buttons: widget.buttons),
      buttonsAlignment: widget.buttonsAlignment,
      // The page flips the camera itself, leaving its words readable.
      body: Stack(children: <Widget>[view, ?widget.child]),
    );
  }
}

/// Embedded scanner view on web: the bundled page in an iframe the size of
/// the widget, the camera filling it.
///
/// What to scan is read once, when the frame is created: give the widget a
/// new key to apply a different configuration. The flip follows the widget,
/// and the callbacks are always the current widget's.
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

  @override
  State<EmbeddedScanner> createState() => _EmbeddedScannerState();
}

class _EmbeddedScannerState extends State<EmbeddedScanner> {
  late final PageScannerController _controller = PageScannerController(
    (PageCall call) => _post(<String, Object>{'call': call.name}),
    continuous: widget.config.continuous,
  );

  html.HTMLIFrameElement? _iframe;
  StreamSubscription<html.MessageEvent>? _messages;

  /// The scan window, as the last layout measured it.
  Size? _window;

  /// The scan window the page was last told about.
  Size? _pageWindow;

  /// The flip the page was last told about, horizontal then vertical.
  (bool, bool)? _pageFlip;

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
    _sendFlip();
  }

  /// Tells the page about a flip it does not have yet.
  void _sendFlip() {
    final (bool, bool) flip = (
      widget.config.flipHorizontal,
      widget.config.flipVertical,
    );
    if (!_pageReady || flip == _pageFlip) return;
    _pageFlip = flip;
    _post(<String, Object>{'call': 'setFlip', 'x': flip.$1, 'y': flip.$2});
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
    _pageFlip = (widget.config.flipHorizontal, widget.config.flipVertical);
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
      // A layout or a flip that changed while the page was loading.
      _sendWindow();
      _sendFlip();
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
    failed: _failed,
    paused: _controller.paused,
    child: widget.child,
  );
}
