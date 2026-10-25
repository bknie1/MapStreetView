// Map Street View 3.0
// Rotate, tilt, and zoom the world map with mouse, controller, or keyboard,
// and keep your view while you zoom.
//
// Controls
//   Mouse       right-drag rotates and tilts; a plain right-click still sets a waypoint
//   Controller  right stick rotates and tilts (it no longer also slides the map)
//   Keyboard    arrow keys rotate and tilt
//   Any         hold Jump to Player to face north at the default tilt again
//
// Options live in MapStreetViewSettings.reds.
//
// How it works, for the curious:
//   The map camera's RotateYaw/RotatePitch are a nudge for the current frame
//   only. Vanilla's input sends the stick value every frame, which is what
//   makes it turn. So MSVCamera runs its own once-a-frame tick and sends the
//   rotation from there, for the stick, the mouse, and for steering the view
//   back after a zoom. Because every turn goes through that tick, it can add
//   up how far you've turned. Each zoom step snaps the tilt back to that zoom
//   level's preset (that's the engine, not us); once the zoom settles we
//   steer back to where you had it.

// Keeps the last view between map visits for the rest of the play session.
public class MSVViewMemory extends ScriptableSystem {
  private let m_yaw: Float;
  private let m_pitch: Float;
  private let m_hasView: Bool;

  public final static func Get(game: GameInstance) -> ref<MSVViewMemory> {
    return GameInstance.GetScriptableSystemsContainer(game).Get(n"MSVViewMemory") as MSVViewMemory;
  }

  public final func Save(yaw: Float, pitch: Float) -> Void {
    this.m_yaw = yaw;
    this.m_pitch = pitch;
    this.m_hasView = true;
  }

  public final func HasView() -> Bool {
    return this.m_hasView;
  }

  public final func GetYaw() -> Float {
    return this.m_yaw;
  }

  public final func GetPitch() -> Float {
    return this.m_pitch;
  }
}

public func MSVRotateLabel() -> String {
  // Vanilla's own "Rotate" label from before the feature was cut; fall back
  // to plain English if a future patch drops the key.
  let label: String = GetLocalizedText("UI-ScriptExports-Rotate0");
  if StrLen(label) == 0 || Equals(label, "UI-ScriptExports-Rotate0") {
    return "Rotate";
  };
  return label;
}

// Measured on 2.5, in the speed-seconds MSVCamera counts in. The engine
// won't tilt more than half a speed-second toward the horizon from the
// top-down preset, and one full turn takes 3.446.
public func MSVPitchMin() -> Float {
  return -0.50;
}

public func MSVPitchMax() -> Float {
  return 0.00;
}

public func MSVFullTurn() -> Float {
  return 3.446;
}

// The same heading, expressed as close to zero as possible.
public func MSVWrapYaw(yaw: Float) -> Float {
  return yaw - MSVFullTurn() * Cast<Float>(RoundF(yaw / MSVFullTurn()));
}

// Owns every rotation the mod sends to the map camera.
//
// Positions are kept in "speed-seconds": full stick for one second moves 1.0.
// We never need degrees, because we only ever replay our own movement.
public class MSVCamera extends IScriptable {
  private let m_map: wref<WorldMapMenuGameController>;
  private let m_preview: wref<inkWorldMapPreviewGameController>;
  private let m_audio: wref<AudioSystem>;
  private let m_game: GameInstance;
  private let m_cfg: ref<MapStreetViewSettings>;

  // An invisible widget whose one-frame animation is our per-frame tick.
  // Game time is frozen while the map is open, so the delay system is no use.
  private let m_tickWidget: wref<inkWidget>;
  private let m_tickProxy: ref<inkAnimProxy>;
  private let m_lastTick: Float;
  private let m_frameTime: Float;

  // Stick and arrow key speeds, after deadzone and sensitivity.
  private let m_stickYaw: Float;
  private let m_stickPitch: Float;

