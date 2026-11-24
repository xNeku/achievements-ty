import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'data.dart';
import 'installer.dart';
import 'logros.dart';

/// Servidor por defecto: se pasa al compilar (`--dart-define=HANGAR_SERVER=https://…`) para no dejarlo en el código.
const servidorPorDefecto = String.fromEnvironment('HANGAR_SERVER');

class Amigo {
  final String id, nombre;
  const Amigo(this.id, this.nombre);
  String get inicial => nombre.trim().isEmpty ? '?' : nombre.trim().substring(0, 1).toUpperCase();
}

class Amistad {
  final String id, estado;
  final Amigo otro;
  final bool laPedi;
  const Amistad(this.id, this.estado, this.otro, this.laPedi);
}

class Partida {
  final String juego, nombre, plataforma;
  final int segundos;
  final DateTime? ultima;
  const Partida(this.juego, this.nombre, this.plataforma, this.segundos, this.ultima);
}

class CuentaError implements Exception {
  final String msg;
  CuentaError(this.msg);
  @override
  String toString() => msg;
}

/// Tu cuenta de Hangar en el servidor (PocketBase): entrar, sincronizar partidas y logros, y amigos.
class Cuenta extends ChangeNotifier {
  String servidor = servidorPorDefecto;
  String? token, userId, email, nombre;
  bool ocupado = false;
  String? error;
  List<Amistad> amistades = const [];
  final Map<String, List<Partida>> actividad = {};
  SharedPreferences? _p;
  Timer? _sync;

