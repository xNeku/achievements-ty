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

Hace falta tu propia copia de cada juego.

- **Mac**: Hangar baja el archivo de la release del port en GitHub, comprueba su sha256 cuando el catálogo lo trae, lo descomprime (zip, dmg o tar) en `~/Library/Application Support/Hangar/juegos` y abre la app. Si el port necesita la copia del juego al arrancar, te pide el archivo una vez y lo recuerda. El tiempo de juego se cuenta solo.
- **Android**: baja el APK de la última release, abre el instalador del sistema y luego abre el juego desde Hangar.
- Los ports que se preparan a mano muestran sus pasos en el panel de versiones.

## Estructura

```
app/                 proyecto Flutter
  lib/main.dart      barra lateral fija y navegación
  lib/home.dart      selector de juego y pantalla de tu partida
  lib/library.dart   biblioteca y búsqueda
  lib/installer.dart descargar, instalar y abrir ports (Mac y Android)
  lib/play.dart      botón Jugar y panel de versiones
  lib/pages.dart     logros, amigos y ajustes
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

Lo que todavía no hace: cuentas, amigos y logros reales, y los ports que se preparan a mano (se muestran sus pasos).
