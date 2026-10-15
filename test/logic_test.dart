import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:marshall_tickets/db.dart';
import 'package:marshall_tickets/import_parser.dart';
import 'package:marshall_tickets/screens/concert_list.dart';
import 'package:marshall_tickets/transfer.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('parser: sample file', () {
    final codes = parseCodes(File('sampleData.txt').readAsStringSync(), csv: false);
    expect(codes.length, 103);
    expect(codes.first, '7916061048');
    expect(codes.last, startsWith('https://sklep.pullthewire.pl/'));
  });

  test('parser: csv header, separators, quotes, blanks, dups', () {
    expect(parseCodes('Kod;name\r\n"abc";x\n\n def ,y\nabc,z\n', csv: true), ['abc', 'def']);
    expect(parseCodes('code\n', csv: true), isEmpty);
    expect(parseCodes('code\n', csv: false), ['code']);
  });

  test('splitNow: today..+3 days soonest first, rest keeps order', () {
    Concert c(int id, DateTime? d) => Concert(id, '$id', d, 0, 0);
    final now = DateTime(2026, 10, 16, 23, 30); // Friday late evening
    final all = [
      c(1, DateTime(2026, 10, 20)), // Tue, +4: not now
      c(2, DateTime(2026, 10, 19)), // Mon, +3
      c(3, DateTime(2026, 10, 18)), // Sun
      c(4, DateTime(2026, 10, 16)), // today (midnight)
      c(5, DateTime(2026, 10, 15)), // yesterday
      c(6, null),
    ];
    final (soon, rest) = splitNow(all, now);
    expect(soon.map((c) => c.id), [4, 3, 2]);
    expect(rest.map((c) => c.id), [1, 5, 6]);
  });

  group('transfer', () {
    final at = DateTime(2026, 10, 16, 20, 14, 3, 123, 456);
    final data = TransferData('Marshall Live', DateTime(2026, 10, 16), [
      for (var i = 0; i < 800; i++) Ticket('${7916061048 + i * 7919}', i.isEven ? at : null),
      Ticket('https://sklep.pullthewire.pl/x?a=1|b„ż”', null), // separator and non-ASCII survive
    ]);

    test('round trip in any order, exact content, same fingerprint', () {
      final (frames, fp) = encodeTransfer(data);
      expect(frames.length, greaterThan(1));
      final rx = TransferReceiver();
      for (final f in frames.reversed) {
        expect(rx.add(f), isTrue);
        expect(rx.add(f), isFalse, reason: 'repeat ignored');
      }
      expect(rx.complete, isTrue);
      final got = rx.decode();
      expect(fingerprint(rx.hash!), fp);
      expect([got.name, got.date], [data.name, data.date]);
      expect(got.tickets.map((t) => (t.code, t.scannedAt)), data.tickets.map((t) => (t.code, t.scannedAt)));
    });

    test('any altered frame is rejected, never a partial result', () {
      final (frames, _) = encodeTransfer(data);
      for (final i in [0, frames.length ~/ 2, frames.length - 1]) {
        final rx = TransferReceiver();
        for (var j = 0; j < frames.length; j++) {
          var f = frames[j];
          if (j == i) {
            final k = f.length - 3; // flip one payload character
            f = f.replaceRange(k, k + 1, f[k] == 'A' ? 'B' : 'A');
          }
          rx.add(f);
        }
        expect(rx.decode, throwsA(anything));
      }
    });

    test('foreign frames ignored, a new transfer starts over', () {
      final rx = TransferReceiver();
      expect(rx.add('7916061048'), isFalse);
      expect(rx.add('MT1|x|5|3|AAAA'), isFalse);
      final (a, _) = encodeTransfer(data);
      final (b, _) = encodeTransfer(TransferData('Other', null, [Ticket('1', null)]));
      rx.add(a.first);
      rx.add(b.first);
      expect([rx.received, rx.total, rx.complete], [1, 1, true]);
      expect(rx.decode().name, 'Other');
    });

    test('sameName ignores case and surrounding spaces', () {
      expect(sameName(' Marshall Live ', 'marshall live'), isTrue);
      expect(sameName('Marshall Live', 'Marshall Live 2'), isFalse);
    });
  });

  group('db', () {
    late Db db;
    late int a, b;

    setUp(() async {
      sqfliteFfiInit();
      db = await Db.open(inMemoryDatabasePath, databaseFactoryFfi);
      a = await db.saveConcert(null, 'A', null);
      b = await db.saveConcert(null, 'B', DateTime(2026, 11, 1));
      await db.importCodes(a, ['1', '2'], replace: false);
      await db.importCodes(b, ['9'], replace: false);
    });
    tearDown(() => db.close());

    test('scan: valid, already scanned, invalid, other concert, unscan', () async {
      expect((await db.scan(a, ' 1 ')).status, ScanStatus.valid);
      final again = await db.scan(a, '1');
      expect(again.status, ScanStatus.alreadyScanned);
      expect(again.scannedAt, isNotNull);
      final unknown = await db.scan(a, 'x');
      expect([unknown.status, unknown.otherConcert], [ScanStatus.invalid, null]);
      expect((await db.scan(a, '9')).otherConcert, 'B');
      await db.unscan(a, '1');
      expect((await db.scan(a, '1')).status, ScanStatus.valid);
    });

    test('import: join keeps statuses, replace resets', () async {
      await db.scan(a, '1');
      final s = await db.importSummary(a, ['1', '3']);
      expect([s.newCodes, s.alreadyPresent, s.scannedExisting], [1, 1, 1]);

      await db.importCodes(a, ['1', '3'], replace: false);
      var c = await db.concert(a);
      expect([c.total, c.scanned], [3, 1]);

      await db.importCodes(a, ['1', '3'], replace: true);
      c = await db.concert(a);
      expect([c.total, c.scanned], [2, 0]);
    });

    test('transfer join: scanned wins at the earlier time, never un-scans', () async {
      final early = DateTime(2026, 10, 16, 18), late = DateTime(2026, 10, 16, 20);
      await db.importTransfer(a, 'A', null, [Ticket('1', DateTime(2026, 10, 16, 19))], replace: false);
      await db.importTransfer(a, 'A', DateTime(2027), [
        Ticket('1', early), // earlier than local: take it
        Ticket('2', late), // local not scanned: take it
        Ticket('3', null), // new code
      ], replace: false);
      var t = {for (final k in await db.tickets(a)) k.code: k.scannedAt};
      expect(t, {'1': early, '2': late, '3': null});

      await db.importTransfer(a, 'A', null, [Ticket('1', null), Ticket('2', DateTime(2026, 10, 17))], replace: false);
      t = {for (final k in await db.tickets(a)) k.code: k.scannedAt};
      expect(t, {'1': early, '2': late, '3': null}, reason: 'no un-scan, later time ignored');
      expect((await db.concert(a)).date, isNull, reason: 'join keeps receiver date');
    });

    test('transfer replace: takes tickets, statuses, name and date', () async {
      await db.scan(a, '1');
      final at = DateTime(2026, 10, 16, 21);
      await db.importTransfer(a, 'a', DateTime(2026, 10, 16), [Ticket('5', at), Ticket('6', null)], replace: true);
      final c = await db.concert(a);
      expect([c.name, c.date, c.total, c.scanned], ['a', DateTime(2026, 10, 16), 2, 1]);
      expect({for (final k in await db.tickets(a)) k.code: k.scannedAt}, {'5': at, '6': null});
    });

    test('tickets filter/search and delete cascade', () async {
      await db.scan(a, '2');
      expect((await db.tickets(a, filter: TicketFilter.scanned)).map((t) => t.code), ['2']);
      expect((await db.tickets(a, filter: TicketFilter.notScanned)).map((t) => t.code), ['1']);
      expect((await db.tickets(a, search: '1')).map((t) => t.code), ['1']);
      await db.deleteConcert(a);
      expect((await db.concerts()).map((c) => c.name), ['B']);
      await db.saveConcert(null, 'C', DateTime(2026, 12, 1));
      expect((await db.concerts()).map((c) => c.name), ['C', 'B'], reason: 'newest first');
      expect((await db.scan(b, '1')).otherConcert, null);
    });
  });
}
