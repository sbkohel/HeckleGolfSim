extends Control

signal split_started
signal split_closed

const SIZE_TRANSITION_DURATION := 0.8
const FLIGHT_VIEW_RENDER_SHRINK := 2
const CAMERA_TRAIL_DISTANCE := 150.0
const CAMERA_BASE_HEIGHT := 70.0
const CAMERA_LOOK_DISTANCE := 140.0
const CAMERA_LOOK_HEIGHT := 18.0
const CAMERA_FIELD_OF_VIEW := 50.0
const TRACER_HEIGHT_OFFSET := 0.3

var _viewport: SubViewport
var _aspect_container: AspectRatioContainer
var _viewport_container: SubViewportContainer
var _shot_panel: PanelContainer
var _split_clip: Control
var _split_viewport_container: SubViewportContainer
var _split_viewport: SubViewport
var _main_camera_copy: Camera3D
var _main_camera: Camera3D
var _main_camera_cull_mask := 0
var _main_camera_render_suppressed := false
var _camera: Camera3D
var _flight_overlay: TeeShotFlightOverlay
var _map_size := Vector2.ZERO
var _map_position := Vector2.ZERO
var _split_mode := false
var _split_progress := 0.0
var _split_tween: Tween


func _ready() -> void:
	name = "TeeShotView"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_LEFT)

	_shot_panel = PanelContainer.new()
	_shot_panel.name = "ShotPanel"
	_shot_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_shot_panel.clip_contents = true
	add_child(_shot_panel)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.035, 0.055, 0.045, 0.94)
	panel_style.border_color = Color(0.82, 0.78, 0.56, 0.95)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(10)
	panel_style.content_margin_left = 6.0
	panel_style.content_margin_right = 6.0
	panel_style.content_margin_top = 6.0
	panel_style.content_margin_bottom = 6.0
	_shot_panel.add_theme_stylebox_override("panel", panel_style)

	var layout := VBoxContainer.new()
	layout.name = "Layout"
	layout.add_theme_constant_override("separation", 4)
	_shot_panel.add_child(layout)

	var title := Label.new()
	title.text = "TEE SHOT  |  FLIGHT VIEW"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.96, 0.93, 0.78))
	title.add_theme_constant_override("outline_size", 3)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	layout.add_child(title)

	_aspect_container = AspectRatioContainer.new()
	_aspect_container.name = "ShotAspectContainer"
	_aspect_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_aspect_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_aspect_container.ratio = 1.0
	layout.add_child(_aspect_container)

	_viewport_container = SubViewportContainer.new()
	_viewport_container.name = "ShotViewportContainer"
	_viewport_container.custom_minimum_size = Vector2.ONE
	_viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_viewport_container.stretch = true
	_viewport_container.stretch_shrink = FLIGHT_VIEW_RENDER_SHRINK
	_viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport_container.clip_contents = true
	_aspect_container.add_child(_viewport_container)

	_viewport = SubViewport.new()
	_viewport.msaa_3d = SubViewport.MSAA_DISABLED
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport_container.add_child(_viewport)

	_camera = Camera3D.new()
	_camera.name = "TeeShotCamera"
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.fov = CAMERA_FIELD_OF_VIEW
	_camera.cull_mask = 1 << 0
	_viewport.add_child(_camera)
	_camera.make_current()

	_flight_overlay = TeeShotFlightOverlay.new()
	_flight_overlay.name = "TeeShotFlightOverlay"
	_flight_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flight_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flight_overlay.clip_contents = true
	_flight_overlay.z_index = 10
	_viewport_container.add_child(_flight_overlay)


func set_minimap_rect(minimap_rect: Rect2) -> void:
	_map_size = minimap_rect.size
	_map_position = minimap_rect.position
	if not _split_mode:
		position = _map_position
		if not visible:
			size = _map_size
		_shot_panel.position = Vector2.ZERO
		_shot_panel.size = _map_size
	if _viewport != null:
		_aspect_container.ratio = _map_size.x / maxf(1.0, _map_size.y)


