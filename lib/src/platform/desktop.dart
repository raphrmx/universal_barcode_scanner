import 'dart:async';
import 'dart:convert';

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
import 'package:webview_all/webview_all.dart';
import 'package:webview_all_linux/webview_all_linux.dart';
import 'package:webview_all_windows/webview_all_windows.dart';

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
      try {
        switch (controller.platform) {
          case final WindowsWebViewController windows:
            await windows.dispose();
          case final LinuxWebViewController linux:
            await linux.dispose();
          default:
            await controller.loadHtmlString(_blankPage);
        }
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
  final ScannerBar? bar;

  /// Colour behind the camera. Black when null.
  final Color? backgroundColor;

  /// The buttons over the camera.
  final Set<ScannerButton> buttons;

  /// Where [buttons] sit.
  final AlignmentGeometry buttonsAlignment;

  @override
  State<DesktopScannerPage> createState() => _DesktopScannerPageState();
}

class _DesktopScannerPageState extends State<DesktopScannerPage>
    implements _PageOwner {
  late final _Lease _lease = _Lease(this);

  /// Set on the first code of a single scan, so a second one is ignored.
  bool _delivered = false;

  /// Drives the page for the buttons: pause and torch.
  late final PageScannerController _controller = PageScannerController(
    (PageCall call) => unawaited(_lease.webview.run('${call.name}()')),
    continuous: widget.config.continuous,
  );

  late final ScannerButtons _buttons = ScannerButtons(
    flipHorizontal: widget.config.flipHorizontal,
    flipVertical: widget.config.flipVertical,
    // Before the page is up this is lost, and configure carries the flip.
    onFlip: (bool horizontal, bool vertical) =>
        unawaited(_lease.webview.run('setFlip($horizontal, $vertical)')),
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

  /// Hands the page its settings, which also starts the camera, with the
  /// flips as the buttons now have them.
  @override
  void onPageLoaded() {
    final Map<String, String> settings = widget.config
        .withFlip(
          horizontal: _buttons.flipHorizontal,
          vertical: _buttons.flipVertical,
        )
        .toPage(host: 'desktop', background: widget.backgroundColor);
    unawaited(_lease.webview.run('configure(${jsonEncode(settings)})'));
    // After configure, which would otherwise undo a pause held back.
    _controller.pageReady();
  }

  @override
  void onPageMessage(String data) {
    if (!mounted) return;
    final PageMessage? message = PageMessage.parse(data);
    switch (message) {
      case PageCode(:final String code):
        if (!widget.config.continuous) {
          if (_delivered) return;
          _delivered = true;
        }
        widget.onScanned(code);
      case PageClose():
        _close();
      case PageTorch():
        _controller.handle(message);
      // The page says itself why the camera did not start.
      case PageError():
      case PageReady():
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
          : ScannerButtonGroup(state: _buttons, buttons: widget.buttons),
      buttonsAlignment: widget.buttonsAlignment,
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

  late final PageScannerController _controller = PageScannerController(
    (PageCall call) => unawaited(_lease.webview.run('${call.name}()')),
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
    final ScannerConfig old = oldWidget.config;
    // Before configure, the page gets the current flip with the rest.
    if (_configured &&
        (config.flipHorizontal != old.flipHorizontal ||
            config.flipVertical != old.flipVertical)) {
      unawaited(
        _lease.webview.run(
          'setFlip(${config.flipHorizontal}, ${config.flipVertical})',
        ),
      );
    }
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
    final Map<String, String> settings = widget.config.toEmbeddedPage(
      host: 'desktop',
      window: window,
    );
    unawaited(_lease.webview.run('configure(${jsonEncode(settings)})'));
    // Scripts run in order, so what was held back lands after configure,
    // which would otherwise undo a pause.
    _controller.pageReady();
  }

  void _onWindow(Size window) {
    final Size? previous = _window;
    _window = window;
    if (!_configured) {
      _configure();
    } else if (previous != window) {
      unawaited(
        _lease.webview.run(
          'setWindow(${window.width.round()}, ${window.height.round()})',
        ),
      );
    }
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
    paused: _controller.paused,
    child: widget.child,
  );
}
