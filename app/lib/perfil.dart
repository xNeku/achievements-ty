import 'package:material_ui/material_ui.dart';

import 'cuenta.dart';
import 'data.dart';
import 'installer.dart';
import 'logros.dart';
import 'theme.dart';
import 'widgets.dart';

String _horas(int s) => s < 3600 ? '${(s / 60).floor()} min' : '${(s / 3600).toStringAsFixed(1).replaceAll('.', ',')} h';

String _hace(DateTime? d) {
  if (d == null) return 'Sin jugar';
  final m = DateTime.now().difference(d).inMinutes;
  if (m < 60) return 'Hace un rato';
  if (m < 60 * 24) return 'Hoy';
  if (m < 60 * 48) return 'Ayer';
  if (m < 60 * 24 * 7) return 'Hace ${m ~/ (60 * 24)} días';
  return '${d.day}/${d.month}/${d.year}';
}

/// Tu perfil: quién eres, cuánto has jugado, qué has conseguido y a qué has jugado últimamente.
class PerfilScreen extends StatelessWidget {
  final Perfil perfil;
  final Installer installer;
  final Cuenta cuenta;
  final List<Juego> juegos;
  final ValueChanged<Juego> onPick;
  final VoidCallback onAmigos, onAjustes, onLogros;
  const PerfilScreen({
    super.key,
    required this.perfil,
    required this.installer,
    required this.cuenta,
    required this.juegos,
    required this.onPick,
    required this.onAmigos,
    required this.onAjustes,
    required this.onLogros,
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([perfil, installer, cuenta]),
        builder: (context, _) => LayoutBuilder(builder: (context, box) {
          final compact = box.maxHeight < 560;
          final porRepo = {for (final j in juegos) for (final r in j.repos) r.repo: j};
          // Juegos a los que has jugado, del más reciente al más antiguo
          final jugados = <Juego, ({int segundos, DateTime? ultima})>{};
          for (final e in installer.todos) {
            final j = porRepo[e.key];
            if (j == null) continue;
            final prev = jugados[j];
            final u = e.value.ultima;
            jugados[j] = (
              segundos: (prev?.segundos ?? 0) + e.value.segundos,
              ultima: prev?.ultima == null || (u != null && u.isAfter(prev!.ultima!)) ? u : prev?.ultima,
            );
          }
          final recientes = jugados.entries.toList()
            ..sort((a, b) => (b.value.ultima ?? DateTime(2000)).compareTo(a.value.ultima ?? DateTime(2000)));
          final ganados = hitos.where((h) => perfil.ganados.containsKey(h.id)).toList()
            ..sort((a, b) => perfil.ganados[b.id]!.compareTo(perfil.ganados[a.id]!));
          final nombre = perfil.nombre.isEmpty ? 'Sin nombre' : perfil.nombre;

          Widget stat(String v, String l) => Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: compact ? 16 : 24),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(v, style: T.sans(size: compact ? 28 : 38, w: FontWeight.w300, height: 1)),
                    const SizedBox(height: 8),
                    Text(l.toUpperCase(), style: T.label(size: 11)),
                  ]),
                ),
              );

          return ListView(
            padding: EdgeInsets.fromLTRB(compact ? 28 : 64, compact ? 24 : 48, compact ? 28 : 64, 48),
            children: [
              // Cabecera
              Row(children: [
                Avatar(letter: perfil.inicial, size: compact ? 76 : 108, glow: C.pink, online: cuenta.dentro),
                SizedBox(width: compact ? 20 : 32),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(nombre, style: T.serif(size: compact ? 40 : 60)),
                    const SizedBox(height: 6),
                    Text(
                      cuenta.dentro ? 'Cuenta de Hangar · ${cuenta.amigos.length} amigos' : 'Solo en este dispositivo · sin cuenta',
                      style: T.sans(size: 14, color: C.ink2),
                    ),
                  ]),
                ),
                TextButton.icon(
                  onPressed: onAjustes,
                  icon: const Icon(Icons.edit_outlined, size: 16, color: C.ink2),
                  label: Text('EDITAR', style: T.label(size: 11, color: C.ink2, w: FontWeight.w600)),
                ),
              ]),
              SizedBox(height: compact ? 22 : 34),
              // Números
              Container(
                decoration: BoxDecoration(color: const Color(0xD1120E11), borderRadius: BorderRadius.circular(22), border: Border.all(color: C.line)),
                child: IntrinsicHeight(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    stat(_horas(installer.segundosTotales), 'Jugadas'),
                    const VerticalDivider(width: 1, color: C.line),
                    stat('${jugados.values.where((v) => v.ultima != null).length}', 'Juegos jugados'),
                    const VerticalDivider(width: 1, color: C.line),
                    stat('${installer.instaladosAhora}', 'Instalados'),
                    const VerticalDivider(width: 1, color: C.line),
                    stat('${ganados.length}/${hitos.length}', 'Logros de Hangar'),
                  ]),
                ),
              ),
              SizedBox(height: compact ? 28 : 44),
              // Jugando últimamente
              Row(children: [
                Expanded(child: Text('Jugando últimamente', style: T.serif(size: compact ? 30 : 40))),
              ]),
              const SizedBox(height: 16),
              if (recientes.isEmpty)
                Panel(
                  padding: const EdgeInsets.all(24),
                  child: Text('Todavía no has jugado con Hangar. Instala un juego desde la biblioteca y aparecerá aquí.', style: T.sans(size: 14, color: C.ink2, height: 1.5)),
                )
              else
                SizedBox(
                  height: compact ? 210 : 260,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: recientes.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 16),
                    itemBuilder: (context, i) {
                      final e = recientes[i];
                      return SizedBox(
                        width: compact ? 120 : 150,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => onPick(e.key),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            AspectRatio(aspectRatio: 2 / 3, child: Cover(e.key, radius: 14)),
                            const SizedBox(height: 8),
                            Text(e.key.nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.sans(size: 13, w: FontWeight.w600)),
                            Text('${_horas(e.value.segundos)} · ${_hace(e.value.ultima)}', maxLines: 1, style: T.sans(size: 12, color: C.ink2)),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
              SizedBox(height: compact ? 28 : 44),
              // Logros de Hangar ganados
              Row(children: [
                Expanded(child: Text('Últimos logros', style: T.serif(size: compact ? 30 : 40))),
                TextButton(onPressed: onLogros, child: Text('VER TODOS', style: T.label(size: 11, color: C.ink, w: FontWeight.w600))),
              ]),
              const SizedBox(height: 16),
              if (ganados.isEmpty)
                Text('Aún no has ganado ninguno. El primero cae en cuanto instales un juego.', style: T.sans(size: 14, color: C.ink2))
              else
                Wrap(spacing: 12, runSpacing: 12, children: [
                  for (final h in ganados.take(6))
                    Container(
                      padding: const EdgeInsets.fromLTRB(10, 10, 18, 10),
                      decoration: BoxDecoration(color: const Color(0xC7120E11), borderRadius: BorderRadius.circular(16), border: Border.all(color: C.line)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(color: h.color, borderRadius: BorderRadius.circular(12)),
                          child: Icon(h.icon, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(h.titulo, style: T.sans(size: 14, w: FontWeight.w600)),
                          Text(_hace(perfil.ganados[h.id]), style: T.sans(size: 12, color: C.ink3)),
                        ]),
                      ]),
                    ),
                ]),
              if (cuenta.dentro && cuenta.amigos.isNotEmpty) ...[
                SizedBox(height: compact ? 28 : 44),
                Row(children: [
                  Expanded(child: Text('Tus amigos', style: T.serif(size: compact ? 30 : 40))),
                  TextButton(onPressed: onAmigos, child: Text('VER TODOS', style: T.label(size: 11, color: C.ink, w: FontWeight.w600))),
                ]),
                const SizedBox(height: 16),
                Wrap(spacing: 18, runSpacing: 14, children: [
                  for (final a in cuenta.amigos.take(8))
                    InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => verPerfilAmigo(context, cuenta, a.otro),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Column(children: [
                          Avatar(letter: a.otro.inicial, size: 54, online: false),
                          const SizedBox(height: 6),
                          Text(a.otro.nombre, style: T.sans(size: 12, color: C.ink2)),
                        ]),
                      ),
                    ),
                ]),
              ],
            ],
          );
        }),
      );
}

