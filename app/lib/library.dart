import 'package:material_ui/material_ui.dart';

import 'data.dart';
import 'theme.dart';
import 'widgets.dart';

/// Biblioteca: colecciones a la izquierda, buscador y rejilla de portadas.
class LibraryScreen extends StatefulWidget {
  final List<Juego> juegos;
  final Set<String> destacados;
  final List<String> recientes;

  /// Repos instalados en este dispositivo.
  final Set<String> instalados;
  final FocusNode searchFocus;
  final ValueChanged<Juego> onPick;
  const LibraryScreen({
    super.key,
    required this.juegos,
    required this.destacados,
    required this.recientes,
    required this.instalados,
    required this.searchFocus,
    required this.onPick,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _q = TextEditingController();
  String _col = 'todos', _orden = 'arte';
  String? _tipo;

  @override
  void initState() {
    super.initState();
    _q.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  void _upd(VoidCallback f) => setState(f);

  List<Juego> get _list {
    Iterable<Juego> l = widget.juegos;
    switch (_col) {
      case 'arte':
        l = l.where((j) => j.cover != null);
      case 'listos':
        l = l.where((j) => j.listo);
      case 'instalados':
        l = l.where((j) => j.repos.any((r) => widget.instalados.contains(r.repo)));
      case 'destacados':
        l = l.where((j) => widget.destacados.contains(j.id));
      case 'recientes':
        final byId = {for (final j in widget.juegos) j.id: j};
        l = widget.recientes.map((id) => byId[id]).whereType<Juego>();
    }
    if (_tipo != null) l = l.where((j) => j.tipos.contains(_tipo) || j.repos.any((r) => r.tipo == _tipo));
    final q = _q.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      l = l.where(
        (j) =>
            j.nombre.toLowerCase().contains(q) || j.proyectos.any((p) => p.toLowerCase().contains(q)) || j.repos.any((r) => r.repo.toLowerCase().contains(q)),
      );
    }
    final out = l.toList();
    if (_col == 'recientes') return out;
    int az(Juego a, Juego b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
    switch (_orden) {
      case 'za':
        out.sort((a, b) => az(b, a));
      case 'az':
        out.sort(az);
      default:
        // Primero lo que se puede instalar aquí, luego lo que tiene portada.
        int peso(Juego j) => (j.listo ? 2 : 0) + (j.cover != null ? 1 : 0);
        out.sort((a, b) {
          final d = peso(b) - peso(a);
          return d != 0 ? d : az(a, b);
        });
    }
    return out;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final compact = box.maxHeight < 560, narrow = box.maxWidth < 760;
      final list = _list;
      return Row(
        children: [
          if (!narrow) _Side(state: this, compact: compact),
          Expanded(
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(compact ? 18 : 30, compact ? 14 : 26, compact ? 18 : 30, compact ? 10 : 18),
                  child: Row(
                    children: [
                      Expanded(
                        child: _SearchField(controller: _q, focus: widget.searchFocus, total: widget.juegos.length),
                      ),
                      const SizedBox(width: 12),
                      if (narrow)
                        _menu('Colección', _col, const {
                          'todos': 'Todos',
                          'listos': 'Listos para jugar',
                          'instalados': 'Instalados',
                          'arte': 'Con portada',
                          'recientes': 'Recientes',
                        }, (v) => _col = v),
                      if (narrow) const SizedBox(width: 12),
                      _menu('Tipo', _tipo ?? '', {'': 'Todos', ...tipoLabel}, (v) => _tipo = v.isEmpty ? null : v),
                      const SizedBox(width: 12),
                      _menu('Orden', _orden, const {'arte': 'Con portada primero', 'az': 'Nombre A–Z', 'za': 'Nombre Z–A'}, (v) => _orden = v),
                    ],
                  ),
                ),
                Expanded(
                  child: list.isEmpty
                      ? _Empty(q: _q.text)
                      : GridView.builder(
                          padding: EdgeInsets.fromLTRB(compact ? 18 : 30, 4, compact ? 18 : 30, 40),
                          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: compact ? 120 : 160,
                            childAspectRatio: 2 / 3,
                            mainAxisSpacing: compact ? 12 : 18,
                            crossAxisSpacing: compact ? 12 : 18,
                          ),
                          itemCount: list.length,
                          itemBuilder: (context, i) =>
                              _Tile(list[i], instalado: list[i].repos.any((r) => widget.instalados.contains(r.repo)), onTap: () => widget.onPick(list[i])),
                        ),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );

  Widget _menu(String label, String cur, Map<String, String> opts, ValueChanged<String> set) {
    final active = cur != opts.keys.first;
    return PopupMenuButton<String>(
      tooltip: label,
      color: C.panel,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: C.line),
      ),
      onSelected: (v) => setState(() => set(v)),
      itemBuilder: (_) => [
        for (final e in opts.entries)
          CheckedPopupMenuItem(
            value: e.key,
            checked: e.key == cur,
            child: Text(e.value, style: T.sans(size: 14)),
          ),
      ],
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0x0FFFFFFF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: active ? const Color(0x4DFFFFFF) : C.line),
        ),
        child: Row(
          children: [
            Text(
              (active ? '$label: ${opts[cur]}' : label).toUpperCase(),
              style: T.label(size: 11, color: active ? C.ink : C.ink2, w: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: C.ink2),
          ],
        ),
      ),
    );
  }
}

class _Side extends StatelessWidget {
  final _LibraryScreenState state;
  final bool compact;
  const _Side({required this.state, required this.compact});

