import 'package:material_ui/material_ui.dart';

import 'cuenta.dart';
import 'idioma.dart';
import 'logros.dart';
import 'theme.dart';
import 'widgets.dart';

String _horas(int s) => s < 3600 ? '${(s / 60).floor()} min' : '${(s / 3600).toStringAsFixed(1).replaceAll('.', idioma.ingles ? '.' : ',')} h';

/// Ventana para entrar o crear tu cuenta de Hangar.
Future<void> abrirCuenta(BuildContext context, Cuenta cuenta, Perfil perfil) => showDialog(
  context: context,
  builder: (_) => _CuentaDialog(cuenta: cuenta, perfil: perfil),
);

class _CuentaDialog extends StatefulWidget {
  final Cuenta cuenta;
  final Perfil perfil;
  const _CuentaDialog({required this.cuenta, required this.perfil});
  @override
  State<_CuentaDialog> createState() => _CuentaDialogState();
}

class _CuentaDialogState extends State<_CuentaDialog> {
  bool _nueva = false;
  final _email = TextEditingController(), _pass = TextEditingController();
  late final _nombre = TextEditingController(text: widget.perfil.nombre);
  late final _servidor = TextEditingController(text: widget.cuenta.servidor);

  @override
  void dispose() {
    for (final c in [_email, _pass, _nombre, _servidor]) {
      c.dispose();
    }
    super.dispose();
  }

