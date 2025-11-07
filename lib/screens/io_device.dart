import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:simple_barcode_scanner/barcode_appbar.dart';
import 'package:simple_barcode_scanner/constant.dart';
import 'package:simple_barcode_scanner/enum.dart';
import 'package:simple_barcode_scanner/flutter_barcode_scanner.dart';
import 'package:simple_barcode_scanner/screens/barcode_controller.dart';
import 'package:simple_barcode_scanner/screens/window.dart';

/// Barcode scanner for mobile and desktop devices
class BarcodeScanner extends StatefulWidget {
  final String lineColor;
  final String cancelButtonText;
  final bool isShowFlashIcon;
  final ScanType scanType;
  final CameraFace cameraFace;
  final Function(String) onScanned;
  final String? appBarTitle;
  final bool? centerTitle;
  final Widget? child;
  final BarcodeAppBar? barcodeAppBar;
  final int? delayMillis;
  final bool? flip;
  final void Function()? onClose;
  final ScanFormat scanFormat;

  const BarcodeScanner({
    super.key,
    required this.lineColor,
    required this.cancelButtonText,
    required this.isShowFlashIcon,
    required this.scanType,
    this.cameraFace = CameraFace.back,
    required this.onScanned,
    this.child,
    this.appBarTitle,
    this.centerTitle,
    this.barcodeAppBar,
    this.delayMillis,
    this.onClose,
    this.flip,
    this.scanFormat = ScanFormat.ALL_FORMATS,
  });

  @override
  State<BarcodeScanner> createState() => _BarcodeScannerState();
}

class _BarcodeScannerState extends State<BarcodeScanner> {
  @override
  Widget build(BuildContext context) {
    if (Platform.isWindows) {
      ///Get Window barcode Scanner UI
      return WindowBarcodeScanner(
        lineColor: widget.lineColor,
        cancelButtonText: widget.cancelButtonText,
        isShowFlashIcon: widget.isShowFlashIcon,
        scanType: widget.scanType,
        onScanned: widget.onScanned,
        onClose: widget.onClose,
        appBarTitle: widget.appBarTitle,
        barcodeAppBar: widget.barcodeAppBar,
        centerTitle: widget.centerTitle,
        delayMillis: widget.delayMillis,
        flip: widget.flip,
      );
    } else {
      /// Scan Android and ios barcode scanner with flutter_barcode_scanner
      /// If onClose is not null then stream barcode otherwise scan barcode
      /// Scan barcode for mobile devices
      ScanMode scanMode;
      switch (widget.scanType) {
        case ScanType.barcode:
          scanMode = ScanMode.BARCODE;
        case ScanType.qr:
          scanMode = ScanMode.QR;
        default:
          scanMode = ScanMode.DEFAULT;
      }
      widget.onClose != null
          ? _streamBarcodeForMobileAndTabDevices(scanMode)
          : _scanBarcodeForMobileAndTabDevices(scanMode);

      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
  }

  Future<void> _scanBarcodeForMobileAndTabDevices(ScanMode scanMode) async {
    final barcode = await FlutterBarcodeScanner.scanBarcode(
      widget.lineColor,
      widget.cancelButtonText,
      widget.isShowFlashIcon,
      scanMode,
      widget.delayMillis,
      widget.cameraFace.name.toUpperCase(),
      widget.scanFormat,
      widget.flip,
    );
    widget.onScanned(barcode);
  }

  void _streamBarcodeForMobileAndTabDevices(ScanMode scanMode) {
    FlutterBarcodeScanner.getBarcodeStreamReceiver(
      widget.lineColor,
      widget.cancelButtonText,
      widget.isShowFlashIcon,
      scanMode,
      widget.delayMillis,
      widget.cameraFace.name.toUpperCase(),
      widget.scanFormat,
      widget.flip,
    )?.listen((barcode) {
      if (barcode != null) {
        barcode == kCancelValue ? widget.onClose?.call() : widget.onScanned(barcode as String? ?? '');
      }
    });
  }
}

// This is for scanner Widget, which is used to scan the barcode.

typedef BarcodeScannerViewCreated = void Function(
    BarcodeViewController controller);

/// for widgets
class BarcodeScannerView extends StatelessWidget {
  final BarcodeScannerViewCreated onBarcodeViewCreated;
  final double? scannerWidth;
  final double? scannerHeight;
  final ScanType scanType;
  final CameraFace cameraFace;
  final Function(String)? onScanned;
  final Widget? child;
  final int? delayMillis;
  final bool? flip;
  final Function? onClose;
  final bool continuous;
  final ScanFormat scanFormat;
  const BarcodeScannerView(
      {super.key,
      this.scannerWidth,
      this.scannerHeight,
      required this.scanType,
      this.cameraFace = CameraFace.back,
      required this.onScanned,
      this.continuous = false,
      this.child,
      this.delayMillis,
      this.flip,
      this.onClose,
      this.scanFormat = ScanFormat.ALL_FORMATS,
      required this.onBarcodeViewCreated});

  @override
  Widget build(BuildContext context) {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidView(
          viewType: 'plugins.codingwithtashi/barcode_scanner_view',
          onPlatformViewCreated: _onPlatformViewCreated,
          creationParams: <String, dynamic>{
            'scanType': scanType.index,
            'cameraFace': cameraFace.index,
            'delayMillis': delayMillis,
            'continuous': continuous,
            'scannerWidth': scannerWidth?.toInt(),
            'scannerHeight': scannerHeight?.toInt(),
            'scanFormat': scanFormat.name,
          },
          creationParamsCodec: const StandardMessageCodec(),
        );
      case TargetPlatform.iOS:
        return UiKitView(
          viewType: 'plugins.codingwithtashi/barcode_scanner_view',
          onPlatformViewCreated: _onPlatformViewCreated,
          creationParams: <String, dynamic>{
            'scanType': scanType.index,
            'cameraFace': cameraFace.index,
            'delayMillis': delayMillis,
            'continuous': continuous,
            'scannerWidth': scannerWidth?.toInt(),
            'scannerHeight': scannerHeight?.toInt(),
            'scanFormat': scanFormat.name,
          },
          creationParamsCodec: const StandardMessageCodec(),
        );
      default:
        return Text(
            '$defaultTargetPlatform is not yet supported by the web_view plugin');
    }
  }

  // Callback method when platform view is created

  void _onPlatformViewCreated(int id) {
    final controller = BarcodeViewController.data(id);
    if (onScanned != null) {
      controller.setOnScanned(onScanned!);
    }
    onBarcodeViewCreated(controller);
  }
}
