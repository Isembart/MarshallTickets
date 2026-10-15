import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../db.dart';
import '../main.dart';
import '../theme.dart';

/// How long a verdict stays full-colour. After that it moves to the log so an
/// old green can't be mistaken for the person now at the door.
const _freshFor = Duration(seconds: 4);

class ScannerScreen extends StatefulWidget {
  final Concert concert;
  const ScannerScreen({super.key, required this.concert});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final _controller = MobileScannerController(formats: const [
    BarcodeFormat.qrCode,
    BarcodeFormat.ean13,
    BarcodeFormat.ean8,
    BarcodeFormat.upcA,
    BarcodeFormat.code128,
    BarcodeFormat.code39,
  ]);
  final _log = <(DateTime, ScanResult)>[]; // newest first
  late int _scanned = widget.concert.scanned;
  bool _fresh = false;
  Timer? _fade;
  String? _lastCode;
  DateTime _lastAt = DateTime(0);
  bool _busy = false;

  @override
  void dispose() {
    _fade?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _check(String code) async {
    code = code.trim();
    if (code.isEmpty || _busy) return;
    // The camera reports the same code many times per second; ignore repeats for 2 s.
    if (code == _lastCode && DateTime.now().difference(_lastAt) < const Duration(seconds: 2)) return;
    _busy = true;
    final result = await db.scan(widget.concert.id, code);
    _lastCode = code;
    _lastAt = DateTime.now();
    _busy = false;
    result.status == ScanStatus.valid ? HapticFeedback.mediumImpact() : HapticFeedback.heavyImpact();
    if (!mounted) return;
    setState(() {
      _log.insert(0, (DateTime.now(), result));
      if (_log.length > 20) _log.removeLast();
      if (result.status == ScanStatus.valid) _scanned++;
      _fresh = true;
    });
    _fade?.cancel();
    _fade = Timer(_freshFor, _settle);
  }

  void _settle() {
    _fade?.cancel();
    if (mounted) setState(() => _fresh = false);
  }

  Future<void> _manual() async {
    final text = TextEditingController();
    final code = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (c) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(c).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Wpisz kod biletu', style: Theme.of(c).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: text,
            autofocus: true,
            style: mono(16),
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(hintText: 'np. 7916061048'),
            onSubmitted: (v) => Navigator.pop(c, v),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: () => Navigator.pop(c, text.text), child: const Text('Sprawdź kod')),
        ]),
      ),
    );
    if (code == null) return;
    _lastCode = null; // manual entry always checks, even right after the same camera read
    await _check(code);
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final latest = _log.firstOrNull;
    return Scaffold(
      backgroundColor: Palette.scena,
      body: Column(children: [
        SafeArea(
          bottom: false,
          child: SizedBox(
            height: 56,
            child: Row(children: [
              IconButton(
                  tooltip: 'Zamknij skaner', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
              Expanded(
                child: Text(widget.concert.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
              ),
              Semantics(
                label: 'Wpuszczono $_scanned z ${widget.concert.total}',
                child: Text('$_scanned / ${widget.concert.total}',
                    style: archivo(17, 700, width: 110, color: Palette.kreda)
                        .copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
              ),
              IconButton(onPressed: _controller.toggleTorch, icon: const Icon(Icons.flashlight_on), tooltip: 'Latarka'),
            ]),
          ),
        ),
        Expanded(
          child: Stack(fit: StackFit.expand, children: [
            MobileScanner(
              controller: _controller,
              onDetect: (capture) {
                final code = capture.barcodes.firstOrNull?.rawValue;
                if (code != null) _check(code);
              },
              errorBuilder: (context, error) => ColoredBox(
                color: Palette.scena,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Aparat jest niedostępny (${error.errorCode.name}). '
                      'Sprawdź uprawnienia aparatu albo wpisz kod ręcznie.',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                ),
              ),
            ),
            // Aiming corners only; detection covers the whole preview.
            const IgnorePointer(
              child: Center(
                child: FractionallySizedBox(
                  widthFactor: 0.66,
                  child: AspectRatio(aspectRatio: 1, child: CustomPaint(painter: _Corners())),
                ),
              ),
            ),
          ]),
        ),
        AnimatedSize(
          duration: still ? Duration.zero : const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _fresh && latest != null
              ? _Verdict(key: ObjectKey(latest), at: latest.$1, result: latest.$2, still: still, onDismiss: _settle)
              : _Idle(log: _log, onManual: _manual),
        ),
      ]),
    );
  }
}