  InputDecoration _dec(String hint) => InputDecoration(
    isDense: true,
    hintText: hint,
    hintStyle: T.sans(size: 14, color: C.ink3),
    filled: true,
    fillColor: const Color(0x0FFFFFFF),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: C.line),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0x59FFFFFF)),
    ),
  );

  Future<void> _ok() async {
    final c = widget.cuenta;
    if (_servidor.text.trim() != c.servidor) c.setServidor(_servidor.text);
    final ok = _nueva ? await c.registrar(_email.text.trim(), _pass.text, _nombre.text.trim()) : await c.entrar(_email.text.trim(), _pass.text);
    if (!mounted) return;
    if (ok) {
      if (_nueva && _nombre.text.trim().isNotEmpty) widget.perfil.setNombre(_nombre.text.trim());
      if (!_nueva && (c.nombre ?? '').isNotEmpty && widget.perfil.nombre.isEmpty) widget.perfil.setNombre(c.nombre!);
      Navigator.pop(context);
      await c.cargarAmigos();
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.cuenta,
    builder: (context, _) {
      final c = widget.cuenta;
      return Dialog(
        backgroundColor: C.panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(_nueva ? t('Crear cuenta') : t('Entrar'), style: T.serif(size: 36)),
                const SizedBox(height: 6),
                Text(t('Tu cuenta guarda tus horas y logros, y te deja añadir amigos.'), style: T.sans(size: 13, color: C.ink2)),
                const SizedBox(height: 20),
                if (!c.configurado || _servidor.text.isNotEmpty && _servidor.text != c.servidor || servidorPorDefecto.isEmpty) ...[
                  TextField(
                    controller: _servidor,
                    style: T.sans(size: 14),
                    keyboardType: TextInputType.url,
                    decoration: _dec('Servidor (p. ej. https://1-2-3-4.sslip.io)'),
                  ),
                  const SizedBox(height: 10),
                ],
                if (_nueva) ...[
                  TextField(controller: _nombre, style: T.sans(size: 14), decoration: _dec(t('Tu nombre (lo verán tus amigos)'))),
                  const SizedBox(height: 10),
                ],
                TextField(controller: _email, style: T.sans(size: 14), keyboardType: TextInputType.emailAddress, decoration: _dec(t('Correo'))),
                const SizedBox(height: 10),
                TextField(
                  controller: _pass,
                  style: T.sans(size: 14),
                  obscureText: true,
                  decoration: _dec(_nueva ? t('Contraseña (8 caracteres o más)') : t('Contraseña')),
                  onSubmitted: (_) => _ok(),
                ),
                if (c.error != null) ...[const SizedBox(height: 12), Text(c.error!, style: T.sans(size: 13, color: const Color(0xFFFF8A80)))],
                const SizedBox(height: 20),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => setState(() => _nueva = !_nueva),
                      child: Text(_nueva ? t('Ya tengo cuenta') : t('Crear una cuenta'), style: T.sans(size: 13, color: C.ink2)),
                    ),
                    const Spacer(),
                    c.ocupado
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: C.acc))
                        : PlayPill(onTap: _ok, label: _nueva ? t('Crear') : t('Entrar'), icon: Icons.arrow_forward_rounded, compact: true),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Amigos: buscar gente, solicitudes y a qué juegan tus amigos.
class AmigosScreen extends StatefulWidget {
  final Cuenta cuenta;
  final Perfil perfil;
  const AmigosScreen({super.key, required this.cuenta, required this.perfil});
  @override
  State<AmigosScreen> createState() => _AmigosScreenState();
}

class _AmigosScreenState extends State<AmigosScreen> {
  final _q = TextEditingController();
  List<Amigo> _resultados = const [];
  bool _buscando = false;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    setState(() => _buscando = true);
    final r = await widget.cuenta.buscar(_q.text);
    if (!mounted) return;
    setState(() {
      _resultados = r;
      _buscando = false;
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.cuenta, widget.perfil]),
    builder: (context, _) {
      final c = widget.cuenta;
      return LayoutBuilder(
        builder: (context, box) {
          final compact = box.maxHeight < 560;
          return ListView(
            padding: EdgeInsets.fromLTRB(compact ? 28 : 64, compact ? 24 : 48, compact ? 28 : 64, 48),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(t('Amigos'), style: T.serif(size: compact ? 40 : 56)),
                  ),
                  if (c.dentro)
                    IconButton(
                      onPressed: c.ocupado ? null : c.cargarAmigos,
                      tooltip: t('Actualizar'),
                      icon: const Icon(Icons.refresh_rounded, color: C.ink2),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                c.dentro
                    ? t('{0} amigos · conectado como {1}', [c.amigos.length, c.nombre?.isNotEmpty == true ? c.nombre : c.email])
                    : t('Busca a tus amigos, mira a qué juegan y compara logros.'),
                style: T.sans(size: 15, color: C.ink2),
              ),
              SizedBox(height: compact ? 22 : 34),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 880),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: c.dentro ? _conectado(c) : _sinCuenta(context, c)),
              ),
            ],
          );
        },
      );
    },
  );

  List<Widget> _sinCuenta(BuildContext context, Cuenta c) => [
    Panel(
      padding: const EdgeInsets.all(28),
      child: Row(
        children: [
          Avatar(letter: widget.perfil.inicial, size: 56, online: false),
          const SizedBox(width: 20),
          Expanded(
            child: Text(
              t('Para tener amigos necesitas una cuenta de Hangar. Tus horas y tus logros se guardan en ella y se ven desde cualquier dispositivo.'),
              style: T.sans(size: 15, color: C.ink2, height: 1.5),
            ),
          ),
          const SizedBox(width: 16),
          PlayPill(onTap: () => abrirCuenta(context, c, widget.perfil), label: t('Entrar'), icon: Icons.person_rounded, compact: true),
        ],
      ),
    ),
  ];

  List<Widget> _conectado(Cuenta c) {
    final buscar = TextField(
      controller: _q,
      style: T.sans(size: 14),
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => _buscar(),
      decoration: InputDecoration(
        filled: true,
        fillColor: const Color(0x0FFFFFFF),
        hintText: t('Buscar por nombre'),
        hintStyle: T.sans(size: 14, color: C.ink3),
        prefixIcon: const Icon(Icons.person_search_outlined, color: C.ink2),
        suffixIcon: _buscando
            ? const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: C.acc)),
              )
            : IconButton(
                icon: const Icon(Icons.arrow_forward_rounded, color: C.ink2),
                onPressed: _buscar,
                tooltip: t('Buscar'),
              ),
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
    final yaRelacion = {for (final a in c.amistades) a.otro.id};
    Widget fila(Amigo a, {String? texto, List<Widget> acciones = const [], bool online = false}) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Panel(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            Avatar(letter: a.inicial, size: 46, online: online),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.nombre, style: T.sans(size: 15, w: FontWeight.w600)),
                  if (texto != null)
                    Text(
                      texto,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: T.sans(size: 13, color: C.ink2),
                    ),
                ],
              ),
            ),
            ...acciones,
          ],
        ),
      ),
    );
    Widget boton(String t, VoidCallback f, {Color color = C.ink}) => TextButton(
      onPressed: c.ocupado ? null : f,
      child: Text(
        t,
        style: T.label(size: 11, color: color, w: FontWeight.w600),
      ),
    );
    Widget titulo(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(2, 26, 0, 10),
      child: Text(t, style: T.label(size: 11, w: FontWeight.w600)),
    );

    return [
      buscar,
      if (c.error != null)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(c.error!, style: T.sans(size: 13, color: const Color(0xFFFF8A80))),
        ),
      if (_resultados.isNotEmpty) ...[
        titulo(t('RESULTADOS')),
        for (final a in _resultados)
          fila(
            a,
            acciones: [yaRelacion.contains(a.id) ? Text(t('YA ESTÁ'), style: T.label(size: 11)) : boton(t('AÑADIR'), () => c.pedir(a), color: C.pink)],
          ),
      ],
      if (c.pendientesParaMi.isNotEmpty) ...[
        titulo(t('TE QUIEREN AÑADIR')),
        for (final a in c.pendientesParaMi)
          fila(
            a.otro,
            acciones: [
              boton(t('RECHAZAR'), () => c.quitar(a), color: C.ink3),
              boton(t('ACEPTAR'), () => c.aceptar(a), color: C.ok),
            ],
          ),
      ],
      titulo(t('TUS AMIGOS')),
      if (c.amigos.isEmpty)
        Text(t('Todavía no tienes amigos en Hangar. Búscalos por su nombre.'), style: T.sans(size: 14, color: C.ink2))
      else
        for (final a in c.amigos)
          () {
            final act = c.actividad[a.otro.id] ?? const [];
            final ult = act.isEmpty ? null : act.first;
            return fila(
              a.otro,
              online: ult?.ultima != null && DateTime.now().difference(ult!.ultima!).inMinutes < 30,
              texto: ult == null ? t('Aún no ha jugado con Hangar') : t('Jugó a {0} · {1} en total', [ult.nombre, _horas(ult.segundos)]),
              acciones: [boton(t('QUITAR'), () => c.quitar(a), color: C.ink3)],
            );
          }(),
      if (c.pendientesMias.isNotEmpty) ...[
        titulo(t('ESPERANDO RESPUESTA')),
        for (final a in c.pendientesMias)
          fila(
            a.otro,
            texto: t('Solicitud enviada'),
            acciones: [boton(t('CANCELAR'), () => c.quitar(a), color: C.ink3)],
          ),
      ],
    ];
  }
}
