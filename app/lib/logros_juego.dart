import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'data.dart';
import 'idioma.dart';
import 'theme.dart';
import 'widgets.dart';

/// Un logro de la lista de un juego.
class LogroJuego {
  final String nombre, descripcion;
  final int puntos;
  final String? icono;
  final bool secreto;
  const LogroJuego(this.nombre, this.descripcion, this.puntos, this.icono, this.secreto);
}

class SetLogros {
  final String fuente, nombre;
  final int total, puntos;
  final List<LogroJuego> logros;
  const SetLogros(this.fuente, this.nombre, this.total, this.puntos, this.logros);
}

final Map<String, Future<List<SetLogros>>> _cache = {};

/// Carga la lista de logros de un juego desde la base de datos que lleva la app.
Future<List<SetLogros>> cargarLogros(Juego j) => _cache.putIfAbsent(j.id, () async {
  if (j.logros.isEmpty) return const [];
  try {
    final raw = await rootBundle.loadString('assets/logros/${catalogoMac ? 'mac' : 'android'}/${j.id}.json');
    final d = jsonDecode(raw) as Map<String, dynamic>;
    return [
      for (final s in (d['sets'] as List))
        SetLogros('${s['fuente']}', '${s['nombre']}', (s['total'] as num?)?.toInt() ?? 0, (s['puntos'] as num?)?.toInt() ?? 0, [
          for (final l in (s['logros'] as List))
            LogroJuego('${l['nombre'] ?? ''}', '${l['descripcion'] ?? ''}', (l['puntos'] as num?)?.toInt() ?? 0, l['icono'] as String?, l['tipo'] == 'secreto'),
        ]),
    ];
  } catch (_) {
    return const [];
  }
});

final Map<String, Uint8List> _iconos = {};

Widget _icono(String? src, {double size = 58}) {
  Widget fallback = Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      color: C.glass,
      border: Border.all(color: C.line),
    ),
    child: const Icon(Icons.emoji_events_outlined, color: C.ink3),
  );
  if (src == null) return fallback;
  final Widget img;
  if (src.startsWith('data:')) {
    final bytes = _iconos.putIfAbsent(src, () => UriData.parse(src).contentAsBytes());
    img = Image.memory(bytes, width: size, height: size, fit: BoxFit.cover, gaplessPlayback: true);
  } else {
    img = SizedBox(
      width: size,
      height: size,
      child: NetImg(src, fallback: fallback),
    );
  }
  return ClipRRect(borderRadius: BorderRadius.circular(14), child: img);
}

/// La sección «Logros» de la pantalla de un juego.
class LogrosDelJuego extends StatefulWidget {
  final Juego juego;
  const LogrosDelJuego(this.juego, {super.key});
  @override
  State<LogrosDelJuego> createState() => _LogrosDelJuegoState();
}

class _LogrosDelJuegoState extends State<LogrosDelJuego> {
  int _set = 0;

  @override
  void didUpdateWidget(LogrosDelJuego old) {
    super.didUpdateWidget(old);
    if (old.juego.id != widget.juego.id) _set = 0;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<SetLogros>>(
    future: cargarLogros(widget.juego),
    builder: (context, snap) {
      final sets = snap.data ?? const <SetLogros>[];
      if (snap.connectionState != ConnectionState.done) return const SizedBox(height: 120);
      if (sets.isEmpty) {
        return Panel(
          padding: const EdgeInsets.all(28),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: C.glass,
                  border: Border.all(color: C.line),
                ),
                child: const Icon(Icons.emoji_events_outlined, color: C.ink3, size: 26),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Text(
                  t('Todavía no tenemos la lista de logros de este juego. La base de datos de Hangar crece cada semana.'),
                  style: T.sans(size: 15, color: C.ink2, height: 1.5),
                ),
              ),
            ],
          ),
        );
      }
      final s = sets[_set.clamp(0, sets.length - 1)];
      final unidad = s.fuente.startsWith('xbox') ? 'G' : 'pts';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(t('{0} logros · {1} {2} · lista de {3}', [s.total, s.puntos, unidad, fuenteLabel[s.fuente] ?? s.fuente]), style: T.sans(size: 14, color: C.ink2)),
              ),
              if (sets.length > 1)
                for (var i = 0; i < sets.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: ChoiceChip(
                      label: Text(fuenteLabel[sets[i].fuente] ?? sets[i].fuente, style: T.sans(size: 12)),
                      selected: i == _set,
                      onSelected: (_) => setState(() => _set = i),
                      showCheckmark: false,
                      selectedColor: const Color(0x2EFFFFFF),
                      backgroundColor: const Color(0x0DFFFFFF),
                      side: const BorderSide(color: C.line),
                    ),
                  ),
            ],
          ),
          const SizedBox(height: 8),
          Text(t('Se desbloquearán cuando el port avise a Hangar. Por ahora puedes ver qué te espera.'), style: T.sans(size: 12, color: C.ink3)),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, box) {
              final cols = (box.maxWidth / 320).floor().clamp(1, 4);
              final w = (box.maxWidth - (cols - 1) * 12) / cols;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final l in s.logros)
                    SizedBox(
                      width: w,
                      child: Panel(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Opacity(opacity: .85, child: _icono(l.icono, size: 52)),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l.nombre,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: T.sans(size: 14, w: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    l.secreto && l.descripcion.isEmpty ? t('Logro secreto') : l.descripcion,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: T.sans(size: 12.5, color: C.ink2, height: 1.35),
                                  ),
                                  if (l.puntos > 0) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      '${l.puntos} $unidad',
                                      style: T.label(size: 10, color: C.ink3, w: FontWeight.w600),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      );
    },
  );
}
