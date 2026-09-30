import 'package:flutter_test/flutter_test.dart';
import 'package:universal_barcode_scanner/universal_barcode_scanner.dart';

T _as<T extends ScanContent>(String text) {
  final ScanContent? content = ScanContent.parse(text);
  expect(content, isA<T>(), reason: text);
  return content! as T;
}

void main() {
  group('links', () {
    test('an http or https address', () {
      expect(
        _as<UrlContent>('https://example.com/a?b=1').url,
        Uri.parse('https://example.com/a?b=1'),
      );
      expect(_as<UrlContent>('HTTP://EXAMPLE.COM').url.host, 'example.com');
    });

    test('a bookmark, its address with or without a scheme', () {
      final UrlContent mark = _as<UrlContent>(
        r'MEBKM:TITLE:Comapps\: packages;URL:packages.comapps.be;;',
      );
      expect(mark.url, Uri.parse('http://packages.comapps.be'));
      expect(mark.title, 'Comapps: packages');
    });

    test('nothing for plain text, a product number or a bare word', () {
      expect(ScanContent.parse('5412345678908'), isNull);
      expect(ScanContent.parse('hello world'), isNull);
      expect(ScanContent.parse('https://'), isNull);
      expect(const ScanResult('5412345678908').content, isNull);
    });
  });

  group('Wi-Fi', () {
    test('the fields in any order', () {
      final WifiContent wifi = _as<WifiContent>(
        'WIFI:T:WPA;S:Home;P:secret;H:true;;',
      );
      expect(wifi.ssid, 'Home');
      expect(wifi.password, 'secret');
      expect(wifi.security, WifiSecurity.wpa);
      expect(wifi.hidden, isTrue);

      final WifiContent other = _as<WifiContent>('WIFI:P:pw;S:Net;T:WEP;;');
      expect(other.security, WifiSecurity.wep);
      expect(other.hidden, isFalse);
    });

    test('escaped characters and quotes', () {
      final WifiContent wifi = _as<WifiContent>(
        r'WIFI:S:"My\;Net";T:WPA;P:a\:b\\c;;',
      );
      expect(wifi.ssid, 'My;Net');
      expect(wifi.password, r'a:b\c');
    });

    test('an open network has no password', () {
      expect(
        _as<WifiContent>('WIFI:S:Cafe;T:nopass;P:;;').security,
        WifiSecurity.open,
      );
      final WifiContent open = _as<WifiContent>('WIFI:S:Cafe;;');
      expect(open.security, WifiSecurity.open);
      expect(open.password, isNull);
    });

    test('WPA2 and WPA3 are WPA, and a password without a type too', () {
      expect(
        _as<WifiContent>('WIFI:S:a;T:SAE;P:x;;').security,
        WifiSecurity.wpa,
      );
      expect(_as<WifiContent>('WIFI:S:a;P:x;;').security, WifiSecurity.wpa);
    });

    test('nothing without a name', () {
      expect(ScanContent.parse('WIFI:T:WPA;P:secret;;'), isNull);
    });
  });

  group('contacts', () {
    test('a vCard 3.0', () {
      final ContactContent contact = _as<ContactContent>(
        'BEGIN:VCARD\r\n'
        'VERSION:3.0\r\n'
        'N:Doe;John;;Dr.;\r\n'
        'FN:John Doe\r\n'
        'ORG:Comapps;Research\r\n'
        'TITLE:Engineer\r\n'
        'TEL;TYPE=CELL:+32 470 00 00 00\r\n'
        'TEL;TYPE=WORK:+32 2 000 00 00\r\n'
        'EMAIL:john@example.com\r\n'
        'item1.URL:https://example.com\r\n'
        'ADR;TYPE=WORK:;;Rue de la Loi 16;Brussels;;1000;Belgium'
        '\r\n'
        r'NOTE:First line\nsecond\, with a comma'
        '\r\n'
        'END:VCARD',
      );
      expect(contact.name, 'John Doe');
      expect(contact.organization, 'Comapps, Research');
      expect(contact.title, 'Engineer');
      expect(contact.phones, <String>['+32 470 00 00 00', '+32 2 000 00 00']);
      expect(contact.emails, <String>['john@example.com']);
      expect(contact.urls, <String>['https://example.com']);
      expect(contact.address, 'Rue de la Loi 16, Brussels, 1000, Belgium');
      expect(contact.note, 'First line\nsecond, with a comma');
    });

    test('the structured name when there is no formatted one', () {
      final ContactContent contact = _as<ContactContent>(
        'BEGIN:VCARD\nVERSION:3.0\nN:Doe;Jane;Ann;Ms.;\nEND:VCARD',
      );
      expect(contact.name, 'Ms. Jane Ann Doe');
    });

    test('folded lines and quoted-printable, as vCard 2.1 writes them', () {
      final ContactContent contact = _as<ContactContent>(
        'BEGIN:VCARD\n'
        'VERSION:2.1\n'
        'FN;CHARSET=UTF-8;ENCODING=QUOTED-PRINTABLE:Ren=C3=A9 Ma=\n'
        'gritte\n'
        'NOTE:A long note that goes\n'
        ' on the next line\n'
        'END:VCARD',
      );
      expect(contact.name, 'René Magritte');
      expect(contact.note, 'A long note that goeson the next line');
    });

    test('a MECARD, its name family name first', () {
      final ContactContent contact = _as<ContactContent>(
        'MECARD:N:Doe,John;TEL:0470000000;TEL:021234567;'
        r'EMAIL:john@example.com;URL:https\://example.com;ADR:Brussels;;',
      );
      expect(contact.name, 'John Doe');
      expect(contact.phones, <String>['0470000000', '021234567']);
      expect(contact.urls, <String>['https://example.com']);
      expect(contact.address, 'Brussels');
    });

    test('nothing for an empty card', () {
      expect(ScanContent.parse('BEGIN:VCARD\nVERSION:3.0\nEND:VCARD'), isNull);
    });
  });

  group('e-mails', () {
    test('mailto, with its subject and body decoded', () {
      final EmailContent mail = _as<EmailContent>(
        'mailto:john@example.com?subject=Hello%20there&body=See%20you',
      );
      expect(mail.address, 'john@example.com');
      expect(mail.subject, 'Hello there');
      expect(mail.body, 'See you');
    });

    test('MATMSG and SMTP', () {
      final EmailContent matmsg = _as<EmailContent>(
        'MATMSG:TO:a@b.be;SUB:Hi;BODY:Text;;',
      );
      expect(matmsg.address, 'a@b.be');
      expect(matmsg.subject, 'Hi');
      expect(matmsg.body, 'Text');

      final EmailContent smtp = _as<EmailContent>('SMTP:a@b.be:Hi:Te:xt');
      expect(smtp.subject, 'Hi');
      expect(smtp.body, 'Te:xt');
    });

    test('broken escapes are kept as they are', () {
      expect(_as<EmailContent>('mailto:a%zz@b.be').address, 'a%zz@b.be');
    });
  });

  group('phone and text messages', () {
    test('tel', () {
      expect(_as<PhoneContent>('tel:+32%202%20123').number, '+32 2 123');
      expect(ScanContent.parse('tel:'), isNull);
    });

    test('SMSTO and sms', () {
      final SmsContent smsto = _as<SmsContent>('SMSTO:+32470:Hello: you');
      expect(smsto.number, '+32470');
      expect(smsto.message, 'Hello: you');

      final SmsContent uri = _as<SmsContent>('sms:+32470?body=Hi%20there');
      expect(uri.number, '+32470');
      expect(uri.message, 'Hi there');

      expect(_as<SmsContent>('MMSTO:+32470').message, isNull);
    });
  });

  group('places', () {
    test('geo, with an altitude and a query', () {
      final GeoContent geo = _as<GeoContent>(
        'geo:50.8467,4.3525,100?q=Grand-Place',
      );
      expect(geo.latitude, 50.8467);
      expect(geo.longitude, 4.3525);
      expect(geo.altitude, 100);
      expect(geo.query, 'Grand-Place');
      expect(_as<GeoContent>('GEO:-33.9,18.4;u=35').altitude, isNull);
    });

    test('nothing for coordinates off the globe or missing', () {
      expect(ScanContent.parse('geo:91,0'), isNull);
      expect(ScanContent.parse('geo:10'), isNull);
    });
  });

  group('events', () {
    test('a timed event in UTC', () {
      final EventContent event = _as<EventContent>(
        'BEGIN:VCALENDAR\n'
        'BEGIN:VEVENT\n'
        'SUMMARY:Launch\n'
        'DTSTART:20260930T090000Z\n'
        'DTEND:20260930T103000Z\n'
        'LOCATION:Brussels\n'
        r'DESCRIPTION:Coffee\, then talks'
        '\n'
        'END:VEVENT\n'
        'END:VCALENDAR',
      );
      expect(event.summary, 'Launch');
      expect(event.start, DateTime.utc(2026, 9, 30, 9));
      expect(event.end, DateTime.utc(2026, 9, 30, 10, 30));
      expect(event.allDay, isFalse);
      expect(event.location, 'Brussels');
      expect(event.description, 'Coffee, then talks');
    });

    test('a whole day, and a local time', () {
      final EventContent day = _as<EventContent>(
        'BEGIN:VEVENT\nSUMMARY:Holiday\nDTSTART;VALUE=DATE:20261225\n'
        'END:VEVENT',
      );
      expect(day.start, DateTime(2026, 12, 25));
      expect(day.allDay, isTrue);

      final EventContent local = _as<EventContent>(
        'BEGIN:VEVENT\nDTSTART;TZID=Europe/Brussels:20261001T143000\n'
        'END:VEVENT',
      );
      expect(local.start, DateTime(2026, 10, 1, 14, 30));
      expect(local.start!.isUtc, isFalse);
    });

    test('nothing without a title or a start', () {
      expect(
        ScanContent.parse('BEGIN:VEVENT\nLOCATION:Nowhere\nEND:VEVENT'),
        isNull,
      );
    });
  });

  test('a switch over the content, as an app writes it', () {
    String describe(ScanResult result) => switch (result.content) {
      WifiContent(:final String ssid) => 'wifi $ssid',
      UrlContent(:final Uri url) => 'link ${url.host}',
      PhoneContent(:final String number) => 'call $number',
      _ => 'text ${result.text}',
    };
    expect(describe(const ScanResult('WIFI:S:Home;;')), 'wifi Home');
    expect(describe(const ScanResult('https://a.be')), 'link a.be');
    expect(describe(const ScanResult('tel:112')), 'call 112');
    expect(describe(const ScanResult('abc')), 'text abc');
  });
}
