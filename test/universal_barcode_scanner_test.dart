import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_barcode_scanner/src/constants.dart';
import 'package:universal_barcode_scanner/src/embedded_page.dart';
import 'package:universal_barcode_scanner/src/scan_feedback.dart';
import 'package:universal_barcode_scanner/src/scanner_buttons.dart';
import 'package:universal_barcode_scanner/src/scanner_chrome.dart';
import 'package:universal_barcode_scanner/src/scanner_config.dart';
import 'package:universal_barcode_scanner/src/scanner_controller.dart';
import 'package:universal_barcode_scanner/src/scanner_round_button.dart';
import 'package:universal_barcode_scanner/src/scanner_verdict.dart';
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

/// Lets events sent to the event channel reach the stream. The channel hands
/// them on outside the test's fake time, so a moment of real time is needed
/// before the frames that react to them.
Future<void> _deliver(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await _frames(tester);
}

int _sessionOf(MethodCall call) =>
    (call.arguments as Map<Object?, Object?>)['session']! as int;

void main() {
  late List<MethodCall> calls;
  late Future<Object?> Function(MethodCall call) answer;

  /// The event sink of the current continuous scan, once Dart listens.
  MockStreamHandlerEventSink? sink;

  setUp(() {
    calls = <MethodCall>[];
    sink = null;
    answer = (MethodCall call) async => null;
    _messenger.setMockMethodCallHandler(_channel, (MethodCall call) {
      calls.add(call);
      return answer(call);
    });
    _messenger.setMockStreamHandler(
      _events,
      MockStreamHandler.inline(
        onListen: (Object? arguments, MockStreamHandlerEventSink events) {
          sink = events;
        },
      ),
    );
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

  group('scanImage', () {
    test('hands the bytes and the formats to the native decoder', () async {
      answer = (MethodCall call) async => <Object?>[
        <String, Object?>{'code': '5412345678908', 'format': 'ean_13'},
        <String, Object?>{'code': 'WIFI:S:Home;;', 'format': 'qr_code'},
        <String, Object?>{'code': '', 'format': 'qr_code'},
      ];
      final List<ScanResult> codes = await UniversalBarcodeScanner.scanImage(
        <int>[1, 2, 3],
        scanFormat: ScanFormat.onlyBarcode,
      );
      expect(calls.single.method, 'scanImage');
      final Map<Object?, Object?> arguments =
          calls.single.arguments as Map<Object?, Object?>;
      expect(arguments['bytes'], Uint8List.fromList(<int>[1, 2, 3]));
      expect(arguments['scanFormat'], 'ONLY_BARCODE');
      // An empty code is no code.
      expect(codes, const <ScanResult>[
        ScanResult('5412345678908', format: BarcodeFormat.ean13),
        ScanResult('WIFI:S:Home;;', format: BarcodeFormat.qrCode),
      ]);
      expect(codes.last.content, isA<WifiContent>());
    });

    test('answers an empty list for an image with no code', () async {
      answer = (MethodCall call) async => <Object?>[];
      expect(await UniversalBarcodeScanner.scanImage(Uint8List(4)), isEmpty);
    });

    test('says when the bytes are no image', () async {
      answer = (MethodCall call) async => throw PlatformException(
        code: 'invalid_image',
        message: 'Not an image.',
      );
      await expectLater(
        UniversalBarcodeScanner.scanImage(<int>[0]),
        throwsA(
          isA<ScannerException>().having(
            (ScannerException e) => e.code,
            'code',
            ScannerErrorCode.invalidImage,
          ),
        ),
      );
    });

    test('reads the page answer for an image', () {
      final PageMessage? read = PageMessage.parse(
        '{"image":3,"codes":[{"code":"abc","format":"qr_code"},'
        '{"code":"","format":"qr_code"}]}',
      );
      expect(read, isA<PageImage>());
      final PageImage image = read! as PageImage;
      expect(image.id, 3);
      expect(image.results, const <ScanResult>[
        ScanResult('abc', format: BarcodeFormat.qrCode),
      ]);

      final PageImage failed =
          PageMessage.parse(
                '{"image":4,"failed":"invalid_image","message":"no"}',
              )!
              as PageImage;
      expect(failed.results, isNull);
      expect(failed.failed, 'invalid_image');
      expect(failed.message, 'no');
    });
  });

  group('wire format', () {
    test('ScanFormat carries the names the native scanners expect', () {
      expect(ScanFormat.all.wireName, 'ALL_FORMATS');
      expect(ScanFormat.onlyQrCode.wireName, 'ONLY_QR_CODE');
      expect(ScanFormat.onlyBarcode.wireName, 'ONLY_BARCODE');
    });

    test('the native arguments name every setting', () {
      const ScannerConfig config = ScannerConfig(
        lineColor: Color(0xFF112233),
        cancelLabel: 'Back',
        showTorchButton: true,
        scanWindow: ScanWindow.square,
        cameraFace: CameraFace.front,
        scanFormat: ScanFormat.onlyQrCode,
        scanDelay: Duration(milliseconds: 1500),
        continuous: true,
      );
      expect(config.toNative(), <String, Object?>{
        'lineColor': '#FF112233',
        'cancelLabel': 'Back',
        'showTorchButton': true,
        'continuous': true,
        'scanWindow': 'square',
        'cameraFace': 'front',
        'scanFormat': 'ONLY_QR_CODE',
        'delayMillis': 1500,
      });
    });

    test('asks for frames only when the app wants them', () {
      const ScannerConfig config = ScannerConfig(
        scanFormat: ScanFormat.none,
        frameInterval: Duration(milliseconds: 250),
      );
      expect(config.toNative()['frameMillis'], 250);
      expect(config.toNative()['scanFormat'], 'NONE');
      expect(config.toPage(host: 'web')['frames'], '250');
      expect(config.toPage(host: 'web')['formats'], 'none');
      expect(
        const ScannerConfig().toNative().containsKey('frameMillis'),
        isFalse,
      );
      expect(
        const ScannerConfig().toPage(host: 'web').containsKey('frames'),
        isFalse,
      );
    });

    test('reads a frame from a platform and from the page', () {
      final Uint8List bytes = Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6]);
      final ScanFrame? frame = ScanFrame.fromWire(<String, Object?>{
        'width': 3,
        'height': 2,
        'bytes': bytes,
        'quarterTurns': 5,
      });
      expect(frame?.width, 3);
      expect(frame?.height, 2);
      expect(frame?.quarterTurns, 1);
      expect(
        ScanFrame.fromWire(<String, Object?>{
          'width': 4,
          'height': 2,
          'bytes': bytes,
        }),
        isNull,
      );
      final PageMessage? message = PageMessage.parse(
        jsonEncode(<String, Object?>{
          'frame': <String, Object?>{
            'width': 3,
            'height': 2,
            'data': base64Encode(bytes),
          },
        }),
      );
      expect(message, isA<PageFrame>());
      expect((message! as PageFrame).frame.bytes, bytes);
    });

    test('the page settings are what barcode.html reads', () {
      const ScannerConfig config = ScannerConfig(
        lineColor: Color(0xFF112233),
        cameraFace: CameraFace.front,
        scanFormat: ScanFormat.onlyBarcode,
        scanDelay: Duration(seconds: 2),
        continuous: true,
      );
      final Map<String, String> page = config.toPage(
        host: 'desktop',
        background: const Color(0xFFFFFFFF),
      );
      // The words, checked on their own below.
      expect(page.remove('labels'), isNotNull);
      expect(page, <String, String>{
        'host': 'desktop',
        'line': '#112233',
        'background': '#FFFFFF',
        'continuous': '1',
        'delay': '2000',
        'facing': 'user',
        'window': 'wide',
        'flipX': '0',
        'flipY': '0',
        'animate': '1',
        'formats': 'barcode',
      });
      expect(
        const ScannerConfig(
          scanWindow: ScanWindow.square,
        ).toPage(host: 'web')['window'],
        'square',
      );
    });

    test('hands the page its words, for where it runs', () {
      Map<String, Object?> words(ScannerLabels labels, String host) =>
          jsonDecode(
                ScannerConfig(labels: labels).toPage(host: host)['labels']!,
              )
              as Map<String, Object?>;

      expect(words(ScannerLabels.english, 'web')['blocked'], <String>[
        'Camera blocked',
        ScannerLabels.english.cameraBlockedWeb,
      ]);
      expect(words(ScannerLabels.french, 'desktop')['blocked'], <String>[
        'Caméra bloquée',
        ScannerLabels.french.cameraBlockedDesktop,
      ]);
      expect(words(ScannerLabels.dutch, 'web').keys, <String>[
        'blocked',
        'missing',
        'busy',
        'insecure',
        'failed',
        'decoder',
      ]);
      expect(ScannerLabels.german.copyWith(torch: 'Licht').torch, 'Licht');
    });

    test('no window reaches every side as none', () {
      const ScannerConfig config = ScannerConfig(scanWindow: ScanWindow.none);
      expect(config.toNative()['scanWindow'], 'none');
      expect(config.toPage(host: 'web')['window'], 'none');
    });

    // The desktop page is kept between two scans: a background left out
    // would keep the previous scan's.
    test('the page always gets a background', () {
      expect(
        const ScannerConfig().toPage(host: 'web')['background'],
        '#000000',
      );
    });

    test('page messages are JSON, so no code reads as a command', () {
      expect(
        PageMessage.parse('{"code":"{\\"close\\":true}"}'),
        isA<PageCode>().having(
          (PageCode m) => m.code,
          'code',
          '{"close":true}',
        ),
      );
      expect(PageMessage.parse('{"close":true}'), isA<PageClose>());
      expect(PageMessage.parse('plain text'), isNull);
      expect(PageMessage.parse('{"code":""}'), isNull);
      expect(PageMessage.parse(42), isNull);
    });

    test('reads a camera error and the torch state', () {
      expect(
        PageMessage.parse(
          '{"error":{"code":"camera_permission_denied","message":"no"}}',
        ),
        isA<PageError>()
            .having((PageError m) => m.code, 'code', 'camera_permission_denied')
            .having((PageError m) => m.message, 'message', 'no'),
      );
      expect(
        PageMessage.parse('{"torch":true}'),
        isA<PageTorch>().having((PageTorch m) => m.on, 'on', true),
      );
      expect(PageMessage.parse('{"torch":"yes"}'), isNull);
      expect(PageMessage.parse('{"ready":true}'), isA<PageReady>());
    });
  });

  group('the embedded page', () {
    test('sends the embedded settings with the scan window', () {
      final Map<String, String> page = const ScannerConfig(
        scanWindow: ScanWindow.square,
      ).toEmbeddedPage(host: 'web', window: const Size(240.4, 240.6));

      expect(page['embedded'], '1');
      expect(page['window'], 'square');
      expect(page['windowWidth'], '240');
      expect(page['windowHeight'], '241');
    });

    test('places the window as the native views do', () {
      expect(
        scanWindowRect(const Size(400, 300), ScanWindow.none, null),
        isNull,
      );
      expect(
        scanWindowRect(const Size(400, 300), ScanWindow.square, null),
        Rect.fromCenter(
          center: const Offset(200, 150),
          width: 225,
          height: 225,
        ),
      );
      // Capped on a wide view.
      expect(
        scanWindowRect(const Size(1000, 800), ScanWindow.wide, null)?.size,
        const Size(416, 208),
      );
      // Clear of the buttons at the sides, and low in a short view, so the
      // dimmed surround still frames it.
      final Size low = scanWindowRect(
        const Size(480, 210),
        ScanWindow.wide,
        null,
      )!.size;
      expect(low.width, moreOrLessEquals(345.6));
      expect(low.height, 126);
      // A requested size, clamped to the view.
      expect(
        scanWindowRect(
          const Size(200, 100),
          ScanWindow.wide,
          const Size(300, 60),
        )?.size,
        const Size(200, 60),
      );
    });

    /// A link that notes every call as `name(arguments)`.
    PageLink link(
      List<String> calls, {
      ScannerConfig config = const ScannerConfig(),
    }) => PageLink(
      (String name, List<Object> arguments) =>
          calls.add('$name(${arguments.join(', ')})'),
      config,
    );

    test('drives the page and hears back from it', () async {
      final List<String> calls = <String>[];
      final PageScannerController controller = PageScannerController(
        link(calls)..ready(const ScannerConfig()),
        continuous: true,
      );
      final List<ScanResult> results = <ScanResult>[];
      ScannerException? error;
      controller
        ..onResult = results.add
        ..onError = (ScannerException e) => error = e;

      await controller.pauseScanning();
      expect(controller.isPaused.value, isTrue);
      await controller.resumeScanning();
      final Future<bool> torch = controller.toggleFlash();
      final Future<double> zoom = controller.setZoom(2);
      controller
        ..handle(const PageCode('A', format: BarcodeFormat.ean13))
        ..handle(const PageError('camera_unavailable', 'busy'))
        ..handle(const PageTorch(on: true))
        ..handle(const PageZoom(2));

      expect(calls, <String>[
        'pauseScanning()',
        'resumeScanning()',
        'toggleTorch()',
        'setZoom(2.0)',
      ]);
      expect(await torch, isTrue);
      expect(controller.isTorchOn.value, isTrue);
      expect(await zoom, 2);
      expect(controller.zoom.value, 2);
      expect(results, <ScanResult>[
        const ScanResult('A', format: BarcodeFormat.ean13),
      ]);
      expect(error?.code, ScannerErrorCode.cameraUnavailable);

      controller
        ..dispose()
        ..handle(const PageCode('B'));
      await controller.pauseScanning();
      expect(results, hasLength(1));
      expect(calls, hasLength(4));
      expect(await controller.toggleFlash(), isFalse);
    });

    test('holds calls back until the page is up', () async {
      final List<String> calls = <String>[];
      final PageLink page = link(calls);
      final PageScannerController controller = PageScannerController(
        page,
        continuous: true,
      );

      await controller.resumeScanning();
      await controller.pauseScanning();
      final Future<bool> torch = controller.toggleFlash();
      page
        ..setFlip(horizontal: true, vertical: false)
        ..switchFace()
        ..setWindow(const Size(200, 100));
      expect(calls, isEmpty);

      page.ready(const ScannerConfig(), window: const Size(200, 100));
      // What differs from what the page opened with, and no more.
      expect(calls, <String>[
        'setFlip(true, false)',
        'setFacing(user)',
        'pauseScanning()',
        'toggleTorch()',
      ]);
      controller.handle(const PageTorch(on: false));
      expect(await torch, isFalse);

      // A resume after a pause, both before the page was up, sends nothing.
      final List<String> later = <String>[];
      final PageLink other = link(later);
      final PageScannerController second = PageScannerController(
        other,
        continuous: true,
      );
      await second.pauseScanning();
      await second.resumeScanning();
      other.ready(const ScannerConfig());
      expect(later, isEmpty);
    });

    test('sends each change once, and none that changes nothing', () {
      final List<String> calls = <String>[];
      final PageLink page = link(
        calls,
        config: const ScannerConfig(flipHorizontal: true),
      )..ready(const ScannerConfig(flipHorizontal: true));

      page
        ..setFlip(horizontal: true, vertical: false)
        ..setWindow(const Size(300, 120))
        ..setWindow(const Size(300, 120))
        ..setFace(CameraFace.back);
      expect(calls, <String>['setWindow(300, 120)']);
    });

    test('says when the view stops reading', () async {
      final List<String> calls = <String>[];
      final PageScannerController controller = PageScannerController(
        link(calls)..ready(const ScannerConfig()),
        continuous: false,
      );
      expect(controller.isPaused.value, isFalse);

      // A view that is not continuous stops on its first code, by itself:
      // nothing to send.
      controller.handle(const PageCode('A'));
      expect(controller.isPaused.value, isTrue);
      expect(calls, isEmpty);
      await controller.resumeScanning();
      expect(controller.isPaused.value, isFalse);
      expect(calls, <String>['resumeScanning()']);
      await controller.pauseScanning();
      expect(controller.isPaused.value, isTrue);
      controller.dispose();
    });

    testWidgets('stops the scan line while paused', (
      WidgetTester tester,
    ) async {
      final ValueNotifier<bool> paused = ValueNotifier<bool>(false);
      addTearDown(paused.dispose);
      await tester.pumpWidget(
        ScanWindowOverlay(
          window: const Rect.fromLTWH(10, 10, 200, 100),
          lineColor: const Color(0xFFFF6666),
          paused: paused,
        ),
      );
      expect(tester.binding.hasScheduledFrame, isTrue);

      paused.value = true;
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);

      paused.value = false;
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isTrue);
    });

    testWidgets('reports the window it draws over the page', (
      WidgetTester tester,
    ) async {
      Size? window;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 400,
              height: 300,
              child: EmbeddedPageFrame(
                view: const SizedBox.expand(),
                config: const ScannerConfig(),
                onWindow: (Size size) => window = size,
              ),
            ),
          ),
        ),
      );

      expect(window, const Size(288, 144));
      expect(find.byType(ScanWindowOverlay), findsOneWidget);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 400,
            height: 300,
            child: EmbeddedPageFrame(
              view: const SizedBox.expand(),
              config: const ScannerConfig(scanWindow: ScanWindow.none),
              onWindow: (Size size) => window = size,
            ),
          ),
        ),
      );
      expect(window, Size.zero);
      expect(find.byType(ScanWindowOverlay), findsNothing);
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
    testWidgets("hands the native screen the bar's cancel label", (
      WidgetTester tester,
    ) async {
      await _on(TargetPlatform.android, () async {
        answer = (MethodCall call) async => null;
        final BuildContext home = await pumpHome(tester);

        unawaited(
          UniversalBarcodeScanner.scan(
            home,
            bar: const ScannerBar(cancelLabel: 'Retour'),
            buttons: const <ScannerButton>{ScannerButton.torch},
          ),
        );
        await _frames(tester);

        final Map<Object?, Object?> arguments =
            calls.single.arguments as Map<Object?, Object?>;
        expect(arguments['cancelLabel'], 'Retour');
        // A torch button asked for shows the native one.
        expect(arguments['showTorchButton'], true);
      });
    });

    testWidgets('still takes the old cancelLabel, first', (
      WidgetTester tester,
    ) async {
      await _on(TargetPlatform.android, () async {
        answer = (MethodCall call) async => null;
        final BuildContext home = await pumpHome(tester);

        unawaited(
          UniversalBarcodeScanner.scan(
            home,
            cancelLabel: 'Annuler',
            bar: const ScannerBar(cancelLabel: 'Retour'),
          ),
        );
        await _frames(tester);

        expect(
          (calls.single.arguments as Map<Object?, Object?>)['cancelLabel'],
          'Annuler',
        );
      });
    });

    testWidgets('scanResult says which symbology the code is', (
      WidgetTester tester,
    ) async {
      await _on(TargetPlatform.android, () async {
        answer = (MethodCall call) async => <String, Object?>{
          'code': 'https://pub.dev',
          'format': 'qr_code',
        };
        final BuildContext home = await pumpHome(tester);

        ScanResult? result;
        unawaited(
          UniversalBarcodeScanner.scanResult(
            home,
            scanWindowSize: const Size(240, 120),
          ).then((ScanResult? value) => result = value),
        );
        await _frames(tester);

        expect(
          result,
          const ScanResult('https://pub.dev', format: BarcodeFormat.qrCode),
        );
        expect(result!.format.isTwoDimensional, isTrue);
        final Map<Object?, Object?> arguments =
            calls.single.arguments as Map<Object?, Object?>;
        expect(arguments['scanWindowWidth'], 240);
        expect(arguments['scanWindowHeight'], 120);
      });
    });

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
        expect(arguments['session'], isA<int>());
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

    testWidgets('closes the native scanner as soon as the route is popped', (
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
        // One frame: well before the exit transition has run.
        await tester.pump();

        expect(calls.map((MethodCall call) => call.method), <String>[
          'scanBarcode',
          'close',
        ]);
        // The close names the scan it means.
        expect(_sessionOf(calls[1]), _sessionOf(calls[0]));
        await _frames(tester);
      });
    });

    testWidgets('keeps a code read while another route covers the scanner', (
      WidgetTester tester,
    ) async {
      await _on(TargetPlatform.android, () async {
        final Completer<Object?> read = Completer<Object?>();
        answer = (MethodCall call) => call.method == 'scanBarcode'
            ? read.future
            : Future<Object?>.value();
        final BuildContext home = await pumpHome(tester);

        String? code;
        unawaited(
          UniversalBarcodeScanner.scan(
            home,
          ).then((String? value) => code = value),
        );
        await _frames(tester);
        Navigator.of(
          home,
        ).push(MaterialPageRoute<void>(builder: (_) => const Text('on top')));
        await _frames(tester);

        read.complete('behind');
        await _frames(tester);

        expect(code, 'behind');
        expect(find.text('on top'), findsOneWidget);
      });
    });
  });

  group('stream', () {
    // Events are sent from the test body once the scan has asked for them:
    // sent from inside a mock handler, they are delivered outside the test's
    // fake time and only after it ends.
    int openedSession() => _sessionOf(
      calls.firstWhere((MethodCall call) => call.method == 'scanBarcode'),
    );

    testWidgets('emits every code, then closes with the scanner', (
      WidgetTester tester,
    ) async {
      await _on(TargetPlatform.android, () async {
        final BuildContext home = await pumpHome(tester);

        final List<String> codes = <String>[];
        bool done = false;
        UniversalBarcodeScanner.stream(
          home,
          scanDelay: const Duration(seconds: 1),
        ).listen(codes.add, onDone: () => done = true);
        await _frames(tester);

        final int session = openedSession();
        sink!
          ..success(<String, Object?>{'session': session, 'code': 'A'})
          // Another scan's leftovers are not this one's.
          ..success(<String, Object?>{'session': session + 99, 'code': 'X'})
          ..success(<String, Object?>{
            'session': session + 99,
            'event': 'closed',
          })
          ..success(<String, Object?>{'session': session, 'code': 'B'})
          ..success(<String, Object?>{'session': session, 'event': 'closed'});
        await _deliver(tester);

        expect(codes, <String>['A', 'B']);
        expect(done, true);
        final Map<Object?, Object?> arguments =
            calls.first.arguments as Map<Object?, Object?>;
        expect(arguments['continuous'], true);
        expect(arguments['delayMillis'], 1000);
        expect(find.text('home'), findsOneWidget);
      });
    });

    testWidgets('resultStream says which symbology each code is', (
      WidgetTester tester,
    ) async {
      await _on(TargetPlatform.android, () async {
        final BuildContext home = await pumpHome(tester);

        final List<ScanResult> results = <ScanResult>[];
        UniversalBarcodeScanner.resultStream(home).listen(results.add);
        await _frames(tester);

        final int session = openedSession();
        sink!
          ..success(<String, Object?>{
            'session': session,
            'code': '5412345678908',
            'format': 'ean_13',
          })
          // From a scanner that does not say.
          ..success(<String, Object?>{'session': session, 'code': 'B'})
          ..success(<String, Object?>{'session': session, 'event': 'closed'});
        await _deliver(tester);

        expect(results, <ScanResult>[
          const ScanResult('5412345678908', format: BarcodeFormat.ean13),
          const ScanResult('B'),
        ]);
      });
    });

    testWidgets('first() takes one code and closes the scanner', (
      WidgetTester tester,
    ) async {
      await _on(TargetPlatform.iOS, () async {
        final BuildContext home = await pumpHome(tester);

        String? code;
        unawaited(
          UniversalBarcodeScanner.stream(
            home,
          ).first.then((String value) => code = value),
        );
        await _frames(tester);

        final int session = openedSession();
        sink!
          ..success(<String, Object?>{'session': session, 'code': 'first'})
          ..success(<String, Object?>{'session': session, 'code': 'second'});
        await _deliver(tester);

        expect(code, 'first');
        final MethodCall close = calls.firstWhere(
          (MethodCall call) => call.method == 'close',
        );
        expect(_sessionOf(close), session);
        expect(find.text('home'), findsOneWidget);
      });
    });

    testWidgets('emits a failure, then closes', (WidgetTester tester) async {
      await _on(TargetPlatform.android, () async {
        final BuildContext home = await pumpHome(tester);

        final List<Object> errors = <Object>[];
        bool done = false;
        UniversalBarcodeScanner.stream(
          home,
        ).listen((_) {}, onError: errors.add, onDone: () => done = true);
        await _frames(tester);

        final int session = openedSession();
        sink!
          // Meant for another scan: ignored.
          ..error(code: 'camera_unavailable', details: session + 99)
          ..error(
            code: 'camera_unavailable',
            message: 'gone',
            details: session,
          );
        await _deliver(tester);

        expect(errors.single, isA<ScannerException>());
        expect((errors.single as ScannerException).message, 'gone');
        expect(done, true);
        expect(find.text('home'), findsOneWidget);
      });
    });
  });

  group('validator', () {
    int openedSession() => _sessionOf(
      calls.firstWhere((MethodCall call) => call.method == 'scanBarcode'),
    );

    testWidgets('scan reads on past a code refused, and says so', (
      WidgetTester tester,
    ) async {
      await _on(TargetPlatform.android, () async {
        final BuildContext home = await pumpHome(tester);

        ScanResult? result;
        bool done = false;
        unawaited(
          UniversalBarcodeScanner.scanResult(
            home,
            labels: ScannerLabels.french,
            validator: (ScanResult code) => code.text.startsWith('OK'),
          ).then((ScanResult? value) {
            result = value;
            done = true;
          }),
        );
        await _frames(tester);

        final int session = openedSession();
        // The native scanner reads on, for the validator to see every code.
        expect(
          (calls.first.arguments as Map<Object?, Object?>)['continuous'],
          true,
        );
        sink!.success(<String, Object?>{'session': session, 'code': 'NO'});
        await _deliver(tester);
        expect(done, false);
        expect(
          calls
              .singleWhere((MethodCall call) => call.method == 'rejected')
              .arguments,
          <String, Object?>{'session': session, 'message': 'Code refusé'},
        );

        sink!.success(<String, Object?>{
          'session': session,
          'code': 'OK-1',
          'format': 'qr_code',
        });
        await _deliver(tester);
        expect(done, true);
        expect(result, const ScanResult('OK-1', format: BarcodeFormat.qrCode));
        expect(calls.any((MethodCall call) => call.method == 'close'), true);
      });
    });

    testWidgets('stream emits only the codes accepted', (
      WidgetTester tester,
    ) async {
      await _on(TargetPlatform.android, () async {
        final BuildContext home = await pumpHome(tester);

        final List<ScanResult> codes = <ScanResult>[];
        UniversalBarcodeScanner.resultStream(
          home,
          validator: (ScanResult code) => code.format == BarcodeFormat.ean13,
        ).listen(codes.add);
        await _frames(tester);

        final int session = openedSession();
        sink!
          ..success(<String, Object?>{
            'session': session,
            'code': 'A',
            'format': 'qr_code',
          })
          ..success(<String, Object?>{
            'session': session,
            'code': '5412345678908',
            'format': 'ean_13',
          });
        await _deliver(tester);

        expect(codes, const <ScanResult>[
          ScanResult('5412345678908', format: BarcodeFormat.ean13),
        ]);
        expect(
          calls.where((MethodCall call) => call.method == 'rejected'),
          hasLength(1),
        );
      });
    });

    testWidgets('a refusal shows over the camera, then goes', (
      WidgetTester tester,
    ) async {
      final ScanVerdicts verdicts = ScanVerdicts();
      addTearDown(verdicts.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ScannerChrome(
            body: const SizedBox.expand(),
            verdicts: verdicts,
            rejectedLabel: 'Not this one',
          ),
        ),
      );
      expect(find.text('Not this one'), findsNothing);

      verdicts.rejected();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Not this one'), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Not this one'), findsNothing);
    });

    testWidgets('a code accepted flashes the edge green, without words', (
      WidgetTester tester,
    ) async {
      final ScanVerdicts verdicts = ScanVerdicts();
      addTearDown(verdicts.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ScannerChrome(
            body: const SizedBox.expand(),
            verdicts: verdicts,
            rejectedLabel: 'Not this one',
          ),
        ),
      );
      Color? edge() {
        final Iterable<DecoratedBox> boxes = tester
            .widgetList<DecoratedBox>(find.byType(DecoratedBox))
            .where((DecoratedBox box) {
              final Decoration decoration = box.decoration;
              return decoration is BoxDecoration && decoration.border != null;
            });
        if (boxes.isEmpty) return null;
        final BoxDecoration decoration =
            boxes.single.decoration as BoxDecoration;
        return (decoration.border! as Border).top.color;
      }

      verdicts.accepted();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final Color green = edge()!;
      expect(green.g, greaterThan(green.r));
      expect(find.text('Not this one'), findsNothing);

      await tester.pump(const Duration(milliseconds: 400));
      expect(edge(), isNull);
    });
  });

  group('the buttons', () {
    /// A controller that records what the buttons ask of it.
    ScannerButtons buttons(List<String> calls, {bool torchAnswer = true}) =>
        ScannerButtons(
          flipHorizontal: true,
          flipVertical: false,
          onFlip: (bool h, bool v) => calls.add('flip $h $v'),
        )..controller = _RecordingController(calls, torchAnswer);

    Widget host(
      ScannerButtons state,
      Set<ScannerButton> set, {
      AlignmentGeometry alignment = Alignment.topRight,
    }) => Directionality(
      textDirection: TextDirection.ltr,
      // Loose, so the box keeps its own size under the test window.
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 400,
          height: 300,
          child: ScannerButtonsOverlay(
            state: state,
            buttons: set,
            alignment: alignment,
          ),
        ),
      ),
    );

    testWidgets('drive the controller and the flips', (
      WidgetTester tester,
    ) async {
      final List<String> calls = <String>[];
      final ScannerButtons state = buttons(calls);
      await tester.pumpWidget(host(state, ScannerButton.values.toSet()));

      await tester.tap(find.bySemanticsLabel('Flip horizontally'));
      await tester.tap(find.bySemanticsLabel('Flip vertically'));
      await tester.tap(find.bySemanticsLabel('Pause'));
      await tester.tap(find.bySemanticsLabel('Torch'));
      await tester.pump();

      expect(calls, <String>[
        'flip false false',
        'flip false true',
        'pause',
        'torch',
      ]);
      expect(state.paused, isTrue);
      expect(state.torch, isTrue);
      // The pause button now offers to resume.
      expect(find.bySemanticsLabel('Resume'), findsOneWidget);
    });

    testWidgets('say what the labels say, and switch the camera', (
      WidgetTester tester,
    ) async {
      final List<String> calls = <String>[];
      final ScannerButtons state = ScannerButtons(
        flipHorizontal: false,
        flipVertical: false,
        onFlip: (bool h, bool v) {},
        onSwitchCamera: () => calls.add('switch'),
      )..controller = _RecordingController(calls, true);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ScannerButtonGroup(
            state: state,
            buttons: ScannerButton.values.toSet(),
            labels: ScannerLabels.french,
          ),
        ),
      );

      await tester.tap(find.bySemanticsLabel('Pause'));
      await tester.pump();
      expect(find.bySemanticsLabel('Reprendre'), findsOneWidget);
      expect(find.bySemanticsLabel('Lampe'), findsOneWidget);

      // The pause is the scanner's: the other camera keeps it.
      await tester.tap(find.bySemanticsLabel('Changer de caméra'));
      await tester.pump();
      expect(calls, <String>['pause', 'switch']);
      expect(state.paused, isTrue);
    });

    test(
      'go through the zooms, and back to 1 past what the camera can do',
      () async {
        final _ZoomingController camera = _ZoomingController(max: 2.5);
        final ScannerButtons state = ScannerButtons(
          flipHorizontal: false,
          flipVertical: false,
          onFlip: (bool h, bool v) {},
        )..controller = camera;

        await state.cycleZoom();
        expect(state.zoom, 2);
        await state.cycleZoom();
        // 3 asked, 2.5 applied.
        expect(state.zoom, 2.5);
        await state.cycleZoom();
        // Nothing further: round again.
        expect(state.zoom, 1);
        expect(camera.asked, <double>[2, 3, 1]);

        // A camera that cannot zoom stays at 1.
        final _ZoomingController webcam = _ZoomingController(max: 1);
        state.controller = webcam;
        await state.cycleZoom();
        expect(state.zoom, 1);
        state.dispose();
      },
    );

    testWidgets('show only those asked for, in a fixed order', (
      WidgetTester tester,
    ) async {
      final ScannerButtons state = buttons(<String>[]);
      await tester.pumpWidget(
        host(state, <ScannerButton>{
          ScannerButton.flipVertical,
          ScannerButton.torch,
        }),
      );

      expect(find.bySemanticsLabel('Pause'), findsNothing);
      expect(
        tester.getCenter(find.bySemanticsLabel('Torch')).dx,
        lessThan(tester.getCenter(find.bySemanticsLabel('Flip vertically')).dx),
      );
    });

    testWidgets('sit where they are told, along a side when centred on it', (
      WidgetTester tester,
    ) async {
      final ScannerButtons state = buttons(<String>[]);
      const Set<ScannerButton> two = <ScannerButton>{
        ScannerButton.torch,
        ScannerButton.pause,
      };

      await tester.pumpWidget(host(state, two));
      Rect torch() => tester.getRect(find.bySemanticsLabel('Torch'));
      Rect pause() => tester.getRect(find.bySemanticsLabel('Pause'));
      // Top right, 12 in, side by side.
      expect(pause().topRight, const Offset(388, 12));
      expect(torch().top, pause().top);

      await tester.pumpWidget(
        host(state, two, alignment: Alignment.centerRight),
      );
      expect(torch().left, pause().left);
      expect(pause().right, 388);

      await tester.pumpWidget(
        host(state, two, alignment: Alignment.bottomCenter),
      );
      expect(torch().bottom, 288);
      expect(torch().top, pause().top);
    });

    /// The group in an app, for keyboard focus, the mouse and tooltips.
    Future<ScannerButtons> pumpInApp(
      WidgetTester tester,
      List<String> calls, {
      ScannerButtonStyle style = const ScannerButtonStyle(),
    }) async {
      final ScannerButtons state = buttons(calls);
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 400,
              height: 300,
              child: ScannerButtonsOverlay(
                state: state,
                buttons: const <ScannerButton>{
                  ScannerButton.torch,
                  ScannerButton.pause,
                },
                style: style,
                alignment: Alignment.centerRight,
              ),
            ),
          ),
        ),
      );
      return state;
    }

    testWidgets('are reached with Tab and pressed with Enter or Space', (
      WidgetTester tester,
    ) async {
      final List<String> calls = <String>[];
      await pumpInApp(tester, calls);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      // The button the keyboard is on says what it does.
      expect(find.text('Torch'), findsOneWidget);
      // And has a ring around it, clear of its edge.
      expect(
        tester.getRect(_focusRing),
        tester.getRect(find.bySemanticsLabel('Torch')).inflate(4),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(calls, <String>['torch', 'pause']);
      expect(find.bySemanticsLabel('Resume'), findsOneWidget);
    });

    testWidgets('show the hand, and say what they do when the mouse rests', (
      WidgetTester tester,
    ) async {
      await pumpInApp(tester, <String>[]);
      final TestGesture mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.bySemanticsLabel('Torch')));
      await tester.pump();

      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.click,
      );
      expect(find.text('Torch'), findsNothing);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Torch'), findsOneWidget);
      // Down the right side: the tooltip opens towards the middle.
      expect(
        tester.getRect(find.text('Torch')).right,
        lessThan(tester.getRect(find.bySemanticsLabel('Torch')).left),
      );

      await mouse.moveTo(const Offset(10, 10));
      await tester.pump();
      expect(find.text('Torch'), findsNothing);
    });

    testWidgets('take the style they are given', (WidgetTester tester) async {
      await pumpInApp(
        tester,
        <String>[],
        style: const ScannerButtonStyle(
          size: 56,
          spacing: 20,
          showTooltips: false,
        ),
      );
      final Rect torch = tester.getRect(find.bySemanticsLabel('Torch'));
      final Rect pause = tester.getRect(find.bySemanticsLabel('Pause'));
      expect(torch.size, const Size(56, 56));
      expect(pause.top - torch.bottom, 20);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Torch'), findsNothing);
      expect(
        const ScannerButtonStyle().copyWith(size: 30),
        const ScannerButtonStyle(size: 30),
      );
    });

    testWidgets('keep clear of the close button without a bar', (
      WidgetTester tester,
    ) async {
      final ScannerButtons state = buttons(<String>[]);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ScannerChrome(
            body: const SizedBox.expand(),
            onClose: () {},
            buttons: ScannerButtonGroup(
              state: state,
              buttons: const <ScannerButton>{ScannerButton.torch},
            ),
            buttonsAlignment: Alignment.topLeft,
          ),
        ),
      );

      final Rect close = tester.getRect(find.bySemanticsLabel('Close'));
      final Rect torch = tester.getRect(find.bySemanticsLabel('Torch'));
      expect(torch.left, greaterThan(close.right));

      // The close button takes the same look, and the keyboard too.
      bool closed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: ScannerChrome(
            body: const SizedBox.expand(),
            onClose: () => closed = true,
            closeLabel: 'Fermer',
            buttonStyle: const ScannerButtonStyle(size: 50),
          ),
        ),
      );
      expect(
        tester.getSize(
          find.byWidgetPredicate(
            (Widget w) => w is ScannerRoundButton && w.label == 'Fermer',
          ),
        ),
        const Size(50, 50),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(closed, isTrue);
    });

    testWidgets('give the back icon of a bar its colour', (
      WidgetTester tester,
    ) async {
      const Color red = Color(0xFFFF0000);
      await tester.pumpWidget(
        MaterialApp(
          home: ScannerChrome(
            body: const SizedBox.expand(),
            bar: const ScannerBar(
              foregroundColor: red,
              backIcon: Icon(IconData(0xe5e0)),
            ),
            onClose: () {},
          ),
        ),
      );
      // Not the app's, which is dark on a light theme.
      expect(IconTheme.of(tester.element(find.byType(Icon))).color, red);
    });

    testWidgets('leave the back button of a bar reachable too', (
      WidgetTester tester,
    ) async {
      bool closed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: ScannerChrome(
            body: const SizedBox.expand(),
            bar: const ScannerBar(cancelLabel: 'Retour'),
            onClose: () => closed = true,
          ),
        ),
      );
      expect(_focusRing, findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(_focusRing, findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(closed, isTrue);
    });

    testWidgets('are drawn over an embedded view', (WidgetTester tester) async {
      await _on(TargetPlatform.fuchsia, () async {
        await tester.pumpWidget(
          MaterialApp(
            home: UniversalBarcodeScanner(
              onCreated: (ScannerController _) {},
              buttons: const <ScannerButton>{ScannerButton.flipHorizontal},
            ),
          ),
        );
        expect(find.bySemanticsLabel('Flip horizontally'), findsOneWidget);
        // Mirrored by default off a phone.
        final ScannerRoundButton flip = tester.widget<ScannerRoundButton>(
          find.byWidgetPredicate(
            (Widget w) =>
                w is ScannerRoundButton && w.label == 'Flip horizontally',
          ),
        );
        expect(flip.on, isTrue);
      });
    });
  });

  group('feedback', () {
    testWidgets('vibrates and beeps when asked, and only then', (
      WidgetTester tester,
    ) async {
      final List<String> calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          calls.add(call.method);
          return null;
        },
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('universal_barcode_scanner'),
        (MethodCall call) async {
          calls.add(call.method);
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger
          ..setMockMethodCallHandler(SystemChannels.platform, null)
          ..setMockMethodCallHandler(
            const MethodChannel('universal_barcode_scanner'),
            null,
          );
      });
      await _on(TargetPlatform.android, () async {
        ScanFeedback.play(vibrate: false, beep: false);
        await tester.pump();
        expect(calls, isEmpty);
        ScanFeedback.play(vibrate: true, beep: true);
        await tester.pump();
        expect(calls, <String>['HapticFeedback.vibrate', 'beep']);

        // A refusal: its own sound, and two pulses.
        calls.clear();
        ScanFeedback.rejected(vibrate: true, beep: true);
        await tester.pump(ScanFeedback.rejectedPulseGap);
        expect(calls, <String>[
          'rejectedBeep',
          'HapticFeedback.vibrate',
          'HapticFeedback.vibrate',
        ]);
      });
      await _on(TargetPlatform.linux, () async {
        calls.clear();
        ScanFeedback.play(vibrate: false, beep: true);
        ScanFeedback.rejected(vibrate: false, beep: true);
        await tester.pump();
        // Linux has only the system's own alert sound, for both.
        expect(calls, <String>['SystemSound.play', 'SystemSound.play']);
      });
    });
  });

  group('ScannerChrome', () {
    testWidgets('offers a way out when there is no bar', (
      WidgetTester tester,
    ) async {
      bool closed = false;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ScannerChrome(
            body: const SizedBox.expand(),
            onClose: () => closed = true,
          ),
        ),
      );

      await tester.tap(find.bySemanticsLabel('Close'));
      expect(closed, true);
    });
  });

  group('UniversalBarcodeScanner', () {
    test('mirrors a webcam by default, not a phone camera', () {
      final Map<TargetPlatform, bool> expected = <TargetPlatform, bool>{
        TargetPlatform.android: false,
        TargetPlatform.iOS: false,
        TargetPlatform.macOS: true,
        TargetPlatform.windows: true,
        TargetPlatform.linux: true,
      };
      try {
        expected.forEach((TargetPlatform platform, bool flips) {
          debugDefaultTargetPlatformOverride = platform;
          expect(
            UniversalBarcodeScanner.flipsByDefault,
            flips,
            reason: '$platform',
          );
        });
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    test('tells the page whether to animate', () {
      expect(const ScannerConfig().toPage(host: 'web')['animate'], '1');
      expect(
        const ScannerConfig(animate: false).toPage(host: 'web')['animate'],
        '0',
      );
    });

    testWidgets('turns a native view over when flipped, unless told not to', (
      WidgetTester tester,
    ) async {
      // A native view needs the engine to create it: answer as it would.
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform_views,
        (MethodCall call) async => call.method == 'create' ? 0 : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform_views,
          null,
        ),
      );
      await _on(TargetPlatform.iOS, () async {
        Future<void> pump({required bool flip, bool animate = true}) =>
            tester.pumpWidget(
              MaterialApp(
                home: UniversalBarcodeScanner(
                  onCreated: (ScannerController _) {},
                  flip: flip,
                  animate: animate,
                ),
              ),
            );
        double scaleX() => tester
            .widget<Transform>(
              find
                  .ancestor(
                    of: find.byType(UiKitView),
                    matching: find.byType(Transform),
                  )
                  .first,
            )
            .transform
            .storage[0];

        await pump(flip: false);
        expect(scaleX(), 1);

        await pump(flip: true);
        await tester.pump(const Duration(milliseconds: 175));
        // Half way through, edge on.
        expect(scaleX(), closeTo(0, 0.1));
        await tester.pumpAndSettle();
        expect(scaleX(), -1);

        await pump(flip: false, animate: false);
        await tester.pump();
        expect(scaleX(), 1);
      });
    });

    testWidgets('opens the other camera as a new native view', (
      WidgetTester tester,
    ) async {
      int views = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform_views,
        (MethodCall call) async => call.method == 'create' ? views++ : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform_views,
          null,
        ),
      );
      await _on(TargetPlatform.iOS, () async {
        final List<ScannerController> created = <ScannerController>[];
        await tester.pumpWidget(
          MaterialApp(
            home: UniversalBarcodeScanner(
              onCreated: created.add,
              buttons: const <ScannerButton>{ScannerButton.switchCamera},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(created, hasLength(1));

        await tester.tap(find.bySemanticsLabel('Switch camera'));
        await tester.pumpAndSettle();
        expect(created, hasLength(2));
        expect(
          (tester.widget<UiKitView>(find.byType(UiKitView)).creationParams!
              as Map<String, Object?>)['cameraFace'],
          'front',
        );
      });
    });

    testWidgets('fades a native view in from black, unless told not to', (
      WidgetTester tester,
    ) async {
      // The id Flutter gave the last view, which names its channel.
      int view = -1;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform_views,
        (MethodCall call) async {
          if (call.method != 'create') return null;
          return view = (call.arguments as Map<Object?, Object?>)['id']! as int;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform_views,
          null,
        ),
      );
      await _on(TargetPlatform.iOS, () async {
        Future<void> pump({bool animate = true}) => tester.pumpWidget(
          MaterialApp(
            home: UniversalBarcodeScanner(
              key: ValueKey<bool>(animate),
              onCreated: (ScannerController _) {},
              animate: animate,
            ),
          ),
        );
        double veil() => tester
            .widget<FadeTransition>(
              find
                  .ancestor(
                    of: find.byWidgetPredicate(
                      (Widget w) =>
                          w is ColoredBox && w.color == const Color(0xFF000000),
                    ),
                    matching: find.byType(FadeTransition),
                  )
                  .first,
            )
            .opacity
            .value;

        /// The view saying its camera shows frames, as it does natively.
        Future<void> cameraStarted() =>
            tester.binding.defaultBinaryMessenger.handlePlatformMessage(
              'universal_barcode_scanner/view_$view',
              const StandardMethodCodec().encodeMethodCall(
                const MethodCall('onCameraStarted'),
              ),
              (ByteData? _) {},
            );

        await pump();
        await tester.pump();
        // The camera is not up yet: black, for as long as it takes.
        expect(veil(), 1);
        await tester.pump(const Duration(milliseconds: 800));
        expect(veil(), 1);
        // Its first frame: the fade.
        await cameraStarted();
        await tester.pumpAndSettle();
        expect(veil(), 0);

        // A view that never says so is shown anyway, a little later.
        await tester.pumpWidget(const SizedBox());
        await pump();
        await tester.pump();
        expect(veil(), 1);
        await tester.pump(const Duration(milliseconds: 1500));
        await tester.pumpAndSettle();
        expect(veil(), 0);

        await pump(animate: false);
        await tester.pump();
        expect(veil(), 0);
      });
    });

    testWidgets('takes a validator and continuous without restarting', (
      WidgetTester tester,
    ) async {
      int views = 0;
      int view = -1;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform_views,
        (MethodCall call) async {
          if (call.method != 'create') return null;
          views++;
          return view = (call.arguments as Map<Object?, Object?>)['id']! as int;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform_views,
          null,
        ),
      );
      await _on(TargetPlatform.iOS, () async {
        final List<String> asked = <String>[];
        final List<String> codes = <String>[];
        late ScannerController controller;
        Future<void> pump({ScanValidator? validator}) => tester.pumpWidget(
          MaterialApp(
            home: UniversalBarcodeScanner(
              onCreated: (ScannerController created) => controller = created,
              onResult: (ScanResult result) => codes.add(result.text),
              validator: validator,
            ),
          ),
        );
        Future<void> read(String code) =>
            tester.binding.defaultBinaryMessenger.handlePlatformMessage(
              'universal_barcode_scanner/view_$view',
              const StandardMethodCodec().encodeMethodCall(
                MethodCall('onBarcodeDetected', <String, Object?>{
                  'code': code,
                  'format': 'qr_code',
                }),
              ),
              (ByteData? _) {},
            );

        await pump();
        await tester.pump();
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          MethodChannel('universal_barcode_scanner/view_$view'),
          (MethodCall call) async {
            asked.add(call.method);
            return null;
          },
        );
        // The view reads on; the widget pauses it on the first code.
        expect(
          (tester.widget<UiKitView>(find.byType(UiKitView)).creationParams!
              as Map<String, Object?>)['continuous'],
          true,
        );
        await read('A');
        await read('B');
        await tester.pump();
        expect(codes, <String>['A']);
        expect(asked, <String>['pauseScanning']);
        expect(controller.isPaused.value, isTrue);

        await controller.resumeScanning();
        await pump(validator: (ScanResult code) => code.text != 'X');
        await tester.pump();
        expect(views, 1);
        await read('X');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(codes, <String>['A']);
        expect(find.text('Code not accepted'), findsOneWidget);

        await read('C');
        await tester.pump();
        expect(codes, <String>['A', 'C']);
        await tester.pumpAndSettle();
        expect(views, 1);
      });
    });

    test('hands the page each flip', () {
      expect(
        const ScannerConfig(flipHorizontal: true).toPage(host: 'web'),
        containsPair('flipX', '1'),
      );
      final Map<String, String> both = const ScannerConfig(
        flipHorizontal: true,
        flipVertical: true,
      ).toEmbeddedPage(host: 'desktop', window: Size.zero);
      expect(both['flipX'], '1');
      expect(both['flipY'], '1');
    });

    testWidgets('says so on a platform with no embedded view', (
      WidgetTester tester,
    ) async {
      await _on(TargetPlatform.fuchsia, () async {
        await tester.pumpWidget(
          MaterialApp(
            home: UniversalBarcodeScanner(
              onScanned: (String _) {},
              onCreated: (ScannerController _) {},
            ),
          ),
        );

        expect(find.textContaining('embedded scanner view'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Closed again: a view that never showed a native camera still goes
        // cleanly, as on Windows and Linux.
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      });
    });
  });

  group('ScannerController', () {
    Future<void> send(int id, String method, Object? arguments) =>
        _messenger.handlePlatformMessage(
          'universal_barcode_scanner/view_$id',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(method, arguments),
          ),
          (ByteData? _) {},
        );

    test('turns an error from the view into a ScannerException', () async {
      final ScannerController controller = ChannelScannerController(7);
      ScannerException? received;
      controller.onError = (ScannerException error) => received = error;

      await send(7, 'onError', <String, String>{
        'code': 'camera_permission_denied',
        'message': 'refused',
      });

      expect(received?.code, ScannerErrorCode.permissionDenied);
      expect(received?.message, 'refused');
      controller.dispose();
    });

    test('hands on codes until it is disposed', () async {
      final ScannerController controller = ChannelScannerController(8);
      final List<String> codes = <String>[];
      controller.onScanned = codes.add;

      await send(8, 'onBarcodeDetected', 'before');
      controller.dispose();
      await send(8, 'onBarcodeDetected', 'after');

      expect(codes, <String>['before']);
    });
  });
}

