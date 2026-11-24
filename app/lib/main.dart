import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'amigos.dart';
import 'idioma.dart';
import 'bigpicture.dart';
import 'cuenta.dart';
import 'data.dart';
import 'home.dart';
import 'installer.dart';
import 'library.dart';
import 'logros.dart';
import 'pages.dart';
import 'perfil.dart';
import 'theme.dart';
import 'widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Solo horizontal, a pantalla completa, como una consola.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  // Cada sistema tiene su catálogo: los ports de Android no sirven en el Mac y al revés.
  final mac = kIsWeb ? (Uri.base.queryParameters.containsKey('mac') || Uri.base.fragment == 'mac') : Platform.isMacOS;
  catalogoMac = mac;
  final store = CatalogStore(mac ? 'juegos-mac.json' : 'juegos.json'), ajustes = Ajustes(), installer = Installer(), perfil = Perfil(), cuenta = Cuenta();
  await Future.wait([store.init(), ajustes.init(), installer.init(), perfil.init(), cuenta.init(), arteElegido.init(), idioma.init()]);
  runApp(HangarApp(store: store, ajustes: ajustes, installer: installer, perfil: perfil, cuenta: cuenta));
}

class HangarApp extends StatelessWidget {
  final CatalogStore store;
  final Ajustes ajustes;
  final Installer installer;
  final Perfil perfil;
  final Cuenta cuenta;
  const HangarApp({super.key, required this.store, required this.ajustes, required this.installer, required this.perfil, required this.cuenta});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Hangar',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    home: Shell(store: store, ajustes: ajustes, installer: installer, perfil: perfil, cuenta: cuenta),
  );
}

/// Juegos que salen primero en el selector, si están en el catálogo.
const _portada = ['dark souls remastered', 'nier', 'majora', 'god of war iii', 'persona 5 royal', 'celeste', 'super mario galaxy', 'doom'];

enum Tab { juegos, biblioteca, logros, amigos, ajustes, perfil }

class Shell extends StatefulWidget {
  final CatalogStore store;
  final Ajustes ajustes;
  final Installer installer;
  final Perfil perfil;
  final Cuenta cuenta;
  const Shell({super.key, required this.store, required this.ajustes, required this.installer, required this.perfil, required this.cuenta});
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
  late final AppLifecycleListener _life = AppLifecycleListener(onResume: widget.installer.comprobar);

