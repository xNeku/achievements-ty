import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// El catálogo vive en el repo, uno por sistema. La app usa la última copia descargada y,
/// si no hay, la que viene dentro de la app.
/// Primero el de `main`; si aún no está, el de la última build publicada.
List<String> catalogUrls(String file) => [
  'https://raw.githubusercontent.com/xNeku/achievements-ty/main/data/$file',
  'https://github.com/xNeku/achievements-ty/releases/latest/download/$file',
];

/// Este dispositivo usa el catálogo de Mac (si no, el de Android).
bool catalogoMac = false;

const fuenteLabel = {
  'xbox360': 'Xbox 360',
  'xboxone': 'Xbox One',
  'retroachievements': 'RetroAchievements',
  'steam': 'Steam',
  'psn': 'PlayStation',
  'hangar': 'Hangar',
};

const tipoLabel = {'recomp': 'Recomp', 'decomp': 'Decomp', 'source-port': 'Source port', 'emulator': 'Emulador'};

/// Cómo se instala y arranca un port en el Mac (sale del catálogo de RecompLauncher).
class MacInfo {
  final String? tag, asset, file, sha256, version, size, necesita, aviso, juegoTipo, juegoTexto, url;
  final List<String> pasos, programa, args, ids;

  /// Volcados válidos de la ROM: tamaño en bytes y CRC32 en hexadecimal.
  final List<({String name, int size, String crc32})> dumps;
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
    this.url,
    this.ids = const [],
    this.dumps = const [],
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
      url: j['url'],
      ids: strs((j['check'] as Map?)?['ids']),
      dumps: [
        for (final d in ((j['check'] as Map?)?['dumps'] as List? ?? const []))
          (name: '${d['name'] ?? ''}', size: (d['size'] as num?)?.toInt() ?? 0, crc32: '${d['crc32'] ?? ''}'.toUpperCase()),
      ],
      pasos: strs(j['pasos']),
      programa: strs(j['programa']),
      args: strs(j['args']),
    );
  }

  /// El port necesita que le pasemos la copia del juego al arrancar.
  bool get pideCopia => args.any((a) => a.contains('{game}'));
}

/// El APK que publica un port de Android (lo encuentra el revisor del catálogo en GitHub).
class AndroidInfo {
  final String tag, apk, url;
  final int size;
  final bool pre;
  const AndroidInfo({required this.tag, required this.apk, required this.url, this.size = 0, this.pre = false});
  factory AndroidInfo.fromJson(Map<String, dynamic> j) =>
      AndroidInfo(tag: '${j['tag']}', apk: '${j['apk']}', url: '${j['url']}', size: (j['size'] as num?)?.toInt() ?? 0, pre: j['pre'] == true);
  String get tamano => size <= 0
      ? ''
      : size > 1e9
      ? '${(size / 1e9).toStringAsFixed(1)} GB'
      : '${(size / 1e6).round()} MB';
}

class Repo {
  final String repo, url, tipo;
  final MacInfo? mac;
  final AndroidInfo? android;
  final List<String> requisitos;
  final bool archivado;
  final String? estado;
  const Repo(this.repo, this.url, this.tipo, {this.mac, this.android, this.requisitos = const [], this.archivado = false, this.estado});
  String get owner => repo.split('/').first;
  String get name => repo.split('/').last;

  /// Se puede instalar desde Hangar en este dispositivo.
  bool get listo => catalogoMac ? mac?.asset != null : android != null;

  /// Versión que ofrece el catálogo para este dispositivo.
  String? get version => catalogoMac ? (mac?.tag ?? mac?.version) : android?.tag;

  /// Aviso de mantenimiento, si lo hay.
  String? get aviso => estado ?? (archivado ? 'archivado' : null);
}

class Arte {
  final String? portada, portadaThumb, hero, heroThumb, logo, logoThumb;
  const Arte({this.portada, this.portadaThumb, this.hero, this.heroThumb, this.logo, this.logoThumb});
  factory Arte.fromJson(Map<String, dynamic> j) =>
      Arte(portada: j['portada'], portadaThumb: j['portada_thumb'], hero: j['hero'], heroThumb: j['hero_thumb'], logo: j['logo'], logoThumb: j['logo_thumb']);
}

