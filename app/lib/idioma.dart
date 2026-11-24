import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'en.dart';

/// Idioma de la app: castellano o inglés. La primera vez sigue al del sistema.
class Idioma extends ChangeNotifier {
  String codigo = 'es';
  SharedPreferences? _p;

  bool get ingles => codigo == 'en';

  Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    codigo = _p!.getString('idioma') ?? (PlatformDispatcher.instance.locale.languageCode == 'es' ? 'es' : 'en');
  }

  void poner(String c) {
    if (c == codigo) return;
    codigo = c;
    _p?.setString('idioma', c);
    notifyListeners();
  }

  void alternar() => poner(ingles ? 'es' : 'en');
}

final idioma = Idioma();

/// Traduce un texto escrito en castellano. `{0}`, `{1}`… se cambian por [a].
String t(String es, [List<Object?> a = const []]) {
  var s = idioma.ingles ? (en[es] ?? es) : es;
  for (var i = 0; i < a.length; i++) {
    s = s.replaceAll('{$i}', '${a[i]}');
  }
  return s;
}
