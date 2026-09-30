import 'dart:convert';

import 'package:flutter/foundation.dart';

/// What the text of a code means, where it follows a format phones know: a
/// link, a Wi-Fi network, a contact, an e-mail, a phone number, a text
/// message, a place or an event.
///
/// Read from the text alone, so the same on every platform.
/// `ScanResult.content` is the usual way in:
///
/// ```dart
/// switch (result.content) {
///   case WifiContent wifi:
///     connect(wifi.ssid, wifi.password);
///   case UrlContent link:
///     launchUrl(link.url);
///   default:
///     show(result.text);
/// }
/// ```
@immutable
sealed class ScanContent {
  const ScanContent();

  /// What [text] means, or null when it follows none of the formats known
  /// here, or follows one without what it needs, such as a Wi-Fi network with
  /// no name.
  static ScanContent? parse(String text) {
    final String trimmed = text.trim();
    final String upper = trimmed.toUpperCase();
    bool starts(String prefix) => upper.startsWith(prefix);
    String after(String prefix) => trimmed.substring(prefix.length);

    if (starts('WIFI:')) return WifiContent._parse(after('WIFI:'));
    if (starts('BEGIN:VCARD')) return ContactContent._fromVCard(trimmed);
    if (starts('MECARD:')) return ContactContent._fromMeCard(after('MECARD:'));
    if (starts('BEGIN:VCALENDAR') || starts('BEGIN:VEVENT')) {
      return EventContent._parse(trimmed);
    }
    if (starts('MAILTO:')) return EmailContent._fromMailto(after('MAILTO:'));
    if (starts('MATMSG:')) return EmailContent._fromMatMsg(after('MATMSG:'));
    if (starts('SMTP:')) return EmailContent._fromSmtp(after('SMTP:'));
    if (starts('TEL:')) return PhoneContent._parse(after('TEL:'));
    for (final String prefix in <String>['SMSTO:', 'MMSTO:']) {
      if (starts(prefix)) return SmsContent._fromSmsTo(after(prefix));
    }
    for (final String prefix in <String>['SMS:', 'MMS:']) {
      if (starts(prefix)) return SmsContent._fromUri(after(prefix));
    }
    if (starts('GEO:')) return GeoContent._parse(after('GEO:'));
    if (starts('MEBKM:')) return UrlContent._fromBookmark(after('MEBKM:'));
    if (starts('HTTP://') || starts('HTTPS://')) {
      return UrlContent._fromUrl(trimmed);
    }
    return null;
  }
}

/// A web address.
final class UrlContent extends ScanContent {
  /// A link to [url], called [title] where the code names it.
  const UrlContent(this.url, {this.title});

  /// Where it leads.
  final Uri url;

  /// What the code calls it, from a bookmark code.
  final String? title;

  static UrlContent? _fromUrl(String text, {String? title}) {
    final Uri? url = Uri.tryParse(text);
    if (url == null || url.host.isEmpty) return null;
    return UrlContent(url, title: title);
  }

  /// `MEBKM:TITLE:…;URL:…;;`, the address sometimes without its scheme.
  static UrlContent? _fromBookmark(String body) {
    final Map<String, List<String>> fields = _fields(body);
    final String? address = _first(fields, 'URL');
    if (address == null) return null;
    final bool schemed = address.toLowerCase().startsWith(
      RegExp('[a-z][a-z0-9+.-]*://'),
    );
    return _fromUrl(
      schemed ? address : 'http://$address',
      title: _first(fields, 'TITLE'),
    );
  }

  @override
  String toString() => 'UrlContent($url)';
}

/// How a Wi-Fi network is secured.
enum WifiSecurity {
  /// No password.
  open,

  /// WEP.
  wep,

  /// WPA, WPA2 or WPA3.
  wpa,
}

