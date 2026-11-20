import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'data.dart';
import 'installer.dart';
import 'play.dart';
import 'theme.dart';
import 'widgets.dart';

/// Pantalla de juego: arte enorme, logo y JUGAR. Debajo, en una segunda pantalla,
/// tu partida, los logros y los proyectos de GitHub.
class HomeScreen extends StatefulWidget {
  final List<Juego> juegos;
  final Installer installer;
  final int index;
  final ValueChanged<int> onIndex;
  final bool active, chispas, vibracion;
  final VoidCallback onLibrary, onSearch;
  const HomeScreen({
    super.key,
    required this.juegos,
    required this.installer,
    required this.index,
    required this.onIndex,
    required this.active,
    required this.chispas,
    required this.vibracion,
    required this.onLibrary,
    required this.onSearch,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _down = AnimationController(vsync: this, duration: const Duration(milliseconds: 850));
  late final Animation<double> _t = CurvedAnimation(parent: _down, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInOutCubic);
  final _scroll = ScrollController();
  final _focus = FocusNode(debugLabel: 'home');
  DateTime _lock = DateTime(2000), _lastWheel = DateTime(2000);
  bool _wheelFromTop = false;
  double _pull = 0;

  bool get _open => _down.status == AnimationStatus.forward || _down.status == AnimationStatus.completed;
  Juego get _g => widget.juegos[widget.index];

  @override
  void didUpdateWidget(HomeScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _focus.requestFocus();
    if (!widget.active && old.active) _down.value = 0;
  }

  @override
  void dispose() {
    _down.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _go(int d) {
    final n = widget.juegos.length;
    if (n == 0) return;
    widget.onIndex((widget.index + d + n) % n);
    if (widget.vibracion) HapticFeedback.selectionClick();
  }

  void _setOpen(bool v) {
    if (v == _open) return;
    _lock = DateTime.now();
    if (v) {
      if (_scroll.hasClients) _scroll.jumpTo(0);
      _down.forward();
    } else {
      _down.reverse();
    }
  }

  bool get _locked => DateTime.now().difference(_lock).inMilliseconds < 900;

  void _onWheel(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final now = DateTime.now();
    if (now.difference(_lastWheel).inMilliseconds > 220) {
      _wheelFromTop = _open && (!_scroll.hasClients || _scroll.offset <= 0);
    }
    _lastWheel = now;
    if (_locked) return;
    if (!_open && e.scrollDelta.dy > 6) _setOpen(true);
    if (_open && _wheelFromTop && e.scrollDelta.dy < -6 && (!_scroll.hasClients || _scroll.offset <= 0)) _setOpen(false);
  }

  // Trackpad (Mac): dos dedos arriba/abajo cambian de pantalla, a los lados cambian de juego.
  bool _panTop = false, _panDone = false;
  void _onPanStart(PointerPanZoomStartEvent e) {
    _panTop = _open && (!_scroll.hasClients || _scroll.offset <= 0);
    _panDone = false;
  }

  void _onPanUpdate(PointerPanZoomUpdateEvent e) {
    if (_panDone || _locked) return;
    final p = e.pan;
    if (!_open && p.dx.abs() > 90 && p.dx.abs() > p.dy.abs()) {
      _panDone = true;
      _go(p.dx < 0 ? 1 : -1);
    } else if (!_open && p.dy < -50 && p.dy.abs() > p.dx.abs()) {
      _panDone = true;
      _setOpen(true);
    } else if (_open && _panTop && p.dy > 70 && (!_scroll.hasClients || _scroll.offset <= 0)) {
      _panDone = true;
      _setOpen(false);
    }
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (!_open) {
      if (k == LogicalKeyboardKey.arrowRight) return _handled(() => _go(1));
      if (k == LogicalKeyboardKey.arrowLeft) return _handled(() => _go(-1));
      if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.pageDown) return _handled(() => _setOpen(true));
      if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.gameButtonA) return _handled(() => _play(context));
    } else {
      final top = !_scroll.hasClients || _scroll.offset <= 0;
      if (k == LogicalKeyboardKey.escape || k == LogicalKeyboardKey.gameButtonB || ((k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.pageUp) && top)) {
        return _handled(() => _setOpen(false));
      }
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handled(VoidCallback f) {
    f();
    return KeyEventResult.handled;
  }

  void _play(BuildContext context) => playAction(context, _g, widget.installer);

  @override
  Widget build(BuildContext context) {
    if (widget.juegos.isEmpty) return const Center(child: CircularProgressIndicator(color: C.acc));
    return LayoutBuilder(builder: (context, box) {
      final compact = box.maxHeight < 560;
      return Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Listener(
          onPointerSignal: _onWheel,
          onPointerPanZoomStart: _onPanStart,
          onPointerPanZoomUpdate: _onPanUpdate,
          child: AnimatedBuilder(
            animation: _t,
            builder: (context, _) {
              final t = _t.value, h = box.maxHeight;
              return Stack(children: [
                // Pantalla 1: el juego
                IgnorePointer(
                  ignoring: t > .5,
                  child: Opacity(
                    opacity: (1 - t * 1.4).clamp(0, 1),
                    child: Transform(
                      alignment: Alignment.topCenter,
                      transform: Matrix4.identity()
                        ..translateByDouble(0, -h * .07 * t, 0, 1)
                        ..scaleByDouble(1 - .07 * t, 1 - .07 * t, 1, 1),
                      child: _GameScreen(
                        g: _g,
                        juegos: widget.juegos,
                        index: widget.index,
                        compact: compact,
                        chispas: widget.chispas,
                        onPrev: () => _go(-1),
                        onNext: () => _go(1),
                        onPick: widget.onIndex,
                        onDown: () => _setOpen(true),
                        onPlay: () => _play(context),
                        installer: widget.installer,
                      ),
                    ),
                  ),
                ),
                // Pantalla 2: tu partida
                if (t > 0)
                  IgnorePointer(
                    ignoring: t < .5,
                    child: Opacity(
                      opacity: ((t - .1) / .9).clamp(0, 1),
                      child: Transform.translate(
                        offset: Offset(0, h * .12 * (1 - t)),
                        child: NotificationListener<ScrollNotification>(
                          onNotification: (n) {
                            if (n is ScrollStartNotification) _pull = 0;
                            if (n is OverscrollNotification && n.overscroll < 0 && n.metrics.pixels <= n.metrics.minScrollExtent) {
                              _pull += -n.overscroll;
                              if (_pull > 80 && !_locked) _setOpen(false);
                            }
                            return false;
                          },
                          child: _RecordScreen(g: _g, installer: widget.installer, controller: _scroll, compact: compact, onUp: () => _setOpen(false)),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  top: compact ? 14 : 30,
                  right: compact ? 22 : 40,
                  child: Opacity(
                    opacity: compact ? (1 - t).clamp(0, 1) : 1,
                    child: _TopNav(onLibrary: widget.onLibrary, onSearch: widget.onSearch),
                  ),
                ),
              ]);
            },
          ),
        ),
      );
    });
  }
}

class _TopNav extends StatefulWidget {
  final VoidCallback onLibrary, onSearch;
  const _TopNav({required this.onLibrary, required this.onSearch});
  @override
  State<_TopNav> createState() => _TopNavState();
}

class _TopNavState extends State<_TopNav> {
  late Timer _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = TimeOfDay.now();
    Widget link(String s, VoidCallback f) => TextButton(
          onPressed: f,
          style: TextButton.styleFrom(foregroundColor: C.ink2, padding: const EdgeInsets.symmetric(horizontal: 12)),
          child: Text(s.toUpperCase(), style: T.label(size: 12, color: C.ink2)),
        );
    return Row(children: [
      link('Biblioteca', widget.onLibrary),
      link('Buscar', widget.onSearch),
      const SizedBox(width: 12),
      Text('${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}', style: T.label(size: 12, color: C.ink2)),
    ]);
  }
}

/// Arte del juego: banner nítido arriba con fundido y el mismo arte difuminado de fondo.
class _HeroArt extends StatelessWidget {
  final Juego g;
  const _HeroArt(this.g, {super.key});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final c = hueOf(g.nombre, s1: .5, l: .28);
        final bgFallback = DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(center: const Alignment(.4, -.6), radius: 1.2, colors: [c, Color.lerp(c, C.card, .85)!]),
          ),
        );
        return Stack(fit: StackFit.expand, children: [
          ColoredBox(color: C.card, child: bgFallback),
          // Fondo: el arte difuminado y oscurecido
          if (g.heroSmall != null || g.cover != null)
            ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 36, sigmaY: 36, tileMode: TileMode.clamp),
              child: Opacity(opacity: .55, child: NetImg(g.heroSmall ?? g.cover, cacheWidth: 480)),
            ),
          // Banner nítido arriba, fundido hacia abajo
          if (g.hero != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: box.maxHeight * .82,
              child: ShaderMask(
                shaderCallback: (r) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.white, Colors.white, Colors.transparent],
                  stops: [0, .55, 1],
                ).createShader(r),
                blendMode: BlendMode.dstIn,
                child: NetImg(g.hero, alignment: Alignment.topCenter, fallback: NetImg(g.heroSmall, alignment: Alignment.topCenter)),
              ),
            )
          else if (g.cover != null)
            // Sin banner: la portada a la izquierda, grande, fundida
            Positioned(
              top: 0,
              bottom: 0,
              left: box.maxWidth * .08,
              width: box.maxHeight * .9 * 2 / 3,
              child: ShaderMask(
                shaderCallback: (r) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.white, Colors.white, Colors.transparent],
                  stops: [0, .6, 1],
                ).createShader(r),
                blendMode: BlendMode.dstIn,
                child: Padding(padding: EdgeInsets.only(top: box.maxHeight * .08), child: NetImg(g.coverFull, fit: BoxFit.contain, alignment: Alignment.topCenter)),
              ),
            ),
        ]);
      });
}

