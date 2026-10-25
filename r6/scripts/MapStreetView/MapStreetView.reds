// Map Street View 3.0
// Rotate, tilt, and zoom the world map with mouse, controller, or keyboard,
// and keep your view while you zoom.
//
// Controls
//   Mouse       right-drag rotates and tilts; a plain right-click still sets a waypoint
//   Controller  right stick rotates and tilts (it no longer also slides the map)
//   Keyboard    arrow keys rotate and tilt
//   Any         double-tap Jump to Player to face north again
//
// Options live in MapStreetViewSettings.reds.
//
// How it works, for the curious:
//   The map camera's RotateYaw/RotatePitch take a *speed*, not an angle. The
//   engine keeps turning at the last speed it was handed until it gets a new
//   one. Older versions sent nothing while the stick sat inside the deadzone,
//   so a stick resting at 0.12 left the camera creeping forever; that was the
//   drift people kept reporting. Now every speed goes through MSVCamera, which
//   always sends 0 when idle and adds up speed x time, so it knows how far
//   you've turned. Each zoom step snaps the tilt back to that zoom level's
//   preset (that part is the engine, not us), so once the zoom settles we
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

// Owns every rotation speed the mod sends to the map camera.
//
// Positions are kept in "speed-seconds": holding full speed for one second
// moves 1.0. We never need to know what that is in degrees, because we only
// ever replay our own movement back to the engine.
public class MSVCamera extends IScriptable {
  private let m_preview: wref<inkWorldMapPreviewGameController>;
  private let m_audio: wref<AudioSystem>;
  private let m_game: GameInstance;
  private let m_cfg: ref<MapStreetViewSettings>;

  // Two invisible widgets whose animations double as real-time timers. Game
  // time is frozen while the map is open, so the delay system is no use here.
  private let m_tickWidget: wref<inkWidget>;
  private let m_zoomWidget: wref<inkWidget>;
  private let m_tickProxy: ref<inkAnimProxy>;
  private let m_zoomProxy: ref<inkAnimProxy>;
  private let m_zoomTimeout: Float;

  // Stick and arrow key speeds, after deadzone and sensitivity.
  private let m_stickYaw: Float;
  private let m_stickPitch: Float;

  // Speeds the engine is running with right now.
  private let m_sentYaw: Float;
  private let m_sentPitch: Float;

  // Where the camera is and where we want it. Yaw counts from how the map
  // opened; pitch counts from the current zoom level's preset tilt.
  private let m_yaw: Float;
  private let m_pitch: Float;
  private let m_targetYaw: Float;
  private let m_targetPitch: Float;

  private let m_lastTime: Float;
  private let m_zoomPending: Bool;
  private let m_dragging: Bool;
  private let m_soundPlaying: Bool;

  public final func Setup(preview: wref<inkWorldMapPreviewGameController>, audio: wref<AudioSystem>, game: GameInstance, root: wref<inkCompoundWidget>, cfg: ref<MapStreetViewSettings>, zoomTimeout: Float) -> Void {
    this.m_preview = preview;
    this.m_audio = audio;
    this.m_game = game;
    this.m_cfg = cfg;
    this.m_zoomTimeout = zoomTimeout;
    this.m_tickWidget = this.MakeTimerWidget(root, n"MapStreetViewTick");
    this.m_zoomWidget = this.MakeTimerWidget(root, n"MapStreetViewZoom");
    this.m_lastTime = this.Now();
  }

  private final func MakeTimerWidget(root: wref<inkCompoundWidget>, name: CName) -> wref<inkWidget> {
    let widget: ref<inkRectangle> = new inkRectangle();
    widget.SetName(name);
    widget.SetSize(new Vector2(0.00, 0.00));
    widget.SetInteractive(false);
    widget.Reparent(root);
    return widget;
  }

  // --- Input -----------------------------------------------------------------

  public final func SetStickYaw(raw: Float) -> Void {
    this.Integrate();
    this.m_stickYaw = this.ShapeStick(raw, this.m_cfg.invertYaw);
    this.Update();
  }

