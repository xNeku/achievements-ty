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
      final ok = esAndroid ? await _android.invokeMethod<bool>('isInstalled', e.value.paquete) == true : await FileSystemEntity.type(e.value.target) != FileSystemEntityType.notFound;
      if (!ok && _fase[e.key] != Fase.descargando) _hechos.remove(e.key);
    }
    _save();
    notifyListeners();
  }

  void _save() => _p?.setString('instalados', jsonEncode(_hechos.map((k, v) => MapEntry(k, v.toJson()))));

  Fase fase(Repo r) => _fase[r.repo] ?? (_hechos.containsKey(r.repo) ? Fase.listo : Fase.nada);
  double progreso(Repo r) => _prog[r.repo] ?? 0;
  String? error(Repo r) => _err[r.repo];
  Instalado? instalado(Repo r) => _hechos[r.repo];

  /// Se puede instalar aquí: en el Mac hace falta que el catálogo diga qué archivo bajar.
  bool instalable(Repo r) => esAndroid || (esMac && r.mac?.asset != null);

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
      if (esMac) {
        await _instalarMac(r);
      } else {
        await _instalarAndroid(r);
      }
      _clear(r);
    } catch (e) {
      _fase.remove(r.repo);
      _err[r.repo] = '$e';
      notifyListeners();
    }
  }

  Future<Uri> _resolver(Repo r, {required bool apk}) async {
    final m = r.mac;
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
    final assets = (releases.firstWhere(
      (rel) => ((rel['assets'] as List?) ?? const []).any((a) => apk
          ? '${a['name']}'.toLowerCase().endsWith('.apk')
          : RegExp('^${m!.asset!.split('*').map(RegExp.escape).join('.*')}\$', caseSensitive: false).hasMatch('${a['name']}')),
      orElse: () => releases.first,
    )['assets'] as List)
        .cast<Map<String, dynamic>>();
    Map<String, dynamic>? pick;
    if (apk) {
      final apks = assets.where((a) => '${a['name']}'.toLowerCase().endsWith('.apk')).toList();
      int score(Map a) {
        final n = '${a['name']}'.toLowerCase();
        return (n.contains('arm64') || n.contains('v8a') ? 3 : 0) + (n.contains('universal') ? 2 : 0) - (n.contains('x86') ? 5 : 0) - (n.contains('debug') ? 1 : 0);
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

  Future<File> _descargar(Repo r, Uri url, File dest) async {
    final c = HttpClient()..userAgent = 'Hangar';
    try {
      final req = await c.getUrl(url);
      req.followRedirects = true;
      req.maxRedirects = 10;
      final res = await req.close();
      if (res.statusCode != 200) throw InstallError('La descarga ha fallado (HTTP ${res.statusCode}).');
      final total = res.contentLength;
      await dest.parent.create(recursive: true);
      final sink = dest.openWrite();
      var got = 0;
      await for (final chunk in res) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) _set(r, Fase.descargando, p: got / total, force: false);
      }
      await sink.close();
      return dest;
    } finally {
      c.close();
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
    if (lower.endsWith('.rar') || lower.endsWith('.7z')) throw InstallError('Esta versión viene en ${lower.split('.').last.toUpperCase()}; Hangar todavía no sabe abrirla.');
    final dir = Directory(_dirMac(r));
    final tmp = Directory('${dir.path}.tmp');
    if (await tmp.exists()) await tmp.delete(recursive: true);
    await tmp.create(recursive: true);
    final archive = await _descargar(r, url, File('${tmp.path}/$name'));

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
    } else if (lower.contains('.tar')) {
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

    final target = _buscarArranque(dir, m);
    if (target == null) throw InstallError('Descargado, pero no encuentro la app dentro. Ábrelo desde la carpeta.');
    _hechos[r.repo] = Instalado(dir: dir.path, target: target, version: m.version ?? m.tag ?? '');
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
    _hechos[r.repo] = Instalado(dir: cache.path, target: apk.path, version: segs.length > 2 ? Uri.decodeComponent(segs[segs.length - 2]) : '', paquete: pkg);
    _save();
    final ok = await _android.invokeMethod<bool>('install', apk.path);
    if (ok != true) throw InstallError('Permite a Hangar instalar apps y vuelve a pulsar Instalar.');
  }

  // ───────────────────────── jugar ─────────────────────────

  /// Pide la copia del juego (un archivo de tu disco) y la recuerda para este port.
  Future<String?> elegirCopia(Repo r) async {
    final f = await openFile(confirmButtonText: 'Usar esta copia');
    if (f == null) return null;
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
}
