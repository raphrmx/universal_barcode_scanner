import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:universal_barcode_scanner/universal_barcode_scanner.dart';

const Color _paper = Color(0xFFF6F1EA);
const Color _white = Color(0xFFFFFDFB);
const Color _ink = Color(0xFF1D1712);
const Color _line = Color(0xFFE6DDD1);
const Color _dim = Color(0xFF6F665E);
const Color _accent = Color(0xFF3D9970);
const Color _accentInk = Color(0xFF2B7A55);
const Color _red = Color(0xFFD43F45);

const List<BoxShadow> _shadow = <BoxShadow>[
  BoxShadow(color: Color(0x1F3B2A1A), blurRadius: 24, offset: Offset(0, 10)),
];

/// The width from which the camera and the list sit side by side.
const double _wide = 820;

/// What every ticket of the evening starts with.
const String _event = 'HR26-';

/// A guest and the ticket they bought.
class _Guest {
  const _Guest(this.name, this.pass);

  final String name;
  final String pass;
}

/// The guest list, by ticket number: HR26-0001 is the first.
const List<_Guest> _guests = <_Guest>[
  _Guest('Léa Martin', 'Full pass'),
  _Guest('Noah Peeters', 'Full pass'),
  _Guest('Emma Janssens', 'Evening'),
  _Guest('Lucas Dubois', 'Full pass'),
  _Guest('Mila Claes', 'VIP'),
  _Guest('Arthur Wouters', 'Evening'),
  _Guest('Louise Lambert', 'Full pass'),
  _Guest('Jules Maes', 'Evening'),
  _Guest('Olivia Mertens', 'VIP'),
  _Guest('Victor Dupont', 'Full pass'),
  _Guest('Alice Willems', 'Evening'),
  _Guest('Adam Goossens', 'Full pass'),
  _Guest('Zoé Lemaire', 'Evening'),
  _Guest('Louis Hermans', 'Full pass'),
  _Guest('Chloé Simon', 'VIP'),
  _Guest('Hugo De Smet', 'Evening'),
  _Guest('Nina Leclercq', 'Full pass'),
  _Guest('Liam Jacobs', 'Full pass'),
  _Guest('Elena Vermeulen', 'Evening'),
  _Guest('Gabriel Renard', 'Full pass'),
  _Guest('Sara Dumont', 'VIP'),
  _Guest('Max Hendrickx', 'Evening'),
  _Guest('Lina Fontaine', 'Full pass'),
  _Guest('Tom Michiels', 'Evening'),
];

/// Seats in the hall, for the counter.
const int _capacity = 120;

/// The ticket number of the guest at [index] in [_guests].
String _ticket(int index) => '$_event${(index + 1).toString().padLeft(4, '0')}';

/// The guest a ticket belongs to, or null for a ticket of no guest of the
/// evening.
int? _guestOf(String code) {
  if (!code.startsWith(_event)) return null;
  final int? number = int.tryParse(code.substring(_event.length));
  if (number == null || number < 1 || number > _guests.length) return null;
  return number - 1;
}

/// One line of the gate's log: a guest let in, or a ticket turned away.
class _Entry {
  const _Entry(this.code, this.time, {this.refusal});

  final String code;
  final DateTime time;

  /// Why the ticket was turned away, or null for a guest let in.
  final String? refusal;
}

/// The gate of an evening: the camera reads tickets, the list fills up. A
/// ticket already used or bought for another evening is refused over the
/// camera, and the camera reads on.
class CheckInDemo extends StatefulWidget {
  /// Creates the demo.
  const CheckInDemo({super.key});

  @override
  State<CheckInDemo> createState() => _CheckInDemoState();
}

class _CheckInDemoState extends State<CheckInDemo> {
  /// Guests already in before the screen opened, so the hall is not empty.
  static const int _before = 64;

  final Set<int> _in = <int>{12, 13, 15, 17, 19, 21};
  late final List<_Entry> _log = <_Entry>[
    for (final (int i, int guest) in <int>[21, 19, 17, 15].indexed)
      _Entry(
        _ticket(guest),
        DateTime.now().subtract(Duration(minutes: 2 + i * 3)),
      ),
  ];

  /// Whether [result] lets someone in. A refused ticket is logged with its
  /// reason; the scanner says no over the camera and reads on.
  bool _accept(ScanResult result) {
    final String code = result.text;
    final int? guest = _guestOf(code);
    final String? refusal = guest == null
        ? 'Not a ticket for tonight'
        : _in.contains(guest)
            ? 'Already checked in'
            : null;
    if (refusal != null) {
      // The validator runs while the scanner decides: log after this frame.
      Future<void>.microtask(() {
        if (!mounted) return;
        setState(
          () => _log.insert(
            0,
            _Entry(code, DateTime.now(), refusal: refusal),
          ),
        );
      });
    }
    return refusal == null;
  }