  // Where the camera is and where we want it. Yaw counts from how the map
  // opened; pitch counts from the current zoom level's preset tilt.
  private let m_yaw: Float;
  private let m_pitch: Float;
  private let m_targetYaw: Float;
  private let m_targetPitch: Float;

  // Zoom in progress. The engine's "zoom finished" event doesn't fire on 2.5,
  // so we watch the zoom value until it stops changing.
  private let m_zoomPending: Bool;
  private let m_zoomStart: Float;
  private let m_zoomTimeout: Float;
  private let m_zoomValue: Float;
  private let m_zoomSteadySince: Float;
  private let m_zoomMoved: Bool;

  // Hold-to-reset.
  private let m_holding: Bool;
  private let m_holdStart: Float;
  private let m_holdDone: Bool;

  private let m_dragging: Bool;
  private let m_soundPlaying: Bool;

  private let m_debugText: wref<inkText>;
  private let m_debugLines: array<String>;

  public final func Setup(map: wref<WorldMapMenuGameController>, preview: wref<inkWorldMapPreviewGameController>, audio: wref<AudioSystem>, game: GameInstance, root: wref<inkCompoundWidget>, cfg: ref<MapStreetViewSettings>, zoomTimeout: Float) -> Void {
    let ticker: ref<inkRectangle> = new inkRectangle();
    this.m_map = map;
    this.m_preview = preview;
    this.m_audio = audio;
    this.m_game = game;
    this.m_cfg = cfg;
    this.m_zoomTimeout = zoomTimeout;
    this.m_frameTime = 1.00 / 60.00;
    ticker.SetName(n"MapStreetViewTick");
    ticker.SetSize(new Vector2(0.00, 0.00));
    ticker.SetInteractive(false);
    ticker.Reparent(root);
    this.m_tickWidget = ticker;
    this.MakeDebugText(root);
  }

  // --- Input -----------------------------------------------------------------

  public final func SetStickYaw(raw: Float) -> Void {
    this.m_stickYaw = this.ShapeStick(raw, this.m_cfg.invertYaw);
    this.Wake();
  }

  public final func SetStickPitch(raw: Float) -> Void {
    this.m_stickPitch = this.ShapeStick(raw, this.m_cfg.invertPitch);
    this.Wake();
  }

  public final func AddMouse(dx: Float, dy: Float) -> Void {
    // Mouse moves the goal; the tick chases it smoothly.
    let scale: Float = 0.004 * this.m_cfg.mouseSensitivity;
    this.m_targetYaw += (this.m_cfg.mouseInvertYaw ? -dx : dx) * scale;
    this.m_targetPitch += (this.m_cfg.mouseInvertPitch ? -dy : dy) * scale;
    this.Wake();
  }

  public final func SetDragging(dragging: Bool) -> Void {
    this.m_dragging = dragging;
    this.UpdateSound();
  }

  public final func ShapePan(raw: Float) -> Float {
    let deadzone: Float = ClampF(this.m_cfg.stickDeadzone, 0.00, 0.95);
    if AbsF(raw) <= deadzone {
      return 0.00;
    };
    return raw * this.m_cfg.panSpeed;
  }

  public final func BeginHold() -> Void {
    this.m_holding = true;
    this.m_holdStart = this.Now();
    this.m_holdDone = false;
    this.Wake();
  }

  public final func EndHold() -> Void {
    this.m_holding = false;
  }

  // --- View ------------------------------------------------------------------

  public final func ResetView() -> Void {
    // Face north by the shortest way round, not by unwinding every turn.
    this.m_targetYaw = this.m_yaw - MSVWrapYaw(this.m_yaw);
    this.m_targetPitch = 0.00;
    this.Log("reset view");
    this.Wake();
  }