class _GameScreen extends StatelessWidget {
  final Juego g;
  final Installer installer;
  final List<Juego> juegos;
  final int index;
  final bool compact, chispas;
  final VoidCallback onPrev, onNext, onDown, onPlay;
  final ValueChanged<int> onPick;
  const _GameScreen({
    required this.g,
    required this.juegos,
    required this.index,
    required this.compact,
    required this.chispas,
    required this.onPrev,
    required this.onNext,
    required this.onDown,
    required this.onPlay,
    required this.onPick,
    required this.installer,
  });

  @override
  Widget build(BuildContext context) {
    final pad = compact ? 22.0 : 48.0;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v < -200) onNext();
        if (v > 200) onPrev();
      },
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) < -250) onDown();
      },
      child: Stack(fit: StackFit.expand, children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 800),
          switchInCurve: Curves.easeOutCubic,
          transitionBuilder: (child, a) => FadeTransition(
            opacity: a,
            child: ScaleTransition(scale: Tween(begin: 1.05, end: 1.0).animate(a), child: child),
          ),
          layoutBuilder: (cur, prev) => Stack(fit: StackFit.expand, children: [...prev, ?cur]),
          child: _HeroArt(g, key: ValueKey(g.id)),
        ),
        // Sombras para que el texto se lea
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerRight,
                end: Alignment.centerLeft,
                colors: [Color(0xDB0E090C), Color(0x8C0E090C), Color(0x000E090C)],
                stops: [0, .32, .64],
              ),
            ),
          ),
        ),
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color(0xEB0E090C), Color(0x400E090C), Color(0x000E090C)],
                stops: [0, .34, .58],
              ),
            ),
          ),
        ),
        Embers(enabled: chispas),
        // Logo y datos
        Positioned(
          right: pad,
          top: 0,
          bottom: compact ? 60 : 80,
          width: MediaQuery.sizeOf(context).width * (compact ? .44 : .42),
          child: Align(
            alignment: Alignment.centerRight,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 600),
              switchInCurve: Curves.easeOutCubic,
              transitionBuilder: (child, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(position: Tween(begin: const Offset(0, .06), end: Offset.zero).animate(a), child: child),
              ),
              child: _Info(g, compact: compact, key: ValueKey(g.id)),
            ),
          ),
        ),
        // Flechas y miniaturas
        Positioned(
          left: compact ? 18 : 44,
          bottom: compact ? 18 : 52,
          child: Row(children: [
            GlassButton(icon: Icons.chevron_left_rounded, onTap: onPrev, tooltip: 'Anterior', size: compact ? 42 : 52),
            SizedBox(width: compact ? 10 : 14),
            GlassButton(icon: Icons.chevron_right_rounded, onTap: onNext, tooltip: 'Siguiente', size: compact ? 42 : 52),
            if (MediaQuery.sizeOf(context).width > 980) ...[const SizedBox(width: 18), _Strip(juegos: juegos, index: index, onPick: onPick)],
            const SizedBox(width: 14),
            Text('${(index + 1).toString().padLeft(2, '0')} / ${juegos.length.toString().padLeft(2, '0')}', style: T.label(size: 12, color: C.ink2)),
          ]),
        ),
        // Tiempo, logros y JUGAR
        Positioned(
          right: compact ? 18 : 48,
          bottom: compact ? 16 : 56,
          child: Row(children: [
            _Mini(onTap: onDown, compact: compact, segundos: installer.segundos(g)),
            SizedBox(width: compact ? 12 : 20),
            PlayButton(g: g, installer: installer, compact: compact, onTap: onPlay),
            SizedBox(width: compact ? 8 : 12),
            GlassButton(icon: Icons.more_horiz_rounded, onTap: () => showPlaySheet(context, g, installer), tooltip: 'Versiones', size: compact ? 42 : 52),
          ]),
        ),
        if (!compact)
          Positioned(
            left: 0,
            right: 0,
            bottom: 10,
            child: Center(
              child: TextButton.icon(
                onPressed: onDown,
                style: TextButton.styleFrom(foregroundColor: C.ink3),
                iconAlignment: IconAlignment.end,
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                label: Text('TUS LOGROS', style: T.label(size: 11, color: C.ink3)),
              ),
            ),
          ),
      ]),
    );
  }
}

