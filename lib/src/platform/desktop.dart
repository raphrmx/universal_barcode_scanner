import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:universal_barcode_scanner/src/constants.dart';
import 'package:universal_barcode_scanner/src/embedded_page.dart';
import 'package:universal_barcode_scanner/src/enums.dart';
import 'package:universal_barcode_scanner/src/scan_result.dart';
import 'package:universal_barcode_scanner/src/scanner_bar.dart';
import 'package:universal_barcode_scanner/src/scanner_button_style.dart';
import 'package:universal_barcode_scanner/src/scanner_buttons.dart';
import 'package:universal_barcode_scanner/src/scanner_chrome.dart';
import 'package:universal_barcode_scanner/src/scanner_config.dart';
import 'package:universal_barcode_scanner/src/scanner_controller.dart';
import 'package:universal_barcode_scanner/src/scanner_exception.dart';
import 'package:universal_barcode_scanner/src/scanner_verdict.dart';
import 'package:webview_all/webview_all.dart';

/// Name of the JavaScript channel the bundled page posts scans on. It has to
/// match the `CHANNEL` constant in `assets/barcode.html`.
const String _channelName = 'UniversalBarcodeScanner';

/// How long an idle webview is kept before it is let go.
const Duration _idleBeforeRelease = Duration(minutes: 1);

/// What an unused webview is left showing where it cannot be disposed: no
/// script, no camera.
const String _blankPage = '<!doctype html><title>.</title>';

/// Whoever shows a webview: the scanner page, or an embedded view.
abstract interface class _PageOwner {
  /// The page is up and can take `configure`.
  void onPageLoaded();

  /// The page posted [data].
  void onPageMessage(String data);
}