/// A Wi-Fi network to join.
final class WifiContent extends ScanContent {
  /// The network [ssid], secured by [security] with [password].
  const WifiContent(
    this.ssid, {
    this.security = WifiSecurity.open,
    this.password,
    this.hidden = false,
  });

  /// The network's name.
  final String ssid;

  /// How it is secured.
  final WifiSecurity security;

  /// Its password, null for an open network.
  final String? password;

  /// Whether the network does not announce itself, and has to be joined by
  /// name.
  final bool hidden;

  /// `WIFI:T:WPA;S:name;P:password;H:true;;`, the fields in any order.
  static WifiContent? _parse(String body) {
    final Map<String, List<String>> fields = _fields(body);
    final String? ssid = _unquoted(_first(fields, 'S'));
    if (ssid == null || ssid.isEmpty) return null;
    final String? password = _unquoted(_first(fields, 'P'));
    final String type = (_first(fields, 'T') ?? '').toUpperCase();
    final WifiSecurity security = switch (type) {
      'WEP' => WifiSecurity.wep,
      '' || 'NOPASS' || 'NONE' =>
        password == null || password.isEmpty
            ? WifiSecurity.open
            : WifiSecurity.wpa,
      _ => WifiSecurity.wpa,
    };
    return WifiContent(
      ssid,
      security: security,
      password: security == WifiSecurity.open ? null : password,
      hidden: (_first(fields, 'H') ?? '').toLowerCase() == 'true',
    );
  }

  @override
  String toString() => 'WifiContent($ssid, ${security.name})';
}

/// A person or a business, from a vCard or a MECARD.
final class ContactContent extends ScanContent {
  /// A contact with what the code gives of it.
  const ContactContent({
    this.name,
    this.organization,
    this.title,
    this.phones = const <String>[],
    this.emails = const <String>[],
    this.urls = const <String>[],
    this.address,
    this.note,
  });

  /// The name, in the order it is written: given name first.
  final String? name;

  /// The company.
  final String? organization;

  /// The job title.
  final String? title;

  /// Phone numbers, as written.
  final List<String> phones;

  /// E-mail addresses.
  final List<String> emails;

  /// Web addresses.
  final List<String> urls;

  /// The postal address, on one line.
  final String? address;

  /// A free note.
  final String? note;

  /// `BEGIN:VCARD` … `END:VCARD`, versions 2.1, 3.0 and 4.0.
  static ContactContent? _fromVCard(String text) {
    String? name;
    String? structuredName;
    String? organization;
    String? title;
    String? address;
    String? note;
    final List<String> phones = <String>[];
    final List<String> emails = <String>[];
    final List<String> urls = <String>[];
    for (final _Property property in _properties(text)) {
      final String value = property.value;
      switch (property.name) {
        case 'FN':
          name = value;
        case 'N':
          // Family;Given;Middle;Prefix;Suffix, written given name first.
          final List<String> parts = _components(property.raw, property);
          String part(int index) => index < parts.length ? parts[index] : '';
          structuredName = _joined(<String>[
            part(3),
            part(1),
            part(2),
            part(0),
            part(4),
          ], ' ');
        case 'ORG':
          organization = _joined(_components(property.raw, property), ', ');
        case 'TITLE':
          title = value;
        case 'TEL':
          phones.add(value);
        case 'EMAIL':
          emails.add(value);
        case 'URL':
          urls.add(value);
        case 'ADR':
          // PO box;extended;street;locality;region;postal code;country.
          address ??= _joined(_components(property.raw, property), ', ');
        case 'NOTE':
          note = value;
      }
    }
    return _contact(
      name: _blankToNull(name) ?? structuredName,
      organization: organization,
      title: title,
      phones: phones,
      emails: emails,
      urls: urls,
      address: address,
      note: note,
    );
  }

