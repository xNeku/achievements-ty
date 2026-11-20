import 'package:material_ui/material_ui.dart';

import 'data.dart';
import 'theme.dart';
import 'widgets.dart';

class _Page extends StatelessWidget {
  final String title, lead;
  final List<Widget> children;
  const _Page({required this.title, required this.lead, required this.children});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final compact = box.maxHeight < 560;
        return ListView(
          padding: EdgeInsets.fromLTRB(compact ? 28 : 64, compact ? 24 : 48, compact ? 28 : 64, 48),
          children: [
            Text(title, style: T.serif(size: compact ? 40 : 56)),
            const SizedBox(height: 8),
            Text(lead, style: T.sans(size: 15, color: C.ink2)),
            SizedBox(height: compact ? 22 : 34),
            ConstrainedBox(constraints: const BoxConstraints(maxWidth: 880), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)),
          ],
        );
      });
}

class LogrosScreen extends StatelessWidget {
  final List<Juego> recientes;
  final ValueChanged<Juego> onPick;
  const LogrosScreen({super.key, required this.recientes, required this.onPick});

  @override
  Widget build(BuildContext context) => _Page(
        title: 'Logros',
        lead: 'Aquí verás tu progreso en todos tus juegos.',
        children: [
          Panel(
            padding: const EdgeInsets.all(28),
            child: Row(children: [
              const Icon(Icons.emoji_events_outlined, color: C.acc, size: 34),
              const SizedBox(width: 20),
              Expanded(
                child: Text(
                  'Todavía no hay ningún juego con logros conectados. En cuanto un port los tenga, aparecerán aquí con tu porcentaje y tus horas.',
                  style: T.sans(size: 15, color: C.ink2, height: 1.5),
                ),
              ),
            ]),
          ),
          if (recientes.isNotEmpty) ...[
            const SizedBox(height: 34),
            Text('VISTOS HACE POCO', style: T.label(size: 11, w: FontWeight.w600)),
            const SizedBox(height: 12),
            for (final j in recientes)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Panel(
                  onTap: () => onPick(j),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(children: [
                    SizedBox(width: 44, height: 62, child: Cover(j, radius: 8, compact: true)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(j.nombre, style: T.sans(size: 15, w: FontWeight.w600)),
                        Text('0 h · sin logros todavía', style: T.sans(size: 13, color: C.ink2)),
                      ]),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: C.ink3),
                  ]),
                ),
              ),
          ],
        ],
      );
}

class AmigosScreen extends StatelessWidget {
  const AmigosScreen({super.key});

  @override
  Widget build(BuildContext context) => _Page(
        title: 'Amigos',
        lead: 'Busca a tus amigos, mira a qué juegan y compara logros.',
        children: [
          TextField(
            enabled: false,
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0x0AFFFFFF),
              hintText: 'Buscar por nombre de usuario',
              hintStyle: T.sans(size: 14, color: C.ink3),
              prefixIcon: const Icon(Icons.person_search_outlined, color: C.ink3),
              disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.line)),
            ),
          ),
          const SizedBox(height: 18),
          Panel(
            padding: const EdgeInsets.all(28),
            child: Row(children: [
              const Icon(Icons.group_outlined, color: C.pink, size: 34),
              const SizedBox(width: 20),
              Expanded(
                child: Text('Los amigos llegan con las cuentas de Hangar. Cuando estén listas, podrás añadir gente desde aquí.',
                    style: T.sans(size: 15, color: C.ink2, height: 1.5)),
              ),
            ]),
          ),
        ],
      );
}

class AjustesScreen extends StatelessWidget {
  final CatalogStore store;
  final Ajustes ajustes;
  const AjustesScreen({super.key, required this.store, required this.ajustes});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([store, ajustes]),
        builder: (context, _) {
          final c = store.catalogo;
          final when = c.actualizado == null
              ? 'la copia que trae la app'
              : 'descargado ${c.actualizado!.day}/${c.actualizado!.month} a las ${c.actualizado!.hour.toString().padLeft(2, '0')}:${c.actualizado!.minute.toString().padLeft(2, '0')}';
          Widget toggle(String t, String d, bool v, ValueChanged<bool> f) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Panel(
                  onTap: () => f(!v),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t, style: T.sans(size: 15, w: FontWeight.w600)),
                        Text(d, style: T.sans(size: 13, color: C.ink2)),
                      ]),
                    ),
                    Switch(value: v, onChanged: f, activeTrackColor: C.acc, activeThumbColor: Colors.white),
                  ]),
                ),
              );
          return _Page(
            title: 'Ajustes',
            lead: 'Lo justo para jugar a gusto.',
            children: [
              Panel(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Catálogo', style: T.sans(size: 15, w: FontWeight.w600)),
                      Text(
                        store.cargando
                            ? 'Buscando la última versión en GitHub…'
                            : '${c.juegos.length} juegos · $when${store.error != null ? ' · sin conexión con GitHub' : ''}',
                        style: T.sans(size: 13, color: C.ink2),
                      ),
                    ]),
                  ),
                  TextButton(
                    onPressed: store.cargando ? null : store.refresh,
                    style: TextButton.styleFrom(foregroundColor: C.ink),
                    child: Text('ACTUALIZAR', style: T.label(size: 12, color: store.cargando ? C.ink3 : C.ink, w: FontWeight.w600)),
                  ),
                ]),
              ),
              const SizedBox(height: 10),
              toggle('Vibración', 'Un toque corto al cambiar de juego.', ajustes.vibracion, (v) => ajustes.set(vib: v)),
              toggle('Chispas de fondo', 'Las chispas que suben detrás del juego.', ajustes.chispas, (v) => ajustes.set(fx: v)),
              const SizedBox(height: 24),
              Text('Hangar 0.1 · Arte de SteamGridDB', style: T.sans(size: 12, color: C.ink3)),
            ],
          );
        },
      );
}