class _Info extends StatelessWidget {
  final Juego g;
  final bool compact;
  const _Info(this.g, {super.key, required this.compact});

  @override
  Widget build(BuildContext context) {
    final title = Text(
      g.nombre,
      textAlign: TextAlign.right,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: T.serif(size: compact ? 46 : 78, w: FontWeight.w600, height: .95).copyWith(
        shadows: const [Shadow(color: Color(0x99000000), blurRadius: 30, offset: Offset(0, 10))],
      ),
    );
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
      if (g.logo != null)
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: compact ? 96 : 180),
          child: NetImg(g.logo, fit: BoxFit.contain, alignment: Alignment.centerRight, fallback: title),
        )
      else
        title,
      if (g.subtitulo.isNotEmpty) ...[
        SizedBox(height: compact ? 10 : 16),
        Text(g.subtitulo, textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.sans(size: compact ? 12 : 14, color: C.ink2)),
      ],
      SizedBox(height: compact ? 10 : 18),
      Text(
        [g.tiposTexto, '${g.repos.length} ${g.repos.length == 1 ? 'versión' : 'versiones'}'].where((s) => s.isNotEmpty).join(' · ').toUpperCase(),
        textAlign: TextAlign.right,
        style: T.label(size: 12, color: C.ink2),
      ),
      if (g.descripcion.isNotEmpty && !compact) ...[
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Text(g.descripcion, textAlign: TextAlign.right, maxLines: 3, overflow: TextOverflow.ellipsis, style: T.sans(size: 15, color: C.ink2, height: 1.5)),
        ),
      ],
      if (g.dudoso) ...[
        const SizedBox(height: 10),
        Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.help_outline_rounded, size: 14, color: C.ink3),
          const SizedBox(width: 6),
          Text('Nombre sin confirmar', style: T.sans(size: 12, color: C.ink3)),
        ]),
      ],
    ]);
  }
}

