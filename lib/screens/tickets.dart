import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../db.dart';
import '../import_parser.dart';
import '../main.dart';
import '../theme.dart';
import 'scanner.dart';

class TicketsScreen extends StatefulWidget {
  final int concertId;
  const TicketsScreen({super.key, required this.concertId});

  @override
  State<TicketsScreen> createState() => _TicketsScreenState();
}

class _TicketsScreenState extends State<TicketsScreen> {
  TicketFilter _filter = TicketFilter.all;
  String _search = '';
  bool _searching = false;
  late Future<(Concert, List<Ticket>)> _data = _load();

  Future<(Concert, List<Ticket>)> _load() async => (
        await db.concert(widget.concertId),
        await db.tickets(widget.concertId, filter: _filter, search: _search),
      );

  void _reload() {
    if (!mounted) return;
    setState(() {
      _data = _load();
    });
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _import(Concert concert) async {
    final files = await FilePicker.pickFiles(); // any type: Android often mislabels .csv MIME
    if (files.isEmpty) return;
    final file = files.first;
    final ext = file.extension?.toLowerCase();
    if (ext != 'txt' && ext != 'csv') return _snack('Wybierz plik .txt lub .csv');

    final List<String> codes;
    try {
      codes = parseCodes(await file.xFile.readAsString(), csv: ext == 'csv');
    } catch (_) {
      return _snack('Nie udało się odczytać pliku (oczekiwano tekstu UTF-8)');
    }
    if (codes.isEmpty) return _snack('Plik nie zawiera kodów');

    var replace = false;
    if (concert.total > 0) {
      final s = await db.importSummary(concert.id, codes);
      if (!mounted) return;
      final choice = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Koncert ma już bilety'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final (label, n) in [
              ('Kodów w pliku', codes.length),
              ('Nowych', s.newCodes),
              ('Już na liście', s.alreadyPresent),
            ])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Expanded(child: Text(label)),
                  Text('$n', style: archivo(16, 700).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                ]),
              ),
            const SizedBox(height: 16),
            Text('Połącz dopisze tylko nowe kody. Statusy biletów zostaną bez zmian.',
                style: Theme.of(c).textTheme.bodyMedium),
            const SizedBox(height: 8),
            Text(
                'Zastąp wszystko usunie obecną listę'
                '${s.scannedExisting > 0 ? ', w tym ${s.scannedExisting} zeskanowanych biletów' : ''}.',
                style: Theme.of(c).textTheme.bodyMedium),
          ]),
          actionsOverflowButtonSpacing: 4,
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Anuluj')),
            TextButton(
                style: TextButton.styleFrom(foregroundColor: Palette.stop),
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Zastąp wszystko')),
            FilledButton(onPressed: () => Navigator.pop(c, false), child: const Text('Połącz')),
          ],
        ),
      );
      if (choice == null) return;
      replace = choice;
    }
    await db.importCodes(concert.id, codes, replace: replace);
    _reload();
    _snack('Zaimportowano listę biletów');
  }

  Future<void> _openTicket(Ticket t) async {
    final scanned = t.scannedAt != null;
    final change = await showModalBottomSheet<bool>(
      context: context,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SelectableText(t.code, style: mono(16)),
            const SizedBox(height: 6),
            Text(
              scanned
                  ? 'Zeskanowany o ${formatTime(t.scannedAt!)}, ${formatDate(t.scannedAt!)}'
                  : 'Jeszcze nie zeskanowany',
              style: archivo(16, 500, color: scanned ? Palette.wpusc : Palette.mgla),
            ),
            const SizedBox(height: 24),
            scanned
                ? OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Palette.stop,
                      side: const BorderSide(color: Palette.kulisyHi),
                      minimumSize: const Size(64, 52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      textStyle: archivo(16, 650, width: 105),
                    ),
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text('Cofnij skan'),
                  )
                : FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Oznacz jako zeskanowany')),
          ]),
        ),
      ),
    );
    if (change != true) return;
    scanned ? await db.unscan(widget.concertId, t.code) : await db.scan(widget.concertId, t.code);
    _reload();
  }

  Future<void> _openScanner(Concert concert) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ScannerScreen(concert: concert)));
    _reload();
  }

  void _setSearch(String v) {
    _search = v;
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _data,
      builder: (context, snap) {
        final data = snap.data;
        if (data == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        final (concert, tickets) = data;
        final text = Theme.of(context).textTheme;
        final empty = concert.total == 0;
        return Scaffold(
          appBar: AppBar(
            title: _searching
                ? TextField(
                    autofocus: true,
                    style: mono(15),
                    decoration: const InputDecoration(
                      hintText: 'Szukaj kodu',
                      filled: false,
                      border: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                    onChanged: _setSearch,
                  )
                : Text(concert.name),
            actions: [
              if (!empty)
                _searching
                    ? IconButton(
                        tooltip: 'Zamknij wyszukiwanie',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _searching = false;
                          _setSearch('');
                        },
                      )
                    : IconButton(
                        tooltip: 'Szukaj kodu',
                        icon: const Icon(Icons.search),
                        onPressed: () => setState(() => _searching = true),
                      ),
              if (!empty)
                IconButton(
                    onPressed: () => _import(concert),
                    icon: const Icon(Icons.upload_file),
                    tooltip: 'Importuj listę biletów'),
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: empty
                  ? FilledButton.icon(
                      onPressed: () => _import(concert),
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Importuj listę biletów'))
                  : FilledButton.icon(
                      onPressed: () => _openScanner(concert),
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Skanuj bilety')),
            ),
          ),
          body: empty
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Lista biletów jest pusta', style: text.headlineSmall),
                      const SizedBox(height: 8),
                      Text('Zaimportuj plik .txt (jeden kod w linii) lub .csv (kod w pierwszej kolumnie).',
                          style: text.bodyLarge!.copyWith(color: Palette.mgla)),
                    ],
                  ),
                )
              : CustomScrollView(slivers: [
                  if (!_searching)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      sliver: SliverToBoxAdapter(child: ScanProgress(scanned: concert.scanned, total: concert.total)),
                    ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(children: [
                        for (final (f, label, n, dot) in [
                          (TicketFilter.all, 'Wszystkie', concert.total, null),
                          (TicketFilter.scanned, 'Wpuszczeni', concert.scanned, Palette.wpusc),
                          (TicketFilter.notScanned, 'Czekają', concert.total - concert.scanned, Palette.kulisyHi),
                        ])
                          _FilterTab(
                            label: label,
                            count: n,
                            dot: dot,
                            selected: _filter == f,
                            onTap: () {
                              _filter = f;
                              _reload();
                            },
                          ),
                      ]),
                    ),
                  ),
                  const SliverToBoxAdapter(child: Divider(height: 1, color: Palette.kulisy)),
                  if (tickets.isEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.all(16),
                      sliver: SliverToBoxAdapter(
                        child: Text(
                            _search.isEmpty ? 'Brak biletów w tej grupie.' : 'Żaden kod nie zawiera „$_search”.',
                            style: text.bodyLarge!.copyWith(color: Palette.mgla)),
                      ),
                    )
                  else
                    SliverList.separated(
                      itemCount: tickets.length,
                      separatorBuilder: (_, _) => const Divider(height: 1, color: Palette.kulisy),
                      itemBuilder: (context, i) => _TicketRow(tickets[i], onTap: () => _openTicket(tickets[i])),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                ]),
        );
      },
    );
  }
}

