import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../db.dart';
import '../main.dart';
import '../theme.dart';
import '../transfer.dart';
import 'tickets.dart';

/// How long each frame stays on the sender's screen. Raise it if an older
/// receiving phone keeps missing frames.
const _frameEvery = Duration(milliseconds: 300);

TextStyle _tabular(TextStyle s) => s.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

/// Shows the Concert as a loop of QR frames until closed.
class SendScreen extends StatefulWidget {
  final int concertId;
  const SendScreen({super.key, required this.concertId});

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  List<String>? _frames;
  String _fingerprint = '';
  Concert? _concert;
  int _i = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await db.concert(widget.concertId);
    final (frames, fp) = encodeTransfer(TransferData(c.name, c.date, await db.tickets(c.id)));
    if (!mounted) return;
    setState(() {
      _concert = c;
      _frames = frames;
      _fingerprint = fp;
    });
    _timer = Timer.periodic(_frameEvery, (_) => setState(() => _i = (_i + 1) % frames.length));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frames = _frames, c = _concert;
    final body = Theme.of(context).textTheme.bodyMedium!.copyWith(color: Palette.mgla);
    return Scaffold(
      appBar: AppBar(title: const Text('Wyślij koncert')),
      body: frames == null || c == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
              Text(c.name, style: Theme.of(context).textTheme.titleLarge),
              Text('${c.total} biletów, ${c.scanned} zeskanowanych', style: body),
              const SizedBox(height: 16),
              // White card: QR needs a light quiet zone to be readable.
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: QrImageView(
                  data: frames[_i],
                  backgroundColor: Colors.white,
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                  padding: const EdgeInsets.all(16),
                  gapless: true,
                ),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Text('Klatka ${_i + 1} / ${frames.length}', style: _tabular(archivo(14, 550, color: Palette.mgla))),
                const Spacer(),
                Text('Kod kontrolny ', style: archivo(14, 550, color: Palette.mgla)),
                Text(_fingerprint, style: mono(16, color: Palette.kreda)),
              ]),
              const SizedBox(height: 20),
              Text.rich(
                  TextSpan(children: [
                    TextSpan(text: 'Odbiór: ', style: archivo(14, 700, color: Palette.kreda)),
                    const TextSpan(
                        text: 'na drugim telefonie otwórz „Odbierz koncert” i skieruj aparat na ten kod, aż pasek się '
                            'zapełni. Sprawdź, czy kod kontrolny na obu ekranach jest taki sam.'),
                  ]),
                  style: body),
              const SizedBox(height: 10),
              Text.rich(
                  TextSpan(children: [
                    TextSpan(text: 'Dopasowanie po nazwie: ', style: archivo(14, 700, color: Palette.kreda)),
                    const TextSpan(
                        text: 'jeśli odbiorca ma koncert o tej samej nazwie, zapyta: Połącz albo Zastąp. Zmiana nazwy '
                            'na którymkolwiek telefonie sprawi, że będą traktowane jako różne koncerty.'),
                  ]),
                  style: body),
            ]),
    );
  }
}

/// Collects a Transfer's frames with the camera, verifies it, then imports it.
/// Pops true once something was saved.
class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({super.key});

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  var _rx = TransferReceiver();
  TransferData? _data;
  bool _corrupt = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_data != null) return;
    var added = false;
    for (final b in capture.barcodes) {
      if (b.rawValue != null && _rx.add(b.rawValue!)) added = true;
    }
    if (!added) return;
    setState(() => _corrupt = false);
    if (!_rx.complete) return;
    try {
      final data = _rx.decode();
      HapticFeedback.mediumImpact();
      _controller.stop();
      setState(() => _data = data);
    } catch (_) {
      // Never keep a part of a bad Transfer: start collecting again from scratch.
      HapticFeedback.heavyImpact();
      setState(() {
        _rx = TransferReceiver();
        _corrupt = true;
      });
    }
  }

  Future<void> _save(TransferData t) async {
    final matches = (await db.concerts()).where((c) => sameName(c.name, t.name)).toList();
    if (!mounted) return;
    Concert? target = matches.length == 1 ? matches.first : null;
    if (matches.length > 1) {
      final picked = await showDialog<Concert?>(
        context: context,
        builder: (c) => SimpleDialog(title: const Text('Kilka koncertów o tej nazwie'), children: [
          for (final m in matches)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, m),
              child: Text('${m.name}${m.date == null ? '' : ', ${formatDate(m.date!)}'} (${m.total} biletów)'),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, Concert(-1, '', null, 0, 0)),
            child: const Text('Utwórz nowy koncert'),
          ),
        ]),
      );
      if (picked == null) return;
      if (picked.id != -1) target = picked;
    }

    var replace = false;
    if (target != null && target.total > 0) {
      final s = await db.importSummary(target.id, [for (final k in t.tickets) k.code]);
      if (!mounted) return;
      final choice = await askJoinOrReplace(context, t.tickets.length, s, transfer: true);
      if (choice == null) return;
      replace = choice;
    }
    final id = target?.id ?? await db.saveConcert(null, t.name, t.date);
    await db.importTransfer(id, t.name, t.date, t.tickets, replace: replace);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Odebrano koncert „${t.name}”')));
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      appBar: AppBar(title: const Text('Odbierz koncert')),
      body: data == null ? _scanning(context) : _received(context, data),
    );
  }

  Widget _scanning(BuildContext context) => Column(children: [
        Expanded(
          child: MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Aparat jest niedostępny (${error.errorCode.name}). Sprawdź uprawnienia aparatu.',
                    style: Theme.of(context).textTheme.bodyLarge),
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(
                  _corrupt
                      ? 'Dane nie zgadzają się z sumą kontrolną. Nic nie zapisano — skanuj dalej, odbiór zacznie się od nowa.'
                      : _rx.total == 0
                          ? 'Skieruj aparat na kod z ekranu „Wyślij koncert” na drugim telefonie'
                          : 'Odbieranie… trzymaj aparat na kodzie',
                  style: archivo(16, 600, color: _corrupt ? Palette.stop : Palette.kreda)),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: _rx.total == 0 ? 0 : _rx.received / _rx.total,
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
                color: Palette.wpusc,
                backgroundColor: Palette.kulisy,
              ),
              const SizedBox(height: 6),
              Text('${_rx.received} / ${_rx.total}', style: _tabular(archivo(14, 550, color: Palette.mgla))),
            ]),
          ),
        ),
      ]);

  Widget _received(BuildContext context, TransferData t) {
    final scanned = t.tickets.where((k) => k.scannedAt != null).length;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Odebrano ✓', style: archivo(32, 800, color: Palette.wpusc)),
          const SizedBox(height: 16),
          Text(t.name, style: Theme.of(context).textTheme.titleLarge),
          Text('${t.tickets.length} biletów, $scanned zeskanowanych',
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: Palette.mgla)),
          const SizedBox(height: 16),
          Row(children: [
            Text('Kod kontrolny ', style: archivo(14, 550, color: Palette.mgla)),
            Text(fingerprint(_rx.hash!), style: mono(16, color: Palette.kreda)),
          ]),
          const SizedBox(height: 4),
          Text('Sprawdź, czy jest taki sam jak na telefonie wysyłającym.',
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: Palette.mgla)),
          const Spacer(),
          FilledButton(onPressed: () => _save(t), child: const Text('Zapisz koncert')),
        ]),
      ),
    );
  }
}
