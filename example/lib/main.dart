import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:universal_barcode_scanner/universal_barcode_scanner.dart';

void main() => runApp(const ExampleApp());

const Color _ink = Color(0xFF0E1014);
const Color _panel = Color(0xFF171A20);
const Color _line = Color(0xFF272C36);
const Color _dim = Color(0xFF8B929E);
const Color _accent = Color(0xFF39B37A);

const ScannerBar _appBar = ScannerBar(
  title: 'Point at a barcode',
  centerTitle: false,
  showBackButton: true,
  backIcon: Icon(Icons.arrow_back_ios),
);

/// The three ways to use the scanner: one shot, continuous, embedded.
class ExampleApp extends StatelessWidget {
  /// Creates the example app.
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Universal Barcode Scanner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _ink,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _accent,
          brightness: Brightness.dark,
        ),
      ),
      home: const HomePage(),
    );
  }
}

/// Menu of the three modes, showing what each one returns.
class HomePage extends StatefulWidget {
  /// Creates the menu.
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  StreamSubscription<String>? _stream;
  String? _code;
  String _mode = '';
  int _count = 0;

  /// Whether the camera sits in the result tile.
  bool _embedded = false;
  ScannerController? _controller;
  bool _paused = false;
  bool _torch = false;

  /// How the camera is shown, in every mode. Mirrored by default where the
  /// camera is a webcam, as the package itself does.
  bool _flipHorizontal = UniversalBarcodeScanner.flipsByDefault;
  bool _flipVertical = false;

  @override
  void dispose() {
    _stream?.cancel();
    super.dispose();
  }

  void _found(String code, String mode) {
    if (!mounted) return;
    setState(() {
      _code = code;
      _mode = mode;
      _count++;
    });
  }

  /// One camera at a time: the tile's goes before a scanner opens.
  Future<void> _closeEmbedded() async {
    if (!_embedded) return;
    _toggleEmbedded();
    await WidgetsBinding.instance.endOfFrame;
  }

  /// Embedded: the camera opens in the result tile, and closes from the same
  /// button.
  void _toggleEmbedded() {
    setState(() {
      _embedded = !_embedded;
      _controller = null;
      _paused = false;
      _torch = false;
    });
  }

  Future<void> _togglePause() async {
    final ScannerController? controller = _controller;
    if (controller == null) return;
    if (_paused) {
      await controller.resumeScanning();
    } else {
      await controller.pauseScanning();
    }
    if (mounted) setState(() => _paused = !_paused);
  }

  /// Most webcams have no torch an app can drive: the answer says so.
  Future<void> _toggleTorch() async {
    final bool on = await _controller?.toggleFlash() ?? false;
    if (mounted) setState(() => _torch = on);
  }

  /// One shot: opens the scanner, comes back with a code or null.
  Future<void> _scanOnce() async {
    await _stream?.cancel();
    await _closeEmbedded();
    if (!mounted) return;
    try {
      final String? code = await UniversalBarcodeScanner.scan(
        context,
        bar: _appBar,
        showTorchButton: true,
        cameraFace: CameraFace.back,
        scanFormat: ScanFormat.all,
        flip: _flipHorizontal,
        flipVertical: _flipVertical,
      );
      if (code != null) _found(code, 'one shot');
    } on ScannerException catch (error) {
      _failed(error);
    }
  }

  /// Continuous: the stream closes on its own when the route goes away.
  Future<void> _scanStream() async {
    await _stream?.cancel();
    await _closeEmbedded();
    if (!mounted) return;
    _stream = UniversalBarcodeScanner.stream(
      context,
      bar: _appBar,
      showTorchButton: true,
      scanDelay: const Duration(seconds: 2),
      flip: _flipHorizontal,
      flipVertical: _flipVertical,
    ).listen(
      (String code) => _found(code, 'continuous'),
      onError: (Object error) {
        if (error is ScannerException) _failed(error);
      },
    );
  }

