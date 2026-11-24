import 'package:material_ui/material_ui.dart';

import 'amigos.dart';
import 'cuenta.dart';
import 'data.dart';
import 'installer.dart';
import 'logros.dart';
import 'theme.dart';
import 'widgets.dart';

class _Page extends StatelessWidget {
  final String title, lead;
  final List<Widget> children;
  const _Page({required this.title, required this.lead, required this.children});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final compact = box.maxHeight < 560;
      return ListView(
        padding: EdgeInsets.fromLTRB(compact ? 28 : 64, compact ? 24 : 48, compact ? 28 : 64, 48),
        children: [
          Text(title, style: T.serif(size: compact ? 40 : 56)),
          const SizedBox(height: 8),
          Text(lead, style: T.sans(size: 15, color: C.ink2)),
          SizedBox(height: compact ? 22 : 34),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ],
      );
    },
  );
}

String _horas(int s) => s < 3600 ? '${(s / 60).floor()} min' : '${(s / 3600).toStringAsFixed(1).replaceAll('.', ',')} h';

class LogrosScreen extends StatelessWidget {
  final Perfil perfil;
  final Installer installer;
  final List<Juego> recientes;
  final ValueChanged<Juego> onPick;
  const LogrosScreen({super.key, required this.perfil, required this.installer, required this.recientes, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final hechos = hitos.where((h) => perfil.ganados.containsKey(h.id)).length;
    return _Page(
      title: 'Logros',
      lead: '$hechos de ${hitos.length} logros de Hangar · ${_horas(installer.segundosTotales)} jugadas · ${installer.instaladosAhora} ports instalados',
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(value: hechos / hitos.length, minHeight: 4, color: C.acc, backgroundColor: const Color(0x1AFFFFFF)),
        ),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, box) {
            final cols = (box.maxWidth / 300).floor().clamp(1, 3);
            final w = (box.maxWidth - (cols - 1) * 14) / cols;
            return Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                for (final h in hitos)
                  SizedBox(
                    width: w,
                    child: _Medalla(h, perfil: perfil, installer: installer),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 34),
        Panel(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              const Icon(Icons.emoji_events_outlined, color: C.ink3, size: 28),
              const SizedBox(width: 18),
              Expanded(
                child: Text(
                  'Los logros de cada juego aparecerán en su pantalla cuando el port los publique. Estos de aquí son de Hangar y se ganan jugando a cualquier cosa.',
                  style: T.sans(size: 14, color: C.ink2, height: 1.5),
                ),
              ),
            ],
          ),
        ),
        if (recientes.isNotEmpty) ...[
          const SizedBox(height: 34),
          Text('VISTOS HACE POCO', style: T.label(size: 11, w: FontWeight.w600)),
          const SizedBox(height: 12),
          for (final j in recientes)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Panel(
                onTap: () => onPick(j),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    SizedBox(width: 44, height: 62, child: Cover(j, radius: 8, compact: true)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(j.nombre, style: T.sans(size: 15, w: FontWeight.w600)),
                          Text(
                            installer.segundos(j) == 0 ? 'Sin jugar todavía' : '${_horas(installer.segundos(j))} jugadas',
                            style: T.sans(size: 13, color: C.ink2),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: C.ink3),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _Medalla extends StatelessWidget {
  final Hito h;
  final Perfil perfil;
  final Installer installer;
  const _Medalla(this.h, {required this.perfil, required this.installer});

  @override
  Widget build(BuildContext context) {
    final fecha = perfil.ganados[h.id];
    final ok = fecha != null;
    final p = h.progreso(installer, perfil);
    return Opacity(
      opacity: ok ? 1 : .62,
      child: Panel(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: ok
                    ? RadialGradient(
                        center: const Alignment(-.4, -.5),
                        colors: [Color.lerp(h.color, Colors.white, .35)!, h.color, Color.lerp(h.color, Colors.black, .4)!],
                      )
                    : null,
                color: ok ? null : C.glass,
                boxShadow: ok ? [BoxShadow(color: h.color.withValues(alpha: .35), blurRadius: 22, offset: const Offset(0, 8))] : null,
              ),
              child: Icon(ok ? h.icon : Icons.lock_outline_rounded, color: ok ? Colors.white : C.ink3, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(h.titulo, style: T.sans(size: 15, w: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(h.texto, style: T.sans(size: 13, color: C.ink2, height: 1.35)),
                  const SizedBox(height: 8),
                  if (ok)
                    Text(
                      'CONSEGUIDO EL ${fecha.day}/${fecha.month}/${fecha.year}',
                      style: T.label(size: 10, color: h.color, w: FontWeight.w600),
                    )
                  else
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(value: p, minHeight: 3, color: h.color, backgroundColor: const Color(0x1AFFFFFF)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AjustesScreen extends StatefulWidget {
  final CatalogStore store;
  final Ajustes ajustes;
  final Perfil perfil;
  final Installer installer;
  final Cuenta cuenta;
  const AjustesScreen({super.key, required this.store, required this.ajustes, required this.perfil, required this.installer, required this.cuenta});
  @override
  State<AjustesScreen> createState() => _AjustesScreenState();
}

class _AjustesScreenState extends State<AjustesScreen> {
  late final _nombre = TextEditingController(text: widget.perfil.nombre);

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.store, widget.ajustes, widget.installer, widget.cuenta]),
    builder: (context, _) {
      final store = widget.store, ajustes = widget.ajustes, ins = widget.installer;
      final c = store.catalogo;
      final when = c.actualizado == null
          ? 'la copia que trae la app'
          : 'descargado ${c.actualizado!.day}/${c.actualizado!.month} a las ${c.actualizado!.hour.toString().padLeft(2, '0')}:${c.actualizado!.minute.toString().padLeft(2, '0')}';
      final listos = c.juegos.where((j) => j.listo).length;
      Widget toggle(String t, String d, bool v, ValueChanged<bool> f) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Panel(
          onTap: () => f(!v),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t, style: T.sans(size: 15, w: FontWeight.w600)),
                    Text(d, style: T.sans(size: 13, color: C.ink2)),
                  ],
                ),
              ),
              Switch(value: v, onChanged: f, activeTrackColor: C.acc, activeThumbColor: Colors.white),
            ],
          ),
        ),
      );
      Widget row(String t, String d, Widget trailing) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Panel(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t, style: T.sans(size: 15, w: FontWeight.w600)),
                    Text(d, style: T.sans(size: 13, color: C.ink2)),
                  ],
                ),
              ),
              trailing,
            ],
          ),
        ),
      );
      return _Page(
        title: 'Ajustes',
        lead: 'Lo justo para jugar a gusto.',
        children: [
          row(
            'Cuenta de Hangar',
            widget.cuenta.dentro
                ? 'Conectado como ${widget.cuenta.email}. Tus horas y logros se guardan en el servidor.'
                : 'Sin cuenta: tus horas y logros solo están en este dispositivo.',
            widget.cuenta.dentro
                ? TextButton(
                    onPressed: widget.cuenta.salir,
                    child: Text(
                      'SALIR',
                      style: T.label(size: 12, color: C.ink, w: FontWeight.w600),
                    ),
                  )
                : TextButton(
                    onPressed: () => abrirCuenta(context, widget.cuenta, widget.perfil),
                    child: Text(
                      'ENTRAR',
                      style: T.label(size: 12, color: C.ink, w: FontWeight.w600),
                    ),
                  ),
          ),
          row(
            'Tu nombre',
            'Sale en tu perfil y en la barra lateral.',
            SizedBox(
              width: 240,
              child: TextField(
                controller: _nombre,
                style: T.sans(size: 14),
                textInputAction: TextInputAction.done,
                onSubmitted: (v) {
                  widget.perfil.setNombre(v);
                  widget.cuenta.cambiarNombre(v.trim());
                },
                onTapOutside: (_) {
                  if (_nombre.text.trim() == widget.perfil.nombre) return;
                  widget.perfil.setNombre(_nombre.text);
                  widget.cuenta.cambiarNombre(_nombre.text.trim());
                },
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Escribe tu nombre',
                  hintStyle: T.sans(size: 14, color: C.ink3),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: C.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0x59FFFFFF)),
                  ),
                ),
              ),
            ),
          ),
          row(
            'Catálogo',
            store.cargando
                ? 'Buscando la última versión…'
                : '${c.juegos.length} juegos, $listos listos para instalar aquí · $when${store.error != null ? ' · sin conexión' : ''}',
            TextButton(
              onPressed: store.cargando ? null : store.refresh,
              child: Text(
                'ACTUALIZAR',
                style: T.label(size: 12, color: store.cargando ? C.ink3 : C.ink, w: FontWeight.w600),
              ),
            ),
          ),
          if (ins.esAndroid)
            row(
              'Contar tiempo de juego',
              ins.permisoUso
                  ? 'Activado: Hangar lee del sistema cuánto juegas a cada port.'
                  : 'Android pide permiso de «acceso a uso» para saber cuánto juegas.',
              ins.permisoUso
                  ? const Icon(Icons.check_circle_rounded, color: C.ok)
                  : TextButton(
                      onPressed: ins.pedirPermisoUso,
                      child: Text(
                        'DAR PERMISO',
                        style: T.label(size: 12, color: C.ink, w: FontWeight.w600),
                      ),
                    ),
            ),
          toggle('Vibración', 'Un toque corto al cambiar de juego.', ajustes.vibracion, (v) => ajustes.set(vib: v)),
          toggle('Chispas de fondo', 'Las chispas que suben detrás del juego.', ajustes.chispas, (v) => ajustes.set(fx: v)),
          const SizedBox(height: 14),
          Text(
            'Mando: cruceta o stick para moverte, A para aceptar, B para volver, L1 y R1 para cambiar de sección.',
            style: T.sans(size: 13, color: C.ink3, height: 1.5),
          ),
          const SizedBox(height: 10),
          Text('Hangar 0.4 · Arte de SteamGridDB', style: T.sans(size: 12, color: C.ink3)),
        ],
      );
    },
  );
}
