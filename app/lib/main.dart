import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'data.dart';
import 'home.dart';
import 'library.dart';
import 'pages.dart';
import 'theme.dart';
import 'widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Solo horizontal, a pantalla completa, como una consola.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  final store = CatalogStore(), ajustes = Ajustes();
  await Future.wait([store.init(), ajustes.init()]);
  runApp(HangarApp(store: store, ajustes: ajustes));
}

class HangarApp extends StatelessWidget {
  final CatalogStore store;
  final Ajustes ajustes;
  const HangarApp({super.key, required this.store, required this.ajustes});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Hangar',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: Shell(store: store, ajustes: ajustes),
      );
}

/// Juegos que salen primero en el selector, si están en el catálogo.
const _portada = ['dark souls remastered', 'nier', 'majora', 'god of war iii', 'persona 5 royal', 'celeste', 'super mario galaxy', 'doom'];

enum Tab { juegos, biblioteca, logros, amigos, ajustes }

class Shell extends StatefulWidget {
  final CatalogStore store;
  final Ajustes ajustes;
  const Shell({super.key, required this.store, required this.ajustes});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  Tab _tab = Tab.juegos;
  int _index = 0;
  final List<String> _recientes = [];
  final _searchFocus = FocusNode(debugLabel: 'buscar');
  List<Juego> _destacados = const [];
  List<Juego>? _lastSource;

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  /// Selector: lo que has abierto hace poco y luego los juegos con arte grande.
  List<Juego> _selector(List<Juego> all) {
    if (!identical(all, _lastSource)) {
      _lastSource = all;
      final conHero = all.where((j) => j.hasHero).toList();
      int rank(Juego j) {
        final n = j.nombre.toLowerCase();
        final i = _portada.indexWhere((p) => n.startsWith(p) || n == p);
        return i < 0 ? 999 : i;
      }

      conHero.sort((a, b) {
        final r = rank(a).compareTo(rank(b));
        if (r != 0) return r;
        final l = (b.logo != null ? 1 : 0) - (a.logo != null ? 1 : 0);
        return l != 0 ? l : a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
      });
      _destacados = conHero;
    }
    final byId = {for (final j in all) j.id: j};
    final extra = _recientes.map((id) => byId[id]).whereType<Juego>().where((j) => !_destacados.contains(j)).toList();
    final l = [...extra, ..._destacados];
    return l.isEmpty ? all : l;
  }

  void _pick(Juego j) {
    setState(() {
      _recientes
        ..remove(j.id)
        ..insert(0, j.id);
      if (_recientes.length > 12) _recientes.removeLast();
      final l = _selector(widget.store.catalogo.juegos);
      _index = l.indexOf(j).clamp(0, l.length - 1);
      _tab = Tab.juegos;
    });
  }

  void _search() {
    setState(() => _tab = Tab.biblioteca);
    WidgetsBinding.instance.addPostFrameCallback((_) => _searchFocus.requestFocus());
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([widget.store, widget.ajustes]),
        builder: (context, _) {
          final all = widget.store.catalogo.juegos;
          final sel = _selector(all);
          if (_index >= sel.length) _index = 0;
          final byId = {for (final j in all) j.id: j};
          return Scaffold(
            body: LayoutBuilder(builder: (context, box) {
              final compact = box.maxHeight < 560;
              final gap = compact ? 8.0 : 14.0;
              return Padding(
                padding: EdgeInsets.all(gap),
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: C.card,
                    borderRadius: BorderRadius.circular(compact ? 20 : 30),
                    border: Border.all(color: const Color(0x0FFFFFFF)),
                    boxShadow: const [BoxShadow(color: Color(0xA6000000), blurRadius: 80, offset: Offset(0, 30))],
                  ),
                  child: Row(children: [
                    _Rail(tab: _tab, compact: compact, onTab: (t) => setState(() => _tab = t)),
                    Expanded(
                      child: IndexedStack(index: _tab.index, children: [
                        HomeScreen(
                          juegos: sel,
                          index: _index,
                          onIndex: (i) => setState(() => _index = i),
                          active: _tab == Tab.juegos,
                          chispas: widget.ajustes.chispas,
                          vibracion: widget.ajustes.vibracion,
                          onLibrary: () => setState(() => _tab = Tab.biblioteca),
                          onSearch: _search,
                        ),
                        LibraryScreen(
                          juegos: all,
                          destacados: {for (final j in _destacados) j.id},
                          recientes: _recientes,
                          searchFocus: _searchFocus,
                          onPick: _pick,
                        ),
                        LogrosScreen(recientes: _recientes.map((id) => byId[id]).whereType<Juego>().toList(), onPick: _pick),
                        const AmigosScreen(),
                        AjustesScreen(store: widget.store, ajustes: widget.ajustes),
                      ]),
                    ),
                  ]),
                ),
              );
            }),
          );
        },
      );
}

/// Barra lateral fija.
class _Rail extends StatelessWidget {
  final Tab tab;
  final bool compact;
  final ValueChanged<Tab> onTab;
  const _Rail({required this.tab, required this.compact, required this.onTab});

  @override
  Widget build(BuildContext context) {
    Widget b(Tab t, IconData icon, IconData on, String label) {
      final cur = tab == t;
      return Tooltip(
        message: label,
        preferBelow: false,
        child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
          if (cur)
            Positioned(
              left: compact ? -11 : -20,
              top: 12,
              bottom: 12,
              child: Container(width: 3, decoration: const BoxDecoration(color: C.acc, borderRadius: BorderRadius.horizontal(right: Radius.circular(3)))),
            ),
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => onTab(t),
              child: SizedBox.square(
                dimension: compact ? 42 : 52,
                child: Icon(cur ? on : icon, color: cur ? C.ink : C.ink3, size: compact ? 21 : 24, semanticLabel: label),
              ),
            ),
          ),
        ]),
      );
    }

    final gap = SizedBox(height: compact ? 4 : 14);
    return Container(
      width: compact ? 64 : 92,
      padding: EdgeInsets.symmetric(vertical: compact ? 12 : 26),
      decoration: const BoxDecoration(color: Color(0xCC0E0A0D), border: Border(right: BorderSide(color: C.line))),
      child: Column(children: [
        Avatar(size: compact ? 38 : 52),
        const Spacer(),
        b(Tab.juegos, Icons.sports_esports_outlined, Icons.sports_esports, 'Juegos'),
        gap,
        b(Tab.biblioteca, Icons.grid_view_outlined, Icons.grid_view_rounded, 'Biblioteca'),
        gap,
        b(Tab.logros, Icons.emoji_events_outlined, Icons.emoji_events, 'Logros'),
        gap,
        b(Tab.amigos, Icons.people_outline_rounded, Icons.people_rounded, 'Amigos'),
        const Spacer(),
        Container(width: compact ? 40 : 56, height: 1, color: C.line),
        SizedBox(height: compact ? 8 : 18),
        b(Tab.ajustes, Icons.settings_outlined, Icons.settings, 'Ajustes'),
      ]),
    );
  }
}
