import 'package:flutter/material.dart';

import '../db.dart';
import '../main.dart';
import '../theme.dart';
import 'tickets.dart';

class ConcertListScreen extends StatefulWidget {
  const ConcertListScreen({super.key});

  @override
  State<ConcertListScreen> createState() => _ConcertListScreenState();
}

class _ConcertListScreenState extends State<ConcertListScreen> {
  late Future<List<Concert>> _concerts = db.concerts();

  void _reload() => setState(() {
        _concerts = db.concerts();
      });

  Future<void> _edit([Concert? concert]) async {
    final saved = await showDialog<bool>(context: context, builder: (_) => _ConcertDialog(concert));
    if (saved == true) _reload();
  }

  Future<void> _delete(Concert c) async {
    if (!await confirm(context, 'Usunąć koncert?', '„${c.name}” i wszystkie jego bilety (${c.total}) zostaną usunięte.',
        'Usuń')) {
      return;
    }
    await db.deleteConcert(c.id);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Koncerty')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(onPressed: _edit, icon: const Icon(Icons.add), label: const Text('Nowy koncert')),
        ),
      ),
      body: FutureBuilder(
        future: _concerts,
        builder: (context, snap) {
          final concerts = snap.data;
          if (concerts == null) return const Center(child: CircularProgressIndicator());
          if (concerts.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Nie masz jeszcze koncertów', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text('Dodaj koncert, a potem zaimportuj do niego listę biletów.',
                      style: Theme.of(context).textTheme.bodyLarge!.copyWith(color: Palette.mgla)),
                ],
              ),
            );
          }
          final (soon, rest) = splitNow(concerts, DateTime.now());
          final today = DateUtils.dateOnly(DateTime.now());
          Widget stub(Concert c, {bool inNow = false}) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ConcertStub(
                  concert: c,
                  inNow: inNow,
                  isToday: c.date != null && DateUtils.isSameDay(c.date, today),
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => TicketsScreen(concertId: c.id)));
                    _reload();
                  },
                  menu: PopupMenuButton(
                    tooltip: 'Opcje',
                    icon: const Icon(Icons.more_vert, color: Palette.mgla),
                    onSelected: (edit) => edit ? _edit(c) : _delete(c),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: true, child: Text('Edytuj')),
                      PopupMenuItem(value: false, child: Text('Usuń')),
                    ],
                  ),
                ),
              );
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            children: [
              if (soon.isNotEmpty) ...[
                _SectionTitle('Teraz', color: Palette.kreda),
                for (final c in soon) stub(c, inNow: true),
                if (rest.isNotEmpty) ...[const SizedBox(height: 12), _SectionTitle('Pozostałe', color: Palette.mgla)],
              ],
              for (final c in rest) stub(c),
            ],
          );
        },
      ),
    );
  }
}

/// A concert drawn as a ticket stub: date on the tear-off side, separated by a perforation.
/// Concerts from today up to 3 days ahead (soonest first), and everything else
/// in list order (newest first). On a Friday you still see the weekend's shows.
(List<Concert>, List<Concert>) splitNow(List<Concert> concerts, DateTime now) {
  final from = DateUtils.dateOnly(now);
  final to = DateTime(from.year, from.month, from.day + 3);
  bool soon(Concert c) => c.date != null && !c.date!.isBefore(from) && !DateUtils.dateOnly(c.date!).isAfter(to);
  final upcoming = concerts.where(soon).toList()..sort((a, b) => a.date!.compareTo(b.date!));
  return (upcoming, concerts.where((c) => !soon(c)).toList());
}

const _weekdays = ['pon', 'wt', 'śr', 'czw', 'pt', 'sob', 'nd'];

class _SectionTitle extends StatelessWidget {
  final String title;
  final Color color;
  const _SectionTitle(this.title, {required this.color});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
        child: Text(title, style: archivo(17, 700, width: 108, color: color)),
      );
}