  /// `MECARD:N:Doe,John;TEL:…;EMAIL:…;;`, the name family name first.
  static ContactContent? _fromMeCard(String body) {
    final Map<String, List<String>> fields = _fields(body);
    final String? written = _first(fields, 'N');
    final List<String> name = (written ?? '').split(',');
    return _contact(
      name: _joined(name.reversed.map((String part) => part.trim()), ' '),
      organization: _first(fields, 'ORG'),
      phones: fields['TEL'] ?? const <String>[],
      emails: fields['EMAIL'] ?? const <String>[],
      urls: fields['URL'] ?? const <String>[],
      address: _first(fields, 'ADR'),
      note: _first(fields, 'NOTE'),
    );
  }

  /// A contact, or null for one with nothing in it.
  static ContactContent? _contact({
    String? name,
    String? organization,
    String? title,
    List<String> phones = const <String>[],
    List<String> emails = const <String>[],
    List<String> urls = const <String>[],
    String? address,
    String? note,
  }) {
    List<String> kept(List<String> values) => List<String>.unmodifiable(
      values
          .map((String value) => value.trim())
          .where((String value) => value.isNotEmpty),
    );
    final ContactContent contact = ContactContent(
      name: _blankToNull(name),
      organization: _blankToNull(organization),
      title: _blankToNull(title),
      phones: kept(phones),
      emails: kept(emails),
      urls: kept(urls),
      address: _blankToNull(address),
      note: _blankToNull(note),
    );
    final bool empty =
        contact.name == null &&
        contact.organization == null &&
        contact.phones.isEmpty &&
        contact.emails.isEmpty &&
        contact.urls.isEmpty &&
        contact.address == null;
    return empty ? null : contact;
  }

  @override
  String toString() => 'ContactContent($name)';
}

/// An e-mail to write.
final class EmailContent extends ScanContent {
  /// An e-mail to [address], with [subject] and [body] where given.
  const EmailContent(this.address, {this.subject, this.body});

  /// The recipient. Several are separated by commas.
  final String address;

  /// The subject line.
  final String? subject;

  /// The text of the message.
  final String? body;

  /// `mailto:someone@example.com?subject=…&body=…`.
  static EmailContent? _fromMailto(String rest) {
    final int query = rest.indexOf('?');
    final String to = _decoded(query < 0 ? rest : rest.substring(0, query));
    final Map<String, String> parameters = query < 0
        ? const <String, String>{}
        : _query(rest.substring(query + 1));
    return _email(to, parameters['subject'], parameters['body']);
  }

  /// `MATMSG:TO:…;SUB:…;BODY:…;;`.
  static EmailContent? _fromMatMsg(String body) {
    final Map<String, List<String>> fields = _fields(body);
    return _email(
      _first(fields, 'TO') ?? '',
      _first(fields, 'SUB'),
      _first(fields, 'BODY'),
    );
  }

  /// `SMTP:someone@example.com:subject:body`.
  static EmailContent? _fromSmtp(String rest) {
    final List<String> parts = rest.split(':');
    return _email(
      parts.first,
      parts.length > 1 ? parts[1] : null,
      parts.length > 2 ? parts.sublist(2).join(':') : null,
    );
  }

  static EmailContent? _email(String to, String? subject, String? body) {
    final String address = to.trim();
    if (address.isEmpty && _blankToNull(subject) == null) return null;
    return EmailContent(
      address,
      subject: _blankToNull(subject),
      body: _blankToNull(body),
    );
  }

  @override
  String toString() => 'EmailContent($address)';
}

/// A phone number to call.
final class PhoneContent extends ScanContent {
  /// A call to [number].
  const PhoneContent(this.number);

  /// The number, as written.
  final String number;

  /// `tel:+32 2 123 45 67`.
  static PhoneContent? _parse(String rest) {
    final String number = _decoded(rest).trim();
    return number.isEmpty ? null : PhoneContent(number);
  }

  @override
  String toString() => 'PhoneContent($number)';
}

/// A text message to send.
final class SmsContent extends ScanContent {
  /// A message to [number], reading [message] where given.
  const SmsContent(this.number, {this.message});