  bool get configurado => servidor.trim().isNotEmpty;
  bool get dentro => token != null;
  List<Amistad> get amigos => amistades.where((a) => a.estado == 'aceptada').toList();
  List<Amistad> get pendientesParaMi => amistades.where((a) => a.estado == 'pendiente' && !a.laPedi).toList();
  List<Amistad> get pendientesMias => amistades.where((a) => a.estado == 'pendiente' && a.laPedi).toList();

  Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    servidor = _p!.getString('cuenta_servidor') ?? servidorPorDefecto;
    token = _p!.getString('cuenta_token');
    userId = _p!.getString('cuenta_id');
    email = _p!.getString('cuenta_email');
    nombre = _p!.getString('cuenta_nombre');
    if (dentro) unawaited(_refrescarSesion());
  }

  void setServidor(String s) {
    var v = s.trim();
    if (v.isNotEmpty && !v.startsWith('http')) v = 'https://$v';
    servidor = v.replaceAll(RegExp(r'/+$'), '');
    _p?.setString('cuenta_servidor', servidor);
    notifyListeners();
  }

  Uri _u(String path, [Map<String, String>? q]) => Uri.parse('$servidor$path').replace(queryParameters: q);
  Map<String, String> get _h => {'Content-Type': 'application/json', 'Authorization': ?token};

  Future<dynamic> _req(String metodo, String path, {Object? body, Map<String, String>? q}) async {
    if (!configurado) throw CuentaError('Falta la dirección del servidor de Hangar.');
    final req = http.Request(metodo, _u(path, q))..headers.addAll(_h);
    if (body != null) req.body = jsonEncode(body);
    final res = await http.Response.fromStream(await req.send().timeout(const Duration(seconds: 15)));
    final data = res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
    if (res.statusCode >= 400) {
      if (res.statusCode == 401) await salir();
      final msg = data is Map ? (data['message'] ?? '') : '';
      final campos = data is Map && data['data'] is Map
          ? (data['data'] as Map).values.map((v) => v is Map ? v['message'] : '').where((m) => '$m'.isNotEmpty).join(' ')
          : '';
      throw CuentaError([msg, campos].where((s) => '$s'.isNotEmpty).join(' · ').ifEmpty('Error ${res.statusCode}'));
    }
    return data;
  }

  Future<T?> _hacer<T>(Future<T> Function() f) async {
    ocupado = true;
    error = null;
    notifyListeners();
    try {
      return await f();
    } on CuentaError catch (e) {
      error = e.msg;
    } catch (e) {
      error = 'No hay conexión con el servidor.';
      debugPrint('$e');
    } finally {
      ocupado = false;
      notifyListeners();
    }
    return null;
  }

  void _guardarSesion(Map data) {
    token = data['token'];
    final r = data['record'] as Map;
    userId = r['id'];
    email = r['email'];
    nombre = r['nombre'] ?? '';
    _p?.setString('cuenta_token', token!);
    _p?.setString('cuenta_id', userId!);
    _p?.setString('cuenta_email', email ?? '');
    _p?.setString('cuenta_nombre', nombre ?? '');
  }

  Future<bool> registrar(String email, String pass, String nombre) async =>
      await _hacer(() async {
        await _req(
          'POST',
          '/api/collections/users/records',
          body: {'email': email, 'password': pass, 'passwordConfirm': pass, 'nombre': nombre, 'emailVisibility': false},
        );
        _guardarSesion(await _req('POST', '/api/collections/users/auth-with-password', body: {'identity': email, 'password': pass}));
        return true;
      }) ??
      false;

  Future<bool> entrar(String email, String pass) async =>
      await _hacer(() async {
        _guardarSesion(await _req('POST', '/api/collections/users/auth-with-password', body: {'identity': email, 'password': pass}));
        return true;
      }) ??
      false;

  Future<void> salir() async {
    token = userId = email = nombre = null;
    amistades = const [];
    actividad.clear();
    for (final k in ['cuenta_token', 'cuenta_id', 'cuenta_email', 'cuenta_nombre']) {
      await _p?.remove(k);
    }
    notifyListeners();
  }

  Future<void> _refrescarSesion() async {
    try {
      _guardarSesion(await _req('POST', '/api/collections/users/auth-refresh'));
      await cargarAmigos();
    } catch (_) {}
    notifyListeners();
  }

  Future<void> cambiarNombre(String n) async {
    if (!dentro) return;
    await _hacer(() async {
      await _req('PATCH', '/api/collections/users/records/$userId', body: {'nombre': n});
      nombre = n;
      _p?.setString('cuenta_nombre', n);
    });
  }

  // ───────────────────────── sincronizar ─────────────────────────

  /// Sube tus horas por juego y tus logros de Hangar (se llama sola tras jugar; espera unos segundos).
  void sincronizarPronto(Installer ins, Perfil perfil, List<Juego> juegos) {
    if (!dentro) return;
    _sync?.cancel();
    _sync = Timer(const Duration(seconds: 6), () => sincronizar(ins, perfil, juegos));
  }

  Future<void> sincronizar(Installer ins, Perfil perfil, List<Juego> juegos) async {
    if (!dentro) return;
    try {
      final plat = catalogoMac ? 'mac' : 'android';
      final mias = await _req('GET', '/api/collections/partidas/records', q: {'filter': "user='$userId' && plataforma='$plat'", 'perPage': '500'}) as Map;
      final existentes = {for (final r in mias['items'] as List) r['juego']: r};
      for (final j in juegos) {
        final s = ins.segundos(j), u = ins.ultima(j);
        if (s == 0 && u == null) continue;
        final body = {'user': userId, 'juego': j.id, 'nombre': j.nombre, 'plataforma': plat, 'segundos': s, 'ultima': u?.toUtc().toIso8601String()};
        final prev = existentes[j.id];
        if (prev == null) {
          await _req('POST', '/api/collections/partidas/records', body: body);
        } else if ((prev['segundos'] ?? 0) != s) {
          await _req('PATCH', '/api/collections/partidas/records/${prev['id']}', body: body);
        }
      }
      final ya = await _req('GET', '/api/collections/desbloqueos/records', q: {'filter': "user='$userId' && fuente='hangar'", 'perPage': '200'}) as Map;
      final tengo = {for (final r in ya['items'] as List) r['logro']};
      for (final e in perfil.ganados.entries) {
        if (tengo.contains(e.key)) continue;
        await _req(
          'POST',
          '/api/collections/desbloqueos/records',
          body: {'user': userId, 'juego': 'hangar', 'fuente': 'hangar', 'logro': e.key, 'fecha': e.value.toUtc().toIso8601String()},
        );
      }
    } catch (e) {
      debugPrint('sincronizar: $e');
    }
  }

  // ───────────────────────── amigos ─────────────────────────

  Future<void> cargarAmigos() async {
    if (!dentro) return;
    await _hacer(() async {
      final res = await _req('GET', '/api/collections/amistades/records', q: {'expand': 'de,para', 'perPage': '200'}) as Map;
      amistades = [
        for (final r in res['items'] as List)
          () {
            final laPedi = r['de'] == userId;
            final otro = (r['expand'] as Map?)?[laPedi ? 'para' : 'de'] as Map?;
            return Amistad(r['id'], r['estado'], Amigo(otro?['id'] ?? '', (otro?['nombre'] as String?)?.ifEmpty('Sin nombre') ?? 'Sin nombre'), laPedi);
          }(),
      ];
      for (final a in amigos) {
        final p = await _req('GET', '/api/collections/partidas/records', q: {'filter': "user='${a.otro.id}'", 'sort': '-ultima', 'perPage': '5'}) as Map;
        actividad[a.otro.id] = [
          for (final r in p['items'] as List)
            Partida(r['juego'], r['nombre'] ?? r['juego'], r['plataforma'], (r['segundos'] as num?)?.toInt() ?? 0, DateTime.tryParse(r['ultima'] ?? '')),
        ];
      }
    });
  }

  Future<List<Amigo>> buscar(String q) async {
    if (!dentro || q.trim().length < 2) return const [];
    final limpio = q.trim().replaceAll("'", '');
    final res = await _hacer(() => _req('GET', '/api/collections/users/records', q: {'filter': "nombre~'$limpio' && id!='$userId'", 'perPage': '20'}));
    if (res is! Map) return const [];
    return [for (final r in res['items'] as List) Amigo(r['id'], (r['nombre'] as String?)?.ifEmpty('Sin nombre') ?? 'Sin nombre')];
  }

  Future<void> pedir(Amigo a) async {
    await _hacer(() => _req('POST', '/api/collections/amistades/records', body: {'de': userId, 'para': a.id, 'estado': 'pendiente'}));
    await cargarAmigos();
  }

  Future<void> aceptar(Amistad a) async {
    await _hacer(() => _req('PATCH', '/api/collections/amistades/records/${a.id}', body: {'estado': 'aceptada'}));
    await cargarAmigos();
  }

  Future<void> quitar(Amistad a) async {
    await _hacer(() => _req('DELETE', '/api/collections/amistades/records/${a.id}'));
    await cargarAmigos();
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
