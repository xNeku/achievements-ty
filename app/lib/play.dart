import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'data.dart';
import 'installer.dart';
import 'theme.dart';
import 'widgets.dart';

/// Lo que hace el botón grande: jugar si está instalado, instalar si se puede, y si hay
/// varias versiones sin instalar, dejar elegir.
Future<void> playAction(BuildContext context, Juego g, Installer ins) async {
  final r = ins.principal(g);
  if (r == null) return;
  final f = ins.fase(r);
  if (f == Fase.descargando || f == Fase.preparando || f == Fase.jugando) return showPlaySheet(context, g, ins);
  if (f == Fase.listo) {
    await ins.jugar(r);
  } else if (g.repos.length > 1 || !ins.instalable(r) || (ins.esAndroid && !r.listo) || (r.mac?.pasos.isNotEmpty ?? false)) {
    return showPlaySheet(context, g, ins);
  } else {
    await ins.instalar(r);
  }
  final err = ins.error(r);
  if (err != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(err, style: T.sans(size: 14)),
        backgroundColor: C.panel,
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(label: 'VER', textColor: C.pink, onPressed: () => showPlaySheet(context, g, ins)),
      ),
    );
  }
}

/// Píldora principal con el estado del port: Instalar, Descargando 42 %, Jugar…
class PlayButton extends StatelessWidget {
  final Juego g;
  final Installer installer;
  final bool compact;
  final VoidCallback onTap;
  const PlayButton({super.key, required this.g, required this.installer, required this.compact, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final r = installer.principal(g);
    final f = r == null ? Fase.nada : installer.fase(r);
    final p = r == null ? 0.0 : installer.progreso(r);
    final (label, icon) = switch (f) {
      Fase.descargando => ('Descargando ${(p * 100).round()} %', Icons.downloading_rounded),
      Fase.preparando => ('Preparando', Icons.hourglass_top_rounded),
      Fase.jugando => ('Jugando', Icons.sports_esports_rounded),
      Fase.listo => ('Jugar', Icons.play_arrow_rounded),
      Fase.nada =>
        !installer.soportado
            ? ('Descargar', Icons.download_rounded)
            : (installer.esMac || (r?.listo ?? false))
            ? ('Instalar', Icons.download_rounded)
            : ('Versiones', Icons.list_rounded),
    };
    return Stack(
      children: [
        PlayPill(onTap: onTap, label: label, icon: icon, compact: compact),
        if (f == Fase.descargando)
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: p.clamp(.02, 1),
                    heightFactor: 1,
                    child: const ColoredBox(color: Color(0x2EFFFFFF)),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Panel lateral con todas las versiones del juego y lo que se puede hacer con cada una.
Future<void> showPlaySheet(BuildContext context, Juego g, Installer ins) => showGeneralDialog(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Cerrar',
  barrierColor: const Color(0x99000000),
  transitionDuration: const Duration(milliseconds: 380),
  pageBuilder: (context, _, _) => Align(
    alignment: Alignment.centerRight,
    child: Material(
      color: C.panel,
      borderRadius: const BorderRadius.horizontal(left: Radius.circular(28)),
      child: SizedBox(
        width: 500,
        height: double.infinity,
        child: SafeArea(
          child: ListenableBuilder(
            listenable: ins,
            builder: (context, _) => ListView(
              padding: const EdgeInsets.fromLTRB(32, 32, 32, 32),
              children: [
                Row(
                  children: [
                    Expanded(child: Text(g.repos.length > 1 ? 'Elige versión' : 'Instalar y jugar', style: T.serif(size: 38))),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, color: C.ink2),
                      tooltip: 'Cerrar',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  !ins.soportado
                      ? 'Desde aquí se abre la página de descargas del port en GitHub.'
                      : ins.esMac
                      ? 'Necesitas tu propia copia del juego. Hangar descarga el port de GitHub, lo prepara y lo abre.'
                      : 'Necesitas tu propia copia del juego (la ROM o el disco, en tu tablet). Hangar instala el port y lo abre; la primera vez el juego te pedirá elegir ese archivo.',
                  style: T.sans(size: 14, color: C.ink2, height: 1.5),
                ),
                const SizedBox(height: 24),
                for (final r in g.repos) ...[_RepoRow(r: r, ins: ins), const SizedBox(height: 14)],
              ],
            ),
          ),
        ),
      ),
    ),
  ),
  transitionBuilder: (context, a, _, child) => SlideTransition(
    position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
    child: child,
  ),
);

class _RepoRow extends StatelessWidget {
  final Repo r;
  final Installer ins;
  const _RepoRow({required this.r, required this.ins});

  @override
  Widget build(BuildContext context) {
    final f = ins.fase(r), m = r.mac, rec = ins.instalado(r), err = ins.error(r);
    final a = r.android;
    final meta = [
      r.owner,
      tipoLabel[r.tipo] ?? r.tipo,
      if (r.version != null) r.version!,
      if (ins.esMac && m?.size != null) m!.size!,
      if (!ins.esMac && a != null && a.tamano.isNotEmpty) a.tamano,
      if (!ins.esMac && a != null && a.pre) 'pre-release',
    ].join(' · ');
    final upd = ins.hayActualizacion(r);
    Widget small(String t, {Color color = C.ink2}) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(t, style: T.sans(size: 13, color: color, height: 1.45)),
    );

    Widget primary;
    switch (f) {
      case Fase.descargando:
      case Fase.preparando:
        primary = SizedBox(
          width: 170,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(f == Fase.preparando ? 'Preparando…' : 'Descargando ${(ins.progreso(r) * 100).round()} %', style: T.label(size: 11, color: C.ink)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: f == Fase.preparando ? null : ins.progreso(r),
                  minHeight: 3,
                  color: C.acc,
                  backgroundColor: const Color(0x1AFFFFFF),
                ),
              ),
            ],
          ),
        );
      case Fase.jugando:
        primary = Text(
          'JUGANDO',
          style: T.label(size: 12, color: C.ok, w: FontWeight.w600),
        );
      case Fase.listo:
        primary = upd
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  PlayPill(onTap: () => ins.jugar(r), compact: true),
                  const SizedBox(height: 6),
                  TextButton.icon(
                    onPressed: () => ins.instalar(r),
                    icon: const Icon(Icons.system_update_alt_rounded, size: 16, color: C.ok),
                    label: Text(
                      'ACTUALIZAR A ${r.version}',
                      style: T.label(size: 10, color: C.ok, w: FontWeight.w600),
                    ),
                  ),
                ],
              )
            : PlayPill(onTap: () => ins.jugar(r), compact: true);
      case Fase.nada:
        primary = ins.instalable(r) && (ins.esMac || r.listo)
            ? PlayPill(onTap: () => ins.instalar(r), label: 'Instalar', icon: Icons.download_rounded, compact: true)
            : TextButton(
                onPressed: () => launchUrl(Uri.parse('${r.url}/releases'), mode: LaunchMode.externalApplication),
                child: Text(
                  'VER EN GITHUB',
                  style: T.label(size: 12, color: C.ink, w: FontWeight.w600),
                ),
              );
    }

