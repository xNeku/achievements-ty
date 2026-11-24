import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';

/// Paleta: pared oscura, tarjeta casi negra, tinta cálida y un acento brasa.
abstract final class C {
  static const wall = Color(0xFF0A0809);
  static const card = Color(0xFF120E11);
  static const panel = Color(0xFF1A1418);
  static const ink = Color(0xFFF4EFF1);
  static const ink2 = Color(0x9EF4EFF1); // 62 %
  static const ink3 = Color(0x6BF4EFF1); // 42 %
  static const line = Color(0x14FFFFFF);
  static const glass = Color(0x1AFFFFFF);
  static const glass2 = Color(0x2EFFFFFF);
  static const acc = Color(0xFFE8463B);
  static const pink = Color(0xFFF2507F);
  static const ok = Color(0xFF44D27A);
}

abstract final class T {
  static TextStyle sans({double size = 15, FontWeight w = FontWeight.w400, Color color = C.ink, double? spacing, double? height}) =>
      GoogleFonts.sora(fontSize: size, fontWeight: w, color: color, letterSpacing: spacing, height: height);

  static TextStyle serif({double size = 44, FontWeight w = FontWeight.w500, Color color = C.ink, FontStyle? style, double height = 1}) =>
      GoogleFonts.cormorantGaramond(fontSize: size, fontWeight: w, color: color, fontStyle: style, height: height);

  /// Etiqueta pequeña en mayúsculas, espaciada.
  static TextStyle label({double size = 11, Color color = C.ink3, FontWeight w = FontWeight.w500}) =>
      GoogleFonts.sora(fontSize: size, fontWeight: w, color: color, letterSpacing: size * .18, height: 1.3);
}

ThemeData buildTheme() {
  final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: C.wall,
    colorScheme: base.colorScheme.copyWith(primary: C.acc, secondary: C.pink, surface: C.card),
    textTheme: GoogleFonts.soraTextTheme(base.textTheme).apply(bodyColor: C.ink, displayColor: C.ink),
    splashFactory: InkSparkle.splashFactory,
    textSelectionTheme: const TextSelectionThemeData(cursorColor: C.pink, selectionColor: Color(0x55F2507F)),
  );
}

/// Color estable a partir de un texto, para portadas sin arte.
Color hueOf(String s, {double s1 = .42, double l = .30}) {
  var h = 7;
  for (final c in s.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return HSLColor.fromAHSL(1, (h % 360).toDouble(), s1, l).toColor();
}
