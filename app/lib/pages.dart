import 'package:material_ui/material_ui.dart';

import 'amigos.dart';
import 'comunidad.dart';
import 'idioma.dart';
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

String _horas(int s) => s < 3600 ? '${(s / 60).floor()} min' : '${(s / 3600).toStringAsFixed(1).replaceAll('.', idioma.ingles ? '.' : ',')} h';

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
      title: t('Logros'),
      lead: t('{0} de {1} logros de Hangar · {2} jugadas · {3} ports instalados', [hechos, hitos.length, _horas(installer.segundosTotales), installer.instaladosAhora]),
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
                  t('Los logros de cada juego aparecerán en su pantalla cuando el port los publique. Estos de aquí son de Hangar y se ganan jugando a cualquier cosa.'),
                  style: T.sans(size: 14, color: C.ink2, height: 1.5),
                ),
              ),
            ],
          ),
        ),
        if (recientes.isNotEmpty) ...[
          const SizedBox(height: 34),
          Text(t('VISTOS HACE POCO'), style: T.label(size: 11, w: FontWeight.w600)),
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
                            installer.segundos(j) == 0 ? t('Sin jugar todavía') : t('{0} jugadas', [_horas(installer.segundos(j))]),
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
                      t('CONSEGUIDO EL {0}/{1}/{2}', [fecha.day, fecha.month, fecha.year]),
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
          ? t('la copia que trae la app')
          : t('descargado {0}/{1} a las {2}:{3}', [c.actualizado!.day, c.actualizado!.month, c.actualizado!.hour.toString().padLeft(2, '0'), c.actualizado!.minute.toString().padLeft(2, '0')]);
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
        title: t('Ajustes'),
        lead: t('Lo justo para jugar a gusto.'),
        children: [
          row(
            t('Cuenta de Hangar'),
            widget.cuenta.dentro
                ? t('Conectado como {0}. Tus horas y logros se guardan en el servidor.', [widget.cuenta.email])
                : widget.cuenta.configurado ? t('Sin cuenta: tus horas y logros solo están en este dispositivo. Servidor: {0}', [widget.cuenta.servidor]) : t('Sin cuenta: tus horas y logros solo están en este dispositivo.'),
            widget.cuenta.dentro
                ? TextButton(
                    onPressed: widget.cuenta.salir,
                    child: Text(
                      t('SALIR'),
                      style: T.label(size: 12, color: C.ink, w: FontWeight.w600),
                    ),
                  )
                : TextButton(
                    onPressed: () => abrirCuenta(context, widget.cuenta, widget.perfil),
                    child: Text(
                      t('ENTRAR'),
                      style: T.label(size: 12, color: C.ink, w: FontWeight.w600),
                    ),
                  ),
          ),
          row(
            t('Tu nombre'),
            t('Sale en tu perfil y en la barra lateral.'),
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
                  hintText: t('Escribe tu nombre'),
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
            t('Catálogo'),
            store.cargando
                ? t('Buscando la última versión…')
                : t('{0} juegos, {1} listos para instalar aquí · {2}{3}', [c.juegos.length, listos, when, store.error != null ? t(' · sin conexión') : '']),
            TextButton(
              onPressed: store.cargando ? null : store.refresh,
              child: Text(
                t('ACTUALIZAR'),
                style: T.label(size: 12, color: store.cargando ? C.ink3 : C.ink, w: FontWeight.w600),
              ),
            ),
          ),
          row(
            t('¿Haces ports?'),
            t('Publícalos en Hangar: rellena el formulario o pon el tema «hangar-port» en tu repo. Con un hangar.json decides cómo sale y lleva el sello del autor.'),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: comoPublicar,
                  child: Text(t('CÓMO FUNCIONA'), style: T.label(size: 12, color: C.ink2, w: FontWeight.w600)),
                ),
                TextButton(
                  onPressed: publicarPort,
                  child: Text(t('PUBLICAR'), style: T.label(size: 12, color: C.ink, w: FontWeight.w600)),
                ),
              ],
            ),
          ),
          if (ins.esAndroid)
            row(
              t('Tiempo de juego exacto'),
              ins.permisoUso
                  ? t('Activado: Hangar lee del sistema cuánto juegas a cada port.')
                  : t('Sin permiso, Hangar cuenta desde que abres un juego hasta que vuelves. Con el permiso de «acceso a uso» lo mide el sistema, al minuto.'),
              ins.permisoUso
                  ? const Icon(Icons.check_circle_rounded, color: C.ok)
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () => _permisoGris(context, ins),
                          child: Text(t('¿SALE EN GRIS?'), style: T.label(size: 12, color: C.ink2, w: FontWeight.w600)),
                        ),
                        TextButton(
                          onPressed: ins.pedirPermisoUso,
                          child: Text(t('DAR PERMISO'), style: T.label(size: 12, color: C.ink, w: FontWeight.w600)),
                        ),
                      ],
                    ),
            ),
          row(
            t('Idioma'),
            t('También se cambia con la bandera de la barra lateral.'),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (c, n) in const [('es', 'Español'), ('en', 'English')])
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: ChoiceChip(
                      selected: idioma.codigo == c,
                      onSelected: (_) => idioma.poner(c),
                      showCheckmark: false,
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      labelPadding: const EdgeInsets.only(left: 4, right: 6),
                      avatar: Bandera(c, ancho: 20),
                      label: Text(n, style: T.sans(size: 13)),
                      selectedColor: const Color(0x33E8463B),
                      backgroundColor: Colors.transparent,
                      side: BorderSide(color: idioma.codigo == c ? C.acc : C.line),
                    ),
                  ),
              ],
            ),
          ),
          toggle(t('Vibración'), t('Un toque corto al cambiar de juego.'), ajustes.vibracion, (v) => ajustes.set(vib: v)),
          toggle(t('Chispas de fondo'), t('Las chispas que suben detrás del juego.'), ajustes.chispas, (v) => ajustes.set(fx: v)),
          toggle(t('Empezar en Big Picture'), t('Hangar se abre directamente en el modo tele, para jugar con mando.'), ajustes.empezarBig, (v) => ajustes.set(big: v)),
          const SizedBox(height: 14),
          Text(
            t('Mando: cruceta o stick para moverte, A para aceptar, B para volver, L1 y R1 para cambiar de sección, Start para el modo Big Picture.'),
            style: T.sans(size: 13, color: C.ink3, height: 1.5),
          ),
          const SizedBox(height: 10),
          Text(t('Hangar 0.5 · Arte de SteamGridDB'), style: T.sans(size: 12, color: C.ink3)),
        ],
      );
    },
  );
}

