import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

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
import 'package:universal_barcode_scanner/src/tones.dart';
import 'package:web/web.dart' as html;

/// How long the page gets to read an image, loading included.
const Duration _imageTimeout = Duration(seconds: 30);

/// The scanner page in a hidden frame, loaded the first time an image is
/// read and kept for the next ones: the decoder it compiled stays warm.
Future<html.HTMLIFrameElement>? _imagePage;

/// The images handed to [_imagePage] and not answered yet.
final Map<int, Completer<List<ScanResult>>> _imageRequests =
    <int, Completer<List<ScanResult>>>{};

int _lastImage = 0;

/// Every code in the encoded image [bytes], read by the scanner page in a
/// hidden frame, off the app's thread where a worker can run.
Future<List<ScanResult>> readImage(Uint8List bytes, ScanFormat format) async {
  final html.HTMLIFrameElement frame = await (_imagePage ??= _loadImagePage());
  final int id = ++_lastImage;
  final Completer<List<ScanResult>> answer = Completer<List<ScanResult>>();
  _imageRequests[id] = answer;
  frame.contentWindow?.postMessage(
    jsonEncode(<String, Object>{
      'call': 'readImage',
      'args': <Object>[
        id,
        base64Encode(bytes),
        ScannerConfig.formatsToPage(format),
      ],
    }).toJS,
    html.window.location.origin.toJS,
  );
  return await answer.future.timeout(
    _imageTimeout,
    onTimeout: () {
      _imageRequests.remove(id);
      throw const ScannerException(
        ScannerErrorCode.unknown,
        'The scanner page did not read the image in time.',
      );
    },
  );
}

Future<html.HTMLIFrameElement> _loadImagePage() {
  final Completer<html.HTMLIFrameElement> loaded =
      Completer<html.HTMLIFrameElement>();
  final html.HTMLIFrameElement frame = html.HTMLIFrameElement()
    ..src = ScannerAsset.webPath
    ..setAttribute('aria-hidden', 'true')
    ..tabIndex = -1
    ..style.display = 'none';
  frame.addEventListener(
    'load',
    ((html.Event _) {
      if (!loaded.isCompleted) loaded.complete(frame);
    }).toJS,
  );
  html.window.addEventListener(
    'message',
    ((html.MessageEvent event) {
      if (event.origin != html.window.location.origin) return;
      if (!event.source.strictEquals(frame.contentWindow).toDart) return;
      final PageMessage? message = PageMessage.parse(event.data.dartify());
      if (message is! PageImage) return;
      final Completer<List<ScanResult>>? request = _imageRequests.remove(
        message.id,
      );
      final List<ScanResult>? results = message.results;
      if (request == null) return;
      if (results != null) {
        request.complete(results);
      } else {
        request.completeError(
          ScannerException(
            ScannerErrorCode.fromWire(message.failed ?? ''),
            message.message,
          ),
        );
      }
    }).toJS,
  );
  html.document.body?.append(frame);
  return loaded.future;
}

/// One audio context for every beep: a browser caps how many a page opens.
html.AudioContext? _audio;

/// A short beep for a code read, a tone made here: no sound file to fetch.
void playBeep() => _play(Tone.accepted);

/// The sound of a code refused: two lower tones, with the two pulses of the
/// vibration.
void playRejectedBeep() => _play(Tone.rejected);