  /// The number to send it to.
  final String number;

  /// The text, ready to send.
  final String? message;

  /// `SMSTO:number:message`.
  static SmsContent? _fromSmsTo(String rest) {
    final int colon = rest.indexOf(':');
    return _sms(
      colon < 0 ? rest : rest.substring(0, colon),
      colon < 0 ? null : rest.substring(colon + 1),
    );
  }

  /// `sms:number?body=message`.
  static SmsContent? _fromUri(String rest) {
    final int query = rest.indexOf('?');
    final Map<String, String> parameters = query < 0
        ? const <String, String>{}
        : _query(rest.substring(query + 1));
    return _sms(
      _decoded(query < 0 ? rest : rest.substring(0, query)),
      parameters['body'],
    );
  }

  static SmsContent? _sms(String number, String? message) {
    final String to = number.trim();
    return to.isEmpty ? null : SmsContent(to, message: _blankToNull(message));
  }

  @override
  String toString() => 'SmsContent($number)';
}

/// A place on the map.
final class GeoContent extends ScanContent {
  /// The point at [latitude] and [longitude].
  const GeoContent(this.latitude, this.longitude, {this.altitude, this.query});

  /// Degrees north, negative to the south.
  final double latitude;

  /// Degrees east, negative to the west.
  final double longitude;

  /// Metres above sea level, where given.
  final double? altitude;

  /// What to search for there, from `?q=`.
  final String? query;

  /// `geo:50.8467,4.3525,100?q=Grand-Place`.
  static GeoContent? _parse(String rest) {
    final int queryAt = rest.indexOf('?');
    final String point = queryAt < 0 ? rest : rest.substring(0, queryAt);
    // Parameters such as `;u=35` follow the coordinates.
    final List<String> parts = point.split(';').first.split(',');
    if (parts.length < 2) return null;
    final double? latitude = double.tryParse(parts[0].trim());
    final double? longitude = double.tryParse(parts[1].trim());
    if (latitude == null ||
        longitude == null ||
        latitude.abs() > 90 ||
        longitude.abs() > 180) {
      return null;
    }
    final Map<String, String> parameters = queryAt < 0
        ? const <String, String>{}
        : _query(rest.substring(queryAt + 1));
    return GeoContent(
      latitude,
      longitude,
      altitude: parts.length > 2 ? double.tryParse(parts[2].trim()) : null,
      query: _blankToNull(parameters['q']),
    );
  }

  @override
  String toString() => 'GeoContent($latitude, $longitude)';
}

/// An event for the calendar, from an iCalendar `VEVENT`.
final class EventContent extends ScanContent {
  /// An event with what the code gives of it.
  const EventContent({
    this.summary,
    this.start,
    this.end,
    this.allDay = false,
    this.location,
    this.description,
  });

  /// Its title.
  final String? summary;

  /// When it starts: in UTC when the code says so, local time otherwise.
  final DateTime? start;

  /// When it ends.
  final DateTime? end;

  /// Whether it takes whole days rather than hours.
  final bool allDay;

  /// Where it happens.
  final String? location;

  /// What it is about.
  final String? description;

  static EventContent? _parse(String text) {
    String? summary;
    String? location;
    String? description;
    DateTime? start;
    DateTime? end;
    bool allDay = false;
    bool inEvent = false;
    for (final _Property property in _properties(text)) {
      if (property.name == 'BEGIN' &&
          property.value.toUpperCase() == 'VEVENT') {
        inEvent = true;
      } else if (property.name == 'END' &&
          property.value.toUpperCase() == 'VEVENT') {
        break;
      } else if (inEvent) {
        switch (property.name) {
          case 'SUMMARY':
            summary = property.value;
          case 'LOCATION':
            location = property.value;
          case 'DESCRIPTION':
            description = property.value;
          case 'DTSTART':
            start = _date(property.value);
            allDay = !property.value.toUpperCase().contains('T');
          case 'DTEND':
            end = _date(property.value);
        }
      }
    }
    if (summary == null && start == null) return null;
    return EventContent(
      summary: _blankToNull(summary),
      start: start,
      end: end,
      allDay: start != null && allDay,
      location: _blankToNull(location),
      description: _blankToNull(description),
    );
  }