class _Strip extends StatelessWidget {
  final List<Juego> juegos;
  final int index;
  final ValueChanged<int> onPick;
  const _Strip({required this.juegos, required this.index, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final n = juegos.length, span = n < 9 ? n : 9;
    final start = n <= 9 ? 0 : index - 4;
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      for (var k = 0; k < span; k++)
        Builder(builder: (context) {
          final i = (start + k + n) % n, on = i == index;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onPick(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                width: on ? 44 : 34,
                height: on ? 62 : 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: on ? Border.all(color: C.ink, width: 2) : null,
                ),
                child: Opacity(opacity: on ? 1 : .5, child: Cover(juegos[i], radius: 6, compact: true)),
              ),
            ),
          );
        }),
    ]);
  }
}

String horas(int s) => s < 3600 ? '${(s / 60).floor()} min' : '${(s / 3600).toStringAsFixed(s < 36000 ? 1 : 0).replaceAll('.', ',')} h';

String cuando(DateTime? d) {
  if (d == null) return 'Nunca';
  final days = DateTime.now().difference(d).inDays;
  if (days == 0) return 'Hoy';
  if (days == 1) return 'Ayer';
  if (days < 7) return 'Hace $days días';
  return '${d.day}/${d.month}/${d.year}';
}

class _Mini extends StatelessWidget {
  final VoidCallback onTap;
  final bool compact;
  final int segundos;
  const _Mini({required this.onTap, required this.compact, required this.segundos});

