import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class Concert {
  final int id;
  final String name;
  final DateTime? date;
  final int total;
  final int scanned;
  Concert(this.id, this.name, this.date, this.total, this.scanned);
}

class Ticket {
  final String code;
  final DateTime? scannedAt;
  Ticket(this.code, this.scannedAt);
}

enum ScanStatus { valid, alreadyScanned, invalid }

class ScanResult {
  final ScanStatus status;
  final String code;
  final DateTime? scannedAt; // when first scanned, for alreadyScanned
  final String? otherConcert; // for invalid: concert the code belongs to
  ScanResult(this.status, this.code, {this.scannedAt, this.otherConcert});
}

class ImportSummary {
  final int newCodes, alreadyPresent, scannedExisting;
  ImportSummary(this.newCodes, this.alreadyPresent, this.scannedExisting);
}

enum TicketFilter { all, scanned, notScanned }

class Db {
  final Database _db;
  Db._(this._db);

  static Future<Db> open([String? path, DatabaseFactory? factory]) async {
    path ??= p.join(await getDatabasesPath(), 'tickets.db');
    final db = await (factory ?? databaseFactory).openDatabase(path,
        options: OpenDatabaseOptions(
          version: 1,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, _) async {
            await db.execute('CREATE TABLE concerts (id INTEGER PRIMARY KEY, name TEXT NOT NULL, date TEXT)');
            await db.execute('CREATE TABLE tickets (id INTEGER PRIMARY KEY, '
                'concert_id INTEGER NOT NULL REFERENCES concerts(id) ON DELETE CASCADE, '
                'code TEXT NOT NULL, scanned_at TEXT, UNIQUE(concert_id, code))');
          },
        ));
    return Db._(db);
  }

  Future<void> close() => _db.close();

  // Concerts

  Future<List<Concert>> concerts() async {
    final rows = await _db.rawQuery('SELECT c.id, c.name, c.date, COUNT(t.id) AS total, COUNT(t.scanned_at) AS scanned '
        'FROM concerts c LEFT JOIN tickets t ON t.concert_id = c.id '
        'GROUP BY c.id ORDER BY c.date IS NULL, c.date DESC, c.name');
    return rows
        .map((r) => Concert(r['id'] as int, r['name'] as String, _date(r['date']), r['total'] as int, r['scanned'] as int))
        .toList();
  }

  Future<Concert> concert(int id) async => (await concerts()).firstWhere((c) => c.id == id);

  Future<int> saveConcert(int? id, String name, DateTime? date) async {
    final values = {'name': name, 'date': date?.toIso8601String()};
    if (id == null) return _db.insert('concerts', values);
    await _db.update('concerts', values, where: 'id = ?', whereArgs: [id]);
    return id;
  }

  Future<void> deleteConcert(int id) => _db.delete('concerts', where: 'id = ?', whereArgs: [id]);

  // Tickets

  Future<List<Ticket>> tickets(int concertId, {TicketFilter filter = TicketFilter.all, String search = ''}) async {
    var where = 'concert_id = ? AND code LIKE ?';
    if (filter == TicketFilter.scanned) where += ' AND scanned_at IS NOT NULL';
    if (filter == TicketFilter.notScanned) where += ' AND scanned_at IS NULL';
    final rows = await _db.query('tickets',
        where: where, whereArgs: [concertId, '%${search.trim()}%'], orderBy: 'scanned_at IS NULL, scanned_at DESC, id');
    return rows.map((r) => Ticket(r['code'] as String, _date(r['scanned_at']))).toList();
  }

  Future<void> unscan(int concertId, String code) =>
      _db.update('tickets', {'scanned_at': null}, where: 'concert_id = ? AND code = ?', whereArgs: [concertId, code]);

  // Import

  Future<ImportSummary> importSummary(int concertId, List<String> codes) async {
    final existing = {
      for (final r in await _db.query('tickets', where: 'concert_id = ?', whereArgs: [concertId]))
        r['code'] as String: r['scanned_at'] != null
    };
    final present = codes.where(existing.containsKey).length;
    return ImportSummary(codes.length - present, present, existing.values.where((s) => s).length);
  }

  /// replace: drop the concert's tickets (and statuses) first. Otherwise Join:
  /// only new codes are added, existing tickets untouched.
  Future<void> importCodes(int concertId, List<String> codes, {required bool replace}) => _db.transaction((tx) async {
        if (replace) await tx.delete('tickets', where: 'concert_id = ?', whereArgs: [concertId]);
        final batch = tx.batch();
        for (final code in codes) {
          batch.insert('tickets', {'concert_id': concertId, 'code': code}, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
        await batch.commit(noResult: true);
      });

  /// Import of a Transfer. replace: the concert takes the sender's tickets,
  /// statuses, name and date. Join: new codes are added, and a ticket scanned on
  /// either side ends up scanned at the earlier time; nothing is un-scanned.
  Future<void> importTransfer(int concertId, String name, DateTime? date, List<Ticket> tickets, {required bool replace}) =>
      _db.transaction((tx) async {
        if (replace) {
          await tx.delete('tickets', where: 'concert_id = ?', whereArgs: [concertId]);
          await tx.update('concerts', {'name': name, 'date': date?.toIso8601String()}, where: 'id = ?', whereArgs: [concertId]);
        }
        final existing = {
          for (final r in await tx.query('tickets', where: 'concert_id = ?', whereArgs: [concertId]))
            r['code'] as String: _date(r['scanned_at'])
        };
        final batch = tx.batch();
        for (final t in tickets) {
          final at = t.scannedAt?.toIso8601String();
          if (!existing.containsKey(t.code)) {
            batch.insert('tickets', {'concert_id': concertId, 'code': t.code, 'scanned_at': at},
                conflictAlgorithm: ConflictAlgorithm.ignore);
          } else if (t.scannedAt != null && (existing[t.code] == null || t.scannedAt!.isBefore(existing[t.code]!))) {
            batch.update('tickets', {'scanned_at': at},
                where: 'concert_id = ? AND code = ?', whereArgs: [concertId, t.code]);
          }
        }
        await batch.commit(noResult: true);
      });

  // Scan

  Future<ScanResult> scan(int concertId, String rawCode) async {
    final code = rawCode.trim();
    // Conditional update: atomic, so a double read can't yield two "valid" results.
    final updated = await _db.update('tickets', {'scanned_at': DateTime.now().toIso8601String()},
        where: 'concert_id = ? AND code = ? AND scanned_at IS NULL', whereArgs: [concertId, code]);
    if (updated == 1) return ScanResult(ScanStatus.valid, code);

    final rows = await _db.query('tickets', where: 'concert_id = ? AND code = ?', whereArgs: [concertId, code]);
    if (rows.isNotEmpty) {
      return ScanResult(ScanStatus.alreadyScanned, code, scannedAt: _date(rows.first['scanned_at']));
    }
    final other = await _db.rawQuery(
        'SELECT c.name FROM tickets t JOIN concerts c ON c.id = t.concert_id WHERE t.code = ? LIMIT 1', [code]);
    return ScanResult(ScanStatus.invalid, code, otherConcert: other.isEmpty ? null : other.first['name'] as String);
  }

  static DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String);
}