  public final func RestoreView(yaw: Float, pitch: Float) -> Void {
    this.m_targetYaw = MSVWrapYaw(yaw);
    this.m_targetPitch = ClampF(pitch, MSVPitchMin(), MSVPitchMax());
    this.Log("restore view yaw " + FloatToStringPrec(yaw, 3) + " pitch " + FloatToStringPrec(pitch, 3));
    this.Wake();
  }

  public final func GetTargetYaw() -> Float {
    return this.m_targetYaw;
  }

  public final func GetTargetPitch() -> Float {
    return this.m_targetPitch;
  }

  public final func ZoomLevelChanged(oldLevel: Int32, newLevel: Int32) -> Void {
    // Hold off steering while the engine tweens to the new level, or we'd
    // fight it. Stick input still goes through.
    let now: Float = this.Now();
    this.m_zoomPending = true;
    this.m_zoomStart = now;
    this.m_zoomSteadySince = now;
    this.m_zoomMoved = false;
    this.m_zoomValue = this.ReadZoom();
    this.Log("zoom level " + IntToString(oldLevel) + " -> " + IntToString(newLevel) + ", tilt was " + FloatToStringPrec(this.m_pitch, 3));
    this.Wake();
  }

  public final func ZoomFinished() -> Void {
    if !this.m_zoomPending {
      return;
    };
    this.m_zoomPending = false;
    // The engine just put the tilt back on the preset, so we're at 0 again.
    // Leaving the target alone is what makes us steer back.
    this.m_pitch = 0.00;
    if !this.m_cfg.keepViewOnZoom {
      this.m_targetPitch = 0.00;
    };
    if this.m_cfg.keepRotationOnZoom {
      this.m_yaw = 0.00;
    };
    this.Log("zoom settled after " + FloatToStringPrec(this.Now() - this.m_zoomStart, 2) + "s, steering to yaw " + FloatToStringPrec(this.m_targetYaw, 3) + " pitch " + FloatToStringPrec(this.m_targetPitch, 3));
    this.Wake();
  }

  public final func Stop() -> Void {
    this.m_stickYaw = 0.00;
    this.m_stickPitch = 0.00;
    this.m_targetYaw = this.m_yaw;
    this.m_targetPitch = this.m_pitch;
    this.m_dragging = false;
    this.m_holding = false;
    this.m_zoomPending = false;
    if IsDefined(this.m_tickProxy) {
      this.m_tickProxy.UnregisterFromCallback(inkanimEventType.OnFinish, this, n"OnTick");
      this.m_tickProxy.Stop(true);
      this.m_tickProxy = null;
    };
  }

  // --- Tick ------------------------------------------------------------------

  private final func Now() -> Float {
    return EngineTime.ToFloat(GameInstance.GetEngineTime(this.m_game));
  }

  private final func ReadZoom() -> Float {
    if IsDefined(this.m_map) {
      return this.m_map.MSVCurrentZoom();
    };
    return 0.00;
  }

  private final func Wake() -> Void {
    if IsDefined(this.m_tickProxy) || !IsDefined(this.m_tickWidget) {
      return;
    };
    this.m_lastTick = this.Now();
    this.PlayTick();
  }

  private final func PlayTick() -> Void {
    // A near-zero duration finishes on the very next frame.
    let anim: ref<inkAnimDef> = new inkAnimDef();
    let wait: ref<inkAnimTransparency> = new inkAnimTransparency();
    wait.SetStartTransparency(1.00);
    wait.SetEndTransparency(1.00);
    wait.SetDuration(0.001);
    anim.AddInterpolator(wait);
    this.m_tickProxy = this.m_tickWidget.PlayAnimation(anim);
    this.m_tickProxy.RegisterToCallback(inkanimEventType.OnFinish, this, n"OnTick");
  }