  @override
  void initState() {
    super.initState();
    _life;
    widget.installer.addListener(_revisarLogros);
    widget.perfil.addListener(_revisarLogros);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revisarLogros();
      if (widget.ajustes.empezarBig) _abrirBig();
    });
  }

  /// Avisa cuando se gana un logro de Hangar.
  void _revisarLogros() {
    // Con cuenta, las horas y los logros se suben solos unos segundos después.
    widget.cuenta.sincronizarPronto(widget.installer, widget.perfil, widget.store.catalogo.juegos);
    final nuevos = widget.perfil.revisar(widget.installer);
    if (nuevos.isEmpty || !mounted) return;
    for (final h in nuevos) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: C.panel,
          width: 460,
          duration: const Duration(seconds: 4),
          content: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: h.color, borderRadius: BorderRadius.circular(12)),
                child: Icon(h.icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      t('LOGRO DESBLOQUEADO'),
                      style: T.label(size: 10, color: h.color, w: FontWeight.w600),
                    ),
                    Text(h.titulo, style: T.sans(size: 15, w: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    setState(() {});
  }

  bool _enBig = false;

  /// Modo Big Picture, a pantalla completa para la tele.
  Future<void> _abrirBig() async {
    if (_enBig) return;
    _enBig = true;
    final all = widget.store.catalogo.juegos;
    _selector(all);
    await abrirBigPicture(context, juegos: all, destacados: _destacados, installer: widget.installer);
    _enBig = false;
  }

  /// Mando: L1/R1 cambian de sección, B vuelve a Juegos y Start abre Big Picture.
  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final tabs = Tab.values;
    if (k == LogicalKeyboardKey.gameButtonStart || k == LogicalKeyboardKey.gameButtonMode || k == LogicalKeyboardKey.f11) {
      _abrirBig();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.gameButtonLeft1 || k == LogicalKeyboardKey.gameButtonRight1) {
      final i = (_tab.index + (k == LogicalKeyboardKey.gameButtonRight1 ? 1 : -1) + tabs.length) % tabs.length;
      setState(() => _tab = tabs[i]);
      return KeyEventResult.handled;
    }
    if ((k == LogicalKeyboardKey.gameButtonB || k == LogicalKeyboardKey.escape || k == LogicalKeyboardKey.goBack) && _tab != Tab.juegos) {
      setState(() => _tab = Tab.juegos);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    widget.installer.removeListener(_revisarLogros);
    widget.perfil.removeListener(_revisarLogros);
    _life.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Selector: lo que has abierto hace poco y luego los juegos con arte grande.
  List<Juego> _selector(List<Juego> all) {
    if (!identical(all, _lastSource)) {
      _lastSource = all;
      // Primero los que se pueden instalar aquí, luego los que tienen arte grande.
      final conHero = all.where((j) => j.hasHero || j.listo).toList();
      int rank(Juego j) {
        final base = j.listo ? 0 : 100000;
        return base + _rank0(j);
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

  int _rank0(Juego j) {
    if (j.orden < 9999) return j.orden; // el catálogo ya trae su orden (Mac)
    final n = j.nombre.toLowerCase();
    final i = _portada.indexWhere((p) => n.startsWith(p) || n == p);
    return i < 0 ? 100 + j.orden + (j.hasHero ? 0 : 20000) : i;
  }

  void _pick(Juego j) {
    widget.perfil.ver(j.id);
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
    listenable: Listenable.merge([widget.store, widget.ajustes, widget.installer, widget.perfil, arteElegido, idioma]),
    builder: (context, _) {
      final all = widget.store.catalogo.juegos;
      final sel = _selector(all);
      if (_index >= sel.length) _index = 0;
      final byId = {for (final j in all) j.id: j};
      return Scaffold(
        body: Focus(
          onKeyEvent: _onKey,
          child: LayoutBuilder(
            builder: (context, box) {
              final compact = box.maxHeight < 560;
              final gap = compact ? 8.0 : 14.0;
              final railW = compact ? 64.0 : 92.0;
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
                  // El arte del juego llega hasta el borde; la barra flota encima como cristal.
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: IndexedStack(
                          index: _tab.index,
                          children: [
                            HomeScreen(
                              inset: railW,
                              juegos: sel,
                              installer: widget.installer,
                              index: _index,
                              onIndex: (i) {
                                widget.perfil.ver(sel[i].id);
                                setState(() => _index = i);
                              },
                              active: _tab == Tab.juegos,
                              chispas: widget.ajustes.chispas,
                              vibracion: widget.ajustes.vibracion,
                              onLibrary: () => setState(() => _tab = Tab.biblioteca),
                              onSearch: _search,
                            ),
                            for (final page in [
                              LibraryScreen(
                                juegos: all,
                                destacados: {for (final j in _destacados) j.id},
                                recientes: _recientes,
                                instalados: {
                                  for (final j in all)
                                    for (final r in j.repos)
                                      if (widget.installer.instalado(r) != null) r.repo,
                                },
                                searchFocus: _searchFocus,
                                onPick: _pick,
                              ),
                              LogrosScreen(
                                perfil: widget.perfil,
                                installer: widget.installer,
                                recientes: _recientes.map((id) => byId[id]).whereType<Juego>().toList(),
                                onPick: _pick,
                              ),
                              AmigosScreen(cuenta: widget.cuenta, perfil: widget.perfil),
                              AjustesScreen(
                                store: widget.store,
                                ajustes: widget.ajustes,
                                perfil: widget.perfil,
                                installer: widget.installer,
                                cuenta: widget.cuenta,
                              ),
                              PerfilScreen(
                                perfil: widget.perfil,
                                installer: widget.installer,
                                cuenta: widget.cuenta,
                                juegos: all,
                                onPick: _pick,
                                onAmigos: () {
                                  widget.cuenta.cargarAmigos();
                                  setState(() => _tab = Tab.amigos);
                                },
                                onAjustes: () => setState(() => _tab = Tab.ajustes),
                                onLogros: () => setState(() => _tab = Tab.logros),
                              ),
                            ])
                              Padding(
                                padding: EdgeInsets.only(left: railW),
                                child: page,
                              ),
                          ],
                        ),
                      ),
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: railW,
                        child: _Rail(
                          tab: _tab,
                          compact: compact,
                          letra: widget.perfil.inicial,
                          onBig: _abrirBig,
                          onTab: (t) {
                            if (t == Tab.amigos) widget.cuenta.cargarAmigos();
                            setState(() => _tab = t);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      );
    },
  );
}

/// Barra lateral fija.
class _Rail extends StatelessWidget {
  final Tab tab;
  final bool compact;
  final ValueChanged<Tab> onTab;
  final VoidCallback onBig;
  final String letra;
  const _Rail({required this.tab, required this.compact, required this.letra, required this.onTab, required this.onBig});

  @override
  Widget build(BuildContext context) {
    Widget b(Tab t, IconData icon, IconData on, String label) {
      final cur = tab == t;
      return Tooltip(
        message: label,
        preferBelow: false,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            if (cur)
              Positioned(
                left: compact ? -11 : -20,
                top: 12,
                bottom: 12,
                child: Container(
                  width: 3,
                  decoration: const BoxDecoration(
                    color: C.acc,
                    borderRadius: BorderRadius.horizontal(right: Radius.circular(3)),
                  ),
                ),
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
          ],
        ),
      );
    }

    final gap = SizedBox(height: compact ? 4 : 14);
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: compact ? 12 : 26),
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xB30E0A0D), Color(0x8C0E0A0D)]),
            border: Border(right: BorderSide(color: Color(0x12FFFFFF))),
          ),
          child: Column(
            children: [
              Tooltip(
                message: t('Tu perfil'),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => onTab(Tab.perfil),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: tab == Tab.perfil ? C.acc : Colors.transparent, width: 2),
                    ),
                    child: Avatar(letter: letra, size: compact ? 34 : 48),
                  ),
                ),
              ),
              const Spacer(),
              b(Tab.juegos, Icons.sports_esports_outlined, Icons.sports_esports, t('Juegos')),
              gap,
              b(Tab.biblioteca, Icons.grid_view_outlined, Icons.grid_view_rounded, t('Biblioteca')),
              gap,
              b(Tab.logros, Icons.emoji_events_outlined, Icons.emoji_events, t('Logros')),
              gap,
              b(Tab.amigos, Icons.people_outline_rounded, Icons.people_rounded, t('Amigos')),
              const Spacer(),
              Container(width: compact ? 40 : 56, height: 1, color: C.line),
              SizedBox(height: compact ? 8 : 18),
              // Idioma: la bandera es la del idioma actual; al tocarla cambia al otro.
              Tooltip(
                message: idioma.ingles ? 'Cambiar a español' : 'Switch to English',
                preferBelow: false,
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: idioma.alternar,
                    child: SizedBox.square(
                      dimension: compact ? 42 : 52,
                      child: Center(child: Bandera(idioma.codigo, ancho: compact ? 24 : 28)),
                    ),
                  ),
                ),
              ),
              gap,
              Tooltip(
                message: t('Big Picture (Start)'),
                preferBelow: false,
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: onBig,
                    child: SizedBox.square(
                      dimension: compact ? 42 : 52,
                      child: Icon(Icons.tv_rounded, color: C.ink3, size: compact ? 21 : 24, semanticLabel: 'Big Picture'),
                    ),
                  ),
                ),
              ),
              gap,
              b(Tab.ajustes, Icons.settings_outlined, Icons.settings, t('Ajustes')),
            ],
          ),
        ),
      ),
    );
  }
}