/// Android 13+ bloquea algunos permisos a las apps instaladas fuera de la Play Store («ajuste restringido»).
Future<void> _permisoGris(BuildContext context, Installer ins) => showDialog(
  context: context,
  builder: (context) => AlertDialog(
    backgroundColor: C.panel,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    title: Text(t('Si el interruptor sale en gris'), style: T.serif(size: 28)),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Text(
        t('Android bloquea este permiso a las apps que no vienen de la Play Store. Para desbloquearlo:\n\n'
            '1. Pulsa «Abrir info de Hangar».\n'
            '2. Toca el menú ⋮ de arriba a la derecha.\n'
            '3. Elige «Permitir ajustes restringidos» y confirma.\n'
            '4. Vuelve aquí y pulsa «Dar permiso»: el interruptor ya se podrá activar.\n\n'
            'Si en tu tablet no aparece ese menú, no pasa nada: Hangar sigue contando el tiempo por su cuenta.'),
        style: T.sans(size: 14, color: C.ink2, height: 1.55),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: Text(t('CERRAR'), style: T.label(size: 12, color: C.ink2))),
      TextButton(
        onPressed: () {
          Navigator.pop(context);
          ins.abrirInfoApp();
        },
        child: Text(t('ABRIR INFO DE HANGAR'), style: T.label(size: 12, color: C.ink, w: FontWeight.w600)),
      ),
    ],
  ),
);