  /// `20260930`, `20260930T143000` or `20260930T143000Z`.
  static DateTime? _date(String value) {
    final RegExpMatch? match = RegExp(
      r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})?(Z)?)?$',
      caseSensitive: false,
    ).firstMatch(value.trim());
    if (match == null) return null;
    int part(int group) => int.parse(match.group(group) ?? '0');
    final List<int> fields = <int>[
      part(1),
      part(2),
      part(3),
      part(4),
      part(5),
      part(6),
    ];
    return match.group(7) == null
        ? DateTime(
            fields[0],
            fields[1],
            fields[2],
            fields[3],
            fields[4],
            fields[5],
          )
        : DateTime.utc(
            fields[0],
            fields[1],
            fields[2],
            fields[3],
            fields[4],
            fields[5],
          );
  }

  @override
  String toString() => 'EventContent($summary, $start)';
}

// ---------------------------------------------------------------------------
// Reading the formats.

/// The `KEY:value;KEY:value;;` fields of WIFI, MECARD, MATMSG and MEBKM
/// codes, keys in capitals. A backslash takes the character after it as it is,
/// so a value may hold `;`, `:` or `,`.
Map<String, List<String>> _fields(String body) {
  final Map<String, List<String>> fields = <String, List<String>>{};
  final StringBuffer key = StringBuffer();
  final StringBuffer value = StringBuffer();
  bool inValue = false;
  void end() {
    if (inValue) {
      (fields[key.toString().trim().toUpperCase()] ??= <String>[]).add(
        value.toString(),
      );
    }
    key.clear();
    value.clear();
    inValue = false;
  }

  for (int index = 0; index < body.length; index++) {
    final String char = body[index];
    if (char == r'\' && index + 1 < body.length) {
      (inValue ? value : key).write(body[++index]);
    } else if (char == ';') {
      end();
    } else if (char == ':' && !inValue) {
      inValue = true;
    } else {
      (inValue ? value : key).write(char);
    }
  }
  end();
  return fields;
}

String? _first(Map<String, List<String>> fields, String key) {
  final List<String>? values = fields[key];
  return values == null || values.isEmpty ? null : values.first;
}

/// A Wi-Fi name or password may be written between double quotes.
String? _unquoted(String? value) {
  if (value != null &&
      value.length >= 2 &&
      value.startsWith('"') &&
      value.endsWith('"')) {
    return value.substring(1, value.length - 1);
  }
  return value;
}