    return Panel(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.name, style: T.sans(size: 16, w: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(meta, style: T.sans(size: 13, color: C.ink2)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              primary,
            ],
          ),
          if (r.aviso != null) small('Este proyecto está ${r.aviso}: puede que no reciba más arreglos.', color: const Color(0xFFE9B949)),
          if (!ins.esMac && !r.listo && ins.esAndroid)
            small('No publica un APK en GitHub, así que no se puede instalar desde aquí. Mira su página por si hay que compilarlo.'),
          if (err != null) small(err, color: const Color(0xFFFF8A80)),
          if (ins.avisoCopia[r.repo] != null) small(ins.avisoCopia[r.repo]!, color: const Color(0xFFE9B949)),
          if (m?.aviso != null) small(m!.aviso!) else if (m?.necesita != null) small(m!.necesita!),
          if (r.requisitos.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'LO QUE PIDE PARA JUGAR',
              style: T.label(size: 10, color: C.ink3, w: FontWeight.w600),
            ),
            for (final q in r.requisitos) small('· $q'),
          ],
          if (rec != null && m != null && m.pideCopia)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                children: [
                  const Icon(Icons.album_outlined, size: 16, color: C.ink3),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      rec.copia == null ? (m.juegoTexto ?? 'Elige tu copia del juego') : 'Tu copia: ${rec.copia!.split('/').last}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: T.sans(size: 13, color: C.ink2),
                    ),
                  ),
                  TextButton(
                    onPressed: () => ins.elegirCopia(r),
                    child: Text(rec.copia == null ? 'ELEGIR' : 'CAMBIAR', style: T.label(size: 11, color: C.ink)),
                  ),
                ],
              ),
            ),
          if (m != null && m.pasos.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'ESTE PORT SE PREPARA A MANO',
              style: T.label(size: 10, color: C.acc, w: FontWeight.w600),
            ),
            for (var i = 0; i < m.pasos.length; i++) small('${i + 1}. ${m.pasos[i]}'),
          ],
          if (rec != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (ins.esMac)
                  TextButton.icon(onPressed: () => ins.abrirCarpeta(r), icon: const Icon(Icons.folder_open_rounded, size: 16), label: const Text('Carpeta')),
                TextButton.icon(
                  onPressed: () => ins.desinstalar(r),
                  icon: const Icon(Icons.delete_outline_rounded, size: 16),
                  label: const Text('Desinstalar'),
                ),
                const Spacer(),
                if (rec.segundos > 0)
                  Text('${(rec.segundos / 3600).toStringAsFixed(1).replaceAll('.', ',')} h jugadas', style: T.sans(size: 12, color: C.ink3)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