  protected cb func OnTick(proxy: ref<inkAnimProxy>) -> Bool {
    let now: Float = this.Now();
    let dt: Float = now - this.m_lastTick;
    this.m_tickProxy = null;
    this.m_lastTick = now;
    // Use the real frame time, but don't let a hitch count as one giant frame.
    if dt > 0.00 && dt < 0.10 {
      this.m_frameTime = dt;
    } else {
      dt = this.m_frameTime;
    };
    this.Step(now, dt);
    if this.NeedsTick() {
      this.PlayTick();
    };
  }

  private final func Step(now: Float, dt: Float) -> Void {
    let yaw: Float;
    let pitch: Float;
    if this.m_zoomPending {
      this.WatchZoom(now);
    };
    if this.m_holding && !this.m_holdDone && now - this.m_holdStart >= 0.60 {
      this.m_holdDone = true;
      this.ResetView();
    };
    // The stick drives directly and carries the goal along with it, so the
    // catch-up only ever closes a gap the player didn't make with the stick.
    if this.m_stickYaw != 0.00 {
      yaw = this.m_stickYaw;
      this.m_targetYaw += yaw * dt;
    } else {
      if !this.m_zoomPending {
        yaw = this.CatchUp(this.m_targetYaw - this.m_yaw);
      };
    };
    if this.m_stickPitch != 0.00 {
      pitch = this.m_stickPitch;
      this.m_targetPitch += pitch * dt;
    } else {
      if !this.m_zoomPending {
        pitch = this.CatchUp(this.m_targetPitch - this.m_pitch);
      };
    };
    if IsDefined(this.m_preview) {
      if yaw != 0.00 {
        this.m_preview.RotateYaw(yaw);
        this.m_yaw += yaw * dt;
      };
      if pitch != 0.00 {
        this.m_preview.RotatePitch(pitch);
        this.m_pitch += pitch * dt;
      };
    };
    // The engine stops tilting at its limits, so stop counting there too.
    // Otherwise the count runs past what's on screen and every restore
    // afterwards chases a tilt the camera can't reach.
    this.m_pitch = ClampF(this.m_pitch, MSVPitchMin(), MSVPitchMax());
    this.m_targetPitch = ClampF(this.m_targetPitch, MSVPitchMin(), MSVPitchMax());
    this.UpdateSound();
    this.RefreshDebugText();
  }

  private final func NeedsTick() -> Bool {
    return this.m_stickYaw != 0.00 || this.m_stickPitch != 0.00 || this.m_zoomPending || (this.m_holding && !this.m_holdDone) || AbsF(this.m_targetYaw - this.m_yaw) >= 0.003 || AbsF(this.m_targetPitch - this.m_pitch) >= 0.003;
  }

  // Close a gap quickly but smoothly: full speed when far, easing in near the end.
  private final func CatchUp(gap: Float) -> Float {
    if AbsF(gap) < 0.003 {
      return 0.00;
    };
    return ClampF(gap / 0.15, -1.00, 1.00);
  }

  private final func WatchZoom(now: Float) -> Void {
    let zoom: Float = this.ReadZoom();
    if AbsF(zoom - this.m_zoomValue) > 0.0001 {
      this.m_zoomValue = zoom;
      this.m_zoomSteadySince = now;
      this.m_zoomMoved = true;
    };
    if (this.m_zoomMoved && now - this.m_zoomSteadySince > 0.12) || now - this.m_zoomStart > this.m_zoomTimeout {
      this.ZoomFinished();
    };
  }

  private final func ShapeStick(raw: Float, invert: Bool) -> Float {
    let deadzone: Float = ClampF(this.m_cfg.stickDeadzone, 0.00, 0.95);
    let size: Float = AbsF(raw);
    let out: Float;
    if size <= deadzone {
      return 0.00;
    };
    // Rescale so movement starts from zero right past the deadzone instead of
    // jumping straight to the deadzone's value.
    out = (size - deadzone) / (1.00 - deadzone) * ClampF(this.m_cfg.stickSensitivity, 0.05, 1.00);
    if raw < 0.00 {
      out = -out;
    };
    return invert ? -out : out;
  }

