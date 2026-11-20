# Hangar

Launcher para Android de decomps, recomps y source ports de código abierto. Un selector de juegos a pantalla grande, tu partida y tus logros debajo, los proyectos de GitHub de cada juego y una biblioteca con buscador.

Hecho en Flutter para Android y Mac. Solo horizontal, como una consola.

## Descargar la app

Cada cambio en `app/` o `data/` compila la app y la publica en [Releases](../../releases/latest):

- **Android**: `hangar.apk`. Descárgalo en el dispositivo y ábrelo. Las builds van firmadas con una clave de depuración distinta cada vez: desinstala la anterior antes de instalar una nueva.
- **Mac**: `hangar-mac.zip`. Descomprímelo y arrastra Hangar a Aplicaciones. Como no está firmado por Apple, la primera vez hay que permitirlo en Ajustes del Sistema → Privacidad y seguridad → «Abrir igualmente», o ejecutar `xattr -dr com.apple.quarantine /Applications/Hangar.app`.

## Catálogo

`data/juegos.json` es la lista de juegos (nombre curado, proyectos, repos, tipo y arte de SteamGridDB).

- La app descarga la última versión desde la rama `main` del repo cada vez que se abre, así que **para actualizar el catálogo basta con editar este archivo en GitHub**: no hace falta compilar otra vez.
- Si no hay conexión, usa la copia que va dentro del APK.

## Estructura

```
app/                 proyecto Flutter
  lib/main.dart      barra lateral fija y navegación
  lib/home.dart      selector de juego y pantalla de tu partida
  lib/library.dart   biblioteca y búsqueda
  lib/pages.dart     logros, amigos y ajustes
  lib/data.dart      modelo del catálogo y descarga
data/juegos.json     catálogo
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

Lo que todavía no hace: instalar o lanzar los juegos (el botón Jugar abre las descargas del port en GitHub), cuentas, amigos y logros reales.
