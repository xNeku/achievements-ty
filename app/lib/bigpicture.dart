import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'data.dart';
import 'installer.dart';
import 'play.dart';
import 'theme.dart';
import 'widgets.dart';

/// Modo Big Picture: pantalla completa pensada para la tele y el mando.
/// Filas grandes de portadas; A juega, Y abre las versiones, B sale.
Future<void> abrirBigPicture(BuildContext context, {required List<Juego> juegos, required List<Juego> destacados, required Installer installer}) =>
    Navigator.of(context).push(PageRouteBuilder(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 450),
      pageBuilder: (_, _, _) => BigPicture(juegos: juegos, destacados: destacados, installer: installer),
      transitionsBuilder: (_, a, _, child) => FadeTransition(
        opacity: a,
        child: ScaleTransition(scale: Tween(begin: 1.04, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)), child: child),
      ),
    ));

class BigPicture extends StatefulWidget {
  final List<Juego> juegos, destacados;
  final Installer installer;
  const BigPicture({super.key, required this.juegos, required this.destacados, required this.installer});
  @override
  State<BigPicture> createState() => _BigPictureState();
}

class _BigPictureState extends State<BigPicture> {
  Juego? _foco;
  late Timer _reloj;

  @override
  void initState() {
    super.initState();
    _reloj = Timer.periodic(const Duration(seconds: 20), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _reloj.cancel();
    super.dispose();
  }

  List<(String, List<Juego>)> _filas() {
    final ins = widget.installer;
    bool instalado(Juego j) => j.repos.any((r) => ins.instalado(r) != null);
    final seguir = widget.juegos.where(instalado).toList()
      ..sort((a, b) => (ins.ultima(b) ?? DateTime(2000)).compareTo(ins.ultima(a) ?? DateTime(2000)));
    final listos = widget.juegos.where((j) => j.listo && !instalado(j) && j.cover != null).take(40).toList();
    final destacados = widget.destacados.where((j) => !instalado(j)).take(30).toList();
    return [
      if (seguir.isNotEmpty) ('Seguir jugando', seguir),
      if (listos.isNotEmpty) ('Listos para jugar', listos),
      if (destacados.isNotEmpty) ('Destacados', destacados),
    ];
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.gameButtonB || k == LogicalKeyboardKey.escape || k == LogicalKeyboardKey.goBack) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    // Flechas y cruceta mueven el foco entre portadas (en algunos sistemas harían scroll).
    final dir = switch (k) {
      LogicalKeyboardKey.arrowRight => TraversalDirection.right,
      LogicalKeyboardKey.arrowLeft => TraversalDirection.left,
      LogicalKeyboardKey.arrowUp => TraversalDirection.up,
      LogicalKeyboardKey.arrowDown => TraversalDirection.down,
      _ => null,
    };
    if (dir != null) {
      FocusManager.instance.primaryFocus?.focusInDirection(dir);
      return KeyEventResult.handled;
    }
    if ((k == LogicalKeyboardKey.gameButtonY || k == LogicalKeyboardKey.gameButtonX || k == LogicalKeyboardKey.keyY) && _foco != null) {
      showPlaySheet(context, _foco!, widget.installer);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.installer,
        builder: (context, _) {
          final filas = _filas();
          final g = _foco ?? (filas.isEmpty ? null : filas.first.$2.first);
          final now = TimeOfDay.now();
          return Scaffold(
            backgroundColor: C.wall,
            body: Focus(
              onKeyEvent: _onKey,
              child: Stack(fit: StackFit.expand, children: [
                // Fondo: el arte del juego enfocado, difuminado
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 600),
                  child: g == null
                      ? const SizedBox.shrink()
                      : ImageFiltered(
                          key: ValueKey(g.id),
                          imageFilter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28, tileMode: TileMode.mirror),
                          child: Opacity(opacity: .45, child: SizedBox.expand(child: NetImg(g.hero ?? g.cover, cacheWidth: 640))),
                        ),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x660A0809), Color(0xF20A0809)], stops: [0, .55]),
                  ),
                ),
                SafeArea(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    // Barra superior
                    Padding(
                      padding: const EdgeInsets.fromLTRB(56, 28, 56, 0),
                      child: Row(children: [
                        const Icon(Icons.landscape_outlined, color: C.pink, size: 30),
                        const SizedBox(width: 12),
                        Text('Hangar', style: T.sans(size: 22, w: FontWeight.w700)),
                        const SizedBox(width: 14),
                        Text('BIG PICTURE', style: T.label(size: 12, color: C.ink3, w: FontWeight.w600)),
                        const Spacer(),
                        Text('${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}', style: T.sans(size: 22, w: FontWeight.w300)),
                      ]),
                    ),
                    // Juego enfocado
                    if (g != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(56, 28, 56, 8),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: Row(key: ValueKey(g.id), crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                                Text(g.nombre, maxLines: 2, overflow: TextOverflow.ellipsis, style: T.serif(size: 54, w: FontWeight.w600)),
                                const SizedBox(height: 8),
                                Text(
                                  [
                                    g.tiposTexto,
                                    if (widget.installer.segundos(g) > 0) '${(widget.installer.segundos(g) / 3600).toStringAsFixed(1).replaceAll('.', ',')} h jugadas',
                                    if (g.logros.isNotEmpty) '${g.logros.first.total} logros',
                                  ].where((s) => s.isNotEmpty).join(' · ').toUpperCase(),
                                  style: T.label(size: 12, color: C.ink2),
                                ),
                              ]),
                            ),
                            PlayButton(g: g, installer: widget.installer, compact: false, onTap: () => playAction(context, g, widget.installer)),
                          ]),
                        ),
                      ),
                    // Filas
                    Expanded(
                      child: filas.isEmpty
                          ? Center(child: Text('No hay juegos que mostrar todavía.', style: T.sans(size: 18, color: C.ink2)))
                          : ListView(
                              padding: const EdgeInsets.fromLTRB(0, 12, 0, 24),
                              children: [
                                for (var f = 0; f < filas.length; f++)
                                  _Fila(
                                    titulo: filas[f].$1,
                                    juegos: filas[f].$2,
                                    installer: widget.installer,
                                    autofocus: f == 0,
                                    onFoco: (j) => setState(() => _foco = j),
                                    onAbrir: (j) => playAction(context, j, widget.installer),
                                  ),
                              ],
                            ),
                    ),
                    // Ayuda de botones
                    Padding(
                      padding: const EdgeInsets.fromLTRB(56, 0, 56, 22),
                      child: Row(children: [
                        _Boton('A', 'Jugar', const Color(0xFF44D27A)),
                        _Boton('Y', 'Versiones', const Color(0xFFE9B949)),
                        _Boton('B', 'Salir', const Color(0xFFE8463B)),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.close_fullscreen_rounded, color: C.ink2, size: 18),
                          label: Text('SALIR DE BIG PICTURE', style: T.label(size: 11, color: C.ink2, w: FontWeight.w600)),
                        ),
                      ]),
                    ),
                  ]),
                ),
              ]),
            ),
          );
        },
      );
}

