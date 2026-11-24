import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'data.dart';

enum Fase { nada, descargando, preparando, listo, jugando }

/// Lo que se guarda de cada port instalado.
class Instalado {
  final String dir, target, version;
  final String? copia, paquete;
  final int segundos;
  final DateTime? ultima;
  const Instalado({required this.dir, required this.target, required this.version, this.copia, this.paquete, this.segundos = 0, this.ultima});

  Map<String, dynamic> toJson() => {
    'dir': dir,
    'target': target,
    'version': version,
    'copia': copia,
    'paquete': paquete,
    'segundos': segundos,
    'ultima': ultima?.toIso8601String(),
  };
  factory Instalado.fromJson(Map<String, dynamic> j) => Instalado(
    dir: j['dir'] ?? '',
    target: j['target'] ?? '',
    version: j['version'] ?? '',
    copia: j['copia'],
    paquete: j['paquete'],
    segundos: j['segundos'] ?? 0,
    ultima: DateTime.tryParse(j['ultima'] ?? ''),
  );
  Instalado copyWith({String? copia, int? segundos, DateTime? ultima}) => Instalado(
    dir: dir,
    target: target,
    version: version,
    copia: copia ?? this.copia,
    paquete: paquete,
    segundos: segundos ?? this.segundos,
    ultima: ultima ?? this.ultima,
  );
}

class InstallError implements Exception {
  final String msg;
  InstallError(this.msg);
  @override
  String toString() => msg;
}

/// Instala, arranca y desinstala ports. En el Mac descarga la release de GitHub, la comprueba,
/// la descomprime y abre la app. En Android descarga el APK y abre el instalador del sistema.
class Installer extends ChangeNotifier {
  final Map<String, Instalado> _hechos = {};
  final Map<String, Fase> _fase = {};
  final Map<String, double> _prog = {};
  final Map<String, String> _err = {};
  SharedPreferences? _p;
  DateTime _lastNotify = DateTime(2000);

  static const _android = MethodChannel('hangar/android');

