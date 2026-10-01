import 'dart:async';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:universal_barcode_scanner/universal_barcode_scanner.dart';

import 'check_in.dart';

void main() => runApp(const ExampleApp());

const Color _paper = Color(0xFFF6F1EA);
const Color _white = Color(0xFFFFFDFB);
const Color _ink = Color(0xFF1D1712);
const Color _line = Color(0xFFE6DDD1);
const Color _dim = Color(0xFF6F665E);
const Color _accent = Color(0xFF3D9970);
const Color _accentInk = Color(0xFF2B7A55);
const Color _red = Color(0xFFD43F45);

/// The soft shadow under every card.
const List<BoxShadow> _shadow = <BoxShadow>[
  BoxShadow(color: Color(0x1F3B2A1A), blurRadius: 24, offset: Offset(0, 10)),
];

/// Width of the page's column of content.
const double _contentWidth = 520;

const ScannerBar _appBar = ScannerBar(
  title: 'Point at a barcode',
  centerTitle: false,
  showBackButton: true,
  backIcon: Icon(Icons.arrow_back_ios),
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
        scaffoldBackgroundColor: _paper,
        colorScheme: ColorScheme.fromSeed(seedColor: _accent),
        chipTheme: const ChipThemeData(
          backgroundColor: _white,
          selectedColor: Color(0xFFDDEFE5),
          side: BorderSide(color: _line),
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
  StreamSubscription<ScanResult>? _stream;

  /// What the last read gave: one code from the camera, every code of an
  /// image.
  List<ScanResult> _results = const <ScanResult>[];
  String _mode = '';
  int _count = 0;

  /// Whether the camera sits in the result tile.
  bool _embedded = false;

  /// Where the scanner's own buttons sit, in every mode.
  Alignment _buttonsAt = Alignment.centerRight;

  /// The buttons over the camera: the torch, pausing and both flips. Pausing
  /// means little to a scan that ends on its first code.
  static const Set<ScannerButton> _allButtons = <ScannerButton>{
    ScannerButton.torch,
    ScannerButton.pause,
    ScannerButton.flipHorizontal,
    ScannerButton.flipVertical,
    ScannerButton.zoom,
    ScannerButton.switchCamera,
  };
  static const Set<ScannerButton> _onceButtons = <ScannerButton>{
    ScannerButton.torch,
    ScannerButton.flipHorizontal,
    ScannerButton.flipVertical,
    ScannerButton.zoom,
    ScannerButton.switchCamera,
  };

  /// The words of the buttons and of the page, in every mode.
  ScannerLabels _labels = ScannerLabels.english;

  /// How the buttons look, in every mode.
  ScannerButtonStyle _style = const ScannerButtonStyle();

  /// Which codes the camera modes take; the others are refused over the
  /// camera and reading goes on.
  ScanValidator? _accept;

  static final List<(String, ScanValidator?)> _accepts =
      <(String, ScanValidator?)>[
    ('Any code', null),
    ('Links only', (ScanResult code) => code.content is UrlContent),
    (
      'Products only',
      (ScanResult code) =>
          code.format == BarcodeFormat.ean13 ||
          code.format == BarcodeFormat.ean8 ||
          code.format == BarcodeFormat.upcA ||
          code.format == BarcodeFormat.upcE,
    ),
  ];

  static const List<(String, ScannerButtonStyle)> _styles =
      <(String, ScannerButtonStyle)>[
    ('Round', ScannerButtonStyle()),
    (
      'Square',
      ScannerButtonStyle(
        backgroundColor: Color(0xCCFFFFFF),
        foregroundColor: Color(0xFF0E1014),
        activeBackgroundColor: _accent,
        activeForegroundColor: Color(0xFFFFFFFF),
        focusColor: _accent,
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
    ),
    ('Large', ScannerButtonStyle(size: 56, iconSize: 26, spacing: 10)),
  ];

  @override
  void dispose() {
    _stream?.cancel();
    super.dispose();
  }

  void _found(ScanResult result, String mode) {
    if (!mounted) return;
    setState(() {
      _results = <ScanResult>[result];
      _mode = mode;
      _count++;
    });
  }

  /// An image the user picks: a photo, a screenshot, a scan. The package
  /// takes bytes; where they come from is the app's business, here
  /// `file_picker`.
  Future<void> _pickImage() async {
    final PlatformFile? file = await FilePicker.pickFile(type: FileType.image);
    if (file == null) return;
    await _readImage(await file.readAsBytes());
  }

  /// Pictures that ship with the app, one per kind of content, to try the
  /// reader without an image of one's own.
  static const List<(String, String)> _samples = <(String, String)>[
    ('Wi-Fi', 'wifi'),
    ('Link', 'link'),
    ('Contact', 'contact'),
    ('E-mail', 'email'),
    ('Phone', 'phone'),
    ('Text message', 'sms'),
    ('Place', 'place'),
    ('Event', 'event'),
    ('Product', 'product'),
    ('Two at once', 'two_codes'),
  ];

  /// The sample picture [name], from the app's assets.
  Future<void> _readSample(String name) async {
    final ByteData image = await rootBundle.load('assets/samples/$name.png');
    await _readImage(
      image.buffer.asUint8List(image.offsetInBytes, image.lengthInBytes),
    );
  }

  /// Every code in [bytes], an encoded image.
  Future<void> _readImage(Uint8List bytes) async {
    try {
      final List<ScanResult> results = await UniversalBarcodeScanner.scanImage(
        bytes,
      );
      if (!mounted) return;
      setState(() {
        _results = results;
        _mode = 'image';
        _count++;
      });
    } on ScannerException catch (error) {
      _failed(error);
    }
  }

  /// One camera at a time: the tile's goes before a scanner opens.
  Future<void> _closeEmbedded() async {
    if (!_embedded) return;
    _toggleEmbedded();
    await WidgetsBinding.instance.endOfFrame;
  }

  /// Embedded: the camera opens in the result tile, and closes from the same
  /// button.
  void _toggleEmbedded() => setState(() => _embedded = !_embedded);

  /// One shot: opens the scanner, comes back with a code or null.
  Future<void> _scanOnce() async {
    await _stream?.cancel();
    await _closeEmbedded();
    if (!mounted) return;
    try {
      final ScanResult? result = await UniversalBarcodeScanner.scanResult(
        context,
        bar: _appBar,
        cameraFace: CameraFace.back,
        scanFormat: ScanFormat.all,
        buttons: _onceButtons,
        buttonsAlignment: _buttonsAt,
        labels: _labels,
        buttonStyle: _style,
        vibrate: true,
        beep: true,
        validator: _accept,
      );
      if (result != null) _found(result, 'one shot');
    } on ScannerException catch (error) {
      _failed(error);
    }
  }

  /// Continuous: the stream closes on its own when the route goes away.
  Future<void> _scanStream() async {
    await _stream?.cancel();
    await _closeEmbedded();
    if (!mounted) return;
    _stream = UniversalBarcodeScanner.resultStream(
      context,
      bar: _appBar,
      scanDelay: const Duration(seconds: 2),
      buttons: _allButtons,
      buttonsAlignment: _buttonsAt,
      labels: _labels,
      buttonStyle: _style,
      vibrate: true,
      beep: true,
      validator: _accept,
    ).listen(
      (ScanResult result) => _found(result, 'continuous'),
      onError: (Object error) {
        if (error is ScannerException) _failed(error);
      },
    );
  }

  void _failed(ScannerException error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(switch (error.code) {
          ScannerErrorCode.permissionDenied =>
            'The camera permission was refused.',
          ScannerErrorCode.invalidImage => 'The image could not be opened.',
          _ => 'The camera could not be used.',
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        // The whole page scrolls, its scrollbar at the window's edge; the
        // content keeps to a column in the middle.
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double side = math.max(
              20,
              (constraints.maxWidth - _contentWidth) / 2,
            );
            return ListView(
              padding: EdgeInsets.fromLTRB(side, 28, side, 32),
              children: <Widget>[
                const Text(
                  'FLUTTER · SIX PLATFORMS',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2.6,
                    color: _accentInk,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Universal Barcode Scanner',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.9,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Barcodes and QR codes from one call, on Android, iOS, '
                  'Linux, macOS, web and Windows.',
                  style: TextStyle(fontSize: 15, color: _dim, height: 1.45),
                ),
                const SizedBox(height: 22),
                _Result(
                  results: _results,
                  // The camera modes never hand a refused code on; an
                  // image gives every code, and a code read before the
                  // Accept row changed is checked again.
                  accept: _accept,
                  mode: _mode,
                  count: _count,
                  camera: _embedded
                      ? UniversalBarcodeScanner(
                          continuous: true,
                          buttons: _allButtons,
                          buttonsAlignment: _buttonsAt,
                          labels: _labels,
                          buttonStyle: _style,
                          vibrate: true,
                          beep: true,
                          validator: _accept,
                          onResult: (ScanResult result) =>
                              _found(result, 'embedded'),
                          onError: _failed,
                          onCreated: (ScannerController _) {},
                        )
                      : null,
                  controls: _embedded
                      ? <Widget>[
                          OutlinedButton.icon(
                            onPressed: _toggleEmbedded,
                            icon: const Icon(Icons.close, size: 18),
                            label: const Text('Close'),
                          ),
                        ]
                      : const <Widget>[],
                ),
                const SizedBox(height: 12),
                _Options(
                  label: 'Buttons',
                  children: <Widget>[
                    for (final (String label, Alignment at)
                        in const <(String, Alignment)>[
                      ('Right side', Alignment.centerRight),
                      ('Top right', Alignment.topRight),
                      ('Top left', Alignment.topLeft),
                      ('Bottom', Alignment.bottomCenter),
                    ])
                      ChoiceChip(
                        label: Text(label),
                        selected: _buttonsAt == at,
                        onSelected: (bool _) => setState(() => _buttonsAt = at),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                _Options(
                  label: 'Look',
                  children: <Widget>[
                    for (final (String label, ScannerButtonStyle style)
                        in _styles)
                      ChoiceChip(
                        label: Text(label),
                        selected: _style == style,
                        onSelected: (bool _) => setState(() => _style = style),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                _Options(
                  label: 'Words',
                  children: <Widget>[
                    for (final (String label, ScannerLabels labels)
                        in const <(String, ScannerLabels)>[
                      ('English', ScannerLabels.english),
                      ('Français', ScannerLabels.french),
                      ('Nederlands', ScannerLabels.dutch),
                      ('Deutsch', ScannerLabels.german),
                    ])
                      ChoiceChip(
                        label: Text(label),
                        selected: identical(_labels, labels),
                        onSelected: (bool _) =>
                            setState(() => _labels = labels),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                _Options(
                  label: 'Accept',
                  children: <Widget>[
                    for (final (String label, ScanValidator? accept)
                        in _accepts)
                      ChoiceChip(
                        label: Text(label),
                        selected: identical(_accept, accept),
                        onSelected: (bool _) =>
                            setState(() => _accept = accept),
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                _Mode(
                  title: 'Embedded view',
                  body: 'Puts the camera inside your own layout, here the tile '
                      'above, with buttons for the torch, pausing and '
                      'flipping.',
                  action: 'Open',
                  // Closed from the tile, next to the other controls.
                  onPressed: _embedded ? null : _toggleEmbedded,
                ),
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
                  title: 'Read an image',
                  body: 'Reads every code in a picture, says what each one '
                      'holds and which ones the Accept row refuses. Pick one '
                      'of yours, or try one of these:',
                  action: 'Pick',
                  onPressed: _pickImage,
                  footer: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: <Widget>[
                      for (final (String label, String name) in _samples)
                        ActionChip(
                          label: Text(label),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _readSample(name),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                const _ShowcaseEntry(),
                const SizedBox(height: 16),
                const _Note(),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The way into [CheckInDemo]: the package at work in an app of its own.
class _ShowcaseEntry extends StatelessWidget {
  const _ShowcaseEntry();

  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color(0xFF2B7A55), Color(0xFF3D9970)],
          ),
        ),
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (BuildContext context) => const CheckInDemo(),
            ),
          ),
          child: const Padding(
            padding: EdgeInsets.fromLTRB(20, 18, 16, 18),
            child: Row(
              children: <Widget>[
                Icon(Icons.confirmation_number_outlined,
                    size: 34, color: Colors.white),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Event check-in',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'A gate app on the embedded view: tickets read, guests '
                        'counted, the wrong ones refused.',
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.4,
                          color: Color(0xE6FFFFFF),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 10),
                Icon(Icons.arrow_forward, color: Colors.white),
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
  const _Result({
    required this.results,
    required this.accept,
    required this.mode,
    required this.count,
    this.camera,
    this.controls = const <Widget>[],
  });

  /// The codes of the last read: one from the camera, any number from an
  /// image.
  final List<ScanResult> results;

  /// The Accept row's choice, which [results] are checked against.
  final ScanValidator? accept;
  final String mode;
  final int count;

  /// The embedded scanner, when it is open in this tile.
  final Widget? camera;

  /// What drives [camera].
  final List<Widget> controls;

  @override
  Widget build(BuildContext context) {
    final bool found = results.isNotEmpty;
    final ScanValidator? accept = this.accept;
    final List<bool> refused = <bool>[
      for (final ScanResult result in results)
        accept != null && !accept(result),
    ];
    final bool emptyImage = !found && mode == 'image' && count > 0;
    final bool allRefused = found && refused.every((bool no) => no);
    final Color tone = allRefused ? _red : _accent;
    final Widget? camera = this.camera;
    final String heading = !found
        ? emptyImage
            ? 'NO CODE IN THE IMAGE'
            : 'NOTHING SCANNED YET'
        : allRefused
            ? results.length > 1
                ? 'REFUSED, $mode, ${results.length} CODES'
                : 'REFUSED, $mode'
            : results.length > 1
                ? 'SCANNED, $mode, ${results.length} CODES'
                : results.single.format == BarcodeFormat.unknown
                    ? 'SCANNED, $mode'
                    : 'SCANNED, $mode, ${_formatLabel(results.single.format)}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: !found
            ? _white
            : allRefused
                ? const Color(0xFFFCEDEC)
                : const Color(0xFFEAF5EF),
        border: Border.all(color: found ? tone : _line),
        borderRadius: BorderRadius.circular(16),
        boxShadow: _shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                !found
                    ? Icons.qr_code_scanner
                    : allRefused
                        ? Icons.block
                        : Icons.check_circle,
                size: 17,
                color: found ? tone : _dim,
              ),
              const SizedBox(width: 8),
              Text(
                heading,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: found ? (allRefused ? _red : _accentInk) : _dim,
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
          if (camera != null) ...<Widget>[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: 210,
                width: double.infinity,
                child: camera,
              ),
            ),
          ],
          if (!found) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              emptyImage
                  ? 'The image holds no code this platform reads.'
                  : camera == null
                      ? 'Pick a mode below and point the camera at a barcode.'
                      : 'Point the camera at a barcode.',
              style: const TextStyle(fontSize: 14.5, height: 1.4, color: _dim),
            ),
          ],
          for (final (int i, ScanResult result) in results.indexed)
            _Code(
              result,
              withFormat: results.length > 1,
              refused: refused[i],
            ),
          if (controls.isNotEmpty) ...<Widget>[
            const SizedBox(height: 14),
            // Compact, so the three fit on one line of a phone.
            OutlinedButtonTheme(
              data: OutlinedButtonThemeData(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  // Neutral: closing is not the tile's green action.
                  foregroundColor: _ink,
                  side: const BorderSide(color: _line),
                ),
              ),
              child: Wrap(spacing: 6, runSpacing: 8, children: controls),
            ),
          ],
        ],
      ),
    );
  }
}

/// One code read: its text, and what it holds where the text follows a
/// format a phone knows.
class _Code extends StatelessWidget {
  const _Code(
    this.result, {
    required this.withFormat,
    required this.refused,
  });

  final ScanResult result;

  /// Whether the Accept row refused it.
  final bool refused;

  /// Whether to name the symbology, when several codes share the tile.
  final bool withFormat;

  @override
  Widget build(BuildContext context) {
    final String? meaning = _describe(result.content);
    final String format = _formatLabel(result.format);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SelectableText(
            result.text,
            style: const TextStyle(
              fontSize: 17,
              height: 1.4,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
              color: _ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            <String>[
              if (withFormat && format.isNotEmpty) format,
              '${result.text.length} characters',
            ].join(' · '),
            style: const TextStyle(fontSize: 12.5, color: _dim),
          ),
          if (meaning != null) ...<Widget>[
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                const Icon(Icons.auto_awesome, size: 15, color: _accentInk),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    meaning,
                    style: const TextStyle(fontSize: 13.5, color: _accentInk),
                  ),
                ),
              ],
            ),
          ],
          if (refused) ...<Widget>[
            const SizedBox(height: 6),
            const Row(
              children: <Widget>[
                Icon(Icons.block, size: 15, color: _red),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Refused by the Accept row: a scanner would say so and '
                    'read on.',
                    style: TextStyle(fontSize: 13.5, color: _red),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// What a code holds, in words, or null for plain text.
String? _describe(ScanContent? content) => switch (content) {
      UrlContent(:final Uri url) => 'A link to ${url.host}',
      WifiContent(:final String ssid, :final WifiSecurity security) =>
        'A Wi-Fi network, $ssid, '
            '${security == WifiSecurity.open ? 'open' : security.name.toUpperCase()}',
      ContactContent(:final String? name, :final String? organization) =>
        'A contact, ${name ?? organization ?? 'with no name'}',
      EmailContent(:final String address) => 'An e-mail to $address',
      PhoneContent(:final String number) => 'A phone number, $number',
      SmsContent(:final String number) => 'A text message to $number',
      GeoContent(:final double latitude, :final double longitude) =>
        'A place, $latitude, $longitude',
      EventContent(:final String? summary) =>
        'An event, ${summary ?? 'untitled'}',
      null => null,
    };

/// A row of choices after its label. The labels share one width, so every
/// row of choices starts at the same place.
class _Options extends StatelessWidget {
  const _Options({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 70,
          // Level with the text of the first line of chips.
          child: Padding(
            padding: const EdgeInsets.only(top: 9),
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: _dim),
            ),
          ),
        ),
        Expanded(
          child: Wrap(spacing: 8, runSpacing: 8, children: children),
        ),
      ],
    );
  }
}

/// One of the ways in, with what it gives back.
class _Mode extends StatelessWidget {
  const _Mode({
    required this.title,
    required this.body,
    required this.action,
    required this.onPressed,
    this.footer,
  });

  final String title;
  final String body;
  final String action;
  final VoidCallback? onPressed;

  /// Under the text, across the card.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final bool off = onPressed == null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: _shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
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
                        color: off ? _dim : _ink,
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
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _line,
                  disabledForegroundColor: _dim,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                ),
                child: Text(action),
              ),
            ],
          ),
          if (footer case final Widget footer) ...<Widget>[
            const SizedBox(height: 12),
            footer,
          ],
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

/// How a symbology is usually written.
String _formatLabel(BarcodeFormat format) => switch (format) {
      BarcodeFormat.aztec => 'Aztec',
      BarcodeFormat.codabar => 'Codabar',
      BarcodeFormat.code39 => 'Code 39',
      BarcodeFormat.code93 => 'Code 93',
      BarcodeFormat.code128 => 'Code 128',
      BarcodeFormat.dataMatrix => 'Data Matrix',
      BarcodeFormat.ean8 => 'EAN-8',
      BarcodeFormat.ean13 => 'EAN-13',
      BarcodeFormat.itf => 'ITF',
      BarcodeFormat.pdf417 => 'PDF417',
      BarcodeFormat.qrCode => 'QR code',
      BarcodeFormat.upcA => 'UPC-A',
      BarcodeFormat.upcE => 'UPC-E',
      BarcodeFormat.unknown => '',
    };