  private final func UpdateSound() -> Void {
    let active: Bool = this.m_dragging || this.m_stickYaw != 0.00 || this.m_stickPitch != 0.00;
    if Equals(active, this.m_soundPlaying) {
      return;
    };
    this.m_soundPlaying = active;
    if this.m_cfg.soundEnabled && IsDefined(this.m_audio) {
      this.m_audio.Play(active ? n"ui_menu_scrolling_start" : n"ui_menu_scrolling_stop");
    };
  }

  // --- Debug overlay ---------------------------------------------------------

  // Debug output goes on screen, over the map, so it can be read or
  // screenshotted without any logging mods.
  public final func Log(text: String) -> Void {
    if !this.m_cfg.debugLog {
      return;
    };
    ArrayPush(this.m_debugLines, text);
    if ArraySize(this.m_debugLines) > 16 {
      ArrayErase(this.m_debugLines, 0);
    };
    this.RefreshDebugText();
  }

  private final func MakeDebugText(root: wref<inkCompoundWidget>) -> Void {
    let text: ref<inkText>;
    if !this.m_cfg.debugLog {
      return;
    };
    text = new inkText();
    text.SetName(n"MapStreetViewDebug");
    text.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
    text.SetFontSize(26);
    text.SetTintColor(new HDRColor(1.00, 0.85, 0.30, 1.00));
    text.SetAnchor(inkEAnchor.TopLeft);
    text.SetMargin(new inkMargin(60.00, 400.00, 0.00, 0.00));
    text.SetInteractive(false);
    text.Reparent(root);
    this.m_debugText = text;
  }

  private final func RefreshDebugText() -> Void {
    let body: String;
    let i: Int32;
    if !IsDefined(this.m_debugText) {
      return;
    };
    body = "MAP STREET VIEW DEBUG\nnow  yaw " + FloatToStringPrec(this.m_yaw, 3) + " pitch " + FloatToStringPrec(this.m_pitch, 3) + "  |  goal yaw " + FloatToStringPrec(this.m_targetYaw, 3) + " pitch " + FloatToStringPrec(this.m_targetPitch, 3) + "  |  stick " + FloatToStringPrec(this.m_stickYaw, 2) + " / " + FloatToStringPrec(this.m_stickPitch, 2) + "  |  " + IntToString(RoundF(1.00 / this.m_frameTime)) + " fps" + (this.m_zoomPending ? "  |  ZOOMING" : "");
    while i < ArraySize(this.m_debugLines) {
      body += "\n" + this.m_debugLines[i];
      i += 1;
    };
    this.m_debugText.SetText(body);
  }
}

// --- World map hooks ---------------------------------------------------------

@addField(WorldMapMenuGameController)
private let m_msvCamera: ref<MSVCamera>;

@addField(WorldMapMenuGameController)
private let m_msvSettings: ref<MapStreetViewSettings>;

@addField(WorldMapMenuGameController)
private let m_msvViewRestored: Bool;

// Right mouse: pressed, and whether it has turned into a drag yet.
@addField(WorldMapMenuGameController)
private let m_msvRightDown: Bool;

@addField(WorldMapMenuGameController)
private let m_msvRightDragging: Bool;

@addField(WorldMapMenuGameController)
private let m_msvRightDragged: Bool;

@addField(WorldMapMenuGameController)
private let m_msvWaypointPending: Bool;

@addField(WorldMapMenuGameController)
private let m_msvRightPressTime: Float;

@addField(WorldMapMenuGameController)
private let m_msvRightTravel: Float;

@addField(WorldMapMenuGameController)
private let m_msvRightHeldX: Float;

@addField(WorldMapMenuGameController)
private let m_msvRightHeldY: Float;

@addMethod(WorldMapMenuGameController)
private final func MSVSettings() -> ref<MapStreetViewSettings> {
  if !IsDefined(this.m_msvSettings) {
    this.m_msvSettings = new MapStreetViewSettings();
  };
  return this.m_msvSettings;
}