  @override
  Widget build(BuildContext context) {
    Widget stat(String v, String l) => Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
          Text(v, style: T.sans(size: compact ? 16 : 20, w: FontWeight.w600, height: 1.1)),
          Text(l.toUpperCase(), style: T.label(size: 10, color: C.ink3)),
        ]);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(children: [stat(segundos == 0 ? '0 h' : horas(segundos), 'Jugado'), SizedBox(width: compact ? 16 : 26), stat('—', 'Logros')]),
      ),
    );
  }
}

/// Segunda pantalla: tu partida, logros y repos.
class _RecordScreen extends StatelessWidget {
  final Juego g;
  final Installer installer;
  final ScrollController controller;
  final bool compact;
  final VoidCallback onUp;
  const _RecordScreen({required this.g, required this.installer, required this.controller, required this.compact, required this.onUp});

  @override
  Widget build(BuildContext context) {
    final side = compact ? 24.0 : 64.0;
    return Stack(fit: StackFit.expand, children: [
      const ColoredBox(color: C.card),
      ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 46, sigmaY: 46, tileMode: TileMode.clamp),
        child: Opacity(opacity: .4, child: NetImg(g.heroSmall ?? g.cover, cacheWidth: 400)),
      ),
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x59120E11), Color(0xD1120E11)], stops: [0, .6]),
        ),
      ),
      CustomScrollView(
        controller: controller,
        physics: const ClampingScrollPhysics(),
        slivers: [
          SliverPersistentHeader(pinned: true, delegate: _Header(g: g, compact: compact, onUp: onUp, side: side)),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(side, compact ? 28 : 48, side, 56),
            sliver: SliverList.list(children: [
              const SectionTitle('Tu partida'),
              _Stats(compact: compact, segundos: installer.segundos(g), ultima: installer.ultima(g)),
              SizedBox(height: compact ? 36 : 56),
              const SectionTitle('Logros'),
              Panel(
                padding: const EdgeInsets.all(28),
                child: Row(children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), color: C.glass, border: Border.all(color: C.line)),
                    child: const Icon(Icons.emoji_events_outlined, color: C.ink3, size: 26),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Text(
                      'Este juego todavía no tiene lista de logros. Cuando la tenga, aparecerán aquí con su rareza y la fecha en que los consigas.',
                      style: T.sans(size: 15, color: C.ink2, height: 1.5),
                    ),
                  ),
                ]),
              ),
              SizedBox(height: compact ? 36 : 56),
              SectionTitle('Proyectos', italic: 'en GitHub', trailing: Text('${g.repos.length} ${g.repos.length == 1 ? 'versión' : 'versiones'}', style: T.sans(size: 14, color: C.ink2))),
              LayoutBuilder(builder: (context, box) {
                final cols = (box.maxWidth / 340).floor().clamp(1, 4);
                final w = (box.maxWidth - (cols - 1) * 14) / cols;
                return Wrap(spacing: 14, runSpacing: 14, children: [for (final r in g.repos) SizedBox(width: w, child: _RepoCard(r))]);
              }),
              if (g.notas.isNotEmpty || g.dudoso) ...[
                SizedBox(height: compact ? 36 : 56),
                const SectionTitle('Sobre el nombre'),
                Panel(
                  child: Text(
                    [if (g.dudoso) 'El nombre de este juego es una deducción y puede no ser correcto.', ...g.notas].join('\n'),
                    style: T.sans(size: 14, color: C.ink2, height: 1.6),
                  ),
                ),
              ],
              const SizedBox(height: 56),
              Center(child: Text('Hangar · Arte de SteamGridDB · Código de cada proyecto en GitHub', style: T.sans(size: 12, color: C.ink3))),
            ]),
          ),
        ],
      ),
    ]);
  }
}

