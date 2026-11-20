import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hangar/data.dart';

void main() {
  test('parsea el catálogo con y sin arte', () {
    const raw = '{"juegos":[{"id":"b","nombre":"Beta","proyectos":["Beta Recomp"],"tipos":["recomp"],'
        '"repos":[{"repo":"x/beta","url":"https://github.com/x/beta","tipo":"recomp"}],"confianza_nombre":"alta","notas":[],"arte":null},'
        '{"id":"a","nombre":"Alfa","proyectos":[],"tipos":["decomp"],"repos":[{"repo":"y/alfa","tipo":"decomp"}],'
        '"confianza_nombre":"baja","notas":["?"],"arte":{"portada_thumb":"p.jpg","hero":"h.png"}}]}';
    final l = Catalogo.parse(raw);
    expect(l.map((j) => j.nombre), ['Alfa', 'Beta']);
    expect(l.first.cover, 'p.jpg');
    expect(l.first.hasHero, true);
    expect(l.first.dudoso, true);
    expect(l.last.subtitulo, 'Beta Recomp');
    expect(l.first.repos.first.url, 'https://github.com/y/alfa');
  });

  test('lee la información de instalación para Mac', () {
    const raw = '{"juegos":[{"id":"z","nombre":"Zelda","tipos":["recomp"],"repos":[{"repo":"a/b","tipo":"recomp",'
        '"mac":{"tag":"v1","asset":"Z-*-macOS.zip","args":["--rom","{game}"],"pasos":["uno"],"juego":{"tipo":"rom","texto":"Tu ROM"}}}]}]}';
    final r = Catalogo.parse(raw).single.repos.single;
    expect(r.mac?.asset, 'Z-*-macOS.zip');
    expect(r.mac?.pideCopia, true);
    expect(r.mac?.pasos, ['uno']);
    expect(r.mac?.juegoTexto, 'Tu ROM');
  });

  test('el catálogo de Mac del repo se puede leer', () {
    final l = Catalogo.parse(File('assets/juegos-mac.json').readAsStringSync());
    expect(l.length, greaterThan(400));
    expect(l.where((j) => j.repos.any((r) => r.mac?.asset != null)).length, greaterThan(400));
  });
}