  /// Hands the gate the ticket of [code], read from its picture as a camera
  /// would read it: nobody visiting the demo has a ticket of tonight.
  Future<void> _handIn(String code) async {
    final ByteData image = await rootBundle.load('assets/tickets/$code.png');
    final List<ScanResult> results = await UniversalBarcodeScanner.scanImage(
      image.buffer.asUint8List(image.offsetInBytes, image.lengthInBytes),
    );
    if (!mounted) return;
    for (final ScanResult result in results) {
      if (_accept(result)) _admit(result);
    }
  }

  void _admit(ScanResult result) {
    final int? guest = _guestOf(result.text);
    if (guest == null) return;
    setState(() {
      _in.add(guest);
      _log.insert(0, _Entry(result.text, DateTime.now()));
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool wide = MediaQuery.sizeOf(context).width >= _wide;
    final Widget camera = _Camera(
      scanner: UniversalBarcodeScanner(
        continuous: true,
        scanFormat: ScanFormat.onlyQrCode,
        scanWindow: ScanWindow.square,
        lineColor: _accent,
        vibrate: true,
        beep: true,
        validator: _accept,
        onResult: _admit,
        onCreated: (ScannerController _) {},
      ),
    );
    final Widget gate = _Gate(
      count: _before + _in.length,
      log: _log,
      onTicket: _handIn,
      wide: wide,
    );
    return Scaffold(
      backgroundColor: _paper,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _Header(wide: wide),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  wide ? 28 : 16,
                  wide ? 8 : 4,
                  wide ? 28 : 16,
                  wide ? 28 : 16,
                ),
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Expanded(flex: 11, child: camera),
                          const SizedBox(width: 24),
                          Expanded(flex: 9, child: gate),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          SizedBox(height: 280, child: camera),
                          const SizedBox(height: 14),
                          Expanded(child: gate),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The evening's name, the gate, and the way back.
class _Header extends StatelessWidget {
  const _Header({required this.wide});

  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(wide ? 16 : 6, 10, wide ? 28 : 16, 10),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back, color: _ink),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'GATE A · TONIGHT 20:00',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2.4,
                    color: _accentInk,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'The High Route, a film night',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: wide ? 24 : 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    color: _ink,
                  ),
                ),
              ],
            ),
          ),
          if (wide)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFDDEFE5),
                borderRadius: BorderRadius.circular(30),
              ),
              child: const Row(
                children: <Widget>[
                  Icon(Icons.circle, size: 9, color: _accent),
                  SizedBox(width: 8),
                  Text(
                    'Doors open',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _accentInk,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The camera, in a dark rounded frame with a line saying what to do.
class _Camera extends StatelessWidget {
  const _Camera({required this.scanner});

  final Widget scanner;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF15130F),
        borderRadius: BorderRadius.circular(24),
        boxShadow: _shadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          scanner,
          Positioned(
            left: 16,
            top: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0x99000000),
                borderRadius: BorderRadius.circular(30),
              ),
              child: const Row(
                children: <Widget>[
                  Icon(Icons.qr_code_2, size: 16, color: Colors.white),
                  SizedBox(width: 7),
                  Text(
                    'Hold the ticket in the square',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// How full the hall is, the last ticket read, and the ones before it.
class _Gate extends StatelessWidget {
  const _Gate({
    required this.count,
    required this.log,
    required this.onTicket,
    required this.wide,
  });

  final int count;
  final List<_Entry> log;

  /// Hands a ticket to try to the gate.
  final ValueChanged<String> onTicket;

  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
          decoration: BoxDecoration(
            color: _white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: _shadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(end: count.toDouble()),
                    duration: const Duration(milliseconds: 500),
                    builder: (BuildContext context, double value, Widget? _) =>
                        Text(
                      '${value.round()}',
                      style: const TextStyle(
                        fontSize: 38,
                        height: 1,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.2,
                        color: _ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 4),
                    child: Text(
                      '/ $_capacity checked in',
                      style: TextStyle(fontSize: 14, color: _dim),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: count / _capacity),
                  duration: const Duration(milliseconds: 500),
                  builder: (BuildContext context, double value, Widget? _) =>
                      LinearProgressIndicator(
                    value: value,
                    minHeight: 8,
                    backgroundColor: const Color(0xFFEDE6DC),
                    color: _accent,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _TicketStrip(onPick: onTicket, wide: wide),
        const SizedBox(height: 14),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: _white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: _shadow,
            ),
            clipBehavior: Clip.antiAlias,
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 8, 20, 6),
                  child: Text(
                    'AT THE GATE',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.2,
                      color: _dim,
                    ),
                  ),
                ),
                for (final (int i, _Entry entry) in log.indexed)
                  _Line(entry, latest: i == 0, key: ValueKey<_Entry>(entry)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One ticket at the gate: who, which pass, when, and whether they got in.
class _Line extends StatelessWidget {
  const _Line(this.entry, {required this.latest, super.key});

  final _Entry entry;

  /// Whether it is the ticket just read, drawn larger.
  final bool latest;

  @override
  Widget build(BuildContext context) {
    final int? guest = _guestOf(entry.code);
    final String? refusal = entry.refusal;
    final bool ok = refusal == null;
    final String name = guest == null ? 'Unknown ticket' : _guests[guest].name;
    final String initials = guest == null
        ? '?'
        : name.split(' ').map((String part) => part[0]).take(2).join();
    final String time =
        '${entry.time.hour.toString().padLeft(2, '0')}:${entry.time.minute.toString().padLeft(2, '0')}';
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (BuildContext context, double t, Widget? child) => Opacity(
        opacity: t,
        child:
            Transform.translate(offset: Offset(0, (1 - t) * -12), child: child),
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        padding:
            EdgeInsets.symmetric(horizontal: 12, vertical: latest ? 12 : 9),
        decoration: BoxDecoration(
          color: !latest
              ? Colors.transparent
              : ok
                  ? const Color(0xFFEAF5EF)
                  : const Color(0xFFFCEDEC),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: <Widget>[
            CircleAvatar(
              radius: latest ? 21 : 17,
              backgroundColor:
                  ok ? const Color(0xFFDDEFE5) : const Color(0xFFF8DADB),
              child: Text(
                initials,
                style: TextStyle(
                  fontSize: latest ? 14 : 12.5,
                  fontWeight: FontWeight.w700,
                  color: ok ? _accentInk : _red,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: latest ? 16 : 14.5,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ok
                        ? '${_guests[guest!].pass} · ${entry.code}'
                        : '$refusal · ${entry.code}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: ok ? _dim : _red),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(time, style: const TextStyle(fontSize: 12.5, color: _dim)),
            const SizedBox(width: 10),
            Icon(
              ok ? Icons.check_circle : Icons.cancel,
              size: latest ? 22 : 18,
              color: ok ? _accent : _red,
            ),
          ],
        ),
      ),
    );
  }
}

/// The tickets the demo ships, for a visitor with none of their own: two
/// guests of tonight and a ticket of another evening.
const List<(String, String, String)> _samples = <(String, String, String)>[
  ('HR26-0008', 'Jules Maes', 'Evening'),
  ('HR26-0009', 'Olivia Mertens', 'VIP'),
  ('HR25-0310', 'Sam Laurent', 'Last year'),
];

/// The tickets to try, beside the camera rather than over it: tap one to
/// hand it to the gate, which reads it from its picture with `scanImage`, or
/// hold another device's camera to it.
class _TicketStrip extends StatelessWidget {
  const _TicketStrip({required this.onPick, required this.wide});

  final ValueChanged<String> onPick;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: _shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'TICKETS TO TRY',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.2,
              color: _dim,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            wide
                ? 'Tap one to hand it to the gate, twice to see it refused, or '
                    'scan it with another device.'
                : 'Tap one to hand it to the gate, twice to see it refused.',
            style: const TextStyle(fontSize: 12.5, height: 1.4, color: _dim),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              for (final (int i, (String code, String name, String _))
                  in _samples.indexed) ...<Widget>[
                if (i > 0) const SizedBox(width: 10),
                Expanded(
                  child: _Ticket(
                    code: code,
                    name: name,
                    qr: wide ? 92 : 64,
                    onTap: () => onPick(code),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// A ticket: the evening, the guest, and the QR code the gate reads.
class _Ticket extends StatelessWidget {
  const _Ticket({
    required this.code,
    required this.name,
    required this.qr,
    required this.onTap,
  });

  final String code;
  final String name;

  /// The side of the QR code.
  final double qr;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool tonight = code.startsWith(_event);
    return Material(
      color: _white,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          border: Border.all(color: _line),
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          onTap: onTap,
          child: Column(
            children: <Widget>[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 5),
                color: tonight ? _accentInk : _dim,
                child: Text(
                  tonight ? 'TONIGHT' : 'LAST YEAR',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.6,
                    color: Colors.white,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
                child: Column(
                  children: <Widget>[
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Image.asset(
                      'assets/tickets/$code.png',
                      width: qr,
                      height: qr,
                      filterQuality: FilterQuality.none,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
