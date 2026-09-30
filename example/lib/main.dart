import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:universal_barcode_scanner/universal_barcode_scanner.dart';

void main() => runApp(const ExampleApp());

const Color _ink = Color(0xFF0E1014);
const Color _panel = Color(0xFF171A20);
const Color _line = Color(0xFF272C36);
const Color _dim = Color(0xFF8B929E);
const Color _accent = Color(0xFF39B37A);
const Color _red = Color(0xFFE5484D);

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
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _ink,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _accent,
          brightness: Brightness.dark,
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

  /// For each of [_results], whether the Accept row refused it. The camera
  /// modes never hand a refused code on; an image gives every code, so the
  /// example checks them itself.
  List<bool> _refused = const <bool>[];
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
      _refused = const <bool>[false];
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
      final ScanValidator? accept = _accept;
      setState(() {
        _results = results;
        _refused = <bool>[
          for (final ScanResult result in results)
            accept != null && !accept(result),
        ];
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
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
              children: <Widget>[
                const Text(
                  'Universal Barcode Scanner',
                  style: TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.7,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Barcodes and QR codes from one call, on Android, iOS, '
                  'Linux, macOS, web and Windows.',
                  style: TextStyle(fontSize: 14.5, color: _dim, height: 1.45),
                ),
                const SizedBox(height: 22),
                _Result(
                  results: _results,
                  refused: _refused,
                  mode: _mode,
                  count: _count,
                  camera: _embedded
                      ? UniversalBarcodeScanner(
                          // A validator added or removed applies when the
                          // view starts.
                          key: ValueKey<ScanValidator?>(_accept),
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
                const SizedBox(height: 8),
                const _Note(),
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
    required this.refused,
    required this.mode,
    required this.count,
    this.camera,
    this.controls = const <Widget>[],
  });

  /// The codes of the last read: one from the camera, any number from an
  /// image.
  final List<ScanResult> results;

  /// For each of [results], whether the Accept row refused it.
  final List<bool> refused;
  final String mode;
  final int count;

  /// The embedded scanner, when it is open in this tile.
  final Widget? camera;

  /// What drives [camera].
  final List<Widget> controls;

  @override
  Widget build(BuildContext context) {
    final bool found = results.isNotEmpty;
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
            ? _panel
            : allRefused
                ? const Color(0xFF2A1618)
                : const Color(0xFF13251C),
        border: Border.all(color: found ? tone : _line),
        borderRadius: BorderRadius.circular(14),
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
                  color: found ? tone : _dim,
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
              refused: i < refused.length && refused[i],
            ),
          if (controls.isNotEmpty) ...<Widget>[
            const SizedBox(height: 14),
            // Compact, so the three fit on one line of a phone.
            OutlinedButtonTheme(
              data: OutlinedButtonThemeData(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
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
              color: Colors.white,
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
                const Icon(Icons.auto_awesome, size: 15, color: _accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    meaning,
                    style: const TextStyle(fontSize: 13.5, color: _accent),
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
        color: _panel,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(14),
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
                        color: off ? _dim : Colors.white,
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
                  foregroundColor: const Color(0xFF07130D),
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
