import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:universal_barcode_scanner/src/barcode_app_bar.dart';
import 'package:universal_barcode_scanner/src/barcode_view_controller.dart';
import 'package:universal_barcode_scanner/src/constants.dart';
import 'package:universal_barcode_scanner/src/enums.dart';
import 'package:universal_barcode_scanner/src/native_scanner.dart';
import 'package:universal_barcode_scanner/src/platform/windows.dart';

ScanMode _scanModeOf(ScanType type) => switch (type) {
  ScanType.qr => ScanMode.qr,
  ScanType.barcode => ScanMode.barcode,
  ScanType.defaultMode => ScanMode.defaultMode,
};

/// Full-screen scanner for the platforms that have `dart:io`.
///
/// Windows goes through a webview; Android, iOS and macOS through their native
/// scanner. Linux says so rather than failing on a missing plugin.
class BarcodeScannerPage extends StatefulWidget {
  /// Creates the scanner page.
  const BarcodeScannerPage({
    super.key,
    required this.onScanned,
    this.lineColor = kDefaultLineColor,
    this.cancelButtonText = 'Cancel',
    this.isShowFlashIcon = false,
    this.scanType = ScanType.barcode,
    this.cameraFace = CameraFace.back,
    this.child,
    this.barcodeAppBar,
    this.scanDelay,
    this.flip = false,
    this.onClose,
    this.scanFormat = ScanFormat.all,
  });

  /// Colour of the scan line.
  final Color lineColor;

  /// Label of the cancel button.
  final String cancelButtonText;

  /// Whether the torch toggle is shown.
  final bool isShowFlashIcon;

  /// What the scanner looks for.
  final ScanType scanType;

  /// Which camera to open.
  final CameraFace cameraFace;

  /// Called with every code read.
  final ValueChanged<String> onScanned;

  /// Drawn over the scanner.
  final Widget? child;

  /// App bar shown above the scanner, or null for none.
  final BarcodeAppBar? barcodeAppBar;

  /// Pause between two reads in continuous mode.
  final Duration? scanDelay;

  /// Whether the preview is mirrored.
  final bool flip;

  /// Called when the scanner closes.
  final VoidCallback? onClose;

  /// Symbologies to accept.
  final ScanFormat scanFormat;

  @override
  State<BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<BarcodeScannerPage> {
  StreamSubscription<dynamic>? _codes;
  bool _started = false;

  @override
  void dispose() {
    _codes?.cancel();
    super.dispose();
  }

  /// Platforms that reach the native scanner over the method channel.
  bool get _hasNativeScanner =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  /// Started from the first build rather than from `initState` so the native
  /// activity is not launched for a page that never gets mounted.
  void _startOnce() {
    if (_started) return;
    _started = true;
    if (widget.onClose != null) {
      _stream();
    } else {
      _scanOnce();
    }
  }

  Future<void> _scanOnce() async {
    final String code = await NativeScanner.scan(
      lineColor: widget.lineColor,
      cancelButtonText: widget.cancelButtonText,
      isShowFlashIcon: widget.isShowFlashIcon,
      scanMode: _scanModeOf(widget.scanType),
      delay: widget.scanDelay,
      cameraFace: widget.cameraFace,
      scanFormat: widget.scanFormat,
    );
    widget.onScanned(code);
  }

  void _stream() {
    _codes =
        NativeScanner.stream(
          lineColor: widget.lineColor,
          cancelButtonText: widget.cancelButtonText,
          isShowFlashIcon: widget.isShowFlashIcon,
          scanMode: _scanModeOf(widget.scanType),
          delay: widget.scanDelay,
          cameraFace: widget.cameraFace,
          scanFormat: widget.scanFormat,
        ).listen((dynamic code) {
          if (code is! String) return;
          if (code == kCancelValue) {
            widget.onClose?.call();
          } else {
            widget.onScanned(code);
          }
        });
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isWindows) {
      return WindowsBarcodeScannerPage(
        lineColor: widget.lineColor,
        cancelButtonText: widget.cancelButtonText,
        isShowFlashIcon: widget.isShowFlashIcon,
        scanType: widget.scanType,
        cameraFace: widget.cameraFace,
        onScanned: widget.onScanned,
        barcodeAppBar: widget.barcodeAppBar,
        scanDelay: widget.scanDelay,
        flip: widget.flip,
        onClose: widget.onClose,
      );
    }

    if (!_hasNativeScanner) {
      // Reaching the method channel here would only raise a
      // MissingPluginException, which says nothing useful.
      return Scaffold(
        body: Center(
          child: Text('$defaultTargetPlatform is not supported yet'),
        ),
      );
    }

    _startOnce();
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

/// Embedded scanner view for Android and iOS.
class BarcodeScannerView extends StatelessWidget {
  /// Creates the embedded view.
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

  Map<String, dynamic> get _creationParams => <String, dynamic>{
    'scanType': scanType.index,
    'cameraFace': cameraFace.index,
    'delayMillis': scanDelay?.inMilliseconds,
    'continuous': continuous,
    'scannerWidth': scannerWidth?.toInt(),
    'scannerHeight': scannerHeight?.toInt(),
    'scanFormat': scanFormat.wireName,
  };

  void _onPlatformViewCreated(int id) {
    final BarcodeViewController controller = BarcodeViewController.data(id);
    controller.onScanned = onScanned;
    onBarcodeViewCreated(controller);
  }

  @override
  Widget build(BuildContext context) {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidView(
          viewType: 'universal_barcode_scanner/view',
          onPlatformViewCreated: _onPlatformViewCreated,
          creationParams: _creationParams,
          creationParamsCodec: const StandardMessageCodec(),
        );
      case TargetPlatform.iOS:
        return UiKitView(
          viewType: 'universal_barcode_scanner/view',
          onPlatformViewCreated: _onPlatformViewCreated,
          creationParams: _creationParams,
          creationParamsCodec: const StandardMessageCodec(),
        );
      default:
        return Center(
          child: Text('$defaultTargetPlatform has no embedded scanner view'),
        );
    }
  }
}