/// Plays [tone] with the browser's oscillators.
void _play(Tone tone) {
  try {
    final html.AudioContext audio = _audio ??= html.AudioContext();
    // A context made before the page was touched starts suspended.
    if (audio.state == 'suspended') unawaited(audio.resume().toDart);
    final double now = audio.currentTime;
    for (final double start in tone.starts) {
      final html.OscillatorNode oscillator = audio.createOscillator()
        ..type = tone.wave.name
        ..frequency.value = tone.hertz;
      final html.GainNode gain = audio.createGain();
      final double at = now + start;
      // Faded out rather than cut, which clicks.
      gain.gain
        ..setValueAtTime(tone.volume, at)
        ..exponentialRampToValueAtTime(Tone.floor, at + Tone.length);
      oscillator
        ..connect(gain)
        ..start(at)
        ..stop(at + Tone.length);
      gain.connect(audio.destination);
    }
  } on Object {
    // No audio in this browser: silence.
  }
}

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
    this.buttonStyle = const ScannerButtonStyle(),
    this.verdicts,
  });

  /// What to scan and how.
  final ScannerConfig config;

  /// Called with every code read.
  final ValueChanged<ScanResult> onScanned;

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

  /// How the buttons look.
  final ScannerButtonStyle buttonStyle;

  /// The verdict on each code read, each one shown over the camera.
  final ScanVerdicts? verdicts;

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  /// The frame, once Flutter has created it.
  html.HTMLIFrameElement? _iframe;

  StreamSubscription<html.MessageEvent>? _messages;
  bool _delivered = false;

  /// What the page is asked to show.
  late final PageLink _link = PageLink(_call, widget.config);

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

  /// The settings the frame was opened with, in its address.
  ScannerConfig? _openedWith;

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

  void _call(String name, List<Object> arguments) =>
      _post(<String, Object>{'call': name, 'args': arguments});

  void _post(Map<String, Object> message) {
    _iframe?.contentWindow?.postMessage(
      jsonEncode(message).toJS,
      html.window.location.origin.toJS,
    );
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
    final ScannerConfig config = _openedWith = _link.apply(widget.config);
    final Uri page = Uri(
      path: ScannerAsset.webPath,
      queryParameters: <String, String>{
        ...config.toPage(host: 'web', background: widget.backgroundColor),
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
      case PageCode(:final String code, :final BarcodeFormat format):
        if (!widget.config.continuous) {
          if (_delivered) return;
          _delivered = true;
        }
        widget.onScanned(ScanResult(code, format: format));
      case PageClose():
        widget.onClose();
      case PageTorch():
      case PageZoom():
        _controller.handle(message);
      case PageReady():
        // Buttons pressed while the page was loading go to it now.
        _link.ready(_openedWith ?? widget.config);
      // The page says itself why the camera did not start.
      case PageError():
      case PageImage():
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
  /// What the page is asked to show.
  late final PageLink _link = PageLink(_call, widget.config);

  late final PageScannerController _controller = PageScannerController(
    _link,
    continuous: widget.config.continuous,
  );

  html.HTMLIFrameElement? _iframe;
  StreamSubscription<html.MessageEvent>? _messages;

  /// The scan window, as the last layout measured it.
  Size? _window;

  /// The settings and the scan window the frame was opened with, in its
  /// address.
  ScannerConfig? _openedWith;
  Size _openedWindow = Size.zero;

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
    _messages?.cancel();
    // A code or an error still in flight must not reach a widget that is
    // gone. The camera stops with the frame.
    _controller.dispose();
    super.dispose();
  }

  void _call(String name, List<Object> arguments) {
    _iframe?.contentWindow?.postMessage(
      jsonEncode(<String, Object>{'call': name, 'args': arguments}).toJS,
      html.window.location.origin.toJS,
    );
  }

  /// Called during the build, before the frame exists the first time.
  void _onWindow(Size window) {
    _window = window;
    _link.setWindow(window);
  }

  void _onElementCreated(Object element) {
    final html.HTMLIFrameElement iframe = element as html.HTMLIFrameElement;
    final Size window = _openedWindow = _window ?? Size.zero;
    final ScannerConfig config = _openedWith = _link.apply(widget.config);
    final Uri page = Uri(
      path: ScannerAsset.webPath,
      queryParameters: <String, String>{
        ...config.toEmbeddedPage(host: 'web', window: window),
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
      // A layout, a flip or a camera that changed while the page was loading
      // goes to it now.
      _link.ready(_openedWith ?? widget.config, window: _openedWindow);
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
    paused: _controller.isPaused,
    child: widget.child,
  );
}
