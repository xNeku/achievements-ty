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

## Servidor (cuentas, amigos y logros)

`server/` monta en un VPS pequeño (2 GB de RAM basta) [PocketBase](https://pocketbase.io) con las cuentas, amistades, partidas y logros desbloqueados, y Caddy con HTTPS automático. Sin dominio usa `<ip-con-guiones>.sslip.io`.

```bash
# En el VPS (AlmaLinux/Rocky/RHEL 8 o 9), como root:
curl -fsSL https://raw.githubusercontent.com/xNeku/achievements-ty/main/server/instalar.sh | RAMA=main bash
```

El script instala todo, crea la cuenta del panel (te enseña la contraseña una vez), activa 1 GB de swap y deja un temporizador que cada noche baja la última `logros.db` y los catálogos a `https://<servidor>/logros/`.

Para que las apps lo usen sin escribirlo a mano, guarda la dirección en GitHub como variable del repo `HANGAR_SERVER` (Settings → Secrets and variables → Actions → Variables). También se puede escribir en Ajustes → Cuenta de Hangar.

## Los desarrolladores publican sus ports

Hangar se alimenta de quien hace los ports. Guía para ellos (en inglés): [PUBLISH.md](PUBLISH.md).

- **Formulario** `.github/ISSUE_TEMPLATE/publicar-port.yml` (bilingüe). Desde la app: botón `+` de la biblioteca o
  «¿Haces ports?» en Ajustes. Un bot (`.github/workflows/propuestas.yml` + `tools/propuestas.py`) revisa el repo,
  su `hangar.json`, el APK o la descarga de Mac, y comenta lo que ve.
- **Tema `hangar-port`**: cada día el bot busca repos con ese tema y abre una issue ya revisada para cada uno nuevo.
- **`hangar.json`** en el repo del port: su autor decide descripción, requisitos, qué APK o archivo de Mac bajar, cómo
  arrancarlo e imágenes. `tools/revisar_catalogo.py` lo relee en cada build. Lleva el sello **del autor** en la app
  (también si lo envía el dueño del repo).
- **Aprobar**: etiqueta `aprobado` (solo quien tiene permiso en el repo). Entra en `data/juegos*.json`, se cierra la
  issue y se lanza la build. La app lo ve al momento (lee el catálogo de `main`), sin actualizarse.
- **Imágenes**: alternativas de SteamGridDB (`tools/arte/steamgriddb.py`, secreto `SGDB_API_KEY`), elegibles en la app
  con «Cambiar imágenes»; «Proponer otra» abre `mejorar-imagenes.yml`, con la misma aprobación.

Las issues solo disparan workflows de la rama principal: esto funciona cuando está en `main`.

## Idioma

Castellano e inglés. La bandera de la barra lateral (o Ajustes → Idioma) cambia al momento. Los textos se escriben en
castellano dentro de `t('…')` y su traducción va en `app/lib/en.dart`; un test falla si alguno no está traducido.

## Modo Big Picture

Pantalla completa para la tele y el mando: botón de la tele en la barra, o Start en el mando.
Filas de Seguir jugando, Listos para jugar y Destacados. A juega, Y abre las versiones, B sale.
En Ajustes se puede hacer que Hangar arranque directamente así.

## Lo que hace distinto a Hangar

- Android y Mac, en horizontal y con mando (cruceta, A, B, L1 y R1).
- Logros de Hangar: doce logros que se ganan usando la app (instalar, jugar horas, explorar el catálogo…), con aviso al desbloquearlos.
- Cuenta de Hangar en tu propio servidor: tus horas y logros se guardan en ella y puedes añadir amigos y ver a qué juegan.

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
  lib/cuenta.dart    cuenta, sincronización y amigos (servidor)
  lib/amigos.dart    pantalla de amigos y ventana de cuenta
server/              instalación del servidor (PocketBase + Caddy)
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

Lo que todavía no hace: desbloquear los logros de cada juego, ajustes por juego y preparar los ports que se montan a mano (se muestran sus pasos).