@addMethod(WorldMapMenuGameController)
public final func MSVCurrentZoom() -> Float {
  return this.GetCurrentZoom();
}

@wrapMethod(WorldMapMenuGameController)
protected cb func OnEntityAttached() -> Bool {
  let result: Bool = wrappedMethod();
  let settings: ref<WorldMapSettings_Record> = this.GetSettings();
  let zoomTimeout: Float = 1.00;
  if IsDefined(settings) {
    zoomTimeout = MaxF(settings.ZoomTransitionTime(), settings.MouseZoomTransitionTime()) + 0.15;
  };
  // Fresh settings each visit so changes made in Mod Settings apply right away.
  this.m_msvSettings = new MapStreetViewSettings();
  this.m_msvCamera = new MSVCamera();
  this.m_msvCamera.Setup(this, this.GetEntityPreview(), this.m_audioSystem, this.m_player.GetGame(), this.GetRootCompoundWidget(), this.m_msvSettings, zoomTimeout);
  this.RegisterToGlobalInputCallback(n"OnPostOnRelative", this, n"OnMSVRelativeInput");
  this.MSVLogMapSettings();
  if this.m_readyToZoom {
    this.MSVRestoreView();
  };
  return result;
}

@wrapMethod(WorldMapMenuGameController)
protected cb func OnRemovePreloader(widget: wref<inkWidget>) -> Bool {
  let result: Bool = wrappedMethod(widget);
  this.MSVRestoreView();
  return result;
}

@addMethod(WorldMapMenuGameController)
private final func MSVRestoreView() -> Void {
  let memory: ref<MSVViewMemory>;
  if this.m_msvViewRestored || !IsDefined(this.m_msvCamera) {
    return;
  };
  this.m_msvViewRestored = true;
  memory = MSVViewMemory.Get(this.m_player.GetGame());
  if this.MSVSettings().rememberView && IsDefined(memory) && memory.HasView() {
    this.m_msvCamera.RestoreView(memory.GetYaw(), memory.GetPitch());
  };
}

@addMethod(WorldMapMenuGameController)
private final func MSVShutdown() -> Void {
  let memory: ref<MSVViewMemory>;
  if !IsDefined(this.m_msvCamera) {
    return;
  };
  memory = MSVViewMemory.Get(this.m_player.GetGame());
  if IsDefined(memory) {
    memory.Save(this.m_msvCamera.GetTargetYaw(), this.m_msvCamera.GetTargetPitch());
  };
  this.m_msvCamera.Stop();
  this.m_msvCamera = null;
}

@wrapMethod(WorldMapMenuGameController)
protected cb func OnEntityDetached() -> Bool {
  let result: Bool = wrappedMethod();
  this.UnregisterFromGlobalInputCallback(n"OnPostOnRelative", this, n"OnMSVRelativeInput");
  this.MSVShutdown();
  return result;
}

@wrapMethod(WorldMapMenuGameController)
protected cb func OnUninitialize() -> Bool {
  this.MSVShutdown();
  return wrappedMethod();
}

@wrapMethod(WorldMapMenuGameController)
protected cb func OnZoomLevelChanged(oldLevel: Int32, newLevel: Int32) -> Bool {
  let result: Bool = wrappedMethod(oldLevel, newLevel);
  if IsDefined(this.m_msvCamera) {
    this.m_msvCamera.ZoomLevelChanged(oldLevel, newLevel);
  };
  return result;
}

@wrapMethod(WorldMapMenuGameController)
protected cb func OnZoomTransitionFinished() -> Bool {
  let result: Bool = wrappedMethod();
  if IsDefined(this.m_msvCamera) {
    this.m_msvCamera.ZoomFinished();
  };
  return result;
}

