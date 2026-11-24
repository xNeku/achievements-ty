import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'installer.dart';
import 'idioma.dart';

/// Un logro de Hangar: se gana usando la app, en cualquier juego.
class Hito {
  final String id, titulo, texto;
  final IconData icon;
  final Color color;
  final int meta;
  final int Function(Installer ins, Perfil p) valor;
  const Hito(this.id, this.titulo, this.texto, this.icon, this.color, this.meta, this.valor);
  bool hecho(Installer ins, Perfil p) => valor(ins, p) >= meta;
  double progreso(Installer ins, Perfil p) => (valor(ins, p) / meta).clamp(0, 1).toDouble();
}

const _bronce = Color(0xFFB9886A), _plata = Color(0xFFB9B2B6), _oro = Color(0xFFE9B949), _brasa = Color(0xFFE8463B);

List<Hito> get hitos => <Hito>[
  Hito('despegue', t('Primer despegue'), t('Instala tu primer port.'), Icons.flight_takeoff_rounded, _bronce, 1, (i, _) => i.instalacionesTotales),
  Hito('partida', t('Primera partida'), t('Abre un juego desde Hangar.'), Icons.play_arrow_rounded, _bronce, 1, (i, _) => i.sesionesTotales),
  Hito('nombre', t('Con nombre propio'), t('Ponle nombre a tu perfil.'), Icons.badge_outlined, _bronce, 1, (_, p) => p.nombre.isEmpty ? 0 : 1),
  Hito('explorador', t('Explorador'), t('Abre 25 juegos del catálogo.'), Icons.travel_explore_rounded, _bronce, 25, (_, p) => p.vistos.length),
  Hito('hora', t('Calentando motores'), t('Juega una hora en total.'), Icons.local_fire_department_outlined, _plata, 3600, (i, _) => i.segundosTotales),
  Hito('picoteo', t('Picoteo'), t('Juega a tres juegos distintos.'), Icons.grid_view_rounded, _plata, 3, (i, _) => i.juegosJugados),
  Hito('constante', t('Constante'), t('Abre juegos desde Hangar diez veces.'), Icons.repeat_rounded, _plata, 10, (i, _) => i.sesionesTotales),
  Hito('lleno', t('Hangar lleno'), t('Ten cinco ports instalados a la vez.'), Icons.warehouse_outlined, _plata, 5, (i, _) => i.instaladosAhora),
  Hito('biblioteca', t('Rata de biblioteca'), t('Abre 100 juegos del catálogo.'), Icons.menu_book_rounded, _oro, 100, (_, p) => p.vistos.length),
  Hito('veterano', t('Piloto veterano'), t('Juega diez horas en total.'), Icons.military_tech_outlined, _oro, 36000, (i, _) => i.segundosTotales),
  Hito('coleccion', t('Coleccionista'), t('Instala diez ports distintos.'), Icons.collections_bookmark_outlined, _oro, 10, (i, _) => i.instalacionesTotales),
  Hito('leyenda', t('Leyenda del hangar'), t('Juega cincuenta horas en total.'), Icons.workspace_premium_outlined, _brasa, 180000, (i, _) => i.segundosTotales),
];

/// Tu perfil local: nombre, juegos que has mirado y logros de Hangar ganados (con fecha).
class Perfil extends ChangeNotifier {
  String nombre = '';
  final Set<String> vistos = {};
  final Map<String, DateTime> ganados = {};
  SharedPreferences? _p;

  String get inicial => nombre.trim().isEmpty ? 'T' : nombre.trim().characters.first.toUpperCase();

  Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    nombre = _p!.getString('perfil_nombre') ?? '';
    vistos.addAll(_p!.getStringList('perfil_vistos') ?? const []);
    final raw = _p!.getString('perfil_logros');
    if (raw != null) {
      (jsonDecode(raw) as Map<String, dynamic>).forEach((k, v) {
        final d = DateTime.tryParse('$v');
        if (d != null) ganados[k] = d;
      });
    }
  }

  void setNombre(String n) {
    nombre = n.trim();
    _p?.setString('perfil_nombre', nombre);
    notifyListeners();
  }

  void ver(String id) {
    if (vistos.add(id)) {
      _p?.setStringList('perfil_vistos', vistos.toList());
      notifyListeners();
    }
  }

  /// Apunta los logros recién conseguidos y los devuelve para avisar.
  List<Hito> revisar(Installer ins) {
    final nuevos = [
      for (final h in hitos)
        if (!ganados.containsKey(h.id) && h.hecho(ins, this)) h,
    ];
    if (nuevos.isEmpty) return const [];
    for (final h in nuevos) {
      ganados[h.id] = DateTime.now();
    }
    _p?.setString('perfil_logros', jsonEncode(ganados.map((k, v) => MapEntry(k, v.toIso8601String()))));
    return nuevos;
  }
}
