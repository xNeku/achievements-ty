import 'package:material_ui/material_ui.dart';

import 'comunidad.dart';
import 'idioma.dart';
import 'data.dart';
import 'theme.dart';
import 'widgets.dart';

/// Elegir la portada, el fondo y el logo de un juego entre las opciones que hay.
/// Lo que elijas se queda en este dispositivo; si ninguna convence, se propone otra en GitHub.
Future<void> elegirImagenes(BuildContext context, Juego g) => showDialog(
  context: context,
  barrierColor: const Color(0xB3000000),
  builder: (_) => _Selector(g: g),
);

class _Selector extends StatefulWidget {
  final Juego g;
  const _Selector({required this.g});
  @override
  State<_Selector> createState() => _SelectorState();
}

class _SelectorState extends State<_Selector> {
  String _tipo = 'portada';
  Map<String, String> get _tipos => {'portada': t('Portada'), 'hero': t('Fondo'), 'logo': 'Logo'};

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: arteElegido,
    builder: (context, _) {
      final g = widget.g;
      final ops = g.opciones(_tipo);
      final elegida = arteElegido.de(g.id, _tipo);
      final actual = elegida ?? (ops.isEmpty ? null : ops.first.url);
      final (aspecto, ancho) = switch (_tipo) {
        'portada' => (2 / 3, 150.0),
        'hero' => (16 / 9, 300.0),
        _ => (2.4, 260.0),
      };
      return Dialog(
        backgroundColor: C.panel,
        insetPadding: const EdgeInsets.all(28),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980, maxHeight: 640),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(30, 26, 30, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t('Imágenes'), style: T.serif(size: 34)),
                    Text(g.nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.sans(size: 14, color: C.ink2)),
                  ]),
                ),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  style: SegmentedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    selectedBackgroundColor: C.acc,
                    foregroundColor: C.ink2,
                    selectedForegroundColor: Colors.white,
                    side: const BorderSide(color: C.line),
                  ),
                  segments: [
                    for (final e in _tipos.entries)
                      ButtonSegment(value: e.key, label: Text('${e.value} (${g.opciones(e.key).length})', style: T.sans(size: 13))),
                  ],
                  selected: {_tipo},
                  onSelectionChanged: (v) => setState(() => _tipo = v.first),
                ),
                const SizedBox(width: 8),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: C.ink2), tooltip: t('Cerrar')),
              ]),
              const SizedBox(height: 18),
              Expanded(
                child: ops.isEmpty
                    ? Center(
                        child: Text(
                          t('Todavía no hay {0} para este juego.', [_tipos[_tipo]!.toLowerCase()]),
                          style: T.sans(size: 15, color: C.ink2),
                        ),
                      )
                    : GridView.builder(
                        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: ancho,
                          childAspectRatio: aspecto,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 14,
                        ),
                        itemCount: ops.length,
                        itemBuilder: (context, i) {
                          final o = ops[i];
                          final on = o.url == actual;
                          return InkWell(
                            borderRadius: BorderRadius.circular(14),
                            // La primera es la del catálogo: elegirla es quitar tu elección.
                            onTap: () => arteElegido.elegir(g.id, _tipo, i == 0 ? null : o.url),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              decoration: BoxDecoration(
                                color: _tipo == 'logo' ? const Color(0xFF1C171B) : null,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: on ? C.pink : C.line, width: on ? 3 : 1),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(on ? 11 : 13),
                                child: Stack(fit: StackFit.expand, children: [
                                  Padding(
                                    padding: EdgeInsets.all(_tipo == 'logo' ? 14 : 0),
                                    child: NetImg(o.thumb, fit: _tipo == 'logo' ? BoxFit.contain : BoxFit.cover, cacheWidth: 400),
                                  ),
                                  if (i == 0)
                                    Positioned(
                                      left: 8,
                                      bottom: 8,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(color: const Color(0xD90E0A0D), borderRadius: BorderRadius.circular(8)),
                                        child: Text(t('CATÁLOGO'), style: T.label(size: 9, color: C.ink2, w: FontWeight.w600)),
                                      ),
                                    ),
                                  if (on)
                                    const Positioned(
                                      right: 8,
                                      top: 8,
                                      child: CircleAvatar(radius: 13, backgroundColor: C.pink, child: Icon(Icons.check_rounded, size: 16, color: Colors.white)),
                                    ),
                                ]),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: Text(
                    t('Lo que elijas solo cambia en este dispositivo. ¿Tienes una mejor? Propónla y saldrá para todos.'),
                    style: T.sans(size: 13, color: C.ink3),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => mejorarImagenes(g),
                  icon: const Icon(Icons.add_photo_alternate_outlined, size: 18, color: C.ink),
                  label: Text(t('PROPONER OTRA'), style: T.label(size: 11, color: C.ink, w: FontWeight.w600)),
                ),
              ]),
            ]),
          ),
        ),
      );
    },
  );
}