/// El perfil de un amigo: a qué ha jugado y cuánto.
Future<void> verPerfilAmigo(BuildContext context, Cuenta cuenta, Amigo a) => showDialog(
      context: context,
      builder: (context) {
        final act = cuenta.actividad[a.id] ?? const <Partida>[];
        final total = act.fold<int>(0, (s, p) => s + p.segundos);
        return Dialog(
          backgroundColor: C.panel,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Avatar(letter: a.inicial, size: 64, online: false, glow: C.pink),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(a.nombre, style: T.serif(size: 34)),
                      Text('${_horas(total)} jugadas en sus últimos juegos', style: T.sans(size: 13, color: C.ink2)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 22),
                if (act.isEmpty)
                  Text('Todavía no ha jugado con Hangar.', style: T.sans(size: 14, color: C.ink2))
                else
                  for (final p in act)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Panel(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(children: [
                          Expanded(child: Text(p.nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.sans(size: 14, w: FontWeight.w600))),
                          Text('${_horas(p.segundos)} · ${_hace(p.ultima)}', style: T.sans(size: 12, color: C.ink2)),
                        ]),
                      ),
                    ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: () => Navigator.pop(context), child: Text('CERRAR', style: T.label(size: 12, color: C.ink, w: FontWeight.w600))),
                ),
              ]),
            ),
          ),
        );
      },
    );
