import 'dart:async';

import 'package:flutter/material.dart';
import 'package:universal_barcode_scanner/universal_barcode_scanner.dart';

void main() => runApp(const ExampleApp());

const BarcodeAppBar _appBar = BarcodeAppBar(
  appBarTitle: 'Scan',
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
      theme: ThemeData(colorSchemeSeed: Colors.blue),
      home: const HomePage(),
    );
  }
}

/// Menu of the three demos, showing what each one returns.
class HomePage extends StatefulWidget {
  /// Creates the menu.
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  StreamSubscription<String>? _stream;
  String _result = '';

  @override
  void dispose() {
    _stream?.cancel();
    super.dispose();
  }

  /// One shot: opens the scanner, comes back with a code or null.
  Future<void> _scanOnce() async {
    final String? code = await UniversalBarcodeScanner.scan(
      context,
      barcodeAppBar: _appBar,
      isShowFlashIcon: true,
      scanDelay: const Duration(milliseconds: 500),
      cameraFace: CameraFace.back,
      scanFormat: ScanFormat.onlyBarcode,
    );
    if (!mounted) return;
    setState(() => _result = code ?? 'cancelled');
  }

  /// Continuous: the stream closes on its own when the route goes away.
  void _scanStream() {
    _stream?.cancel();
    _stream = UniversalBarcodeScanner.stream(
      context,
      barcodeAppBar: _appBar,
      isShowFlashIcon: true,
      scanDelay: const Duration(seconds: 2),
    ).listen((String code) {
      if (mounted) setState(() => _result = code);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Universal Barcode Scanner')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ElevatedButton(
              onPressed: _scanOnce,
              child: const Text('Scan once'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _scanStream,
              child: const Text('Scan continuously'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) => const EmbeddedPage(),
                ),
              ),
              child: const Text('Embedded view (Android and iOS)'),
            ),
            const SizedBox(height: 20),
            Text('Result: $_result'),
          ],
        ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Embedded view')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            SizedBox(
              width: 200,
              height: 200,
              child: UniversalBarcodeScanner(
                scaleWidth: 400,
                scaleHeight: 200,
                continuous: true,
                onScanned: (String code) => setState(() => _result = code),
                onBarcodeViewCreated: (BarcodeViewController controller) =>
                    _controller = controller,
              ),
            ),
            const SizedBox(height: 20),
            Text(_result),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => _controller?.toggleFlash(),
              child: const Text('Toggle flash'),
            ),
            ElevatedButton(
              onPressed: () => _controller?.pauseScanning(),
              child: const Text('Pause scanning'),
            ),
            ElevatedButton(
              onPressed: () => _controller?.resumeScanning(),
              child: const Text('Resume scanning'),
            ),
          ],
        ),
      ),
    );
  }
}
