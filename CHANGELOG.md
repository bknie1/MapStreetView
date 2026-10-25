# Changelog

## 3.0.0

Rewritten for game version 2.5.

- Added mouse controls: hold right mouse and drag to rotate and tilt. Right-click still sets waypoints. No Input Loader needed.
- Fixed zooming resetting the tilt. The view is restored after each zoom step.
- Fixed the map drifting or rotating on its own. The camera now gets an explicit stop when a stick returns to center, and the deadzone is rescaled so movement starts smoothly.
- Fixed the right stick sliding the map while rotating it.
- Fixed rotation sounds repeating or getting stuck. They no longer share state with vanilla zoom sounds.
- Added: the view is remembered between map visits.
- Added: hold Jump to Player to reset the view.
- Added: a Rotate button hint.
- Added: a deadzone for left-stick panning, plus a pan speed option.
- Added a settings file with optional Mod Settings support. No mod is required.
- Added a debug overlay option for diagnosing future patches.

## 2.1

- Controller deadzone fix, based on HaywirePhoenix's suggestion.

Earlier versions: see the Nexus Mods page.
