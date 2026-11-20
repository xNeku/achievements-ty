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
}
