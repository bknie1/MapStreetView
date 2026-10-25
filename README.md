# Map Street View

Rotate, tilt, and zoom the Cyberpunk 2077 world map, the way you could at launch, with mouse, controller, or keyboard.

[Nexus Mods page](https://www.nexusmods.com/cyberpunk2077/mods/9911) · Built for game version 2.5 · Needs only [redscript](https://www.nexusmods.com/cyberpunk2077/mods/1511)

## What it does

At launch the world map had a free camera you could spin and tilt. Patch 1.5 removed it, but the engine still has the rotate and tilt controls, just unused. This mod turns them back on and fixes the problems that came with them.

- **Mouse:** hold right mouse and drag to rotate and tilt. A quick right-click still sets a waypoint.
- **Controller:** the right stick rotates and tilts. It no longer slides the map at the same time.
- **Keyboard:** the arrow keys rotate and tilt.
- **Zooming keeps your view.** Each zoom step normally snaps the tilt back to a preset. The mod steers it back to where you had it.
- **Remembers your view** between map visits.
- **Hold Jump to Player** to face north and return to the default tilt.
- **No more drift.** The map no longer creeps or rotates on its own with a worn or sensitive stick.
- An on-screen **Rotate** button hint, an adjustable pan speed, and sound you can switch off.

## Install

Extract the zip into your `Cyberpunk 2077` folder so you end up with:

```
Cyberpunk 2077/r6/scripts/MapStreetView/MapStreetView.reds
Cyberpunk 2077/r6/scripts/MapStreetView/MapStreetViewSettings.reds
```

Vortex and Mod Organizer 2 can install the zip directly. To upgrade from 2.x, overwrite the old files.

**Remove "Map Rotation with Mouse" if you have it.** It changes the same map controls and the two will fight over them.

## Settings

Every option has a default that works without any other mods. You have two ways to change them:

- **Edit `MapStreetViewSettings.reds`.** Each option is one line; change the value after the `=` and restart the game.
- **Use [Mod Settings](https://www.nexusmods.com/cyberpunk2077/mods/4885) (optional).** If it's installed, the same options appear in-game under *Settings → Mods → Map Street View*.

| Option | Default | |
|---|---|---|
| Keep view when zooming | on | Put your tilt back after each zoom step |
| Also keep rotation when zooming | off | Only needed if zooming also turns the map for you |
| Remember view between map visits | on | |
| Hold Jump to Player to reset view | on | |
| Right-drag rotates | on | Turn off to leave right mouse as vanilla |
| Mouse sensitivity / invert | 1.0 / off | |
| Stick deadzone | 0.15 | Raise if the map moves on its own |
| Rotation speed | 1.0 | Right stick and arrow keys |
| Invert rotation / tilt | off | |
| Pan speed | 1.0 | WASD and left stick |
| Rotation sounds | on | |
| Show Rotate button hint | on | |
| Debug overlay | off | Shows camera details on the map, for bug reports |

The Nexus page also offers ready-made versions with different defaults: **Silent**, **Inverted tilt**, and **No mouse drag**.

## Compatibility

- Not compatible with mods that also change rotating or panning on the world map, such as *Map Rotation with Mouse* or *3D World Map Explorer*.
- Flat 2D map replacers work, but tilting them looks odd because the map icons are 3D.
- Map skins and re-colours work.

## Building releases

```powershell
./tools/package.ps1 -Version 3.0.0
```

This writes one zip per variant to `dist/`. Each variant is the same script with different defaults in `MapStreetViewSettings.reds`.

## How it works

The map camera's rotate calls take a speed rather than an angle, and the engine keeps turning at the last speed it was given. The mod routes every rotation through one place: it always sends zero when you let go, which fixes the drift, and it adds up how far you've turned, which lets it restore your tilt after the engine resets it on zoom. The comments in `MapStreetView.reds` cover the rest.

Reference: CD Projekt RED's game scripts, as decompiled in [adamsmasher/cyberpunk](https://codeberg.org/adamsmasher/cyberpunk).

## Credits

- **HaywirePhoenix** for the original deadzone fix.
- **MikhailVP** and **cutterhead** for pointing out that the right stick should stop panning while it rotates.
- Everyone in the Nexus comments who reported bugs and asked for the mouse controls.

Made by Sindahive (Ghostlight).