@wrapMethod(WorldMapMenuGameController)
private final func HandleAxisInput(e: ref<inkPointerEvent>) -> Void {
  let camera: ref<MSVCamera> = this.m_msvCamera;
  let preview: wref<inkWorldMapPreviewGameController>;
  if !IsDefined(camera) {
    wrappedMethod(e);
    return;
  };
  // Right stick and arrow keys.
  if e.IsAction(n"world_map_menu_rotate_yaw") {
    camera.SetStickYaw(e.GetAxisData());
    return;
  };
  if e.IsAction(n"world_map_menu_rotate_pitch") {
    camera.SetStickPitch(e.GetAxisData());
    return;
  };
  // The game binds the right stick to panning as well as rotating. Panning
  // at the same time made rotating feel broken, so the right stick only
  // rotates now. The left stick and WASD still pan.
  if e.IsAction(n"world_map_menu_move_horizontal_alt") || e.IsAction(n"world_map_menu_move_vertical_alt") {
    return;
  };
  // Panning gets the same deadzone, so a worn left stick doesn't slide the map.
  preview = this.GetEntityPreview();
  if e.IsAction(n"world_map_menu_move_horizontal") {
    preview.Move(new Vector4(1.00, 0.00, 0.00, 0.00), camera.ShapePan(e.GetAxisData()));
    return;
  };
  if e.IsAction(n"world_map_menu_move_vertical") {
    preview.Move(new Vector4(0.00, 1.00, 0.00, 0.00), camera.ShapePan(e.GetAxisData()));
    return;
  };
  wrappedMethod(e);
}

@wrapMethod(WorldMapMenuGameController)
private final func HandlePressInput(e: ref<inkPointerEvent>) -> Void {
  let isRotate: Bool;
  let isWaypoint: Bool;
  if IsDefined(this.m_msvCamera) && this.MSVSettings().mouseDragRotates && this.m_player.PlayerLastUsedKBM() {
    // Right mouse arrives as two separate events, "rotate" and "set
    // waypoint". Hold the waypoint until release: if the mouse moved in
    // between it was a drag, otherwise set the waypoint then.
    isRotate = e.IsAction(n"world_map_menu_rotate_mouse");
    isWaypoint = e.IsAction(n"world_map_menu_track_waypoint");
    if isRotate || isWaypoint {
      if !this.m_msvRightDragging {
        this.m_msvRightDragged = false;
      };
      this.m_msvRightPressTime = EngineTime.ToFloat(GameInstance.GetEngineTime(this.m_player.GetGame()));
      if isRotate {
        this.m_msvRightDown = true;
        this.m_msvRightTravel = 0.00;
        this.m_msvRightHeldX = 0.00;
        this.m_msvRightHeldY = 0.00;
      };
      if isWaypoint {
        this.m_msvWaypointPending = true;
      };
      // Right mouse is also bound to Back; this flag is how vanilla keeps the
      // map from closing on a right-click.
      this.m_pressedRMB = true;
      return;
    };
  };
  if IsDefined(this.m_msvCamera) && this.MSVSettings().holdToReset && e.IsAction(n"world_map_menu_jump_to_player") {
    this.m_msvCamera.BeginHold();
  };
  wrappedMethod(e);
}

@wrapMethod(WorldMapMenuGameController)
private final func HandleReleaseInput(e: ref<inkPointerEvent>) -> Void {
  if this.m_msvRightDown && e.IsAction(n"world_map_menu_rotate_mouse") {
    this.m_msvRightDown = false;
    if this.m_msvRightDragging {
      this.m_msvRightDragging = false;
      if IsDefined(this.m_msvCamera) {
        this.m_msvCamera.SetDragging(false);
      };
      this.SetCursorContext(n"Default");
    };
  };
  if this.m_msvWaypointPending && e.IsAction(n"world_map_menu_track_waypoint") {
    this.m_msvWaypointPending = false;
    // Only a quick, still click sets a waypoint. A drag, or holding the
    // button for a while, never does.
    if !this.m_msvRightDragged && EngineTime.ToFloat(GameInstance.GetEngineTime(this.m_player.GetGame())) - this.m_msvRightPressTime < 0.30 {
      this.TryTrackQuestOrSetWaypoint();
    };
  };
  if IsDefined(this.m_msvCamera) && e.IsAction(n"world_map_menu_jump_to_player") {
    this.m_msvCamera.EndHold();
  };
  wrappedMethod(e);
}

