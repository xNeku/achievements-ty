import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// El catálogo vive en el repo, uno por sistema. La app usa la última copia descargada y,
/// si no hay, la que viene dentro de la app.
String catalogUrl(String file) => 'https://raw.githubusercontent.com/xNeku/achievements-ty/main/data/$file';

const tipoLabel = {'recomp': 'Recomp', 'decomp': 'Decomp', 'source-port': 'Source port', 'emulator': 'Emulador'};

/// Cómo se instala y arranca un port en el Mac (sale del catálogo de RecompLauncher).
class MacInfo {
  final String? tag, asset, file, sha256, version, size, necesita, aviso, juegoTipo, juegoTexto;
  final List<String> pasos, programa, args;
  const MacInfo({
    this.tag,
    this.asset,
    this.file,
    this.sha256,
    this.version,
    this.size,
    this.necesita,
    this.aviso,
    this.juegoTipo,
    this.juegoTexto,
    this.pasos = const [],
    this.programa = const [],
    this.args = const [],
  });

  factory MacInfo.fromJson(Map<String, dynamic> j) {
    List<String> strs(Object? v) => (v as List? ?? const []).map((e) => '$e').toList();
    final juego = j['juego'] as Map<String, dynamic>?;
    return MacInfo(
      tag: j['tag'],
      asset: j['asset'],
      file: j['file'],
      sha256: j['sha256'],
      version: j['version'],
      size: j['size'],
      necesita: j['necesita'],
      aviso: j['aviso'],
      juegoTipo: juego?['tipo'],
      juegoTexto: juego?['texto'],
      pasos: strs(j['pasos']),
      programa: strs(j['programa']),
      args: strs(j['args']),
    );
  }

  /// El port necesita que le pasemos la copia del juego al arrancar.
  bool get pideCopia => args.any((a) => a.contains('{game}'));
}

class Repo {
  final String repo, url, tipo;
  final MacInfo? mac;
  const Repo(this.repo, this.url, this.tipo, {this.mac});
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
  final String id, nombre, confianza, descripcion;
  final int orden;
  final List<String> proyectos, tipos, notas;
  final List<Repo> repos;
  final Arte? arte;
  const Juego({
    required this.id,
    required this.nombre,
    required this.confianza,
    this.descripcion = '',
    this.orden = 9999,
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
      descripcion: '${j['descripcion'] ?? ''}',
      orden: (j['orden'] as num?)?.toInt() ?? 9999,
      proyectos: strs(j['proyectos']),
      tipos: strs(j['tipos']),
      notas: strs(j['notas']),
      repos: (j['repos'] as List? ?? const [])
          .map((r) => Repo('${r['repo']}', '${r['url'] ?? 'https://github.com/${r['repo']}'}', '${r['tipo'] ?? ''}',
              mac: r['mac'] is Map<String, dynamic> ? MacInfo.fromJson(r['mac']) : null))
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
  /// `juegos.json` (Android) o `juegos-mac.json` (Mac).
  final String file;
  CatalogStore(this.file);
  Catalogo catalogo = const Catalogo([], 'vacío', null);
  bool cargando = false;
  String? error;

  String get _kRaw => 'catalogo_raw_$file';
  String get _kWhen => 'catalogo_when_$file';

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_kRaw);
    if (cached != null) {
      try {
        catalogo = Catalogo(Catalogo.parse(cached), 'GitHub', DateTime.tryParse(prefs.getString(_kWhen) ?? ''));
      } catch (_) {}
    }
    if (catalogo.juegos.isEmpty) {
      final raw = await rootBundle.loadString('assets/$file');
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
      final r = await http.get(Uri.parse(catalogUrl(file))).timeout(const Duration(seconds: 12));
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
