import 'dart:async';

import 'package:flutter/services.dart';
import 'package:universal_barcode_scanner/src/constants.dart';
import 'package:universal_barcode_scanner/src/enums.dart';

/// Scan mode understood by the Android and iOS scanners.
///
/// The native side reads the enum by index, so the order is part of the wire
/// format and must not change.
enum ScanMode { qr, barcode, defaultMode }

/// Thin wrapper over the Android and iOS method channel.
///
/// Please note that this code is a reimplementation of
/// https://github.com/AmolGangadhare/flutter_barcode_scanner, which has not
/// been updated for a long time.
abstract final class NativeScanner {
  static const MethodChannel _channel = MethodChannel(
    'universal_barcode_scanner',
  );

  static const EventChannel _eventChannel = EventChannel(
    'universal_barcode_scanner/events',
  );

  static Map<String, dynamic> _params({
    required Color lineColor,
    required String cancelButtonText,
    required bool isShowFlashIcon,
    required ScanMode scanMode,
    required Duration? delay,
    required CameraFace cameraFace,
    required ScanFormat scanFormat,
    required bool continuous,
  }) => <String, dynamic>{
    'lineColor': colorToHex(lineColor),
    'cancelButtonText': cancelButtonText,
    'isShowFlashIcon': isShowFlashIcon,
    'isContinuousScan': continuous,
    'scanMode': scanMode.index,
    'delayMillis': delay?.inMilliseconds ?? 0,
    'cameraFacingText': cameraFace.name.toUpperCase(),
    'scanFormat': scanFormat.wireName,
    'scannerWidth': 280,
    'scannerHeight': 280,
  };

  /// Scans with the camera until a code is read, then returns it.
  static Future<String> scan({
    required Color lineColor,
    required String cancelButtonText,
    required bool isShowFlashIcon,
    required ScanMode scanMode,
    required Duration? delay,
    required CameraFace cameraFace,
    required ScanFormat scanFormat,
  }) async {
    final Object? result = await _channel.invokeMethod(
      'scanBarcode',
      _params(
        lineColor: lineColor,
        cancelButtonText: cancelButtonText,
        isShowFlashIcon: isShowFlashIcon,
        scanMode: scanMode,
        delay: delay,
        cameraFace: cameraFace,
        scanFormat: scanFormat,
        continuous: false,
      ),
    );
    return result is String ? result : '';
  }

  /// Opens the camera and emits every code read until the user cancels.
  static Stream<dynamic> stream({
    required Color lineColor,
    required String cancelButtonText,
    required bool isShowFlashIcon,
    required ScanMode scanMode,
    required Duration? delay,
    required CameraFace cameraFace,
    required ScanFormat scanFormat,
  }) {
    _channel.invokeMethod(
      'scanBarcode',
      _params(
        lineColor: lineColor,
        cancelButtonText: cancelButtonText,
        isShowFlashIcon: isShowFlashIcon,
        scanMode: scanMode,
        delay: delay,
        cameraFace: cameraFace,
        scanFormat: scanFormat,
        continuous: true,
      ),
    );
    return _eventChannel.receiveBroadcastStream();
  }
}