  bool get esMac => !kIsWeb && Platform.isMacOS;
  bool get esAndroid => !kIsWeb && Platform.isAndroid;
  bool get soportado => esMac || esAndroid;

  Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    final raw = _p!.getString('instalados');
    if (raw != null) {
      (jsonDecode(raw) as Map<String, dynamic>).forEach((k, v) => _hechos[k] = Instalado.fromJson(v));
    }
    await comprobar();
  }

  /// Revisa qué sigue instalado (en Android el usuario puede desinstalar desde el sistema).
  Future<void> comprobar() async {
    for (final e in _hechos.entries.toList()) {
      final ok = esAndroid
          ? await _android.invokeMethod<bool>('isInstalled', e.value.paquete) == true
          : await FileSystemEntity.type(e.value.target) != FileSystemEntityType.notFound;
      if (!ok && _fase[e.key] != Fase.descargando) _hechos.remove(e.key);
    }
    _save();
    notifyListeners();
    await leerUso();
  }

  void _save() => _p?.setString('instalados', jsonEncode(_hechos.map((k, v) => MapEntry(k, v.toJson()))));

  Fase fase(Repo r) => _fase[r.repo] ?? (_hechos.containsKey(r.repo) ? Fase.listo : Fase.nada);
  double progreso(Repo r) => _prog[r.repo] ?? 0;
  String? error(Repo r) => _err[r.repo];
  Instalado? instalado(Repo r) => _hechos[r.repo];

  /// Todo lo instalado (repo → registro), para el perfil.
  Iterable<MapEntry<String, Instalado>> get todos => _hechos.entries;

  /// Se puede instalar aquí: en el Mac hace falta que el catálogo diga qué archivo bajar.
  bool instalable(Repo r) => esAndroid || (esMac && r.mac?.asset != null);

  /// Hay una versión más nueva en el catálogo que la instalada.
  bool hayActualizacion(Repo r) {
    final rec = _hechos[r.repo], v = r.version;
    if (rec == null || v == null || rec.version.isEmpty) return false;
    String n(String x) => x.toLowerCase().replaceFirst(RegExp(r'^v'), '').trim();
    return n(rec.version) != n(v);
  }

  /// Contadores para los logros de Hangar.
  int get instalacionesTotales => _p?.getInt('stat_instalaciones') ?? 0;
  int get sesionesTotales => _p?.getInt('stat_sesiones') ?? 0;
  int get segundosTotales => _hechos.values.fold(0, (s, r) => s + r.segundos);
  int get instaladosAhora => _hechos.length;
  int get juegosJugados => _hechos.values.where((r) => r.ultima != null).length;
  void _contar(String k) => _p?.setInt(k, (_p?.getInt(k) ?? 0) + 1);

  int segundos(Juego j) => j.repos.fold(0, (s, r) => s + (_hechos[r.repo]?.segundos ?? 0));
  DateTime? ultima(Juego j) {
    DateTime? best;
    for (final r in j.repos) {
      final u = _hechos[r.repo]?.ultima;
      if (u != null && (best == null || u.isAfter(best))) best = u;
    }
    return best;
  }

  /// El port que manda en el botón principal: el instalado, o el primero que se pueda instalar.
  Repo? principal(Juego j) {
    for (final r in j.repos) {
      if (_hechos.containsKey(r.repo) || _fase[r.repo] == Fase.descargando || _fase[r.repo] == Fase.preparando) return r;
    }
    for (final r in j.repos) {
      if (r.listo) return r;
    }
    for (final r in j.repos) {
      if (instalable(r)) return r;
    }
    return j.repos.isEmpty ? null : j.repos.first;
  }

  void _set(Repo r, Fase f, {double? p, String? err, bool force = true}) {
    _fase[r.repo] = f;
    if (p != null) _prog[r.repo] = p;
    if (err != null) {
      _err[r.repo] = err;
    } else if (f != Fase.nada) {
      _err.remove(r.repo);
    }
    final now = DateTime.now();
    if (force || now.difference(_lastNotify).inMilliseconds > 120) {
      _lastNotify = now;
      notifyListeners();
    }
  }

  void _clear(Repo r) {
    _fase.remove(r.repo);
    _prog.remove(r.repo);
    notifyListeners();
  }

  // ───────────────────────── instalar ─────────────────────────

  Future<void> instalar(Repo r) async {
    if (!soportado) {
      await launchUrl(Uri.parse('${r.url}/releases'), mode: LaunchMode.externalApplication);
      return;
    }
    if (_fase[r.repo] == Fase.descargando || _fase[r.repo] == Fase.preparando) return;
    _set(r, Fase.descargando, p: 0);
    try {
      final antes = _hechos[r.repo];
      if (esMac) {
        await _instalarMac(r);
      } else {
        await _instalarAndroid(r);
      }
      // Al actualizar se conservan tu copia del juego y tu tiempo jugado.
      final nuevo = _hechos[r.repo];
      if (antes != null && nuevo != null) {
        _hechos[r.repo] = Instalado(
          dir: nuevo.dir,
          target: nuevo.target,
          version: nuevo.version,
          copia: antes.copia,
          paquete: nuevo.paquete,
          segundos: antes.segundos,
          ultima: antes.ultima,
        );
        _save();
      } else {
        _contar('stat_instalaciones');
      }
      _clear(r);
    } catch (e) {
      debugPrint('instalar ${r.repo}: $e');
      _fase.remove(r.repo);
      _err[r.repo] = _explicar(e);
      notifyListeners();
    }
  }

  /// Los errores, en cristiano.
  static String _explicar(Object e) => switch (e) {
        InstallError() => '$e',
        SocketException() || HttpException() || TimeoutException() || HandshakeException() =>
          'Se ha cortado la conexión. Pulsa Instalar otra vez y seguirá desde donde se quedó.',
        FileSystemException(:final osError) when (osError?.errorCode == 28) =>
          'No queda espacio en el dispositivo para descargar el juego.',
        _ => 'Algo ha fallado al instalar: $e',
      };

  Future<Uri> _resolver(Repo r, {required bool apk}) async {
    final m = r.mac;
    // Lo normal: el revisor del catálogo ya encontró el archivo en GitHub.
    if (apk && r.android != null) return Uri.parse(r.android!.url);
    if (!apk && m?.url != null) return Uri.parse(m!.url!);
    if (!apk && m?.file != null && m?.tag != null) {
      return Uri.parse('https://github.com/${r.repo}/releases/download/${Uri.encodeComponent(m!.tag!)}/${Uri.encodeComponent(m.file!)}');
    }
    // Con tag, esa release. Sin tag, las últimas (incluidas pre-releases, que muchos ports solo publican así).
    final api = m?.tag != null && !apk
        ? 'https://api.github.com/repos/${r.repo}/releases/tags/${Uri.encodeComponent(m!.tag!)}'
        : 'https://api.github.com/repos/${r.repo}/releases?per_page=10';
    final res = await http.get(Uri.parse(api), headers: {'Accept': 'application/vnd.github+json'}).timeout(const Duration(seconds: 20));
    if (res.statusCode == 403 || res.statusCode == 429) throw InstallError('GitHub ha limitado las consultas. Prueba dentro de un rato.');
    if (res.statusCode != 200) throw InstallError('Este proyecto no tiene ninguna versión publicada en GitHub.');
    final body = jsonDecode(res.body);
    final releases = (body is List ? body : [body]).cast<Map<String, dynamic>>().where((x) => x['draft'] != true).toList();
    if (releases.isEmpty) throw InstallError('Este proyecto no tiene ninguna versión publicada en GitHub.');
    // La primera release que traiga lo que buscamos.
    final assets =
        (releases.firstWhere(
                  (rel) => ((rel['assets'] as List?) ?? const []).any(
                    (a) => apk
                        ? '${a['name']}'.toLowerCase().endsWith('.apk')
                        : RegExp('^${m!.asset!.split('*').map(RegExp.escape).join('.*')}\$', caseSensitive: false).hasMatch('${a['name']}'),
                  ),
                  orElse: () => releases.first,
                )['assets']
                as List)
            .cast<Map<String, dynamic>>();
    Map<String, dynamic>? pick;
    if (apk) {
      final apks = assets.where((a) => '${a['name']}'.toLowerCase().endsWith('.apk')).toList();
      int score(Map a) {
        final n = '${a['name']}'.toLowerCase();
        return (n.contains('arm64') || n.contains('v8a') ? 3 : 0) +
            (n.contains('universal') ? 2 : 0) -
            (n.contains('x86') ? 5 : 0) -
            (n.contains('debug') ? 1 : 0);
      }

      apks.sort((a, b) => score(b) - score(a));
      if (apks.isNotEmpty) pick = apks.first;
      if (pick == null) throw InstallError('La última versión de este proyecto no trae un APK para instalar.');
    } else {
      final re = RegExp('^${m!.asset!.split('*').map(RegExp.escape).join('.*')}\$', caseSensitive: false);
      for (final a in assets) {
        if (re.hasMatch('${a['name']}')) {
          pick = a;
          break;
        }
      }
      if (pick == null) throw InstallError('No encuentro la descarga para Mac en la versión ${m.tag ?? 'actual'}.');
    }
    return Uri.parse('${pick['browser_download_url']}');
  }

  /// Descarga aguantando cortes: si la conexión se cae, espera y sigue desde el último byte
  /// (cabecera Range). Lo descargado se guarda en `<dest>.part`, así que si se agotan los
  /// intentos, al pulsar Instalar otra vez continúa donde se quedó en vez de empezar de cero.
  Future<File> _descargar(Repo r, Uri url, File dest) async {
    await dest.parent.create(recursive: true);
    final part = File('${dest.path}.part');
    // Un trozo de otra versión no sirve: se apunta de qué enlace era.
    final origen = File('${dest.path}.part.url');
    if (!await origen.exists() || await origen.readAsString() != '$url') {
      if (await part.exists()) await part.delete();
      await origen.writeAsString('$url');
    }
    const intentos = 8;
    for (var i = 1;; i++) {
      final c = HttpClient()
        ..userAgent = 'Hangar'
        ..connectionTimeout = const Duration(seconds: 20)
        ..idleTimeout = const Duration(seconds: 20);
      IOSink? sink;
      try {
        var got = await part.exists() ? await part.length() : 0;
        // Cada intento vuelve a pedir la URL de GitHub: el enlace firmado al que redirige caduca.
        final req = await c.getUrl(url);
        req.followRedirects = true;
        req.maxRedirects = 10;
        if (got > 0) req.headers.set(HttpHeaders.rangeHeader, 'bytes=$got-');
        final res = await req.close().timeout(const Duration(seconds: 30));
        if (res.statusCode == 416) {
          // Ya lo teníamos entero.
          await res.drain<void>();
          await origen.delete();
          return await part.rename(dest.path);
        }
        if (res.statusCode != 200 && res.statusCode != 206) {
          throw InstallError('La descarga ha fallado (HTTP ${res.statusCode}).');
        }
        if (res.statusCode == 200) got = 0; // el servidor no admite continuar: desde el principio
        final total = res.contentLength < 0 ? -1 : got + res.contentLength;
        sink = part.openWrite(mode: got > 0 ? FileMode.append : FileMode.write);
        // Si dejan de llegar datos 30 s, se da por cortada y se reintenta.
        await for (final chunk in res.timeout(const Duration(seconds: 30))) {
          sink.add(chunk);
          got += chunk.length;
          if (total > 0) _set(r, Fase.descargando, p: got / total, force: false);
        }
        await sink.close();
        sink = null;
        if (total > 0 && got < total) throw const HttpException('Descarga incompleta');
        if (await dest.exists()) await dest.delete();
        await origen.delete();
        return await part.rename(dest.path);
      } on InstallError {
        rethrow;
      } catch (e) {
        await sink?.close().catchError((_) {});
        debugPrint('descarga, intento $i: $e');
        if (i >= intentos) {
          final hecho = await part.exists() ? await part.length() : 0;
          throw InstallError(
            hecho > 0
                ? 'Se ha cortado la conexión. Pulsa Instalar otra vez y seguirá desde donde se quedó.'
                : 'No hay conexión para descargar. Comprueba el internet y vuelve a intentarlo.',
          );
        }
        _set(r, Fase.descargando, p: _prog[r.repo], force: true);
        await Future<void>.delayed(Duration(seconds: (2 * i).clamp(2, 12)));
      } finally {
        c.close(force: true);
      }
    }
  }

  Future<String> _run(String cmd, List<String> args, {String? cwd}) async {
    final res = await Process.run(cmd, args, workingDirectory: cwd);
    if (res.exitCode != 0) throw InstallError('Falló $cmd: ${'${res.stderr}'.trim().split('\n').last}');
    return '${res.stdout}';
  }

  String _home() => Platform.environment['HOME'] ?? '/tmp';
  String _dirMac(Repo r) => '${_home()}/Library/Application Support/Hangar/juegos/${r.repo.replaceAll('/', '__')}';

  Future<void> _instalarMac(Repo r) async {
    final m = r.mac!;
    final url = await _resolver(r, apk: false);
    final name = Uri.decodeComponent(url.pathSegments.last);
    final lower = name.toLowerCase();
    final dir = Directory(_dirMac(r));
    final tmp = Directory('${dir.path}.tmp');
    if (await tmp.exists()) await tmp.delete(recursive: true);
    await tmp.create(recursive: true);
    // La descarga va aparte para que, si se corta, el siguiente intento continúe.
    final descargas = Directory('${dir.path}.descarga');
    final archive = await _descargar(r, url, File('${descargas.path}/$name'));

    _set(r, Fase.preparando);
    if (m.sha256 != null && url.toString().contains(m.file ?? '\u0000')) {
      final sum = (await _run('shasum', ['-a', '256', archive.path])).split(' ').first.trim();
      if (sum.toLowerCase() != m.sha256!.toLowerCase()) throw InstallError('El archivo descargado no coincide con el del catálogo. No lo instalo.');
    }
    final out = Directory('${tmp.path}/out')..createSync();
    if (lower.endsWith('.zip')) {
      await _run('ditto', ['-x', '-k', archive.path, out.path]);
    } else if (lower.endsWith('.dmg')) {
      final mnt = Directory('${tmp.path}/mnt')..createSync();
      await _run('hdiutil', ['attach', '-nobrowse', '-readonly', '-noverify', '-mountpoint', mnt.path, archive.path]);
      try {
        for (final e in mnt.listSync()) {
          final n = e.path.split('/').last;
          if (n.startsWith('.') || n == 'Applications') continue;
          await _run('ditto', [e.path, '${out.path}/$n']);
        }
      } finally {
        await Process.run('hdiutil', ['detach', mnt.path, '-force']);
      }
    } else if (lower.contains('.tar') || lower.endsWith('.7z') || lower.endsWith('.rar') || lower.endsWith('.tgz')) {
      // bsdtar (el tar del Mac) abre también 7z y rar.
      await _run('tar', ['-xf', archive.path, '-C', out.path]);
    } else {
      // Un ejecutable suelto
      await archive.rename('${out.path}/$name');
      await Process.run('chmod', ['+x', '${out.path}/$name']);
    }
    await Process.run('xattr', ['-dr', 'com.apple.quarantine', out.path]);
    if (await archive.exists()) await archive.delete();

    if (await dir.exists()) await dir.delete(recursive: true);
    await out.rename(dir.path);
    await tmp.delete(recursive: true);
    if (await descargas.exists()) await descargas.delete(recursive: true);

    final target = _buscarArranque(dir, m);
    if (target == null) throw InstallError('Descargado, pero no encuentro la app dentro. Ábrelo desde la carpeta.');
    _hechos[r.repo] = Instalado(dir: dir.path, target: target, version: m.tag ?? m.version ?? '');
    _save();
  }

  /// Busca qué abrir: lo que diga el catálogo, si no la primera .app, y si no un ejecutable.
  String? _buscarArranque(Directory dir, MacInfo m) {
    final all = <FileSystemEntity>[];
    void walk(Directory d, int depth) {
      for (final e in d.listSync(followLinks: false)) {
        final n = e.path.split('/').last;
        if (n == '__MACOSX' || n.startsWith('.')) continue;
        all.add(e);
        if (e is Directory && !n.endsWith('.app') && depth < 4) walk(e, depth + 1);
      }
    }

    walk(dir, 0);
    for (final p in m.programa) {
      final app = p.contains('.app/') ? p.substring(0, p.indexOf('.app/') + 4) : p;
      for (final e in all) {
        if (e.path.endsWith('/$app') || e.path.endsWith('/${app.split('/').last}')) return e.path;
      }
    }
    for (final e in all) {
      if (e is Directory && e.path.endsWith('.app')) return e.path;
    }
    for (final e in all) {
      if (e is File) {
        final n = e.path.split('/').last;
        final mode = e.statSync().mode;
        if ((mode & 0x49) != 0 && !n.contains('.')) return e.path;
      }
    }
    return null;
  }

  Future<void> _instalarAndroid(Repo r) async {
    final url = await _resolver(r, apk: true);
    final cache = await getTemporaryDirectory();
    final apk = await _descargar(r, url, File('${cache.path}/apks/${r.repo.replaceAll('/', '__')}.apk'));
    _set(r, Fase.preparando);
    final pkg = await _android.invokeMethod<String>('packageOf', apk.path);
    if (pkg == null) throw InstallError('El APK descargado no es válido.');
    final segs = url.pathSegments;
    final version = r.android?.tag ?? (segs.length > 2 ? Uri.decodeComponent(segs[segs.length - 2]) : '');
    _hechos[r.repo] = Instalado(dir: cache.path, target: apk.path, version: version, paquete: pkg);
    _save();
    final ok = await _android.invokeMethod<bool>('install', apk.path);
    if (ok != true) throw InstallError('Permite a Hangar instalar apps y vuelve a pulsar Instalar.');
  }

  // ───────────────────────── jugar ─────────────────────────

  /// Pide la copia del juego (un archivo de tu disco) y la recuerda para este port.
  Future<String?> elegirCopia(Repo r) async {
    final f = await openFile(confirmButtonText: 'Usar esta copia');
    if (f == null) return null;
    final aviso = await comprobarCopia(r, f.path);
    if (aviso == null) {
      avisoCopia.remove(r.repo);
    } else {
      avisoCopia[r.repo] = aviso;
    }
    final rec = _hechos[r.repo];
    if (rec != null) {
      _hechos[r.repo] = rec.copyWith(copia: f.path);
      _save();
      notifyListeners();
    }
    return f.path;
  }

  Future<void> jugar(Repo r) async {
    final rec = _hechos[r.repo];
    if (rec == null) return instalar(r);
    final m = r.mac;
    _contar('stat_sesiones');
    if (esAndroid) {
      _hechos[r.repo] = rec.copyWith(ultima: DateTime.now());
      _save();
      notifyListeners();
      final ok = await _android.invokeMethod<bool>('launch', rec.paquete);
      if (ok != true) {
        _err[r.repo] = 'No se pudo abrir. Puede que ya no esté instalado.';
        await comprobar();
      }
      return;
    }
    var copia = rec.copia;
    if (m != null && m.pideCopia && (copia == null || !File(copia).existsSync())) {
      copia = await elegirCopia(r);
      if (copia == null) return;
    }
    final args = [for (final a in m?.args ?? const <String>[]) a.replaceAll('{game}', copia ?? '')];
    final start = DateTime.now();
    _set(r, Fase.jugando);
    try {
      final Process proc;
      if (rec.target.endsWith('.app')) {
        proc = await Process.start('open', ['-W', '-n', rec.target, if (args.isNotEmpty) '--args', ...args]);
      } else {
        await Process.run('chmod', ['+x', rec.target]);
        proc = await Process.start(rec.target, args, workingDirectory: File(rec.target).parent.path, mode: ProcessStartMode.normal);
        unawaited(proc.stdout.drain<void>());
        unawaited(proc.stderr.drain<void>());
      }
      await proc.exitCode;
    } catch (e) {
      _err[r.repo] = 'No se pudo abrir: $e';
    } finally {
      final secs = DateTime.now().difference(start).inSeconds;
      final cur = _hechos[r.repo];
      if (cur != null) _hechos[r.repo] = cur.copyWith(segundos: cur.segundos + (secs > 5 ? secs : 0), ultima: DateTime.now());
      _save();
      _clear(r);
    }
  }

  Future<void> abrirCarpeta(Repo r) async {
    final rec = _hechos[r.repo];
    if (rec != null && esMac) await Process.run('open', [rec.dir]);
  }

  Future<void> desinstalar(Repo r) async {
    final rec = _hechos[r.repo];
    if (rec == null) return;
    if (esAndroid) {
      await _android.invokeMethod('uninstall', rec.paquete);
      return; // se confirma al volver a Hangar (comprobar)
    }
    final d = Directory(rec.dir);
    if (await d.exists()) await d.delete(recursive: true);
    _hechos.remove(r.repo);
    _save();
    notifyListeners();
  }

  // ───────────────────────── comprobar tu copia (Mac) ─────────────────────────

  /// Mira si el archivo elegido es la copia que espera el port. Devuelve un aviso o null si encaja.
  Future<String?> comprobarCopia(Repo r, String path) async {
    final m = r.mac;
    if (m == null) return null;
    final f = File(path);
    if (!await f.exists()) return 'No encuentro el archivo.';
    final ext = path.toLowerCase().split('.').last;
    if (m.ids.isNotEmpty && (ext == 'iso' || ext == 'gcm')) {
      final raf = await f.open();
      final head = String.fromCharCodes(await raf.read(6));
      await raf.close();
      if (!m.ids.any((id) => head.startsWith(id))) return 'Este disco no parece el que pide el port (ID $head; vale ${m.ids.join(', ')}).';
    }
    if (m.dumps.isNotEmpty) {
      final size = await f.length();
      final mismos = m.dumps.where((d) => d.size == size).toList();
      if (mismos.isEmpty) return 'El tamaño no coincide con ninguna versión válida (${m.dumps.map((d) => d.name).join(', ')}).';
      if (size <= 256 * 1024 * 1024) {
        final crc = (await _crc32(f)).toRadixString(16).toUpperCase().padLeft(8, '0');
        if (!mismos.any((d) => d.crc32 == crc)) return 'La ROM no coincide con la versión que pide el port (CRC $crc).';
      }
    }
    return null;
  }

  static List<int>? _tabla;
  Future<int> _crc32(File f) async {
    final t = _tabla ??= List.generate(256, (n) {
      var c = n;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
      }
      return c;
    });
    var crc = 0xFFFFFFFF;
    await for (final chunk in f.openRead()) {
      for (final b in chunk) {
        crc = t[(crc ^ b) & 0xFF] ^ (crc >> 8);
      }
    }
    return crc ^ 0xFFFFFFFF;
  }

  /// Avisos de la última copia elegida, por port.
  final Map<String, String> avisoCopia = {};

  // ───────────────────────── tiempo de juego en Android ─────────────────────────

  bool permisoUso = false;

  /// Lee del sistema cuánto has jugado a cada port instalado (necesita el permiso de uso).
  Future<void> leerUso() async {
    if (!esAndroid) return;
    permisoUso = await _android.invokeMethod<bool>('hasUsage') == true;
    if (!permisoUso) return notifyListeners();
    final pkgs = [
      for (final r in _hechos.values)
        if (r.paquete != null) r.paquete!,
    ];
    if (pkgs.isEmpty) return notifyListeners();
    final res = await _android.invokeMapMethod<String, dynamic>('usage', pkgs) ?? const {};
    for (final e in _hechos.entries.toList()) {
      final u = res[e.value.paquete] as Map?;
      if (u == null) continue;
      final secs = ((u['ms'] as num?) ?? 0) ~/ 1000;
      final last = (u['last'] as num?)?.toInt() ?? 0;
      _hechos[e.key] = e.value.copyWith(
        segundos: secs > e.value.segundos ? secs : e.value.segundos,
        ultima: last > 0 ? DateTime.fromMillisecondsSinceEpoch(last) : e.value.ultima,
      );
    }
    _save();
    notifyListeners();
  }

  Future<void> pedirPermisoUso() => _android.invokeMethod('askUsage');
}
