final _headerWords = RegExp(r'^(code|kod|ticket|bilet|id|ticket_id)$', caseSensitive: false);

/// Ticket Codes from a .txt (one per line) or .csv (first column) file:
/// trimmed, blank lines dropped, in-file duplicates removed, order kept.
List<String> parseCodes(String content, {required bool csv}) {
  var lines = content.split(RegExp(r'\r?\n'));
  var codes = lines.map((l) {
    var c = csv ? l.split(RegExp('[,;]')).first : l;
    c = c.trim();
    if (csv && c.length >= 2 && c.startsWith('"') && c.endsWith('"')) {
      c = c.substring(1, c.length - 1).trim();
    }
    return c;
  }).where((c) => c.isNotEmpty).toList();
  if (csv && codes.isNotEmpty && _headerWords.hasMatch(codes.first)) {
    codes.removeAt(0);
  }
  return codes.toSet().toList();
}
