// Map Street View - settings
//
// Every option below works on its own, no other mods needed. Change a default
// by editing the value after the "=" and restarting the game.
//
// If you happen to have Mod Settings installed, these same options also show
// up in-game under Settings > Mods > Map Street View, and you can skip editing
// this file entirely. Mod Settings is optional; nothing here depends on it.

public class MapStreetViewSettings {

  // --- Controls -------------------------------------------------------------

  @runtimeProperty("ModSettings.mod", "Map Street View")
  @runtimeProperty("ModSettings.category", "Controls")
  @runtimeProperty("ModSettings.displayName", "Keep view when zooming")
  @runtimeProperty("ModSettings.description", "Each zoom step normally snaps the camera tilt back to a preset. This puts your tilt back afterwards.")
  public let keepViewOnZoom: Bool = true;

  @runtimeProperty("ModSettings.mod", "Map Street View")
  @runtimeProperty("ModSettings.category", "Controls")
  @runtimeProperty("ModSettings.displayName", "Also keep rotation when zooming")
  @runtimeProperty("ModSettings.description", "Only needed if zooming also resets which way the map is facing for you.")
  public let keepRotationOnZoom: Bool = false;

  @runtimeProperty("ModSettings.mod", "Map Street View")
  @runtimeProperty("ModSettings.category", "Controls")
  @runtimeProperty("ModSettings.displayName", "Remember view between map visits")
  @runtimeProperty("ModSettings.description", "Reopen the map at the rotation and tilt you left it at.")
  public let rememberView: Bool = true;

  @runtimeProperty("ModSettings.mod", "Map Street View")
  @runtimeProperty("ModSettings.category", "Controls")
  @runtimeProperty("ModSettings.displayName", "Hold Jump to Player to reset view")
  @runtimeProperty("ModSettings.description", "Hold Jump to Player for a moment to face north and return to the default tilt.")
  public let holdToReset: Bool = true;

  // --- Mouse ----------------------------------------------------------------

  @runtimeProperty("ModSettings.mod", "Map Street View")
  @runtimeProperty("ModSettings.category", "Mouse")
  @runtimeProperty("ModSettings.displayName", "Right-drag rotates")
  @runtimeProperty("ModSettings.description", "Hold right mouse and drag to rotate and tilt. A quick right-click still sets a waypoint.")
  public let mouseDragRotates: Bool = true;

  @runtimeProperty("ModSettings.mod", "Map Street View")
  @runtimeProperty("ModSettings.category", "Mouse")
  @runtimeProperty("ModSettings.displayName", "Mouse sensitivity")
  @runtimeProperty("ModSettings.step", "0.05")
  @runtimeProperty("ModSettings.min", "0.1")
  @runtimeProperty("ModSettings.max", "3.0")
  public let mouseSensitivity: Float = 1.0;

  @runtimeProperty("ModSettings.mod", "Map Street View")
  @runtimeProperty("ModSettings.category", "Mouse")
  @runtimeProperty("ModSettings.displayName", "Invert mouse rotation")
  public let mouseInvertYaw: Bool = false;

  @runtimeProperty("ModSettings.mod", "Map Street View")
  @runtimeProperty("ModSettings.category", "Mouse")
  @runtimeProperty("ModSettings.displayName", "Invert mouse tilt")
  public let mouseInvertPitch: Bool = false;

  // --- Controller & keyboard ------------------------------------------------

  @runtimeProperty("ModSettings.mod", "Map Street View")
  @runtimeProperty("ModSettings.category", "Controller and keyboard")
  @runtimeProperty("ModSettings.displayName", "Stick deadzone")
  @runtimeProperty("ModSettings.description", "Raise this if the map rotates or slides on its own.")
  @runtimeProperty("ModSettings.step", "0.01")
  @runtimeProperty("ModSettings.min", "0.0")
  @runtimeProperty("ModSettings.max", "0.5")
  public let stickDeadzone: Float = 0.15;

  @runtimeProperty("ModSettings.mod", "Map Street View")
  @runtimeProperty("ModSettings.category", "Controller and keyboard")
  @runtimeProperty("ModSettings.displayName", "Rotation speed")
  @runtimeProperty("ModSettings.step", "0.05")
  @runtimeProperty("ModSettings.min", "0.1")
  @runtimeProperty("ModSettings.max", "1.0")
  public let stickSensitivity: Float = 1.0;

  @runtimeProperty("ModSettings.mod", "Map Street View")
  @runtimeProperty("ModSettings.category", "Controller and keyboard")
  @runtimeProperty("ModSettings.displayName", "Invert rotation")
  public let invertYaw: Bool = false;

  @runtimeProperty("ModSettings.mod", "Map Street View")
  @runtimeProperty("ModSettings.category", "Controller and keyboard")
  @runtimeProperty("ModSettings.displayName", "Invert tilt")
  public let invertPitch: Bool = false;

  @runtimeProperty("ModSettings.mod", "Map Street View")
  @runtimeProperty("ModSettings.category", "Controller and keyboard")
  @runtimeProperty("ModSettings.displayName", "Pan speed")
  @runtimeProperty("ModSettings.description", "How fast WASD and the left stick slide the map.")
  @runtimeProperty("ModSettings.step", "0.05")
  @runtimeProperty("ModSettings.min", "0.1")
  @runtimeProperty("ModSettings.max", "3.0")
  public let panSpeed: Float = 1.0;

  // --- Sound & misc ---------------------------------------------------------

  @runtimeProperty("ModSettings.mod", "Map Street View")
  @runtimeProperty("ModSettings.category", "Sound")
  @runtimeProperty("ModSettings.displayName", "Rotation sounds")
  @runtimeProperty("ModSettings.description", "Play the scrolling sound while rotating or tilting.")
  public let soundEnabled: Bool = true;

  @runtimeProperty("ModSettings.mod", "Map Street View")
  @runtimeProperty("ModSettings.category", "Sound")
  @runtimeProperty("ModSettings.displayName", "Show Rotate button hint")
  public let showHint: Bool = true;

  @runtimeProperty("ModSettings.mod", "Map Street View")
  @runtimeProperty("ModSettings.category", "Debug")
  @runtimeProperty("ModSettings.displayName", "Debug overlay")
  @runtimeProperty("ModSettings.description", "Shows camera details on top of the map, for bug reports. Leave off unless asked.")
  public let debugLog: Bool = false;
}