String? _blankToNull(String? value) {
  final String? trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String _joined(Iterable<String> parts, String separator) => parts
    .map((String part) => part.trim())
    .where((String part) => part.isNotEmpty)
    .join(separator);

/// Percent-decoded, or as it is where the escapes are broken.
String _decoded(String value) {
  // A `%` not followed by two hex digits: decoding would throw.
  if (RegExp('%(?![0-9A-Fa-f]{2})').hasMatch(value)) return value;
  try {
    return Uri.decodeComponent(value);
  } on FormatException {
    // Escapes that spell no valid UTF-8.
    return value;
  }
}

/// `a=1&b=2`, keys in lower case, values percent-decoded.
Map<String, String> _query(String query) {
  final Map<String, String> parameters = <String, String>{};
  for (final String pair in query.split('&')) {
    final int equals = pair.indexOf('=');
    if (equals <= 0) continue;
    parameters.putIfAbsent(
      pair.substring(0, equals).toLowerCase(),
      () => _decoded(pair.substring(equals + 1)),
    );
  }
  return parameters;
}

/// One line of a vCard or an iCalendar: `NAME;PARAM=x:value`.
class _Property {
  const _Property(this.name, this.parameters, this.raw);

  /// In capitals, without a group such as `item1.`.
  final String name;

  /// In capitals.
  final List<String> parameters;

  /// The value as written, escapes and encoding kept.
  final String raw;

  bool get quotedPrintable => parameters.any(
    (String parameter) => parameter.contains('QUOTED-PRINTABLE'),
  );

  /// The value, decoded and unescaped.
  String get value => _unescaped(_encoded(raw, this));
}

/// The properties of a vCard or an iCalendar, folded lines joined.
List<_Property> _properties(String text) {
  final List<String> lines = <String>[];
  for (final String line in text.replaceAll('\r\n', '\n').split('\n')) {
    final bool continued = line.startsWith(' ') || line.startsWith('\t');
    if (continued && lines.isNotEmpty) {
      lines.last += line.substring(1);
    } else if (lines.isNotEmpty &&
        lines.last.endsWith('=') &&
        lines.last.toUpperCase().contains('QUOTED-PRINTABLE')) {
      // A soft line break of quoted-printable.
      lines.last = lines.last.substring(0, lines.last.length - 1) + line;
    } else {
      lines.add(line);
    }
  }
  final List<_Property> properties = <_Property>[];
  for (final String line in lines) {
    final int colon = _unquotedColon(line);
    if (colon <= 0) continue;
    final List<String> head = line.substring(0, colon).split(';');
    final String name = head.first.split('.').last.trim().toUpperCase();
    properties.add(
      _Property(
        name,
        head
            .skip(1)
            .map((String parameter) => parameter.toUpperCase())
            .toList(),
        line.substring(colon + 1),
      ),
    );
  }
  return properties;
}

/// Where the name and parameters end: the first colon outside quotes.
int _unquotedColon(String line) {
  bool quoted = false;
  for (int index = 0; index < line.length; index++) {
    final String char = line[index];
    if (char == '"') {
      quoted = !quoted;
    } else if (char == ':' && !quoted) {
      return index;
    }
  }
  return -1;
}

/// [raw] decoded from quoted-printable where [property] says it is.
String _encoded(String raw, _Property property) {
  if (!property.quotedPrintable) return raw;
  final List<int> bytes = <int>[];
  for (int index = 0; index < raw.length; index++) {
    final String char = raw[index];
    if (char == '=' && index + 2 < raw.length) {
      final int? byte = int.tryParse(
        raw.substring(index + 1, index + 3),
        radix: 16,
      );
      if (byte != null) {
        bytes.add(byte);
        index += 2;
        continue;
      }
    }
    bytes.addAll(utf8.encode(char));
  }
  return utf8.decode(bytes, allowMalformed: true);
}

/// The `;`-separated components of a structured value, each unescaped.
List<String> _components(String raw, _Property property) {
  final String decoded = _encoded(raw, property);
  final List<String> components = <String>[];
  final StringBuffer current = StringBuffer();
  for (int index = 0; index < decoded.length; index++) {
    final String char = decoded[index];
    if (char == r'\' && index + 1 < decoded.length) {
      current
        ..write(char)
        ..write(decoded[++index]);
    } else if (char == ';') {
      components.add(_unescaped(current.toString()));
      current.clear();
    } else {
      current.write(char);
    }
  }
  components.add(_unescaped(current.toString()));
  return components;
}

/// vCard and iCalendar escapes: `\n`, `\,`, `\;` and `\\`.
String _unescaped(String value) {
  final StringBuffer out = StringBuffer();
  for (int index = 0; index < value.length; index++) {
    final String char = value[index];
    if (char == r'\' && index + 1 < value.length) {
      final String next = value[++index];
      out.write(next == 'n' || next == 'N' ? '\n' : next);
    } else {
      out.write(char);
    }
  }
  return out.toString();
}
