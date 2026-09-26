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

const BarcodeAppBar _appBar = BarcodeAppBar(
  appBarTitle: 'Point at a barcode',
  centerTitle: false,
  enableBackButton: true,
  backButtonIcon: Icon(Icons.arrow_back_ios),
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

  /// One shot: opens the scanner, comes back with a code or null.
  Future<void> _scanOnce() async {
    _stream?.cancel();
    final String? code = await UniversalBarcodeScanner.scan(
      context,
      barcodeAppBar: _appBar,
      isShowFlashIcon: true,
      scanDelay: const Duration(milliseconds: 500),
      cameraFace: CameraFace.back,
      scanFormat: ScanFormat.all,
    );
    if (code != null) _found(code, 'one shot');
  }

  /// Continuous: the stream closes on its own when the route goes away.
  void _scanStream() {
    _stream?.cancel();
    _stream = UniversalBarcodeScanner.stream(
      context,
      barcodeAppBar: _appBar,
      isShowFlashIcon: true,
      scanDelay: const Duration(seconds: 2),
    ).listen((String code) => _found(code, 'continuous'));
  }

  void _openEmbedded() {
    _stream?.cancel();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const EmbeddedPage(),
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
                _Result(code: _code, mode: _mode, count: _count),
                const SizedBox(height: 22),
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
                _Mode(
                  title: 'Embedded view',
                  body: kIsWeb
                      ? 'Puts the camera inside your own layout. Android, iOS, '
                          'macOS and Windows: on the web the scanner runs in '
                          'a frame of its own, so it is a page rather than a '
                          'widget.'
                      : 'Puts the camera inside your own layout, with a '
                          'controller for the torch and for pausing.',
                  action: 'Open',
                  onPressed: kIsWeb ? null : _openEmbedded,
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
  const _Result({required this.code, required this.mode, required this.count});

  final String? code;
  final String mode;
  final int count;

  @override
  Widget build(BuildContext context) {
    final String? value = code;

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
          const SizedBox(height: 12),
          SelectableText(
            value ?? 'Pick a mode below and point the camera at a barcode.',
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
            child: Text(off ? 'Mobile' : action),
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

/// Embedded: the camera sits inside the layout, driven by a controller.
class EmbeddedPage extends StatefulWidget {
  /// Creates the embedded demo.
  const EmbeddedPage({super.key});

  @override
  State<EmbeddedPage> createState() => _EmbeddedPageState();
}

class _EmbeddedPageState extends State<EmbeddedPage> {
  BarcodeViewController? _controller;
  String _result = '';
  bool _paused = false;

  void _togglePause() {
    if (_paused) {
      _controller?.resumeScanning();
    } else {
      _controller?.pauseScanning();
    }
    setState(() => _paused = !_paused);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Embedded view'),
        backgroundColor: _panel,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: 280,
                    height: 280,
                    child: UniversalBarcodeScanner(
                      scaleWidth: 400,
                      scaleHeight: 200,
                      continuous: true,
                      onScanned: (String code) =>
                          setState(() => _result = code),
                      onBarcodeViewCreated:
                          (BarcodeViewController controller) =>
                              _controller = controller,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SelectableText(
                  _result.isEmpty ? 'Waiting for a code' : _result,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: _result.isEmpty ? 14 : 18,
                    fontFamily: _result.isEmpty ? null : 'monospace',
                    color: _result.isEmpty ? _dim : Colors.white,
                  ),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 10,
                  children: <Widget>[
                    OutlinedButton.icon(
                      onPressed: () => _controller?.toggleFlash(),
                      icon: const Icon(Icons.flashlight_on, size: 18),
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
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