  @override
  Widget build(BuildContext context) {
    final w = state.widget;
    final counts = <String, int>{};
    for (final j in w.juegos) {
      for (final t in {...j.tipos, ...j.repos.map((r) => r.tipo)}) {
        counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    Widget item(String label, int n, bool on, VoidCallback f) => Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: on ? const Color(0x1FF2507F) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: f,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: T.sans(size: 14, color: on ? C.pink : C.ink2, w: on ? FontWeight.w600 : FontWeight.w400),
                  ),
                ),
                Text('$n', style: T.sans(size: 12, color: C.ink3)),
              ],
            ),
          ),
        ),
      ),
    );
    Widget head(String s) => Padding(
      padding: const EdgeInsets.fromLTRB(10, 20, 0, 8),
      child: Text(s.toUpperCase(), style: T.label(size: 11, w: FontWeight.w600)),
    );
    return Container(
      width: compact ? 200 : 250,
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: C.line)),
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00120D10), Color(0x29F2507F)], stops: [.55, 1]),
      ),
      padding: EdgeInsets.fromLTRB(16, compact ? 16 : 30, 14, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 6),
            child: Row(
              children: [
                const Icon(Icons.landscape_outlined, color: C.pink, size: 28),
                const SizedBox(width: 10),
                Text('Hangar', style: T.sans(size: 18, w: FontWeight.w700)),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                head('Mis colecciones'),
                item(
                  'Todos los juegos',
                  w.juegos.length,
                  state._col == 'todos' && state._tipo == null,
                  () => state._upd(() {
                    state._col = 'todos';
                    state._tipo = null;
                  }),
                ),
                item('Listos para jugar', w.juegos.where((j) => j.listo).length, state._col == 'listos', () => state._upd(() => state._col = 'listos')),
                item(
                  'Instalados',
                  w.juegos.where((j) => j.repos.any((r) => w.instalados.contains(r.repo))).length,
                  state._col == 'instalados',
                  () => state._upd(() => state._col = 'instalados'),
                ),
                item('Con portada', w.juegos.where((j) => j.cover != null).length, state._col == 'arte', () => state._upd(() => state._col = 'arte')),
                item('Destacados', w.destacados.length, state._col == 'destacados', () => state._upd(() => state._col = 'destacados')),
                item('Recientes', w.recientes.length, state._col == 'recientes', () => state._upd(() => state._col = 'recientes')),
                head('Tipo de proyecto'),
                for (final e in tipoLabel.entries)
                  if ((counts[e.key] ?? 0) > 0)
                    item(e.value, counts[e.key]!, state._tipo == e.key, () => state._upd(() => state._tipo = state._tipo == e.key ? null : e.key)),
              ],
            ),
          ),
          if (!compact)
            Center(
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  const Avatar(size: 76, glow: C.pink),
                  const SizedBox(height: 10),
                  Text('Tu perfil', style: T.sans(size: 14, w: FontWeight.w600)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focus;
  final int total;
  const _SearchField({required this.controller, required this.focus, required this.total});

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    focusNode: focus,
    style: T.sans(size: 14),
    textInputAction: TextInputAction.search,
    decoration: InputDecoration(
      isDense: true,
      filled: true,
      fillColor: const Color(0x0FFFFFFF),
      hintText: 'Busca entre $total juegos o repos',
      hintStyle: T.sans(size: 14, color: C.ink3),
      prefixIcon: const Icon(Icons.search_rounded, color: C.ink2, size: 20),
      suffixIcon: controller.text.isEmpty
          ? null
          : IconButton(
              icon: const Icon(Icons.close_rounded, size: 18, color: C.ink2),
              tooltip: 'Borrar',
              onPressed: controller.clear,
            ),
      contentPadding: const EdgeInsets.symmetric(vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: C.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0x59FFFFFF)),
      ),
    ),
  );
}

class _Tile extends StatefulWidget {
  final Juego j;
  final bool instalado;
  final VoidCallback onTap;
  const _Tile(this.j, {required this.instalado, required this.onTap});
  @override
  State<_Tile> createState() => _TileState();
}

/// Portada que se puede elegir con el dedo, el ratón o el mando (se ilumina al tener el foco).
class _TileState extends State<_Tile> {
  bool _on = false;
  @override
  Widget build(BuildContext context) {
    final chip = widget.instalado ? ('INSTALADO', C.ok) : (widget.j.listo ? ('LISTO', C.pink) : null);
    return Semantics(
      button: true,
      label: widget.j.nombre,
      child: InkWell(
        onTap: widget.onTap,
        onHover: (v) => setState(() => _on = v),
        onFocusChange: (v) => setState(() => _on = v),
        borderRadius: BorderRadius.circular(16),
        focusColor: Colors.transparent,
        hoverColor: Colors.transparent,
        child: AnimatedScale(
          scale: _on ? 1.04 : 1,
          duration: const Duration(milliseconds: 200),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _on ? C.pink : Colors.transparent, width: 2),
              boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 12))],
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Cover(widget.j, radius: 14),
                if (chip != null)
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(color: const Color(0xCC0E0A0D), borderRadius: BorderRadius.circular(6)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(color: chip.$2, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            chip.$1,
                            style: T.label(size: 9, color: C.ink, w: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final String q;
  const _Empty({required this.q});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(40),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Nada por aquí', style: T.serif(size: 36)),
        const SizedBox(height: 8),
        Text(
          q.isEmpty ? 'Esta colección está vacía.' : 'Ningún juego coincide con «$q». Prueba con otra palabra o quita algún filtro.',
          style: T.sans(size: 15, color: C.ink2),
        ),
      ],
    ),
  );
}