class _Corners extends CustomPainter {
  const _Corners();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Palette.kreda
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const l = 28.0;
    final w = size.width, h = size.height;
    for (final (o, dx, dy) in [
      (Offset.zero, 1.0, 1.0),
      (Offset(w, 0), -1.0, 1.0),
      (Offset(0, h), 1.0, -1.0),
      (Offset(w, h), -1.0, -1.0),
    ]) {
      canvas.drawLine(o, o + Offset(l * dx, 0), p);
      canvas.drawLine(o, o + Offset(0, l * dy), p);
    }
  }

  @override
  bool shouldRepaint(_Corners old) => false;
}

(Color, String, String?) _describe(ScanResult r) => switch (r.status) {
      ScanStatus.valid => (Palette.wpusc, 'Wpuść', 'Bilet poprawny'),
      ScanStatus.alreadyScanned => (
          Palette.juz,
          'Już zeskanowany',
          r.scannedAt == null ? null : 'Pierwszy skan o ${formatTime(r.scannedAt!)}, ${formatDate(r.scannedAt!)}'
        ),
      ScanStatus.invalid => (
          Palette.stop,
          'Nie wpuszczaj',
          r.otherConcert == null ? 'Tego kodu nie ma na liście' : 'Bilet na inny koncert: ${r.otherConcert}'
        ),
    };

/// The one loud element: a flood of the signal colour with a single instruction.
/// The shrinking line at the bottom shows how long the verdict stays current.
class _Verdict extends StatelessWidget {
  final DateTime at;
  final ScanResult result;
  final bool still;
  final VoidCallback onDismiss;
  const _Verdict({super.key, required this.at, required this.result, required this.still, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final (color, headline, detail) = _describe(result);
    const ink = Palette.scena;
    return GestureDetector(
      onTap: onDismiss,
      child: Container(
        color: color,
        width: double.infinity,
        constraints: BoxConstraints(minHeight: MediaQuery.sizeOf(context).height * 0.4),
        child: SafeArea(
          top: false,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Semantics(
                  liveRegion: true,
                  child: TweenAnimationBuilder(
                    tween: Tween(begin: still ? 1.0 : 0.88, end: 1.0),
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutBack,
                    builder: (context, s, child) =>
                        Transform.scale(scale: s, alignment: Alignment.centerLeft, child: child),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(headline, style: archivo(64, 850, width: 125, height: 1.0, color: ink)),
                    ),
                  ),
                ),
                if (detail != null) ...[
                  const SizedBox(height: 10),
                  Text(detail, style: archivo(19, 600, color: ink)),
                ],
                const SizedBox(height: 14),
                Text(result.code,
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: mono(13, color: ink.withValues(alpha: 0.7))),
              ]),
            ),
            if (!still)
              TweenAnimationBuilder(
                tween: Tween(begin: 1.0, end: 0.0),
                duration: _freshFor,
                builder: (context, v, _) => FractionallySizedBox(
                  widthFactor: v,
                  child: Container(height: 4, color: ink.withValues(alpha: 0.35)),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Calm state between people: what to do now, and the last few verdicts for reference.
class _Idle extends StatelessWidget {
  final List<(DateTime, ScanResult)> log;
  final VoidCallback onManual;
  const _Idle({required this.log, required this.onManual});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Palette.scena,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Skieruj aparat na kod biletu', style: archivo(18, 600, width: 105, color: Palette.kreda)),
            const SizedBox(height: 12),
            for (final (at, r) in log.take(3)) _LogRow(at: at, result: r),
            if (log.isNotEmpty) const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Palette.kreda,
                side: const BorderSide(color: Palette.kulisyHi),
                minimumSize: const Size(64, 52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                textStyle: archivo(16, 650, width: 105),
              ),
              onPressed: onManual,
              icon: const Icon(Icons.keyboard),
              label: const Text('Wpisz kod ręcznie'),
            ),
          ]),
        ),
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  final DateTime at;
  final ScanResult result;
  const _LogRow({required this.at, required this.result});

  @override
  Widget build(BuildContext context) {
    final (color, headline, _) = _describe(result);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Container(width: 4, height: 34, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(headline, style: archivo(15, 650, color: color)),
            Text(result.code,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: mono(12, color: Palette.mgla)),
          ]),
        ),
        Text(formatTime(at),
            style: archivo(13, 500, color: Palette.mgla).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
      ]),
    );
  }
}
