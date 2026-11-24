# Publish your port on Hangar

> **En castellano:** si haces ports, publícalos en Hangar con el
> [formulario](https://github.com/xNeku/achievements-ty/issues/new?template=publicar-port.yml) o poniendo el tema
> `hangar-port` en tu repositorio. Con un `hangar.json` en tu repo decides cómo sale y lleva el sello **del autor**.

Hangar is a launcher for decomps, recomps and source ports on **Android** and **Mac**. Players pick a game, Hangar
downloads your latest release from GitHub, installs it, launches it, and tracks playtime and achievements.
You keep shipping releases on GitHub as usual: Hangar always offers the newest one.

## Three ways in

1. **Fill the form** → [Publish a port](https://github.com/xNeku/achievements-ty/issues/new?template=publicar-port.yml).
   A bot checks your repo within a minute and tells you what it found.
2. **Add the `hangar-port` topic** to your repository (repo page → ⚙ next to *About* → *Topics*).
   Every day a bot looks for new repos with that topic and opens a review for them.
3. **Add a `hangar.json`** to the root of your default branch (optional, but recommended). Hangar re-reads it on every
   catalog refresh, so your listing stays the way you want. Only people with write access can add it, so ports with a
   `hangar.json` get the **author** badge in the app.

The Hangar team approves each new port once (to keep malware and ROM uploads out). After that, updates are automatic.

## `hangar.json`

Every field is optional.

```json
{
  "description": "Native PC port of the N64 classic, with widescreen and 60 fps.",
  "requirements": ["Your own N64 ROM (USA 1.0, .z64)"],
  "android": {
    "apk": "MyPort-*-arm64-v8a.apk"
  },
  "mac": {
    "asset": "MyPort-*-macOS.zip",
    "app": "MyPort.app",
    "args": ["--rom", "{game}"],
    "needs": "Your own N64 ROM"
  },
  "images": {
    "cover": "https://cdn2.steamgriddb.com/grid/....png",
    "hero": "https://cdn2.steamgriddb.com/hero/....png",
    "logo": "https://cdn2.steamgriddb.com/logo/....png"
  }
}
```

| Field | What it does |
| --- | --- |
| `description` | Shown on the game page (max. 400 characters). |
| `requirements` | What players must bring: the ROM, the disc, the original game files… |
| `android.apk` | Which APK of your release to install. `*` matches anything. Without it Hangar picks the best one (arm64 / universal). |
| `mac.asset` | Which file of your release is the Mac build (`.zip`, `.dmg`, `.tar.gz`, `.7z`). |
| `mac.app` | The `.app` or executable to launch inside it, if there are several. |
| `mac.args` | Launch arguments. `{game}` is replaced by the path of the player's own copy. |
| `mac.needs` | Short text for the "choose your copy" button. |
| `images` | `https` links. Cover is vertical box art (2:3), hero is a wide image without text, logo is a transparent PNG. |

## What Hangar will never do

- Host or link ROMs, ISOs or copyrighted game data. Players always bring their own copy.
- Re-upload your builds: downloads always come from your GitHub releases.
- List a repo that ships game assets.
