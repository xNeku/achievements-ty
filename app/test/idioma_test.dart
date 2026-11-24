import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hangar/en.dart';
import 'package:hangar/idioma.dart';

void main() {
  test('cada texto de la app tiene traducción al inglés', () {
    final faltan = <String>{};
    // t('…') de una sola línea; los textos partidos en varias líneas los revisa la herramienta de i18n.
    final re = RegExp(r"(?<![\w.])t\('((?:[^'\\]|\\.)*)'[,)]");
    for (final f in Directory('lib').listSync().whereType<File>().where((f) => f.path.endsWith('.dart') && !f.path.endsWith('en.dart'))) {
      for (final m in re.allMatches(f.readAsStringSync())) {
        final clave = m.group(1)!.replaceAll(r"\'", "'").replaceAll(r'\$', r'$');
        if (!en.containsKey(clave)) faltan.add('${f.path}: $clave');
      }
    }
    expect(faltan, isEmpty);
  });

  test('t() cambia de idioma y rellena los huecos', () {
    idioma.codigo = 'es';
    expect(t('Hace {0} días', [3]), 'Hace 3 días');
    idioma.codigo = 'en';
    expect(t('Hace {0} días', [3]), '3 days ago');
    expect(t('Un texto sin traducir'), 'Un texto sin traducir');
    idioma.codigo = 'es';
  });
}
