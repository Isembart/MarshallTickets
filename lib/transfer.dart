import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'db.dart';

/// Base64 characters per QR frame. Smaller reads faster off a screen, larger
/// means fewer frames. ~800 tickets ≈ 15–25 frames.
const chunkSize = 500;

/// A Concert as it travels between devices.
class TransferData {
  final String name;
  final DateTime? date;
  final List<Ticket> tickets;
  TransferData(this.name, this.date, this.tickets);
}

/// Frames to show one after another: `MT1|<sha256 of content>|<i>|<n>|<base64 slice>`.
/// The hash ties every frame to one Transfer and lets the receiver verify the whole.
(List<String>, String fingerprint) encodeTransfer(TransferData t) {
  final json = utf8.encode(jsonEncode({
    'n': t.name,
    'd': t.date?.toIso8601String(),
    't': [for (final k in t.tickets) [k.code, k.scannedAt?.microsecondsSinceEpoch]],
  }));
  final hash = sha256.convert(json).toString();
  final b64 = base64.encode(zlib.encode(json));
  final n = (b64.length / chunkSize).ceil();
  return (
    [for (var i = 0; i < n; i++) 'MT1|$hash|$i|$n|${b64.substring(i * chunkSize, ((i + 1) * chunkSize).clamp(0, b64.length))}'],
    fingerprint(hash),
  );
}

String fingerprint(String hash) => '${hash.substring(0, 4)}-${hash.substring(4, 8)}'.toUpperCase();

/// Same Concert for Transfer purposes: names equal ignoring case and surrounding spaces.
bool sameName(String a, String b) => a.trim().toLowerCase() == b.trim().toLowerCase();

/// Collects frames in any order. Frames of a different Transfer start over.
class TransferReceiver {
  String? hash;
  int total = 0;
  final _chunks = <int, String>{};

  int get received => _chunks.length;

  /// Returns true if the frame was new and belongs to this Transfer.
  bool add(String frame) {
    final p = frame.split('|');
    if (p.length != 5 || p[0] != 'MT1') return false;
    final i = int.tryParse(p[2]), n = int.tryParse(p[3]);
    if (i == null || n == null || n < 1 || i < 0 || i >= n) return false;
    if (p[1] != hash || n != total) {
      hash = p[1];
      total = n;
      _chunks.clear();
    }
    if (_chunks.containsKey(i)) return false;
    _chunks[i] = p[4];
    return true;
  }

  bool get complete => total > 0 && received == total;

  /// The Transfer, only if every frame is in and the content hashes to exactly
  /// what the sender announced. Anything else throws: never a partial result.
  TransferData decode() {
    if (!complete) throw StateError('incomplete');
    final json = zlib.decode(base64.decode([for (var i = 0; i < total; i++) _chunks[i]!].join()));
    if (sha256.convert(json).toString() != hash) throw const FormatException('checksum mismatch');
    final m = jsonDecode(utf8.decode(json)) as Map<String, dynamic>;
    final d = m['d'] as String?;
    return TransferData(m['n'] as String, d == null ? null : DateTime.parse(d), [
      for (final t in m['t'] as List)
        Ticket(t[0] as String, t[1] == null ? null : DateTime.fromMicrosecondsSinceEpoch(t[1] as int)),
    ]);
  }
}
