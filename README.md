# Hangar

Launcher para Android de decomps, recomps y source ports de código abierto. Un selector de juegos a pantalla grande, tu partida y tus logros debajo, los proyectos de GitHub de cada juego y una biblioteca con buscador.

Hecho en Flutter para Android y Mac. Solo horizontal, como una consola.

## Descargar la app

Cada cambio en `app/` o `data/` compila la app y la publica en [Releases](../../releases/latest):

- **Android**: `hangar.apk`. Descárgalo en el dispositivo y ábrelo. Todas las builds van firmadas con la misma clave, así que se instalan encima de la anterior.
- **Mac**: `hangar-mac.zip`. Descomprímelo y arrastra Hangar a Aplicaciones. Como no está firmado por Apple, la primera vez hay que permitirlo en Ajustes del Sistema → Privacidad y seguridad → «Abrir igualmente», o ejecutar `xattr -dr com.apple.quarantine /Applications/Hangar.app`.

## Catálogos

Cada sistema tiene el suyo, porque los ports de uno no sirven en el otro:

- `data/juegos.json`: Android. Nombre curado, proyectos, repos, tipo y arte de SteamGridDB.
- `data/juegos-mac.json`: Mac. Sale del catálogo de [RecompLauncher](https://recomplauncher.com), con permiso de su desarrollador: qué archivo bajar de cada release, su sha256, qué copia del juego pide y cómo se arranca.

La app descarga la versión de la rama `main` al abrirse, así que **para actualizar un catálogo basta con editar el archivo en GitHub**. Sin conexión usa la copia que lleva dentro.

## Instalar y jugar

Hace falta tu propia copia de cada juego (la ROM o el disco).

- **Revisor de ports**: en cada build, `tools/revisar_catalogo.py` mira en GitHub cada repo del catálogo: qué APK publica (Android), cuál es la última descarga para Mac, si está archivado y qué pide su README para jugar. Así Hangar sabe qué juegos se pueden instalar de verdad sin preguntar a GitHub desde el dispositivo.
- **Android**: descarga el APK, abre el instalador del sistema y luego abre el juego. Con el permiso de «acceso a uso» cuenta cuánto juegas a cada port.
- **Mac**: descarga la release, comprueba el sha256, descomprime (zip, dmg, tar, 7z o rar), comprueba que tu copia es la que pide el port (IDs del disco o tamaño y CRC de la ROM) y abre la app pasándole tu copia si la necesita. El tiempo de juego se cuenta solo.
- **Actualizaciones**: si el catálogo trae una versión más nueva que la instalada, aparece «Actualizar» en el panel de versiones. Se conservan tu copia y tu tiempo jugado.
- Los ports que se preparan a mano muestran sus pasos en el panel de versiones.

## Base de datos de logros

`tools/logros/construir.py` junta en un único SQLite (`logros.db`, publicado en cada Release) las listas de logros de varias fuentes y enlaza cada juego de nuestros catálogos con la suya:

| Fuente | Qué aporta | Estado |
|---|---|---|
| Volcado de Xbox 360 y Xbox One | ~2.600 juegos, ~95.000 logros con icono | activo |
| RetroAchievements (Web API) | N64, PS1, PS2, GameCube, SNES, GBA… | listo, falta la clave `RA_API_KEY` |
| Steam (`GetSchemaForGame`) | ports de PC | pendiente |

Solo se guardan los datos de los logros (nombre, descripción, puntos e icono); Hangar no vincula ninguna cuenta. Cada juego enlazado lleva su lista en `data/logros/<android|mac>/<id>.json`, que la app muestra en la pantalla del juego. Desbloquearlos necesita que el port avise a Hangar.

## Lo que hace distinto a Hangar

- Android y Mac, en horizontal y con mando (cruceta, A, B, L1 y R1).
- Logros de Hangar: doce logros que se ganan usando la app (instalar, jugar horas, explorar el catálogo…), con aviso al desbloquearlos.
- Perfil con tu nombre. Los amigos llegarán con las cuentas en la nube.

## Estructura

```
app/                 proyecto Flutter
  lib/main.dart      barra lateral fija y navegación
  lib/home.dart      selector de juego y pantalla de tu partida
  lib/library.dart   biblioteca y búsqueda
  lib/installer.dart descargar, instalar y abrir ports (Mac y Android)
  lib/play.dart      botón Jugar y panel de versiones
  lib/pages.dart     logros, amigos y ajustes
  lib/logros.dart    logros de Hangar y perfil
tools/revisar_catalogo.py  revisa en GitHub los ports de los catálogos
tools/logros/construir.py  base de datos de logros
data/logros/         listas de logros de cada juego del catálogo
  lib/data.dart      modelo del catálogo y descarga
data/juegos*.json    catálogos de Android y Mac
.github/workflows/   compilación de Android y Mac
```

## Desarrollo

```bash
cd app
flutter pub get
flutter run            # con un Android conectado, o -d macos en un Mac
flutter build apk
flutter build macos    # solo desde un Mac
```

Lo que todavía no hace: cuentas y amigos en la nube, desbloquear los logros de cada juego, ajustes por juego y preparar los ports que se montan a mano (se muestran sus pasos).
