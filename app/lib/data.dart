import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// El catálogo vive en el repo. La app usa la última copia descargada y,
/// si no hay, la que viene dentro del APK.
const catalogUrl = 'https://raw.githubusercontent.com/xNeku/achievements-ty/main/data/juegos.json';

const tipoLabel = {'recomp': 'Recomp', 'decomp': 'Decomp', 'source-port': 'Source port', 'emulator': 'Emulador'};

class Repo {
  final String repo, url, tipo;
  const Repo(this.repo, this.url, this.tipo);
  String get owner => repo.split('/').first;
  String get name => repo.split('/').last;
}

class Arte {
  final String? portada, portadaThumb, hero, heroThumb, logo, logoThumb;
  const Arte({this.portada, this.portadaThumb, this.hero, this.heroThumb, this.logo, this.logoThumb});
  factory Arte.fromJson(Map<String, dynamic> j) => Arte(
        portada: j['portada'],
        portadaThumb: j['portada_thumb'],
        hero: j['hero'],
        heroThumb: j['hero_thumb'],
        logo: j['logo'],
        logoThumb: j['logo_thumb'],
      );
}

class Juego {
  final String id, nombre, confianza;
  final List<String> proyectos, tipos, notas;
  final List<Repo> repos;
  final Arte? arte;
  const Juego({
    required this.id,
    required this.nombre,
    required this.confianza,
    required this.proyectos,
    required this.tipos,
    required this.notas,
    required this.repos,
    this.arte,
  });

  factory Juego.fromJson(Map<String, dynamic> j) {
    List<String> strs(Object? v) => (v as List? ?? const []).map((e) => '$e').toList();
    return Juego(
      id: '${j['id']}',
      nombre: '${j['nombre']}',
      confianza: '${j['confianza_nombre'] ?? 'original'}',
      proyectos: strs(j['proyectos']),
      tipos: strs(j['tipos']),
      notas: strs(j['notas']),
      repos: (j['repos'] as List? ?? const [])
          .map((r) => Repo('${r['repo']}', '${r['url'] ?? 'https://github.com/${r['repo']}'}', '${r['tipo'] ?? ''}'))
          .toList(),
      arte: j['arte'] is Map<String, dynamic> ? Arte.fromJson(j['arte']) : null,
    );
  }

  String? get cover => arte?.portadaThumb ?? arte?.portada;
  String? get coverFull => arte?.portada ?? arte?.portadaThumb;
  String? get hero => arte?.hero ?? arte?.heroThumb;
  String? get heroSmall => arte?.heroThumb ?? arte?.hero;
  String? get logo => arte?.logo ?? arte?.logoThumb;
  bool get hasHero => hero != null;
  bool get dudoso => confianza == 'baja';
  String get tiposTexto => tipos.map((t) => tipoLabel[t] ?? t).join(' · ');
  String get subtitulo => proyectos.where((p) => p.toLowerCase() != nombre.toLowerCase()).join(' · ');
}

class Catalogo {
  final List<Juego> juegos;
  final String fuente;
  final DateTime? actualizado;
  const Catalogo(this.juegos, this.fuente, this.actualizado);

  static List<Juego> parse(String raw) {
    final j = jsonDecode(raw);
    final list = (j is Map ? j['juegos'] : j) as List;
    final out = list.map((e) => Juego.fromJson(e as Map<String, dynamic>)).toList();
    out.sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
    return out;
  }
}

class CatalogStore extends ChangeNotifier {
  Catalogo catalogo = const Catalogo([], 'vacío', null);
  bool cargando = false;
  String? error;

  static const _kRaw = 'catalogo_raw', _kWhen = 'catalogo_when';

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_kRaw);
    if (cached != null) {
      try {
        catalogo = Catalogo(Catalogo.parse(cached), 'GitHub', DateTime.tryParse(prefs.getString(_kWhen) ?? ''));
      } catch (_) {}
    }
    if (catalogo.juegos.isEmpty) {
      final raw = await rootBundle.loadString('assets/juegos.json');
      catalogo = Catalogo(Catalogo.parse(raw), 'integrado', null);
    }
    notifyListeners();
    refresh();
  }

  Future<void> refresh() async {
    if (cargando) return;
    cargando = true;
    error = null;
    notifyListeners();
    try {
      final r = await http.get(Uri.parse(catalogUrl)).timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) throw 'HTTP ${r.statusCode}';
      final body = utf8.decode(r.bodyBytes);
      final juegos = Catalogo.parse(body);
      if (juegos.isEmpty) throw 'catálogo vacío';
      final now = DateTime.now();
      catalogo = Catalogo(juegos, 'GitHub', now);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kRaw, body);
      await prefs.setString(_kWhen, now.toIso8601String());
    } catch (e) {
      error = '$e';
    } finally {
      cargando = false;
      notifyListeners();
    }
  }
}

/// Ajustes sencillos guardados en el dispositivo.
class Ajustes extends ChangeNotifier {
  bool vibracion = true, chispas = true;
  SharedPreferences? _p;

  Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    vibracion = _p!.getBool('vib') ?? true;
    chispas = _p!.getBool('fx') ?? true;
    notifyListeners();
  }

  void set({bool? vib, bool? fx}) {
    if (vib != null) _p?.setBool('vib', vibracion = vib);
    if (fx != null) _p?.setBool('fx', chispas = fx);
    notifyListeners();
  }
}