class _ConcertStub extends StatelessWidget {
  final Concert concert;
  final bool inNow, isToday;
  final VoidCallback onTap;
  final Widget menu;
  const _ConcertStub(
      {required this.concert, required this.onTap, required this.menu, this.inNow = false, this.isToday = false});

  @override
  Widget build(BuildContext context) {
    final c = concert;
    final text = Theme.of(context).textTheme;
    return ClipPath(
      clipper: const _StubClipper(notchX: 76 + 9),
      child: Material(
        color: isToday ? Palette.kulisyHi : Palette.kulisy,
        child: InkWell(
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                width: 76,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: c.date == null
                      ? [Text('bez\ndaty', textAlign: TextAlign.center, style: text.bodySmall!.copyWith(color: Palette.mgla))]
                      : [
                          Text('${c.date!.day}', style: archivo(32, 800, width: 115, height: 1, color: Palette.kreda)),
                          const SizedBox(height: 2),
                          Text(isToday ? 'dziś' : inNow ? _weekdays[c.date!.weekday - 1] : monthShort(c.date!),
                              style: archivo(14, isToday ? 700 : 500, color: isToday ? Palette.kreda : Palette.mgla)),
                        ],
                ),
              ),
              const SizedBox(width: 18, child: CustomPaint(painter: _Perforation())),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 16, 0, 16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(c.name, style: text.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: ScanProgress(scanned: c.scanned, total: c.total)),
                      const SizedBox(width: 10),
                      Text(
                        c.total == 0 ? 'brak biletów' : '${c.scanned} / ${c.total}',
                        style: archivo(13, 500, color: Palette.mgla)
                            .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                      ),
                    ]),
                  ]),
                ),
              ),
              Center(child: menu),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Perforation extends CustomPainter {
  const _Perforation();

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    final dot = Paint()..color = Palette.mgla.withValues(alpha: 0.45);
    for (var y = 14.0; y < size.height - 12; y += 8) {
      canvas.drawCircle(Offset(x, y), 1.6, dot);
    }
  }

  @override
  bool shouldRepaint(_Perforation old) => false;
}

/// Rounded stub with two half-circle notches punched where the perforation meets the edges.
class _StubClipper extends CustomClipper<Path> {
  final double notchX;
  const _StubClipper({required this.notchX});

  @override
  Path getClip(Size size) => Path.combine(
        PathOperation.difference,
        Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(16))),
        Path()
          ..addOval(Rect.fromCircle(center: Offset(notchX, 0), radius: 8))
          ..addOval(Rect.fromCircle(center: Offset(notchX, size.height), radius: 8)),
      );

  @override
  bool shouldReclip(_StubClipper old) => old.notchX != notchX;
}

class _ConcertDialog extends StatefulWidget {
  final Concert? concert;
  const _ConcertDialog(this.concert);

  @override
  State<_ConcertDialog> createState() => _ConcertDialogState();
}

class _ConcertDialogState extends State<_ConcertDialog> {
  late final _name = TextEditingController(text: widget.concert?.name);
  late DateTime? _date = widget.concert?.date;

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    await db.saveConcert(widget.concert?.id, name, _date);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
        context: context, initialDate: _date ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (d != null) setState(() => _date = d);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.concert == null ? 'Nowy koncert' : 'Edytuj koncert'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: _name,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Nazwa koncertu'),
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 12),
        Material(
          color: Palette.scena,
          borderRadius: BorderRadius.circular(14),
          child: ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            leading: const Icon(Icons.event, color: Palette.kreda),
            title: Text(_date == null ? 'Dodaj datę' : formatDate(_date!)),
            onTap: _pickDate,
            trailing: _date == null
                ? null
                : IconButton(
                    tooltip: 'Usuń datę',
                    onPressed: () => setState(() => _date = null),
                    icon: const Icon(Icons.close, color: Palette.mgla),
                  ),
          ),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Anuluj')),
        FilledButton(onPressed: _save, child: const Text('Zapisz')),
      ],
    );
  }
}