func set_main_camera(camera: Camera3D) -> void:
	if _main_camera == camera:
		return
	_restore_main_camera_rendering()
	_main_camera = camera
	if _split_mode:
		_suppress_main_camera_rendering()


func prepare_for_shot(start_pos: Vector3, current_pos: Vector3, target_pos: Vector3) -> void:
	show_shot(start_pos, current_pos, target_pos)
	var opening_tween := _split_tween
	if opening_tween != null:
		await opening_tween.finished


func show_shot(start_pos: Vector3, _current_pos: Vector3, target_pos: Vector3) -> void:
	_stop_split_transition()
	_flight_overlay.clear_flight_path()
	_split_mode = false
	visible = true
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	size = get_viewport_rect().size
	_start_split_viewport()
	_split_mode = true
	_split_progress = 0.0
	_update_split_layout()
	_sync_main_camera()
	_suppress_main_camera_rendering()
	_sync_main_camera()
	_viewport_container.visible = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_shot_panel.visible = true
	split_started.emit()
	_split_tween = create_tween()
	_split_tween.set_trans(Tween.TRANS_CUBIC)
	_split_tween.set_ease(Tween.EASE_IN_OUT)
	_split_tween.tween_method(_set_split_progress, 0.0, 1.0, SIZE_TRANSITION_DURATION)
	_split_tween.tween_callback(_finish_split_open)
	if _camera == null:
		return

	var shot_direction := target_pos - start_pos
	shot_direction.y = 0.0
	if shot_direction.length_squared() < 0.01:
		shot_direction = _current_pos - start_pos
		shot_direction.y = 0.0
	if shot_direction.length_squared() < 0.01:
		shot_direction = Vector3.FORWARD
	shot_direction = shot_direction.normalized()

	var camera_position := start_pos - shot_direction * CAMERA_TRAIL_DISTANCE + Vector3.UP * CAMERA_BASE_HEIGHT
	var look_target := start_pos + shot_direction * CAMERA_LOOK_DISTANCE + Vector3.UP * CAMERA_LOOK_HEIGHT

	_camera.global_position = camera_position
	_camera.look_at(look_target, Vector3.UP)


func _start_split_viewport() -> void:
	if _split_viewport_container != null:
		return

	_split_clip = Control.new()
	_split_clip.name = "MainViewClip"
	_split_clip.clip_contents = true
	_split_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_split_clip)
	move_child(_split_clip, 0)

	_split_viewport_container = SubViewportContainer.new()
	_split_viewport_container.name = "MainViewViewportContainer"
	_split_viewport_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_split_viewport_container.stretch = true
	_split_viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_split_clip.add_child(_split_viewport_container)

	_split_viewport = SubViewport.new()
	_split_viewport.name = "MainViewViewport"
	_split_viewport.own_world_3d = false
	_split_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_split_viewport_container.add_child(_split_viewport)

	_main_camera_copy = Camera3D.new()
	_main_camera_copy.name = "MirroredMainCamera"
	_main_camera_copy.keep_aspect = Camera3D.KEEP_HEIGHT
	_split_viewport.add_child(_main_camera_copy)


func _set_split_progress(progress: float) -> void:
	_split_progress = progress
	_update_split_layout()


func _update_split_layout() -> void:
	if not _split_mode or _split_clip == null:
		return
	var screen_size := get_viewport_rect().size
	size = screen_size
	var left_width := lerpf(screen_size.x, screen_size.x * 2.0 / 3.0, _split_progress)
	_split_clip.position = Vector2.ZERO
	_split_clip.size = Vector2(left_width, screen_size.y)
	_shot_panel.position = Vector2(left_width, 0.0)
	_shot_panel.size = Vector2(screen_size.x - left_width, screen_size.y)
	_shot_panel.visible = _shot_panel.size.x > 1.0