/// Answers the buttons as a scanner would, noting each call.
final class _RecordingController extends ScannerController {
  _RecordingController(this.calls, this.torchAnswer);

  final List<String> calls;
  final bool torchAnswer;

  @override
  Future<bool> toggleFlash() async {
    calls.add('torch');
    markTorch(torchAnswer);
    return torchAnswer;
  }

  @override
  Future<void> pauseScanning() async {
    calls.add('pause');
    markPaused(true);
  }

  @override
  Future<void> resumeScanning() async {
    calls.add('resume');
    markPaused(false);
  }
}

/// A camera that zooms as far as [max].
final class _ZoomingController extends ScannerController {
  _ZoomingController({required this.max});

  final double max;
  final List<double> asked = <double>[];

  @override
  Future<double> setZoom(double zoom) async {
    asked.add(zoom);
    final double applied = zoom.clamp(1, max).toDouble();
    markZoom(applied);
    return applied;
  }

  @override
  Future<bool> toggleFlash() async => false;

  @override
  Future<void> pauseScanning() async {}

  @override
  Future<void> resumeScanning() async {}
}

/// The ring drawn around what the keyboard is on.
final Finder _focusRing = find.byWidgetPredicate(
  (Widget w) =>
      w is DecoratedBox &&
      w.decoration is BoxDecoration &&
      (w.decoration as BoxDecoration).border != null,
);
