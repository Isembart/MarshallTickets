import 'package:flutter/material.dart';

/// Plain black UI. Colour is reserved for verdicts and scanned state;
/// everything tappable is white.
abstract final class Palette {
  static const scena = Color(0xFF000000); // background
  static const kulisy = Color(0xFF1C1C1E); // surfaces
  static const kulisyHi = Color(0xFF2C2C2E); // raised surfaces, dividers, empty dots
  static const kreda = Color(0xFFF2F2F2); // text, primary actions
  static const mgla = Color(0xFF8E8E93); // secondary text
  static const wpusc = Color(0xFF2BD47D); // valid / scanned
  static const juz = Color(0xFFFFB547); // already scanned
  static const stop = Color(0xFFFF5A5F); // invalid
}

/// Archivo is a variable font: weight and width go through font variations so
/// they render the real instance instead of a synthesised bold.
TextStyle archivo(double size, double weight, {double width = 100, double height = 1.3, Color? color}) => TextStyle(
      fontFamily: 'Archivo',
      fontSize: size,
      height: height,
      color: color,
      fontWeight: FontWeight.values[((weight / 100).round() - 1).clamp(0, 8)],
      fontVariations: [FontVariation('wght', weight), FontVariation('wdth', width)],
    );

/// Ticket Codes: compared character by character, so a mono face with a clear 0/O.
TextStyle mono(double size, {Color? color, double weight = 450}) => TextStyle(
      fontFamily: 'RedHatMono',
      fontSize: size,
      height: 1.3,
      color: color,
      fontVariations: [FontVariation('wght', weight)],
    );

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    surface: Palette.scena,
    onSurface: Palette.kreda,
    onSurfaceVariant: Palette.mgla,
    surfaceContainerHigh: Palette.kulisy,
    surfaceContainerHighest: Palette.kulisyHi,
    primary: Palette.kreda,
    onPrimary: Palette.scena,
    secondaryContainer: Palette.kulisyHi,
    onSecondaryContainer: Palette.kreda,
    error: Palette.stop,
    outline: Palette.kulisyHi,
    outlineVariant: Palette.kulisyHi,
  );
  final text = TextTheme(
    headlineSmall: archivo(26, 700, width: 112, height: 1.15),
    titleLarge: archivo(21, 650, width: 108, height: 1.2),
    titleMedium: archivo(17, 600),
    bodyLarge: archivo(16, 400, height: 1.4),
    bodyMedium: archivo(14, 400, height: 1.4),
    bodySmall: archivo(13, 400),
    labelLarge: archivo(15, 600),
  ).apply(bodyColor: Palette.kreda, displayColor: Palette.kreda);

  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: Palette.scena,
    fontFamily: 'Archivo',
    textTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: Palette.scena,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: text.titleLarge,
      centerTitle: false,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Palette.kulisy,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: text.titleLarge,
      contentTextStyle: text.bodyLarge!.copyWith(color: Palette.kreda),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: archivo(16, 650, width: 105),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(textStyle: text.labelLarge)),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Palette.kulisy,
      hintStyle: text.bodyLarge!.copyWith(color: Palette.mgla),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Palette.kreda, width: 2),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Palette.kreda,
      contentTextStyle: text.bodyLarge!.copyWith(color: Palette.scena),
      behavior: SnackBarBehavior.floating,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: Palette.kreda),
    popupMenuTheme: PopupMenuThemeData(color: Palette.kulisyHi, textStyle: text.bodyLarge),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Palette.kulisy,
      showDragHandle: true,
      dragHandleColor: Palette.kulisyHi,
    ),
    datePickerTheme: const DatePickerThemeData(backgroundColor: Palette.kulisy),
  );
}

/// Thin progress bar shared by the concert stub and the ticket list header.
class ScanProgress extends StatelessWidget {
  final int scanned, total;
  final double height;
  const ScanProgress({super.key, required this.scanned, required this.total, this.height = 6});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: LinearProgressIndicator(
          value: total == 0 ? 0 : scanned / total,
          minHeight: height,
          color: Palette.wpusc,
          backgroundColor: Palette.kreda.withValues(alpha: 0.12), // visible on black and on raised stubs
        ),
      );
}