/// Una imagen alternativa para un juego (de SteamGridDB o propuesta por la comunidad).
class Alternativa {
  final String url, thumb;
  const Alternativa(this.url, this.thumb);
}

/// Las imágenes que cada uno elige para sus juegos (se guardan solo en este dispositivo).
class ArteElegido extends ChangeNotifier {
  Map<String, Map<String, String>> _m = {};
  SharedPreferences? _p;

  Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    try {
      _m = {
        for (final e in (jsonDecode(_p!.getString('arte_elegido') ?? '{}') as Map).entries)
          '${e.key}': Map<String, String>.from(e.value as Map),
      };
    } catch (_) {}
  }

  String? de(String juego, String tipo) => _m[juego]?[tipo];

  void elegir(String juego, String tipo, String? url) {
    final m = _m.putIfAbsent(juego, () => {});
    url == null ? m.remove(tipo) : m[tipo] = url;
    if (m.isEmpty) _m.remove(juego);
    _p?.setString('arte_elegido', jsonEncode(_m));
    notifyListeners();
  }
}

final arteElegido = ArteElegido();

class Juego {
  final String id, nombre, confianza, descripcion;
  final int orden;

  /// Listas de logros que tiene en la base de datos de Hangar (Xbox 360, RetroAchievements…).
  final List<({String fuente, int total, int puntos})> logros;
  final List<String> proyectos, tipos, notas;
  final List<Repo> repos;
  final Arte? arte;

  /// Otras imágenes para elegir: 'portada', 'hero' y 'logo'.
  final Map<String, List<Alternativa>> arteAlt;
  const Juego({
    required this.id,
    required this.nombre,
    required this.confianza,
    this.descripcion = '',
    this.orden = 9999,
    this.logros = const [],
    required this.proyectos,
    required this.tipos,
    required this.notas,
    required this.repos,
    this.arte,
    this.arteAlt = const {},
  });

  factory Juego.fromJson(Map<String, dynamic> j) {
    List<String> strs(Object? v) => (v as List? ?? const []).map((e) => '$e').toList();
    return Juego(
      id: '${j['id']}',
      nombre: '${j['nombre']}',
      confianza: '${j['confianza_nombre'] ?? 'original'}',
      descripcion: '${j['descripcion'] ?? ''}',
      orden: (j['orden'] as num?)?.toInt() ?? 9999,
      logros: [
        for (final l in (j['logros'] as List? ?? const []))
          (fuente: '${l['fuente']}', total: (l['total'] as num?)?.toInt() ?? 0, puntos: (l['puntos'] as num?)?.toInt() ?? 0),
      ],
      proyectos: strs(j['proyectos']),
      tipos: strs(j['tipos']),
      notas: strs(j['notas']),
      repos: (j['repos'] as List? ?? const [])
          .map(
            (r) => Repo(
              '${r['repo']}',
              '${r['url'] ?? 'https://github.com/${r['repo']}'}',
              '${r['tipo'] ?? ''}',
              mac: r['mac'] is Map<String, dynamic> ? MacInfo.fromJson(r['mac']) : null,
              android: r['android'] is Map<String, dynamic> ? AndroidInfo.fromJson(r['android']) : null,
              requisitos: strs(r['requisitos']),
              archivado: r['archivado'] == true,
              estado: r['estado'],
            ),
          )
          .toList(),
      arte: j['arte'] is Map<String, dynamic> ? Arte.fromJson(j['arte']) : null,
      arteAlt: {
        if (j['arte_alt'] is Map)
          for (final e in (j['arte_alt'] as Map).entries)
            '${e.key}': [
              for (final a in (e.value as List? ?? const []))
                if (a is Map && a['url'] is String) Alternativa(a['url'], '${a['thumb'] ?? a['url']}'),
            ],
      },
    );
  }

