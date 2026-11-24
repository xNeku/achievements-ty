import 'package:url_launcher/url_launcher.dart';

import 'data.dart';

/// Repositorio de Hangar, donde se publican ports e imágenes (formularios de issues).
const repoHangar = String.fromEnvironment('HANGAR_REPO', defaultValue: 'xNeku/achievements-ty');

Future<void> _abrir(String plantilla, Map<String, String> campos) => launchUrl(
  Uri.https('github.com', '/$repoHangar/issues/new', {'template': plantilla, ...campos}),
  mode: LaunchMode.externalApplication,
);

/// Formulario para publicar un port en Hangar (ya con la plataforma en la que estás).
Future<void> publicarPort({String nombre = ''}) => _abrir('publicar-port.yml', {
  'plataforma': catalogoMac ? 'Mac' : 'Android',
  if (nombre.isNotEmpty) ...{'nombre': nombre, 'title': '[Port] $nombre'},
});

/// La guía para desarrolladores: formulario, tema hangar-port y hangar.json.
Future<void> comoPublicar() => launchUrl(Uri.parse('https://github.com/$repoHangar/blob/main/PUBLISH.md'), mode: LaunchMode.externalApplication);

/// Formulario para proponer mejores imágenes de un juego.
Future<void> mejorarImagenes(Juego g) => _abrir('mejorar-imagenes.yml', {'juego': g.nombre, 'title': '[Images] ${g.nombre}'});

/// Los fallos de un port se cuentan en su propio repositorio, que es quien lo puede arreglar.
Future<void> informarFallo(Repo r) => launchUrl(Uri.parse('${r.url}/issues'), mode: LaunchMode.externalApplication);