func _sync_main_camera() -> void:
	if _main_camera == null or not is_instance_valid(_main_camera) or _main_camera_copy == null:
		return
	if _split_viewport.world_3d != _main_camera.get_world_3d():
		_split_viewport.world_3d = _main_camera.get_world_3d()
	_main_camera_copy.global_transform = _main_camera.global_transform
	_main_camera_copy.projection = _main_camera.projection
	_main_camera_copy.fov = _main_camera.fov
	_main_camera_copy.size = _main_camera.size
	_main_camera_copy.frustum_offset = _main_camera.frustum_offset
	_main_camera_copy.h_offset = _main_camera.h_offset
	_main_camera_copy.v_offset = _main_camera.v_offset
	_main_camera_copy.near = _main_camera.near
	_main_camera_copy.far = _main_camera.far
	_main_camera_copy.cull_mask = _main_camera_cull_mask if _main_camera_render_suppressed else _main_camera.cull_mask
	_main_camera_copy.environment = _main_camera.environment
	_main_camera_copy.attributes = _main_camera.attributes
	_main_camera_copy.keep_aspect = Camera3D.KEEP_HEIGHT
	if not _main_camera_copy.current:
		_main_camera_copy.make_current()


func _suppress_main_camera_rendering() -> void:
	if _main_camera == null or not is_instance_valid(_main_camera) or _main_camera_render_suppressed:
		return
	_main_camera_cull_mask = _main_camera.cull_mask
	_main_camera_render_suppressed = true
	_main_camera.cull_mask = 0


func _restore_main_camera_rendering() -> void:
	if _main_camera_render_suppressed and _main_camera != null and is_instance_valid(_main_camera):
		_main_camera.cull_mask = _main_camera_cull_mask
	_main_camera_render_suppressed = false


func _process(_delta: float) -> void:
	if _split_mode:
		_update_split_layout()
		_sync_main_camera()


func _finish_split_open() -> void:
	_split_tween = null


func update_tracer(local_points: Array, player_transform: Transform3D, start_pos: Vector3, current_pos: Vector3) -> void:
	var points: Array[Vector3] = []
	for point in local_points:
		if point is Vector3:
			var global_point: Vector3 = player_transform * point
			points.append(global_point + Vector3.UP * TRACER_HEIGHT_OFFSET)
	if points.is_empty() or not points.front().is_equal_approx(start_pos + Vector3.UP * TRACER_HEIGHT_OFFSET):
		points.push_front(start_pos + Vector3.UP * TRACER_HEIGHT_OFFSET)
	if not points.back().is_equal_approx(current_pos + Vector3.UP * TRACER_HEIGHT_OFFSET):
		points.append(current_pos + Vector3.UP * TRACER_HEIGHT_OFFSET)

	_flight_overlay.set_flight_path(_camera, points, start_pos + Vector3.UP * TRACER_HEIGHT_OFFSET)


func update_ball_position(current_pos: Vector3) -> void:
	_flight_overlay.set_ball_position(current_pos + Vector3.UP * TRACER_HEIGHT_OFFSET)


func hide_shot(immediate: bool = false) -> void:
	if not visible:
		return
	if not _split_mode:
		visible = false
		return
	_stop_split_transition()
	if immediate:
		_finish_split_close()
		return
	_split_tween = create_tween()
	_split_tween.set_trans(Tween.TRANS_CUBIC)
	_split_tween.set_ease(Tween.EASE_IN_OUT)
	_split_tween.tween_method(_set_split_progress, _split_progress, 0.0, SIZE_TRANSITION_DURATION)
	_split_tween.tween_callback(_finish_split_close)


func _finish_split_close() -> void:
	_split_tween = null
	_split_mode = false
	_restore_main_camera_rendering()
	if _split_clip != null:
		_split_clip.queue_free()
	_split_clip = null
	_split_viewport_container = null
	_split_viewport = null
	_main_camera_copy = null
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_flight_overlay.clear_flight_path()
	position = _map_position
	size = _map_size
	_shot_panel.position = Vector2.ZERO
	_shot_panel.size = _map_size
	_shot_panel.visible = true
	visible = false
	split_closed.emit()


func _stop_split_transition() -> void:
	if _split_tween != null and _split_tween.is_running():
		_split_tween.kill()
	_split_tween = null


func _exit_tree() -> void:
	_restore_main_camera_rendering()
