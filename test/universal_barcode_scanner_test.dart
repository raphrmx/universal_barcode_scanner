import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_barcode_scanner/src/constants.dart';
import 'package:universal_barcode_scanner/src/scanner_config.dart';
import 'package:universal_barcode_scanner/universal_barcode_scanner.dart';

const MethodChannel _channel = MethodChannel('universal_barcode_scanner');
const EventChannel _events = EventChannel('universal_barcode_scanner/events');

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

/// A home screen whose context the tests scan from.
class _Home extends StatelessWidget {
  const _Home(this.onContext);

  final ValueChanged<BuildContext> onContext;

  @override
  Widget build(BuildContext context) {
    onContext(context);
    return const Text('home');
  }
}

/// Pumps a few frames: enough for the scanner route to push, start and pop,
/// without waiting on its spinner, which never settles.
Future<void> _frames(WidgetTester tester) async {
  for (int i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// Runs [body] as if on [platform], and always puts the platform back: debug
/// flags are checked before tear-downs run.
Future<void> _on(TargetPlatform platform, Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  late List<MethodCall> calls;
  late Future<Object?> Function(MethodCall call) answer;

  setUp(() {
    calls = <MethodCall>[];
    answer = (MethodCall call) async => null;
    _messenger.setMockMethodCallHandler(_channel, (MethodCall call) {
      calls.add(call);
      return answer(call);
    });
  });

  tearDown(() {
    _messenger.setMockMethodCallHandler(_channel, null);
    _messenger.setMockStreamHandler(_events, null);
  });

  Future<BuildContext> pumpHome(WidgetTester tester) async {
    late BuildContext home;
    await tester.pumpWidget(
      MaterialApp(home: _Home((BuildContext context) => home = context)),
    );
    return home;
  }

  group('wire format', () {
    test('ScanFormat carries the names the native scanners expect', () {
      expect(ScanFormat.all.wireName, 'ALL_FORMATS');
      expect(ScanFormat.onlyQrCode.wireName, 'ONLY_QR_CODE');
      expect(ScanFormat.onlyBarcode.wireName, 'ONLY_BARCODE');
    });

    test('the native arguments name every setting', () {
      const ScannerConfig config = ScannerConfig(
        lineColor: Color(0xFF112233),
        cancelButtonText: 'Back',
        showFlashIcon: true,
        scanType: ScanType.qr,
        cameraFace: CameraFace.front,
        scanFormat: ScanFormat.onlyQrCode,
        scanDelay: Duration(milliseconds: 1500),
        continuous: true,
      );
      expect(config.toNative(), <String, Object?>{
        'lineColor': '#FF112233',
        'cancelButtonText': 'Back',
        'showFlashIcon': true,
        'continuous': true,
        'scanType': 'qr',
        'cameraFace': 'front',
        'scanFormat': 'ONLY_QR_CODE',
        'delayMillis': 1500,
      });
    });

    test('the page settings are what barcode.html reads', () {
      const ScannerConfig config = ScannerConfig(
        lineColor: Color(0xFF112233),
        cameraFace: CameraFace.front,
        scanFormat: ScanFormat.onlyBarcode,
        scanDelay: Duration(seconds: 2),
        continuous: true,
      );
      expect(
        config.toPage(background: const Color(0xFFFFFFFF)),
        <String, String>{
          'line': '#112233',
          'background': '#FFFFFF',
          'continuous': '1',
          'delay': '2000',
          'facing': 'user',
          'window': 'wide',
          'formats': 'barcode',
        },
      );
      expect(const ScannerConfig().toPage()['window'], 'wide');
      expect(
        const ScannerConfig(scanType: ScanType.qr).toPage()['window'],
        'square',
      );
      expect(const ScannerConfig().toPage().containsKey('background'), false);
    });
  });

  group('colorToHex', () {
    test('renders eight digits, alpha first', () {
      expect(colorToHex(const Color(0xFFFF6666)), '#FFFF6666');
      expect(colorToHex(kDefaultLineColor), '#FFFF6666');
    });

    test('pads a colour whose alpha is low', () {
      expect(colorToHex(const Color(0x0A0B0C0D)), '#0A0B0C0D');
    });
  });

  group('ScannerException', () {
    test('reads the codes the native scanners send', () {
      expect(
        ScannerErrorCode.fromWire('camera_permission_denied'),
        ScannerErrorCode.permissionDenied,
      );
      expect(
        ScannerErrorCode.fromWire('camera_unavailable'),
        ScannerErrorCode.cameraUnavailable,
      );
      expect(
        ScannerErrorCode.fromWire('already_active'),
        ScannerErrorCode.alreadyActive,
      );
      expect(ScannerErrorCode.fromWire('???'), ScannerErrorCode.unknown);
    });

    test('wraps a PlatformException', () {
      final ScannerException error = ScannerException.from(
        PlatformException(code: 'camera_unavailable', message: 'none'),
      );
      expect(error.code, ScannerErrorCode.cameraUnavailable);
      expect(error.message, 'none');
    });
  });

  group('scan', () {
    testWidgets('returns the code and closes the route', (
      WidgetTester tester,
    ) async {
      await _on(TargetPlatform.android, () async {
        answer = (MethodCall call) async => '-1';
        final BuildContext home = await pumpHome(tester);

        String? code = 'unset';
        unawaited(
          UniversalBarcodeScanner.scan(
            home,
            scanFormat: ScanFormat.onlyQrCode,
          ).then((String? value) => code = value),
        );
        await _frames(tester);

        // '-1' is a code like any other: nothing is reserved any more.
        expect(code, '-1');
        expect(calls.single.method, 'scanBarcode');
        final Map<Object?, Object?> arguments =
            calls.single.arguments as Map<Object?, Object?>;
        expect(arguments['continuous'], false);
        expect(arguments['scanFormat'], 'ONLY_QR_CODE');
        expect(find.text('home'), findsOneWidget);
      });
    });

    testWidgets('returns null when the user backs out', (
      WidgetTester tester,
    ) async {
      await _on(TargetPlatform.iOS, () async {
        final BuildContext home = await pumpHome(tester);

        String? code = 'unset';
        unawaited(
          UniversalBarcodeScanner.scan(
            home,
          ).then((String? value) => code = value),
        );
        await _frames(tester);

        expect(code, isNull);
        expect(find.text('home'), findsOneWidget);
      });
    });

    testWidgets('throws when the camera is refused, and closes the route', (
      WidgetTester tester,
    ) async {
      await _on(TargetPlatform.android, () async {
        answer = (MethodCall call) async => throw PlatformException(
          code: 'camera_permission_denied',
          message: 'refused',
        );
        final BuildContext home = await pumpHome(tester);

        Object? failure;
        unawaited(
          UniversalBarcodeScanner.scan(
            home,
          ).then<void>((_) {}, onError: (Object error) => failure = error),
        );
        await _frames(tester);

        expect(failure, isA<ScannerException>());
        expect(
          (failure! as ScannerException).code,
          ScannerErrorCode.permissionDenied,
        );
        expect(find.text('home'), findsOneWidget);
      });
    });

    testWidgets('closes the native scanner when the app pops the route', (
      WidgetTester tester,
    ) async {
      await _on(TargetPlatform.android, () async {
        final Completer<Object?> never = Completer<Object?>();
        answer = (MethodCall call) => call.method == 'scanBarcode'
            ? never.future
            : Future<Object?>.value();
        final BuildContext home = await pumpHome(tester);

        unawaited(UniversalBarcodeScanner.scan(home));
        await _frames(tester);
        Navigator.of(home).pop();
        await _frames(tester);

        expect(calls.map((MethodCall call) => call.method), <String>[
          'scanBarcode',
          'close',
        ]);
      });
    });
  });

  group('stream', () {
    testWidgets('emits every code, then closes with the scanner', (
      WidgetTester tester,
    ) async {
      await _on(TargetPlatform.android, () async {
        _messenger.setMockStreamHandler(
          _events,
          MockStreamHandler.inline(
            onListen: (Object? arguments, MockStreamHandlerEventSink sink) {
              sink
                ..success('A')
                ..success('B')
                ..success(<String, String>{'event': 'closed'});
            },
          ),
        );
        final BuildContext home = await pumpHome(tester);

        final List<String> codes = <String>[];
        bool done = false;
        UniversalBarcodeScanner.stream(
          home,
          scanDelay: const Duration(seconds: 1),
        ).listen(codes.add, onDone: () => done = true);
        await _frames(tester);

        expect(codes, <String>['A', 'B']);
        expect(done, true);
        final Map<Object?, Object?> arguments =
            calls.first.arguments as Map<Object?, Object?>;
        expect(arguments['continuous'], true);
        expect(arguments['delayMillis'], 1000);
        expect(find.text('home'), findsOneWidget);
      });
    });

    testWidgets('first() takes one code and closes the scanner', (
      WidgetTester tester,
    ) async {
      await _on(TargetPlatform.iOS, () async {
        _messenger.setMockStreamHandler(
          _events,
          MockStreamHandler.inline(
            onListen: (Object? arguments, MockStreamHandlerEventSink sink) {
              sink
                ..success('first')
                ..success('second');
            },
          ),
        );
        final BuildContext home = await pumpHome(tester);

        String? code;
        unawaited(
          UniversalBarcodeScanner.stream(
            home,
          ).first.then((String value) => code = value),
        );
        await _frames(tester);

        expect(code, 'first');
        expect(calls.map((MethodCall call) => call.method), contains('close'));
        expect(find.text('home'), findsOneWidget);
      });
    });

    testWidgets('emits a failure, then closes', (WidgetTester tester) async {
      await _on(TargetPlatform.android, () async {
        _messenger.setMockStreamHandler(
          _events,
          MockStreamHandler.inline(
            onListen: (Object? arguments, MockStreamHandlerEventSink sink) {
              sink.error(code: 'camera_unavailable', message: 'gone');
            },
          ),
        );
        final BuildContext home = await pumpHome(tester);

        final List<Object> errors = <Object>[];
        bool done = false;
        UniversalBarcodeScanner.stream(
          home,
        ).listen((_) {}, onError: errors.add, onDone: () => done = true);
        await _frames(tester);

        expect(errors.single, isA<ScannerException>());
        expect(
          (errors.single as ScannerException).code,
          ScannerErrorCode.cameraUnavailable,
        );
        expect(done, true);
        expect(find.text('home'), findsOneWidget);
      });
    });
  });

  group('UniversalBarcodeScanner', () {
    testWidgets('says so on a platform with no embedded view', (
      WidgetTester tester,
    ) async {
      await _on(TargetPlatform.linux, () async {
        await tester.pumpWidget(
          MaterialApp(
            home: UniversalBarcodeScanner(
              onScanned: (String _) {},
              onBarcodeViewCreated: (BarcodeViewController _) {},
            ),
          ),
        );

        expect(find.textContaining('embedded scanner view'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  });

  group('BarcodeViewController', () {
    test('turns an error from the view into a ScannerException', () async {
      final BarcodeViewController controller = BarcodeViewController.data(7);
      ScannerException? received;
      controller.onError = (ScannerException error) => received = error;

      await _messenger.handlePlatformMessage(
        'universal_barcode_scanner/view_7',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('onError', <String, String>{
            'code': 'camera_permission_denied',
            'message': 'refused',
          }),
        ),
        (ByteData? _) {},
      );

      expect(received?.code, ScannerErrorCode.permissionDenied);
      expect(received?.message, 'refused');
    });
  });
}
