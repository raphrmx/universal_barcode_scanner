import 'dart:ui_web' as ui;

import 'package:flutter/material.dart';
import 'package:simple_barcode_scanner/barcode_appbar.dart';
import 'package:simple_barcode_scanner/constant.dart';
import 'package:simple_barcode_scanner/enum.dart';
import 'package:simple_barcode_scanner/screens/barcode_controller.dart';
// ignore: avoid_web_libraries_in_flutter
import 'package:web/web.dart' as html;

/// Barcode scanner for web using iframe
class BarcodeScanner extends StatelessWidget {
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
  final Function? onClose;
  final ScanFormat scanFormat;

  const BarcodeScanner({
    super.key,
    required this.lineColor,
    required this.cancelButtonText,
    required this.isShowFlashIcon,
    required this.scanType,
    this.cameraFace = CameraFace.back,
    required this.onScanned,
    this.appBarTitle,
    this.centerTitle,
    this.child,
    this.barcodeAppBar,
    this.delayMillis,
    this.onClose,
    this.flip,
    this.scanFormat = ScanFormat.ALL_FORMATS,
  });

  @override
  Widget build(BuildContext context) {
    final createdViewId = DateTime.now().microsecondsSinceEpoch.toString();
    String? barcodeNumber;

    final iframe = html.HTMLIFrameElement()
      ..src = PackageConstant.barcodeFileWebPath
      ..style.border = 'none'
      ..style.width = MediaQuery.of(context).size.width > 640 ? '640px' : '100%'
      ..style.height = MediaQuery.of(context).size.height > 480 ? '480px' : '100%'
      ..onLoad.listen((event) {
        /// Barcode listener on success barcode scanned
        html.window.onMessage.listen((event) {
          /// If barcode is null then assign scanned barcode
          /// and close the screen otherwise keep scanning
          if (barcodeNumber == null) {
            barcodeNumber = event.data.toString();
            onScanned(barcodeNumber!);
          }
        });
      });
    // ignore: undefined_prefixed_name
    ui.platformViewRegistry
        .registerViewFactory(createdViewId, (int viewId) => iframe);
    //final width = MediaQuery.of(context).size.width;
    //final height = MediaQuery.of(context).size.height;
    return Scaffold(
      appBar: _buildAppBar(context),
      body: Stack(
        children: [
          Center(
            child: SizedBox(
              width: MediaQuery.of(context).size.width > 640 ?  640 : MediaQuery.of(context).size.width,
              height: MediaQuery.of(context).size.width > 480 ?  480 : MediaQuery.of(context).size.height,
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()..rotateY(flip == true ? 3.1416 : 0),
                child: HtmlElementView(
                  viewType: createdViewId,
                ),
              ),
            ),
          ),
          if (child != null) child!,
        ],
      ),
    );
  }

  AppBar? _buildAppBar(BuildContext context) {
    if (appBarTitle == null && barcodeAppBar == null) {
      return null;
    }
    if (barcodeAppBar != null) {
      return AppBar(
        title: barcodeAppBar?.appBarTitle != null
            ? Text(barcodeAppBar!.appBarTitle!)
            : null,
        centerTitle: barcodeAppBar?.centerTitle ?? false,
        leading: barcodeAppBar?.enableBackButton == true
            ? IconButton(
                onPressed: () => Navigator.pop(context),
                icon: barcodeAppBar?.backButtonIcon ??
                    const Icon(Icons.arrow_back_ios))
            : null,
        automaticallyImplyLeading: false,
      );
    }
    return AppBar(
      title: Text(appBarTitle ?? kScanPageTitle),
      centerTitle: centerTitle,
      automaticallyImplyLeading: true,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios),
        onPressed: () => Navigator.pop(context),
      ),
    );
  }
}

typedef BarcodeScannerViewCreated = void Function(
    BarcodeViewController controller);

class BarcodeScannerView extends StatelessWidget {
  final BarcodeScannerViewCreated onBarcodeViewCreated;
  final ScanType scanType;
  final CameraFace cameraFace;
  final Function(String)? onScanned;
  final Widget? child;
  final int? delayMillis;
  final bool? flip;
  final Function? onClose;
  final bool continuous;
  final double? scannerWidth;
  final double? scannerHeight;
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
    return const Center(child: Text('Platform not supported'));
  }
}
