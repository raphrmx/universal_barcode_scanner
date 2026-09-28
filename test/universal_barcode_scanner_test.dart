import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_barcode_scanner/src/constants.dart';
import 'package:universal_barcode_scanner/src/embedded_page.dart';
import 'package:universal_barcode_scanner/src/scanner_chrome.dart';
import 'package:universal_barcode_scanner/src/scanner_config.dart';
import 'package:universal_barcode_scanner/src/scanner_controller.dart';
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

    test('the page settings are what barcode.html reads', () {
      const ScannerConfig config = ScannerConfig(
        lineColor: Color(0xFF112233),
        cameraFace: CameraFace.front,
        scanFormat: ScanFormat.onlyBarcode,
        scanDelay: Duration(seconds: 2),
        continuous: true,
      );
      expect(
        config.toPage(host: 'desktop', background: const Color(0xFFFFFFFF)),
        <String, String>{
          'host': 'desktop',
          'line': '#112233',
          'background': '#FFFFFF',
          'continuous': '1',
          'delay': '2000',
          'facing': 'user',
          'window': 'wide',
          'formats': 'barcode',
        },
      );
      expect(
        const ScannerConfig(
          scanWindow: ScanWindow.square,
        ).toPage(host: 'web')['window'],
        'square',
      );
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

    test('drives the page and hears back from it', () async {
      final List<PageCall> calls = <PageCall>[];
      final PageScannerController controller = PageScannerController(
        calls.add,
        continuous: true,
      );
      final List<String> codes = <String>[];
      ScannerException? error;
      controller
        ..onScanned = codes.add
        ..onError = (ScannerException e) => error = e;
      controller.pageReady();

      await controller.pauseScanning();
      await controller.resumeScanning();
      final Future<bool> torch = controller.toggleFlash();
      controller
        ..handle(const PageCode('A'))
        ..handle(const PageError('camera_unavailable', 'busy'))
        ..handle(const PageTorch(on: true));

      expect(calls, <PageCall>[
        PageCall.pauseScanning,
        PageCall.resumeScanning,
        PageCall.toggleTorch,
      ]);
      expect(await torch, isTrue);
      expect(codes, <String>['A']);
      expect(error?.code, ScannerErrorCode.cameraUnavailable);

      controller
        ..dispose()
        ..handle(const PageCode('B'));
      await controller.pauseScanning();
      expect(codes, <String>['A']);
      expect(calls, hasLength(3));
      expect(await controller.toggleFlash(), isFalse);
    });

    test('holds calls back until the page is up', () async {
      final List<PageCall> calls = <PageCall>[];
      final PageScannerController controller = PageScannerController(
        calls.add,
        continuous: true,
      );

      await controller.resumeScanning();
      await controller.pauseScanning();
      final Future<bool> torch = controller.toggleFlash();
      expect(calls, isEmpty);

      controller.handle(const PageReady());
      expect(calls, <PageCall>[PageCall.pauseScanning, PageCall.toggleTorch]);
      controller.handle(const PageTorch(on: false));
      expect(await torch, isFalse);

      // A resume after a pause, both before the page was up, sends nothing.
      final List<PageCall> later = <PageCall>[];
      final PageScannerController other = PageScannerController(
        later.add,
        continuous: true,
      );
      await other.pauseScanning();
      await other.resumeScanning();
      other.pageReady();
      expect(later, isEmpty);
    });

    test('says when the view stops reading', () async {
      final PageScannerController controller = PageScannerController(
        (PageCall _) {},
        continuous: false,
      )..pageReady();
      expect(controller.paused.value, isFalse);

      // A view that is not continuous stops on its first code.
      controller.handle(const PageCode('A'));
      expect(controller.paused.value, isTrue);
      await controller.resumeScanning();
      expect(controller.paused.value, isFalse);
      await controller.pauseScanning();
      expect(controller.paused.value, isTrue);
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

      expect(window, const Size(340, 170));
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