class _Header extends SliverPersistentHeaderDelegate {
  final Juego g;
  final bool compact;
  final VoidCallback onUp;
  final double side;
  _Header({required this.g, required this.compact, required this.onUp, required this.side});

  @override
  double get minExtent => compact ? 70 : 104;
  @override
  double get maxExtent => minExtent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            decoration: const BoxDecoration(color: Color(0x99120E11), border: Border(bottom: BorderSide(color: C.line))),
            padding: EdgeInsets.fromLTRB(side, 0, compact ? 24 : 380, 0),
            child: Row(children: [
              GlassButton(icon: Icons.keyboard_arrow_up_rounded, onTap: onUp, tooltip: 'Volver al juego', size: compact ? 38 : 46),
              const SizedBox(width: 18),
              SizedBox(width: compact ? 30 : 42, height: compact ? 42 : 60, child: Cover(g, radius: 8, compact: true)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(g.nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.serif(size: compact ? 20 : 26, w: FontWeight.w600, height: 1.1)),
                  const SizedBox(height: 4),
                  Text(g.tiposTexto.toUpperCase(), style: T.label(size: 11, color: C.ink2)),
                ]),
              ),
            ]),
          ),
        ),
      );

  @override
  bool shouldRebuild(_Header old) => old.g != g || old.compact != compact;
}

class _Stats extends StatelessWidget {
  final bool compact;
  final int segundos;
  final DateTime? ultima;
  const _Stats({required this.compact, required this.segundos, this.ultima});

  @override
  Widget build(BuildContext context) {
    Widget tile(String big, String small, String label, {double? bar}) => Padding(
          padding: EdgeInsets.fromLTRB(28, compact ? 20 : 28, 28, compact ? 20 : 30),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text.rich(
              TextSpan(children: [
                TextSpan(text: big),
                TextSpan(text: ' $small', style: T.sans(size: 18, color: C.ink2)),
              ]),
              style: T.sans(size: compact ? 32 : 46, w: FontWeight.w300, height: 1),
            ),
            const SizedBox(height: 8),
            Text(label.toUpperCase(), style: T.label(size: 11)),
            if (bar != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(value: bar, minHeight: 3, color: C.acc, backgroundColor: const Color(0x1AFFFFFF)),
              ),
            ],
          ]),
        );
    final t = segundos < 3600 ? ['${(segundos / 60).floor()}', 'min'] : [(segundos / 3600).toStringAsFixed(1).replaceAll('.', ','), 'h'];
    final tiles = [tile(t[0], t[1], 'Tiempo jugado'), tile('0', '', 'Logros obtenidos'), tile('0', '%', 'Completado', bar: 0), tile(cuando(ultima), '', 'Última sesión')];
    return Container(
      decoration: BoxDecoration(color: const Color(0xD1120E11), borderRadius: BorderRadius.circular(22), border: Border.all(color: C.line)),
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const VerticalDivider(width: 1, thickness: 1, color: C.line),
            Expanded(child: tiles[i]),
          ],
        ]),
      ),
    );
  }
}

class _RepoCard extends StatelessWidget {
  final Repo r;
  const _RepoCard(this.r);

  @override
  Widget build(BuildContext context) => Panel(
        onTap: () => launchUrl(Uri.parse(r.url), mode: LaunchMode.externalApplication),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: C.glass, borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.code_rounded, color: C.ink, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.sans(size: 15, w: FontWeight.w600)),
              const SizedBox(height: 2),
              Text('${r.owner} · ${tipoLabel[r.tipo] ?? r.tipo}', maxLines: 1, overflow: TextOverflow.ellipsis, style: T.sans(size: 13, color: C.ink2)),
            ]),
          ),
          const Icon(Icons.north_east_rounded, size: 18, color: C.ink2),
        ]),
      );
}