  void _failed(ScannerException error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error.code == ScannerErrorCode.permissionDenied
              ? 'The camera permission was refused.'
              : 'The camera could not be used.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
              children: <Widget>[
                const Text(
                  'Universal Barcode Scanner',
                  style: TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.7,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Barcodes and QR codes from one call, on Android, iOS, '
                  'Linux, macOS, web and Windows.',
                  style: TextStyle(fontSize: 14.5, color: _dim, height: 1.45),
                ),
                const SizedBox(height: 22),
                _Result(
                  code: _code,
                  mode: _mode,
                  count: _count,
                  camera: _embedded
                      ? UniversalBarcodeScanner(
                          continuous: true,
                          // Changed live: the camera keeps running.
                          flip: _flipHorizontal,
                          flipVertical: _flipVertical,
                          onScanned: (String code) => _found(code, 'embedded'),
                          onError: _failed,
                          onCreated: (ScannerController controller) =>
                              _controller = controller,
                        )
                      : null,
                  controls: _embedded
                      ? <Widget>[
                          OutlinedButton.icon(
                            onPressed: _toggleTorch,
                            icon: Icon(
                              _torch
                                  ? Icons.flashlight_on
                                  : Icons.flashlight_off,
                              size: 18,
                            ),
                            label: const Text('Torch'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _togglePause,
                            icon: Icon(
                              _paused ? Icons.play_arrow : Icons.pause,
                              size: 18,
                            ),
                            label: Text(_paused ? 'Resume' : 'Pause'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _toggleEmbedded,
                            icon: const Icon(Icons.close, size: 18),
                            label: const Text('Close'),
                          ),
                        ]
                      : const <Widget>[],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    FilterChip(
                      avatar: const Icon(Icons.swap_horiz, size: 18),
                      label: const Text('Flip horizontally'),
                      selected: _flipHorizontal,
                      showCheckmark: false,
                      onSelected: (bool on) =>
                          setState(() => _flipHorizontal = on),
                    ),
                    FilterChip(
                      avatar: const Icon(Icons.swap_vert, size: 18),
                      label: const Text('Flip vertically'),
                      selected: _flipVertical,
                      showCheckmark: false,
                      onSelected: (bool on) =>
                          setState(() => _flipVertical = on),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                _Mode(
                  title: 'Embedded view',
                  body: 'Puts the camera inside your own layout, here the tile '
                      'above, with a controller for the torch and for '
                      'pausing.',
                  action: 'Open',
                  // Closed from the tile, next to the other controls.
                  onPressed: _embedded ? null : _toggleEmbedded,
                ),
                _Mode(
                  title: 'Scan once',
                  body:
                      'Opens the scanner, closes on the first code and returns '
                      'it. A Future<String?>, null if the user backs out.',
                  action: 'Scan',
                  onPressed: _scanOnce,
                ),
                _Mode(
                  title: 'Scan continuously',
                  body: 'Stays open and reports every code as it comes, two '
                      'seconds apart. A Stream<String> that closes with the '
                      'route.',
                  action: 'Open',
                  onPressed: _scanStream,
                ),
                const SizedBox(height: 8),
                const _Note(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What the last scan returned, or what to do to get one.
class _Result extends StatelessWidget {
  const _Result({
    required this.code,
    required this.mode,
    required this.count,
    this.camera,
    this.controls = const <Widget>[],
  });

  final String? code;
  final String mode;
  final int count;

  /// The embedded scanner, when it is open in this tile.
  final Widget? camera;

  /// What drives [camera].
  final List<Widget> controls;

  @override
  Widget build(BuildContext context) {
    final String? value = code;
    final Widget? camera = this.camera;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: value == null ? _panel : const Color(0xFF13251C),
        border: Border.all(color: value == null ? _line : _accent),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                value == null ? Icons.qr_code_scanner : Icons.check_circle,
                size: 17,
                color: value == null ? _dim : _accent,
              ),
              const SizedBox(width: 8),
              Text(
                value == null ? 'NOTHING SCANNED YET' : 'SCANNED, $mode',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: value == null ? _dim : _accent,
                ),
              ),
              const Spacer(),
              if (count > 1)
                Text(
                  '$count reads',
                  style: const TextStyle(fontSize: 12, color: _dim),
                ),
            ],
          ),
          if (camera != null) ...<Widget>[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: 210,
                width: double.infinity,
                child: camera,
              ),
            ),
          ],
          const SizedBox(height: 12),
          SelectableText(
            value ??
                (camera == null
                    ? 'Pick a mode below and point the camera at a barcode.'
                    : 'Point the camera at a barcode.'),
            style: TextStyle(
              fontSize: value == null ? 14.5 : 19,
              height: 1.4,
              fontFamily: value == null ? null : 'monospace',
              fontWeight: value == null ? FontWeight.w400 : FontWeight.w600,
              color: value == null ? _dim : Colors.white,
            ),
          ),
          if (value != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              '${value.length} characters',
              style: const TextStyle(fontSize: 12.5, color: _dim),
            ),
          ],
          if (controls.isNotEmpty) ...<Widget>[
            const SizedBox(height: 14),
            // Compact, so the three fit on one line of a phone.
            OutlinedButtonTheme(
              data: OutlinedButtonThemeData(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
              ),
              child: Wrap(spacing: 6, runSpacing: 8, children: controls),
            ),
          ],
        ],
      ),
    );
  }
}

/// One of the three ways in, with what it gives back.
class _Mode extends StatelessWidget {
  const _Mode({
    required this.title,
    required this.body,
    required this.action,
    required this.onPressed,
  });

  final String title;
  final String body;
  final String action;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final bool off = onPressed == null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
      decoration: BoxDecoration(
        color: _panel,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: off ? _dim : Colors.white,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: _dim,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: const Color(0xFF07130D),
              disabledBackgroundColor: _line,
              disabledForegroundColor: _dim,
              padding: const EdgeInsets.symmetric(horizontal: 20),
            ),
            child: Text(action),
          ),
        ],
      ),
    );
  }
}

/// What a browser needs before any of this works.
class _Note extends StatelessWidget {
  const _Note();

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return const SizedBox.shrink();

    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        'In a browser the camera needs your permission, and it is only offered '
        'over HTTPS. A machine without one says so rather than showing you a '
        'black screen.',
        style: TextStyle(fontSize: 12.5, color: _dim, height: 1.5),
      ),
    );
  }
}