@addMethod(WorldMapMenuGameController)
protected cb func OnMSVRelativeInput(e: ref<inkPointerEvent>) -> Bool {
  let dx: Float = 0.00;
  let dy: Float = 0.00;
  if !this.m_msvRightDown || !IsDefined(this.m_msvCamera) {
    return false;
  };
  if e.IsAction(n"mouse_x") {
    dx = e.GetAxisData();
  } else {
    if e.IsAction(n"mouse_y") {
      dy = e.GetAxisData();
    } else {
      return false;
    };
  };
  if !this.m_msvRightDragging {
    // Small wobbles during a click shouldn't count as a drag.
    this.m_msvRightTravel += AbsF(dx) + AbsF(dy);
    this.m_msvRightHeldX += dx;
    this.m_msvRightHeldY += dy;
    if this.m_msvRightTravel < 6.00 {
      return false;
    };
    this.m_msvRightDragging = true;
    this.m_msvRightDragged = true;
    this.m_msvCamera.SetDragging(true);
    this.SetCursorContext(n"Pan");
    dx = this.m_msvRightHeldX;
    dy = this.m_msvRightHeldY;
  };
  this.m_msvCamera.AddMouse(dx, dy);
  return false;
}

@wrapMethod(WorldMapMenuGameController)
private final func RefreshInputHints() -> Void {
  let evt: ref<UpdateInputHintMultipleEvent>;
  let data: InputHintData;
  wrappedMethod();
  if !this.IsEntitySetup() || !this.MSVSettings().showHint {
    return;
  };
  // world_map_fake_rotate is vanilla's leftover hint action; it already shows
  // the right stick or right mouse icon depending on what you're using.
  evt = new UpdateInputHintMultipleEvent();
  evt.targetHintContainer = n"WorldMapInputHints";
  data.action = n"world_map_fake_rotate";
  data.source = n"WorldMap";
  data.localizedLabel = MSVRotateLabel();
  data.sortingPriority = 4;
  data.queuePriority = 4;
  evt.AddInputHint(data, true);
  this.QueueEvent(evt);
}

// With the debug overlay on, show what the game's map camera is set up with,
// so problems on new patches can be diagnosed from a screenshot.
@addMethod(WorldMapMenuGameController)
private final func MSVLogMapSettings() -> Void {
  let settings: ref<WorldMapSettings_Record>;
  let levels: array<wref<WorldMapZoomLevel_Record>>;
  let rotation: EulerAngles;
  let i: Int32;
  if !this.MSVSettings().debugLog || !IsDefined(this.m_msvCamera) {
    return;
  };
  settings = this.GetSettings();
  if !IsDefined(settings) {
    this.m_msvCamera.Log("no map settings record");
    return;
  };
  this.m_msvCamera.Log("current zoom " + FloatToStringPrec(this.GetCurrentZoom(), 3) + ", zoom times " + FloatToStringPrec(settings.ZoomTransitionTime(), 2) + " / mouse " + FloatToStringPrec(settings.MouseZoomTransitionTime(), 2));
  settings.ZoomLevels(levels);
  while i < ArraySize(levels) {
    rotation = levels[i].Rotation();
    this.m_msvCamera.Log("zoom level " + IntToString(i) + ": zoom " + FloatToStringPrec(levels[i].Zoom(), 2) + " pitch " + FloatToStringPrec(rotation.Pitch, 2));
    i += 1;
  };
}