  // Lo que hayas elegido tú manda sobre lo del catálogo.
  String? get cover => arteElegido.de(id, 'portada') ?? arte?.portadaThumb ?? arte?.portada;
  String? get coverFull => arteElegido.de(id, 'portada') ?? arte?.portada ?? arte?.portadaThumb;
  String? get hero => arteElegido.de(id, 'hero') ?? arte?.hero ?? arte?.heroThumb;
  String? get heroSmall => arteElegido.de(id, 'hero') ?? arte?.heroThumb ?? arte?.hero;
  String? get logo => arteElegido.de(id, 'logo') ?? arte?.logo ?? arte?.logoThumb;

  /// Todas las opciones de un tipo de imagen: la del catálogo primero y después las alternativas.
  List<Alternativa> opciones(String tipo) {
    final base = switch (tipo) {
      'portada' => arte?.portada == null ? null : Alternativa(arte!.portada!, arte!.portadaThumb ?? arte!.portada!),
      'hero' => arte?.hero == null ? null : Alternativa(arte!.hero!, arte!.heroThumb ?? arte!.hero!),
      _ => arte?.logo == null ? null : Alternativa(arte!.logo!, arte!.logoThumb ?? arte!.logo!),
    };
    final out = <Alternativa>[?base];
    for (final a in arteAlt[tipo] ?? const <Alternativa>[]) {
      if (!out.any((o) => o.url == a.url)) out.add(a);
    }
    return out;
  }
  bool get hasHero => hero != null;

  /// Algún port se puede instalar en este dispositivo.
  bool get listo => repos.any((r) => r.listo);
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

  String _version = '';

  /// Fecha de la última revisión del catálogo (la más reciente de las que trae en `_meta`).
  static String version(String raw) {
    final head = raw.substring(0, raw.length < 2500 ? raw.length : 2500);
    final fechas = RegExp(r'"(revisado|logros_generado)"\s*:\s*"([^"]+)"').allMatches(head).map((m) => m.group(2)!).toList()..sort();
    return fechas.isEmpty ? '' : fechas.last;
  }

  String get _kRaw => 'catalogo_raw_$file';
  String get _kWhen => 'catalogo_when_$file';

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_kRaw);
    final bundled = await rootBundle.loadString('assets/$file');
    // La copia descargada solo gana si es igual o más reciente que la que trae la app.
    if (cached != null && version(cached).compareTo(version(bundled)) >= 0) {
      try {
        catalogo = Catalogo(Catalogo.parse(cached), 'GitHub', DateTime.tryParse(prefs.getString(_kWhen) ?? ''));
        _version = version(cached);
      } catch (_) {}
    }
    if (catalogo.juegos.isEmpty) {
      catalogo = Catalogo(Catalogo.parse(bundled), 'integrado', null);
      _version = version(bundled);
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
      String? body;
      for (final u in catalogUrls(file)) {
        try {
          final r = await http.get(Uri.parse(u)).timeout(const Duration(seconds: 15));
          if (r.statusCode == 200) {
            body = utf8.decode(r.bodyBytes);
            break;
          }
        } catch (_) {}
      }
      if (body == null) throw 'sin conexión con GitHub';
      // No cambiamos a un catálogo más viejo que el que ya tenemos.
      if (version(body).compareTo(_version) < 0) return;
      _version = version(body);
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
  bool vibracion = true, chispas = true, empezarBig = false;
  SharedPreferences? _p;

  Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    vibracion = _p!.getBool('vib') ?? true;
    chispas = _p!.getBool('fx') ?? true;
    empezarBig = _p!.getBool('big') ?? false;
    notifyListeners();
  }

  void set({bool? vib, bool? fx, bool? big}) {
    if (vib != null) _p?.setBool('vib', vibracion = vib);
    if (big != null) _p?.setBool('big', empezarBig = big);
    if (fx != null) _p?.setBool('fx', chispas = fx);
    notifyListeners();
  }
}
