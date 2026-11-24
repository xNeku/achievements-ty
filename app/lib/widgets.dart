import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import 'data.dart';
import 'theme.dart';

/// Imagen de red con fundido de entrada y sin parpadeos al fallar.
class NetImg extends StatelessWidget {
  final String? url;
  final BoxFit fit;
  final Alignment alignment;
  final int? cacheWidth;
  final Widget? fallback;
  const NetImg(this.url, {super.key, this.fit = BoxFit.cover, this.alignment = Alignment.center, this.cacheWidth, this.fallback});

  @override
  Widget build(BuildContext context) {
    final fb = fallback ?? const SizedBox.shrink();
    if (url == null) return fb;
    return CachedNetworkImage(
      imageUrl: url!,
      fit: fit,
      alignment: alignment,
      memCacheWidth: cacheWidth,
      fadeInDuration: const Duration(milliseconds: 350),
      fadeOutDuration: Duration.zero,
      placeholder: (_, _) => fb,
      errorWidget: (_, _, _) => fb,
    );
  }
}

/// Portada tipográfica para juegos sin arte.
class Placeholder23 extends StatelessWidget {
  final Juego j;
  final bool compact;
  const Placeholder23(this.j, {super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final c = hueOf(j.nombre);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(.6, -1),
          radius: 1.4,
          colors: [Color.lerp(c, Colors.white, .16)!, c, Color.lerp(c, Colors.black, .6)!],
          stops: const [0, .45, 1],
        ),
      ),
      child: compact
          ? Center(
              child: Text(j.nombre.characters.first.toUpperCase(), style: T.serif(size: 22, w: FontWeight.w600)),
            )
          : Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (j.tipos.isNotEmpty)
                    Text(
                      j.tiposTexto.toUpperCase(),
                      style: T.label(size: 9, color: C.ink2, w: FontWeight.w600),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    j.nombre,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: T.sans(size: 15, w: FontWeight.w700, height: 1.15),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Portada 2:3 (arte o tipográfica).
class Cover extends StatelessWidget {
  final Juego j;
  final double radius;
  final bool compact;
  const Cover(this.j, {super.key, this.radius = 14, this.compact = false});

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: NetImg(
      j.cover,
      cacheWidth: compact ? 120 : 320,
      fallback: Placeholder23(j, compact: compact),
    ),
  );
}

/// Botón redondo de cristal.
class GlassButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final double size;
  const GlassButton({super.key, required this.icon, required this.onTap, required this.tooltip, this.size = 52});

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: C.glass,
      shape: const CircleBorder(side: BorderSide(color: Color(0x1FFFFFFF))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox.square(
          dimension: size,
          child: Icon(icon, size: size * .42, color: C.ink),
        ),
      ),
    ),
  );
}

/// Píldora blanca/cristal "JUGAR".
class PlayPill extends StatelessWidget {
  final VoidCallback onTap;
  final String label;
  final IconData icon;
  final bool compact;
  const PlayPill({super.key, required this.onTap, this.label = 'Jugar', this.icon = Icons.play_arrow_rounded, this.compact = false});

  @override
  Widget build(BuildContext context) => Material(
    color: C.glass,
    shape: const StadiumBorder(side: BorderSide(color: Color(0x24FFFFFF))),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(10, 10, compact ? 22 : 30, 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: compact ? 30 : 36,
              height: compact ? 30 : 36,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: Icon(icon, color: C.card, size: compact ? 20 : 24),
            ),
            SizedBox(width: compact ? 10 : 14),
            Text(
              label.toUpperCase(),
              style: T.label(size: compact ? 12 : 14, color: C.ink, w: FontWeight.w600),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Avatar con punto de conexión.
class Avatar extends StatelessWidget {
  final String letter;
  final double size;
  final bool online;
  final Color? glow;
  const Avatar({super.key, this.letter = 'T', this.size = 50, this.online = true, this.glow});

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF5A4A58),
            border: Border.all(color: glow ?? const Color(0x2EFFFFFF), width: glow == null ? 2 : 3),
            boxShadow: glow == null ? null : [BoxShadow(color: glow!.withValues(alpha: .35), blurRadius: 36)],
          ),
          alignment: Alignment.center,
          child: Text(
            letter,
            style: T.sans(size: size * .36, w: FontWeight.w600),
          ),
        ),
        if (online)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: size * .24,
              height: size * .24,
              decoration: BoxDecoration(
                color: C.ok,
                shape: BoxShape.circle,
                border: Border.all(color: C.card, width: 3),
              ),
            ),
          ),
      ],
    ),
  );
}

/// Chispas que suben despacio, del color del acento.
class Embers extends StatefulWidget {
  final Color tint;
  final bool enabled;
  const Embers({super.key, this.tint = C.acc, this.enabled = true});
  @override
  State<Embers> createState() => _EmbersState();
}

class _EmbersState extends State<Embers> with SingleTickerProviderStateMixin {
  late final Ticker _t;
  final _ps = List.generate(38, (_) => _P(math.Random()));
  final _clock = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    _t = createTicker((_) {
      for (final p in _ps) {
        p.step();
      }
      _clock.value++;
    });
    if (widget.enabled) _t.start();
  }

  @override
  void didUpdateWidget(Embers old) {
    super.didUpdateWidget(old);
    if (widget.enabled && !_t.isActive) _t.start();
    if (!widget.enabled && _t.isActive) _t.stop();
  }

  @override
  void dispose() {
    _t.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || MediaQuery.of(context).disableAnimations) return const SizedBox.shrink();
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(painter: _EmberPainter(_ps, widget.tint, _clock), size: Size.infinite),
      ),
    );
  }
}

class _P {
  final math.Random r;
  late double x, y, v, l, a, w;
  _P(this.r) {
    reset();
    y = r.nextDouble();
  }
  void reset() {
    x = r.nextDouble();
    y = 1.05;
    v = .0004 + r.nextDouble() * .0008;
    l = 6 + r.nextDouble() * 14;
    a = .15 + r.nextDouble() * .45;
    w = r.nextDouble() * math.pi * 2;
  }

  void step() {
    y -= v;
    w += .012;
    if (y < -.05) reset();
  }
}

class _EmberPainter extends CustomPainter {
  final List<_P> ps;
  final Color tint;
  _EmberPainter(this.ps, this.tint, Listenable repaint) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size s) {
    final paint = Paint()
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    for (final p in ps) {
      final px = (p.x + math.sin(p.w) * .01) * s.width, py = p.y * s.height;
      paint.color = tint.withValues(alpha: p.a * (p.y < .2 ? (p.y * 5).clamp(0, 1) : 1));
      canvas.drawLine(Offset(px, py), Offset(px - p.l * .35, py + p.l), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Título de sección con tipografía editorial.
class SectionTitle extends StatelessWidget {
  final String text;
  final String? italic;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.italic, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: text),
                if (italic != null)
                  TextSpan(
                    text: ' $italic',
                    style: T.serif(size: 44, style: FontStyle.italic, color: C.ink2),
                  ),
              ],
            ),
            style: T.serif(size: 44),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// Panel con borde fino.
class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final VoidCallback? onTap;
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(20), this.radius = 20, this.onTap});

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xC7120E11),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: const BorderSide(color: C.line),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(padding: padding, child: child),
    ),
  );
}
