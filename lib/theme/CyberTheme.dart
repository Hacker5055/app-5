// CyberTheme.dart
//
// "Cyber Obsidian & Neon Teal": #0B0D12 canvas, glass surfaces, #14B8A6 neon teal
// primary, #F59E0B security amber. Every colour used by the UI lives here.

import 'dart:ui';

import 'package:flutter/material.dart';

class CyberColors {
  const CyberColors._();

  static const Color obsidian = Color(0xFF0B0D12);
  static const Color obsidianDeep = Color(0xFF06080C);
  static const Color surface = Color(0xFF12161D);
  static const Color surfaceHi = Color(0xFF171C25);
  static const Color glass = Color(0x14FFFFFF);
  static const Color glassStrong = Color(0x1FFFFFFF);
  static const Color stroke = Color(0x16FFFFFF);
  static const Color strokeStrong = Color(0x29FFFFFF);

  static const Color teal = Color(0xFF14B8A6);
  static const Color tealBright = Color(0xFF2DD4BF);
  static const Color tealDeep = Color(0xFF0F766E);
  static const Color amber = Color(0xFFF59E0B);
  static const Color amberSoft = Color(0xFFFBBF24);
  static const Color rose = Color(0xFFFB7185);
  static const Color violet = Color(0xFFA78BFA);
  static const Color blue = Color(0xFF60A5FA);

  static const Color text = Color(0xFFE9EEF3);
  static const Color textMuted = Color(0xFF8B98A7);
  static const Color textDim = Color(0xFF5F6B79);

  static const Map<String, Color> metaGroup = <String, Color>{
    'GPS': amber,
    'XMP': violet,
    'IPTC': blue,
    'COMMENT': rose,
    'Exif': tealBright,
    'IFD0': Color(0xFFCBD5E1),
    'IFD1': Color(0xFF94A3B8),
    'PNG': Color(0xFFFCD34D),
    'JFIF': textMuted,
    'ICC': textMuted,
    'MPF': amberSoft,
  };

  static Color forGroup(String group) => metaGroup[group] ?? textMuted;
}

class CyberTypography {
  const CyberTypography._();

  static const String mono = 'monospace';

  static const TextStyle label = TextStyle(
    fontSize: 10,
    letterSpacing: 0.9,
    fontWeight: FontWeight.w600,
    color: CyberColors.textMuted,
    fontFamily: mono,
  );

  static const TextStyle data = TextStyle(
    fontSize: 11,
    height: 1.4,
    fontFamily: mono,
    color: Color(0xFFC3CDD7),
  );

  static const TextStyle title = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    color: CyberColors.text,
  );

  static const TextStyle sectionLabel = TextStyle(
    fontSize: 11,
    letterSpacing: 1.1,
    fontWeight: FontWeight.w700,
    color: Color(0xFFCFD8E1),
  );
}

class CyberTheme {
  const CyberTheme._();

  static const double radius = 20;
  static const double radiusSmall = 12;

  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: CyberColors.teal,
      onPrimary: Color(0xFF04211D),
      secondary: CyberColors.amber,
      onSecondary: Color(0xFF231703),
      surface: CyberColors.obsidian,
      onSurface: CyberColors.text,
      error: CyberColors.rose,
      onError: Color(0xFF2A0910),
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: CyberColors.obsidian,
      canvasColor: CyberColors.obsidian,
      fontFamily: 'Roboto',
      splashFactory: InkSparkle.splashFactory,
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: CyberColors.text,
        displayColor: CyberColors.text,
      ),
      dividerTheme: const DividerThemeData(color: CyberColors.stroke, thickness: 1, space: 1),
      iconTheme: const IconThemeData(color: CyberColors.textMuted, size: 20),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: CyberColors.surfaceHi,
        contentTextStyle: const TextStyle(color: CyberColors.text, fontSize: 13),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSmall)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: CyberColors.obsidianDeep,
        hintStyle: const TextStyle(color: CyberColors.textDim, fontSize: 13),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: const BorderSide(color: CyberColors.stroke),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: const BorderSide(color: CyberColors.stroke),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: const BorderSide(color: CyberColors.teal, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: CyberColors.teal,
          foregroundColor: const Color(0xFF04211D),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSmall)),
          textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, letterSpacing: 0.1),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: CyberColors.tealBright,
          side: const BorderSide(color: Color(0x5C14B8A6)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSmall)),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: CyberColors.tealBright),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? CyberColors.tealBright : CyberColors.textMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? CyberColors.teal.withValues(alpha: 0.32)
              : const Color(0x14FFFFFF),
        ),
        trackOutlineColor: WidgetStateProperty.all(CyberColors.stroke),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: CyberColors.teal,
        inactiveTrackColor: Color(0x1FFFFFFF),
        thumbColor: CyberColors.tealBright,
        overlayColor: Color(0x2214B8A6),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: CyberColors.teal,
        linearTrackColor: Color(0x14FFFFFF),
      ),
    );
  }

  /// Frosted-glass surface used by every card in the app.
  static BoxDecoration glassDecoration({double radius = radius, Color? tint, bool strong = false}) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          (tint ?? Colors.white).withValues(alpha: strong ? 0.085 : 0.055),
          (tint ?? Colors.white).withValues(alpha: 0.018),
        ],
      ),
      border: Border.all(color: strong ? CyberColors.strokeStrong : CyberColors.stroke),
      boxShadow: const <BoxShadow>[
        BoxShadow(color: Color(0xE6000000), blurRadius: 40, offset: Offset(0, 18), spreadRadius: -22),
      ],
    );
  }

  static LinearGradient get tealGlow => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[CyberColors.tealBright, Color(0xFF0F9C8D), Color(0xFF0D7D74)],
      );

  static ImageFilter get blur => ImageFilter.blur(sigmaX: 22, sigmaY: 22);
}