/// A webview and whoever is showing it, if anyone.
///
/// The page never starts the camera on its own: it waits for `configure`,
/// which only the owner on screen sends. A scanner closed before its webview
/// finished loading therefore never lights the camera up behind it.
class _Webview {
  _Webview() {
    controller = WebViewController(onPermissionRequest: _grantCamera)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        _channelName,
        onMessageReceived: (JavaScriptMessage message) =>
            owner?.onPageMessage(message.message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String _) {
            if (loaded || released) return;
            loaded = true;
            owner?.onPageLoaded();
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

  /// Whoever is currently showing this webview.
  _PageOwner? owner;

  Timer? release;

  /// Calls the page's function [name] with [arguments], in order.
  void call(String name, List<Object> arguments) =>
      unawaited(run('$name(${arguments.map(jsonEncode).join(', ')})'));

  Future<void> run(String script) async {
    try {
      await controller.runJavaScript(script);
    } on Object {
      // The page is not up yet, or has gone: nothing to stop or start.
    }
  }

  /// Releases the native webview, and the camera with it.
  ///
  /// In a microtask: the scanner that let it go may be closing in this very
  /// frame, and its webview widget is torn down after its own state.
  void letGo() {
    released = true;
    owner = null;
    scheduleMicrotask(() async {
      // The Windows and Linux controllers of `webview_all` have a `dispose`
      // their common interface does not declare. Called by name, so this
      // package does not depend on either implementation.
      final dynamic platform = controller.platform;
      try {
        // ignore: avoid_dynamic_calls
        await (platform.dispose() as Future<void>);
        // A platform without the method: the only way to learn it.
        // ignore: avoid_catching_errors
      } on NoSuchMethodError {
        await controller.loadHtmlString(_blankPage);
      } on Object {
        // Already gone.
      }
    });
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
/// for the camera. Reopening a scanner within [_idleBeforeRelease] reuses it.
_Webview? _kept;

/// A webview for [owner]: the kept one when nobody is showing it, a new one
/// otherwise. [_Lease.shared] says which, for [_Lease.end].
class _Lease {
  _Lease(_PageOwner owner) {
    final _Webview kept = _kept ??= _Webview();
    if (kept.owner == null) {
      kept.release?.cancel();
      kept.release = null;
      webview = kept;
      shared = true;
    } else {
      // Another scanner is on screen with the kept one.
      webview = _Webview();
      shared = false;
    }
    webview.owner = owner;
  }

  late final _Webview webview;
  late final bool shared;

  /// Stops the camera and hands the webview back: kept for a while when it
  /// is the shared one, let go otherwise.
  void end() {
    final _Webview webview = this.webview;
    webview.owner = null;
    unawaited(webview.run('stopScanner()'));

    if (shared) {
      webview.release = Timer(_idleBeforeRelease, () {
        if (!identical(_kept, webview) || webview.owner != null) return;
        webview.letGo();
        _kept = null;
      });
    } else {
      webview.letGo();
    }
  }
}

/// How long the page gets to read an image, loading included.
const Duration _imageTimeout = Duration(seconds: 30);

/// Every code in the encoded image [bytes], read by the scanner page in a
/// webview nobody sees: the kept one when no scanner is showing it. [formats]
/// is the page's name for the formats to read.
Future<List<ScanResult>> readImageOnDesktop(Uint8List bytes, String formats) =>
    _ImageRead(bytes, formats).answer.future;

/// One image handed to the page, and its answer.
class _ImageRead implements _PageOwner {
  _ImageRead(this.bytes, this.formats) {
    _lease = _Lease(this);
    _timeout = Timer(
      _imageTimeout,
      () => _finish(
        error: const ScannerException(
          ScannerErrorCode.unknown,
          'The scanner page did not read the image in time.',
        ),
      ),
    );
    if (_lease.webview.loaded) onPageLoaded();
  }

  static int _lastId = 0;

  final Uint8List bytes;
  final String formats;
  final int id = ++_lastId;
  final Completer<List<ScanResult>> answer = Completer<List<ScanResult>>();
  late final _Lease _lease;
  late final Timer _timeout;

  @override
  void onPageLoaded() => _lease.webview.call('readImage', <Object>[
    id,
    base64Encode(bytes),
    formats,
  ]);

  @override
  void onPageMessage(String data) {
    final PageMessage? message = PageMessage.parse(data);
    if (message is! PageImage || message.id != id) return;
    final List<ScanResult>? results = message.results;
    if (results != null) {
      _finish(results: results);
    } else {
      _finish(
        error: ScannerException(
          ScannerErrorCode.fromWire(message.failed ?? ''),
          message.message,
        ),
      );
    }
  }

  void _finish({List<ScanResult>? results, ScannerException? error}) {
    if (answer.isCompleted) return;
    _timeout.cancel();
    _lease.end();
    if (error != null) {
      answer.completeError(error);
    } else {
      answer.complete(results ?? const <ScanResult>[]);
    }
  }
}

/// Scanner for the desktop platforms that have no native scanner: Windows and
/// Linux.
///
/// Both run the same bundled scanner page in a webview, WebView2 on
/// Windows and WebKitGTK on Linux, and both need the host to answer the
/// page's camera permission request.
class DesktopScannerPage extends StatefulWidget {
  /// Creates the desktop scanner page.
  const DesktopScannerPage({
    super.key,
    required this.config,
    required this.onScanned,
    required this.onClose,
    this.child,
    this.bar,
    this.backgroundColor,
    this.buttons = const <ScannerButton>{},
    this.buttonsAlignment = Alignment.centerRight,
    this.buttonStyle = const ScannerButtonStyle(),
    this.verdicts,
  });

  /// What to scan and how.
  final ScannerConfig config;

  /// Called with every code read.
  final ValueChanged<ScanResult> onScanned;

  /// Called by the back button.
  final VoidCallback onClose;

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

  /// How the buttons look.
  final ScannerButtonStyle buttonStyle;

  /// The verdict on each code read, each one shown over the camera.
  final ScanVerdicts? verdicts;

  @override
  State<DesktopScannerPage> createState() => _DesktopScannerPageState();
}

class _DesktopScannerPageState extends State<DesktopScannerPage>
    implements _PageOwner {
  late final _Lease _lease = _Lease(this);

  /// Set on the first code of a single scan, so a second one is ignored.
  bool _delivered = false;

  /// What the page is asked to show.
  late final PageLink _link = PageLink(_lease.webview.call, widget.config);

  /// Drives the page for the buttons.
  late final PageScannerController _controller = PageScannerController(
    _link,
    continuous: widget.config.continuous,
  );

  late final ScannerButtons _buttons = ScannerButtons(
    flipHorizontal: widget.config.flipHorizontal,
    flipVertical: widget.config.flipVertical,
    onFlip: (bool horizontal, bool vertical) =>
        _link.setFlip(horizontal: horizontal, vertical: vertical),
    onSwitchCamera: _link.switchFace,
  )..controller = _controller;

  @override
  void initState() {
    super.initState();
    if (_lease.webview.loaded) onPageLoaded();
  }

  @override
  void dispose() {
    _controller.dispose();
    _buttons.dispose();
    _lease.end();
    super.dispose();
  }

  /// Hands the page its settings, as the buttons have them now, which also
  /// starts the camera.
  @override
  void onPageLoaded() {
    final ScannerConfig config = _link.apply(widget.config);
    final Map<String, String> settings = config.toPage(
      host: 'desktop',
      background: widget.backgroundColor,
    );
    unawaited(_lease.webview.run('configure(${jsonEncode(settings)})'));
    // Scripts run in order: what was held back lands after configure.
    _link.ready(config);
  }

  @override
  void onPageMessage(String data) {
    if (!mounted) return;
    final PageMessage? message = PageMessage.parse(data);
    switch (message) {
      case PageCode(:final String code, :final BarcodeFormat format):
        if (!widget.config.continuous) {
          if (_delivered) return;
          _delivered = true;
        }
        widget.onScanned(ScanResult(code, format: format));
      case PageClose():
        _close();
      case PageTorch():
      case PageZoom():
        _controller.handle(message);
      // The page says itself why the camera did not start.
      case PageError():
      case PageReady():
      case PageImage():
      case null:
        break;
    }
  }

  void _close() {
    unawaited(_lease.webview.run('stopScanner()'));
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget view = WebViewWidget(controller: _lease.webview.controller);
    return ScannerChrome(
      backgroundColor: widget.backgroundColor,
      bar: widget.bar,
      onClose: _close,
      buttons: widget.buttons.isEmpty
          ? null
          : ScannerButtonGroup(
              state: _buttons,
              buttons: widget.buttons,
              labels: widget.config.labels,
            ),
      buttonsAlignment: widget.buttonsAlignment,
      closeLabel: widget.config.labels.close,
      buttonStyle: widget.buttonStyle,
      verdicts: widget.verdicts,
      rejectedLabel: widget.config.labels.rejected,
      // The page flips the camera itself, leaving its words readable.
      body: Stack(children: <Widget>[view, ?widget.child]),
    );
  }
}

/// Embedded scanner view on Windows and Linux: the bundled page in a webview
/// the size of the widget, the camera filling it.
///
/// What to scan is read once, when the view starts: give the widget a new key
/// to apply a different configuration. The callbacks are always the current
/// widget's.
class DesktopEmbeddedScanner extends StatefulWidget {
  /// Creates the desktop embedded view.
  const DesktopEmbeddedScanner({
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

  /// Size of the scan window in logical pixels, or null for a default.
  final Size? scanWindowSize;

  /// Drawn over the camera.
  final Widget? child;

  @override
  State<DesktopEmbeddedScanner> createState() => _DesktopEmbeddedScannerState();
}

class _DesktopEmbeddedScannerState extends State<DesktopEmbeddedScanner>
    implements _PageOwner {
  late final _Lease _lease = _Lease(this);

  /// What the page is asked to show.
  late final PageLink _link = PageLink(_lease.webview.call, widget.config);

  late final PageScannerController _controller = PageScannerController(
    _link,
    continuous: widget.config.continuous,
  );

  /// The scan window, once the first layout has measured it. The camera
  /// starts only then, since the page reads inside it.
  Size? _window;

  /// Whether the page has been handed its settings.
  bool _configured = false;

  /// Whether the camera did not start, which the page explains itself.
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller
      ..onScanned = widget.onScanned
      ..onError = widget.onError;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onCreated(_controller);
    });
  }

  @override
  void didUpdateWidget(DesktopEmbeddedScanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller
      ..onScanned = widget.onScanned
      ..onError = widget.onError;
    final ScannerConfig config = widget.config;
    _link
      ..setFlip(
        horizontal: config.flipHorizontal,
        vertical: config.flipVertical,
      )
      ..setFace(config.cameraFace);
  }

  @override
  void dispose() {
    _controller.dispose();
    _lease.end();
    super.dispose();
  }

  @override
  void onPageLoaded() => _configure();

  /// Hands the page its settings, which also starts the camera, once both
  /// the page and the layout are ready.
  void _configure() {
    final Size? window = _window;
    if (_configured || window == null || !_lease.webview.loaded) return;
    _configured = true;
    final ScannerConfig config = _link.apply(widget.config);
    final Map<String, String> settings = config.toEmbeddedPage(
      host: 'desktop',
      window: window,
    );
    unawaited(_lease.webview.run('configure(${jsonEncode(settings)})'));
    // Scripts run in order: what was held back lands after configure.
    _link.ready(config, window: window);
  }

  void _onWindow(Size window) {
    _window = window;
    _link.setWindow(window);
    _configure();
  }

  @override
  void onPageMessage(String data) {
    if (!mounted) return;
    final PageMessage? message = PageMessage.parse(data);
    if (message is PageError && !_failed) setState(() => _failed = true);
    _controller.handle(message);
  }

  @override
  Widget build(BuildContext context) => EmbeddedPageFrame(
    view: WebViewWidget(controller: _lease.webview.controller),
    config: widget.config,
    scanWindowSize: widget.scanWindowSize,
    onWindow: _onWindow,
    failed: _failed,
    paused: _controller.isPaused,
    child: widget.child,
  );
}