class _Fila extends StatelessWidget {
  final String titulo;
  final List<Juego> juegos;
  final Installer installer;
  final bool autofocus;
  final ValueChanged<Juego> onFoco, onAbrir;
  const _Fila({required this.titulo, required this.juegos, required this.installer, required this.autofocus, required this.onFoco, required this.onAbrir});

  @override
  Widget build(BuildContext context) => FocusTraversalGroup(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.fromLTRB(56, 18, 56, 12), child: Text(titulo, style: T.serif(size: 32))),
          SizedBox(
            height: 300,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 18),
              clipBehavior: Clip.none,
              itemCount: juegos.length,
              separatorBuilder: (_, _) => const SizedBox(width: 22),
              itemBuilder: (context, i) => _Tile(
                juego: juegos[i],
                instalado: juegos[i].repos.any((r) => installer.instalado(r) != null),
                autofocus: autofocus && i == 0,
                onFoco: () => onFoco(juegos[i]),
                onAbrir: () => onAbrir(juegos[i]),
              ),
            ),
          ),
        ]),
      );
}

class _Tile extends StatefulWidget {
  final Juego juego;
  final bool instalado, autofocus;
  final VoidCallback onFoco, onAbrir;
  const _Tile({required this.juego, required this.instalado, required this.autofocus, required this.onFoco, required this.onAbrir});
  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> {
  bool _on = false;
  @override
  Widget build(BuildContext context) => InkWell(
        autofocus: widget.autofocus,
        onTap: widget.onAbrir,
        onHover: (v) {
          if (v) widget.onFoco();
        },
        onFocusChange: (v) {
          setState(() => _on = v);
          if (v) {
            widget.onFoco();
            Scrollable.ensureVisible(context, alignment: .3, duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic);
          }
        },
        focusColor: Colors.transparent,
        hoverColor: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedScale(
          scale: _on ? 1.1 : 1,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: 176,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _on ? Colors.white : Colors.transparent, width: 3),
              boxShadow: [BoxShadow(color: _on ? const Color(0x66F2507F) : const Color(0x66000000), blurRadius: _on ? 40 : 20, offset: const Offset(0, 14))],
            ),
            child: Stack(fit: StackFit.expand, children: [
              Cover(widget.juego, radius: 15),
              if (widget.instalado)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: const BoxDecoration(color: Color(0xE60E0A0D), shape: BoxShape.circle),
                    child: const Icon(Icons.check_rounded, size: 16, color: C.ok),
                  ),
                ),
            ]),
          ),
        ),
      );
}

class _Boton extends StatelessWidget {
  final String letra, texto;
  final Color color;
  const _Boton(this.letra, this.texto, this.color);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 26),
        child: Row(children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: .18), border: Border.all(color: color, width: 1.5)),
            child: Text(letra, style: T.sans(size: 13, w: FontWeight.w700, color: color)),
          ),
          const SizedBox(width: 10),
          Text(texto, style: T.sans(size: 15, color: C.ink2)),
        ]),
      );
}
