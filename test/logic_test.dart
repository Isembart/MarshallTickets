import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:marshall_tickets/db.dart';
import 'package:marshall_tickets/import_parser.dart';
import 'package:marshall_tickets/screens/concert_list.dart';
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
