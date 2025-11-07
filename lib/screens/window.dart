import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:simple_barcode_scanner/barcode_appbar.dart';
import 'package:simple_barcode_scanner/constant.dart';
import 'package:simple_barcode_scanner/enum.dart';
import 'package:webview_windows/webview_windows.dart';

class WindowBarcodeScanner extends StatefulWidget {
  final String lineColor;
  final String cancelButtonText;
  final bool isShowFlashIcon;
  final ScanType scanType;
  final CameraFace cameraFace;
  final Function(String) onScanned;
  final String? appBarTitle;
  final bool? centerTitle;
  final BarcodeAppBar? barcodeAppBar;
  final int? delayMillis;
  final bool? flip;
  final Function? onClose;

  const WindowBarcodeScanner({
    super.key,
    required this.lineColor,
    required this.cancelButtonText,
    required this.isShowFlashIcon,
    required this.scanType,
    this.cameraFace = CameraFace.back,
    required this.onScanned,
    this.appBarTitle,
    this.centerTitle,
    this.barcodeAppBar,
    this.delayMillis,
    this.onClose,
    this.flip,
  });

  @override
  State<WindowBarcodeScanner> createState() => _WindowBarcodeScannerState();
}

class _WindowBarcodeScannerState extends State<WindowBarcodeScanner> {
  late WebviewController controller;

  @override
  void initState() {
    super.initState();
    controller = WebviewController();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool isPermissionGranted = false;

    _checkCameraPermission().then((granted) {
      debugPrint("Permission is $granted");
      isPermissionGranted = granted;
    });

    return Scaffold(
      appBar: _buildAppBar(controller, context),
      body: FutureBuilder<bool>(
          future: initPlatformState(
            controller: controller,
          ),
          builder: (context, snapshot) {
            if (snapshot.hasData && snapshot.data != null) {
              return Column(
                children: [
                  Expanded(
                    child: Center(
                      child: Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()..rotateY(widget.flip == true ? 3.1416 : 0),
                        child: Webview(
                          controller,
                          width: 640,
                          height: 480,
                          filterQuality: FilterQuality.high,
                          permissionRequested: (url, permissionKind, isUserInitiated) =>
                              _onPermissionRequested(
                            url: url,
                            kind: permissionKind,
                            isUserInitiated: isUserInitiated,
                            context: context,
                            isPermissionGranted: isPermissionGranted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            } else if (snapshot.hasError) {
              return Center(
                child: Text(snapshot.error.toString()),
              );
            }
            return const Center(
              child: CircularProgressIndicator(),
            );
          }),
    );
  }

  /// Checks if camera permission has already been granted
  Future<bool> _checkCameraPermission() async {
    return await Permission.camera.status.isGranted;
  }

  Future<WebviewPermissionDecision> _onPermissionRequested(
      {required String url,
      required WebviewPermissionKind kind,
      required bool isUserInitiated,
      required BuildContext context,
      required bool isPermissionGranted}) async {
    final WebviewPermissionDecision? decision;

    if (!isPermissionGranted) {
      decision = await showDialog<WebviewPermissionDecision>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('Permission requested'),
          content:
              Text("'${kind.name}' permission is require to scan qr/barcode"),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.pop(context, WebviewPermissionDecision.deny);
              },
              child: const Text('Deny'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context, WebviewPermissionDecision.allow);
              },
              child: const Text('Allow'),
            ),
          ],
        ),
      );
    } else {
      decision = WebviewPermissionDecision.allow;
    }

    return decision ?? WebviewPermissionDecision.none;
  }

  String getAssetFileUrl({required String asset}) {
    final assetsDirectory = p.join(p.dirname(Platform.resolvedExecutable),
        'data', 'flutter_assets', asset);
    return Uri.file(assetsDirectory).toString();
  }

  Future<bool> initPlatformState(
      {required WebviewController controller}) async {
    String? barcodeNumber;

    try {
      await controller.initialize();
      await controller
          .loadUrl(getAssetFileUrl(asset: PackageConstant.barcodeFilePath));

      /// Listen to web to receive barcode
      controller.webMessage.listen((event) {
        if (event['methodName'] == "successCallback") {
          if (event['data'] is String && event['data'].isNotEmpty == true && barcodeNumber == null) {
            barcodeNumber = event['data'] as String;
            widget.onScanned(barcodeNumber!);
          }
        }
      });
    } catch (e) {
      rethrow;
    }
    return true;
  }

  AppBar? _buildAppBar(WebviewController controller, BuildContext context) {
    if (widget.appBarTitle == null && widget.barcodeAppBar == null) {
      return null;
    }
    if (widget.barcodeAppBar != null) {
      return AppBar(
        title: widget.barcodeAppBar?.appBarTitle != null
            ? Text(widget.barcodeAppBar!.appBarTitle!)
            : null,
        centerTitle: widget.barcodeAppBar?.centerTitle ?? false,
        leading: widget.barcodeAppBar!.enableBackButton == true
            ? IconButton(
                onPressed: () {
                  /// send close event to web-view
                  controller.postWebMessage(json.encode({"event": "close"}));
                  //controller.dispose();
                  Navigator.pop(context);
                },
                icon: widget.barcodeAppBar?.backButtonIcon ??
                    const Icon(Icons.arrow_back_ios),
              )
            : null,
        automaticallyImplyLeading: false,
      );
    }
    return AppBar(
      title: Text(widget.appBarTitle ?? kScanPageTitle),
      centerTitle: widget.centerTitle ?? true,
      leading: IconButton(
        onPressed: () {
          /// send close event to web-view
          controller.postWebMessage(json.encode({"event": "close"}));
          controller.dispose();
          Navigator.pop(context);
        },
        icon: const Icon(Icons.arrow_back_ios),
      ),
    );
  }
}