  public final func SetStickPitch(raw: Float) -> Void {
    this.Integrate();
    this.m_stickPitch = this.ShapeStick(raw, this.m_cfg.invertPitch);
    this.Update();
  }

  public final func AddMouse(dx: Float, dy: Float) -> Void {
    // Mouse moves the goal; the catch-up in Update chases it smoothly.
    let scale: Float = 0.004 * this.m_cfg.mouseSensitivity;
    this.Integrate();
    this.m_targetYaw += (this.m_cfg.mouseInvertYaw ? -dx : dx) * scale;
    this.m_targetPitch += (this.m_cfg.mouseInvertPitch ? -dy : dy) * scale;
    this.Update();
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

  // --- View ------------------------------------------------------------------

  public final func ResetView() -> Void {
    this.Integrate();
    this.m_targetYaw = 0.00;
    this.m_targetPitch = 0.00;
    this.Log("reset view");
    this.Update();
  }

  public final func RestoreView(yaw: Float, pitch: Float) -> Void {
    this.Integrate();
    this.m_targetYaw = yaw;
    this.m_targetPitch = pitch;
    this.Log("restore view yaw " + FloatToStringPrec(yaw, 3) + " pitch " + FloatToStringPrec(pitch, 3));
    this.Update();
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
    this.Integrate();
    this.m_zoomPending = true;
    this.Log("zoom level " + IntToString(oldLevel) + " -> " + IntToString(newLevel) + ", tilt was " + FloatToStringPrec(this.m_pitch, 3));
    this.StartZoomTimeout();
    this.Update();
  }

  public final func ZoomFinished() -> Void {
    if !this.m_zoomPending {
      return;
    };
    this.Integrate();
    this.m_zoomPending = false;
    this.StopZoomTimeout();
    // The engine just put the tilt back on the preset, so we're at 0 again.
    // Leaving the target alone is what makes us steer back.
    this.m_pitch = 0.00;
    if !this.m_cfg.keepViewOnZoom {
      this.m_targetPitch = 0.00;
    };
    if this.m_cfg.keepRotationOnZoom {
      this.m_yaw = 0.00;
    };
    this.Log("zoom settled, steering to yaw " + FloatToStringPrec(this.m_targetYaw, 3) + " pitch " + FloatToStringPrec(this.m_targetPitch, 3));
    this.Update();
  }

  public final func Stop() -> Void {
    this.Integrate();
    this.m_stickYaw = 0.00;
    this.m_stickPitch = 0.00;
    this.m_targetYaw = this.m_yaw;
    this.m_targetPitch = this.m_pitch;
    this.m_dragging = false;
    this.Send(0.00, 0.00);
    if IsDefined(this.m_tickProxy) {
      this.m_tickProxy.Stop(true);
      this.m_tickProxy = null;
    };
    this.StopZoomTimeout();
  }

  // --- Internals -------------------------------------------------------------

  private final func Now() -> Float {
    return EngineTime.ToFloat(GameInstance.GetEngineTime(this.m_game));
  }

  // Bring our position up to date with whatever the engine did since last time.
  private final func Integrate() -> Void {
    let now: Float = this.Now();
    let dt: Float = now - this.m_lastTime;
    this.m_lastTime = now;
    if dt <= 0.00 {
      return;
    };
    this.m_yaw += this.m_sentYaw * dt;
    this.m_pitch += this.m_sentPitch * dt;
    // Stick input carries the goal along with it, so catching up only ever
    // closes a gap the player didn't make with the stick themselves.
    this.m_targetYaw += this.m_stickYaw * dt;
    this.m_targetPitch += this.m_stickPitch * dt;
  }

  private final func Update() -> Void {
    let yaw: Float = this.m_stickYaw;
    let pitch: Float = this.m_stickPitch;
    let catchingUp: Bool = false;
    if !this.m_zoomPending {
      yaw += this.CatchUp(this.m_targetYaw - this.m_yaw);
      pitch += this.CatchUp(this.m_targetPitch - this.m_pitch);
      catchingUp = AbsF(this.m_targetYaw - this.m_yaw) >= 0.002 || AbsF(this.m_targetPitch - this.m_pitch) >= 0.002;
    };
    this.Send(ClampF(yaw, -1.00, 1.00), ClampF(pitch, -1.00, 1.00));
    if catchingUp {
      this.StartTick();
    };
    this.UpdateSound();
  }

  // Close a gap quickly but smoothly: speed is proportional to what's left.
  private final func CatchUp(gap: Float) -> Float {
    if AbsF(gap) < 0.002 {
      return 0.00;
    };
    return ClampF(gap / 0.08, -1.00, 1.00);
  }

  private final func Send(yaw: Float, pitch: Float) -> Void {
    if !IsDefined(this.m_preview) {
      return;
    };
    if yaw != this.m_sentYaw {
      this.m_preview.RotateYaw(yaw);
      this.m_sentYaw = yaw;
    };
    if pitch != this.m_sentPitch {
      this.m_preview.RotatePitch(pitch);
      this.m_sentPitch = pitch;
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

  private final func PlayTimer(widget: wref<inkWidget>, duration: Float, callback: CName) -> ref<inkAnimProxy> {
    let anim: ref<inkAnimDef> = new inkAnimDef();
    let wait: ref<inkAnimTransparency> = new inkAnimTransparency();
    let proxy: ref<inkAnimProxy>;
    wait.SetStartTransparency(1.00);
    wait.SetEndTransparency(1.00);
    wait.SetDuration(duration);
    anim.AddInterpolator(wait);
    proxy = widget.PlayAnimation(anim);
    proxy.RegisterToCallback(inkanimEventType.OnFinish, this, callback);
    return proxy;
  }

  private final func StartTick() -> Void {
    if IsDefined(this.m_tickProxy) || !IsDefined(this.m_tickWidget) {
      return;
    };
    this.m_tickProxy = this.PlayTimer(this.m_tickWidget, 0.016, n"OnTick");
  }

  protected cb func OnTick(proxy: ref<inkAnimProxy>) -> Bool {
    this.m_tickProxy = null;
    this.Integrate();
    this.Update();
  }

  // If a zoom never reports finishing, don't stay frozen.
  private final func StartZoomTimeout() -> Void {
    this.StopZoomTimeout();
    if IsDefined(this.m_zoomWidget) {
      this.m_zoomProxy = this.PlayTimer(this.m_zoomWidget, this.m_zoomTimeout, n"OnZoomTimeout");
    };
  }

  private final func StopZoomTimeout() -> Void {
    if IsDefined(this.m_zoomProxy) {
      this.m_zoomProxy.UnregisterFromCallback(inkanimEventType.OnFinish, this, n"OnZoomTimeout");
      this.m_zoomProxy.Stop(true);
      this.m_zoomProxy = null;
    };
  }

  protected cb func OnZoomTimeout(proxy: ref<inkAnimProxy>) -> Bool {
    this.m_zoomProxy = null;
    this.Log("zoom finish never arrived, carrying on");
    this.ZoomFinished();
  }

  public final func Log(text: String) -> Void {
    if this.m_cfg.debugLog {
      ModLog(n"MapStreetView", text);
    };
  }
}

// --- World map hooks ---------------------------------------------------------

@addField(WorldMapMenuGameController)
private let m_msvCamera: ref<MSVCamera>;

@addField(WorldMapMenuGameController)
private let m_msvSettings: ref<MapStreetViewSettings>;

@addField(WorldMapMenuGameController)
private let m_msvViewRestored: Bool;

@addField(WorldMapMenuGameController)
private let m_msvLastJumpTime: Float;

// Right mouse: pressed, and whether it has turned into a drag yet.
@addField(WorldMapMenuGameController)
private let m_msvRightDown: Bool;

@addField(WorldMapMenuGameController)
private let m_msvRightDragging: Bool;

@addField(WorldMapMenuGameController)
private let m_msvRightSetsWaypoint: Bool;

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

@wrapMethod(WorldMapMenuGameController)
protected cb func OnEntityAttached() -> Bool {
  let result: Bool = wrappedMethod();
  let settings: ref<WorldMapSettings_Record> = this.GetSettings();
  let zoomTimeout: Float = 1.50;
  if IsDefined(settings) {
    zoomTimeout = MaxF(settings.ZoomTransitionTime(), settings.MouseZoomTransitionTime()) + 0.50;
  };
  // Fresh settings each visit so changes made in Mod Settings apply right away.
  this.m_msvSettings = new MapStreetViewSettings();
  this.m_msvCamera = new MSVCamera();
  this.m_msvCamera.Setup(this.GetEntityPreview(), this.m_audioSystem, this.m_player.GetGame(), this.GetRootCompoundWidget(), this.m_msvSettings, zoomTimeout);
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
  let now: Float;
  if IsDefined(this.m_msvCamera) && this.MSVSettings().mouseDragRotates && e.IsAction(n"world_map_menu_rotate_mouse") {
    // Right mouse is both "set waypoint" and "rotate". Wait for release:
    // if the mouse moved it was a drag, otherwise set the waypoint then.
    this.m_msvRightDown = true;
    this.m_msvRightDragging = false;
    this.m_msvRightTravel = 0.00;
    this.m_msvRightHeldX = 0.00;
    this.m_msvRightHeldY = 0.00;
    this.m_msvRightSetsWaypoint = e.IsAction(n"world_map_menu_track_waypoint");
    // Right mouse is also bound to Back; this flag is how vanilla keeps the
    // map from closing on a right-click.
    this.m_pressedRMB = true;
    return;
  };
  if IsDefined(this.m_msvCamera) && this.MSVSettings().doubleTapReset && e.IsAction(n"world_map_menu_jump_to_player") {
    now = EngineTime.ToFloat(GameInstance.GetEngineTime(this.m_player.GetGame()));
    if now - this.m_msvLastJumpTime < 0.40 {
      this.m_msvCamera.ResetView();
      this.m_msvLastJumpTime = 0.00;
    } else {
      this.m_msvLastJumpTime = now;
    };
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
    } else {
      if this.m_msvRightSetsWaypoint {
        this.TryTrackQuestOrSetWaypoint();
      };
    };
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

// With debugLog on, write what the game's map camera is set up with, so
// problems on new patches can be diagnosed from a log instead of guesswork.
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
  this.m_msvCamera.Log("camera mode " + (Equals(this.GetEntityPreview().GetCameraMode(), gameuiEWorldMapCameraMode.ZoomLevels) ? "ZoomLevels" : "TopDown") + ", current zoom " + FloatToStringPrec(this.GetCurrentZoom(), 3));
  settings.ZoomLevels(levels);
  while i < ArraySize(levels) {
    rotation = levels[i].Rotation();
    this.m_msvCamera.Log("zoom level " + IntToString(i) + ": zoom " + FloatToStringPrec(levels[i].Zoom(), 2) + " pitch " + FloatToStringPrec(rotation.Pitch, 2) + " yaw " + FloatToStringPrec(rotation.Yaw, 2) + " fov " + FloatToStringPrec(levels[i].Fov(), 2));
    i += 1;
  };
  this.MSVLogCameraRecord("free camera", settings.FreeCamera());
  this.MSVLogCameraRecord("top-down camera", settings.TopDownCamera());
}

@addMethod(WorldMapMenuGameController)
private final func MSVLogCameraRecord(label: String, record: wref<WorldMapFreeCameraSettings_Record>) -> Void {
  if !IsDefined(record) {
    this.m_msvCamera.Log(label + ": none");
    return;
  };
  this.m_msvCamera.Log(label + ": pitch " + FloatToStringPrec(record.RotationMin().Pitch, 2) + ".." + FloatToStringPrec(record.RotationMax().Pitch, 2) + " default " + FloatToStringPrec(record.RotationDefault().Pitch, 2) + ", speed yaw " + FloatToStringPrec(record.RotationSpeed().Yaw, 2) + " pitch " + FloatToStringPrec(record.RotationSpeed().Pitch, 2) + ", mouse rotate " + FloatToStringPrec(record.MouseRotateStrength(), 3) + ", zoom " + FloatToStringPrec(record.ZoomMin(), 2) + ".." + FloatToStringPrec(record.ZoomMax(), 2));
}