/// Filter tab with its count; the dot matches the progress bar's colours.
class _FilterTab extends StatelessWidget {
  final String label;
  final int count;
  final Color? dot;
  final bool selected;
  final VoidCallback onTap;
  const _FilterTab(
      {required this.label, required this.count, required this.dot, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = selected ? Palette.kreda : Palette.mgla;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: selected ? Palette.kreda : Colors.transparent, width: 2)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$count',
                style: archivo(22, 750, width: 112, height: 1.1, color: color)
                    .copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
            const SizedBox(height: 2),
            Row(children: [
              if (dot != null) ...[
                Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
                const SizedBox(width: 6),
              ],
              Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: archivo(13, 550, color: color))),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _TicketRow extends StatelessWidget {
  final Ticket ticket;
  final VoidCallback onTap;
  const _TicketRow(this.ticket, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    final at = ticket.scannedAt;
    return InkWell(
      onTap: onTap,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 4, color: at == null ? Colors.transparent : Palette.wpusc),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
              child: Row(children: [
                Expanded(
                  child: Text(ticket.code, maxLines: 2, overflow: TextOverflow.ellipsis, style: mono(14, color: Palette.mgla)),
                ),
                if (at != null) ...[
                  const SizedBox(width: 12),
                  Text(formatTime(at).substring(0, 5),
                      style: archivo(14, 600, color: Palette.wpusc)
                          .copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                ],
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
