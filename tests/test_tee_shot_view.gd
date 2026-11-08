extends SceneTree

const EXPECTED_TRANSITION_DURATION := 0.8


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var view_script = load("res://UI/tee_shot_view.gd")
	assert(view_script != null, "Tee shot view script must load")

	var view = view_script.new()
	root.add_child(view)
	var main_camera := Camera3D.new()
	main_camera.cull_mask = 3
	root.add_child(main_camera)
	view.set_main_camera(main_camera)
	assert(not view.visible, "Tee shot view must start hidden")
	assert(view._camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "Inset camera must use a perspective broadcast view")
	assert(view._camera.cull_mask == 1, "Inset must show the course and tracer without map overlays")
	assert(view._viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Hidden inset must not render")
	assert(view._viewport.msaa_3d == SubViewport.MSAA_DISABLED, "Tee-shot flight viewport must avoid extra MSAA rendering cost")
	assert(view._viewport_container.stretch_shrink == 2, "Tee-shot course view must render at reduced resolution during flight")
	assert(view._flight_overlay != null, "Inset must draw its tee marker and tracer in an isolated 2D overlay")
	assert(view._viewport.find_child("TeeShotStartMarker", true, false) == null, "Inset must not add tee meshes to the shared 3D world")
	assert(view._viewport.find_child("SolidTeeShotTracer", true, false) == null, "Inset must not add tracer meshes to the shared 3D world")

	var minimap_rect := Rect2(Vector2(30.0, 60.0), Vector2(288.0, 333.0))
	view.set_minimap_rect(minimap_rect)
	assert(view.size.is_equal_approx(minimap_rect.size), "Hidden inset must match the current minimap size")
	assert(view.position.is_equal_approx(minimap_rect.position), "Inset must overlay the current minimap")
	assert(view._aspect_container.ratio < 1.0, "Inset viewport must remain portrait-oriented")

	var tee := Vector3(12.0, 0.0, -8.0)
	var previous_points: Array[Vector3] = [tee, tee + Vector3.UP]
	view._flight_overlay.set_flight_path(view._camera, previous_points, tee)
	view.show_shot(tee, tee + Vector3(0.0, 2.0, -1.0), Vector3(20.0, 0.0, -220.0))
	assert(view.visible, "Tee shot must show the inset")
	assert(view._flight_overlay._points.is_empty(), "Previous shot tracer must be cleared before the next window expands")
	assert(view._split_mode, "Tee shot must switch to the temporary split-screen layout")
	assert(main_camera.cull_mask == 0, "Covered main camera must stop drawing the hidden course during the shot")
	assert(view._main_camera_copy.cull_mask == 3, "Split-screen course camera must preserve the main camera's original cull mask")
	assert(is_equal_approx(view._split_progress, 0.0), "Split-screen transition must start at the full gameplay view")
	assert(view._viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "Inset must update during flight")
	assert(view.SIZE_TRANSITION_DURATION == EXPECTED_TRANSITION_DURATION, "Opening and closing transitions must use the longer duration")
	assert(view._viewport_container.visible, "Course picture must stay visible while the window expands")
	assert(is_equal_approx(view._aspect_container.ratio, minimap_rect.size.x / minimap_rect.size.y), "Course picture must preserve its portrait ratio while expanding")
	var screen_size: Vector2 = view.get_viewport_rect().size
	assert(is_equal_approx(view._split_clip.size.x, screen_size.x), "Opening split must initially cover the full game view")
	var close_shot_camera_position: Vector3 = view._camera.global_position
	assert(view._camera.global_position.z - tee.z > 55.0, "Camera must sit farther behind the tee")
	assert(view._camera.global_position.y - tee.y > 65.0, "Camera must sit well above the tee to see over trees")
	var tee_screen_position: Vector2 = view._camera.unproject_position(tee + Vector3.UP * 0.3)
	assert(tee_screen_position.x >= 0.0 and tee_screen_position.x <= view._viewport.size.x, "Tee marker must project within the inset")
	assert(tee_screen_position.y >= 0.0 and tee_screen_position.y <= view._viewport.size.y, "Tee marker and tee box must project within the inset")
	assert(view.get_node("ShotPanel/Layout/ShotAspectContainer/ShotViewportContainer").clip_contents, "Flight tracer must be clipped to the inset window")
	view.update_tracer([Vector3.ZERO, Vector3(0.0, 8.0, -30.0)], Transform3D.IDENTITY, tee, tee + Vector3(0.0, 12.0, -40.0))
	assert(view._flight_overlay._points.size() >= 2, "Inset must draw a solid flight path from the tee")
	var first_projected_point: Vector2 = view._flight_overlay._projected_points[0]
	var previous_ball_screen_position: Vector2 = view._flight_overlay._ball_marker.marker_position
	view.update_ball_position(tee + Vector3(1.0, 13.0, -42.0))
	var updated_ball_screen_position: Vector2 = view._flight_overlay._ball_marker.marker_position
	assert(not updated_ball_screen_position.is_equal_approx(previous_ball_screen_position), "Ball marker must update independently of tracer geometry")
	view.update_tracer([Vector3.ZERO, Vector3(0.0, 8.0, -30.0)], Transform3D.IDENTITY, tee, tee + Vector3(2.0, 14.0, -45.0))
	assert(view._flight_overlay._projected_points[0].is_equal_approx(first_projected_point), "Tracer updates must keep completed path segments cached")
	assert(not view._flight_overlay._projected_points[-1].is_equal_approx(updated_ball_screen_position), "Throttled tracer geometry may lag the smoothly updated ball marker")
	await process_frame
	await process_frame
	assert(view._camera.global_position.is_equal_approx(close_shot_camera_position), "Camera position must stay fixed for the duration of the shot")
	await create_timer(EXPECTED_TRANSITION_DURATION + 0.1).timeout
	assert(is_equal_approx(view._split_progress, 1.0), "Split transition must finish at the two-thirds gameplay width")
	assert(is_equal_approx(view._split_clip.size.x, screen_size.x * (2.0 / 3.0)), "Gameplay view must occupy the left two-thirds")
	assert(is_equal_approx(view._shot_panel.size.x, screen_size.x / 3.0), "Tee-shot view must occupy the right third")
	view.hide_shot()
	assert(view.visible, "Split layout must remain visible while transitioning back")
	await create_timer(EXPECTED_TRANSITION_DURATION * 0.5).timeout
	assert(view.visible, "Split layout must stay visible during the closing transition")
	assert(view._split_progress < 1.0 and view._split_progress > 0.0, "Split layout must visibly close over time")
	await create_timer(EXPECTED_TRANSITION_DURATION + 0.1).timeout
	assert(not view.visible, "Split layout must hide after returning to the full gameplay view")
	assert(not view._split_mode, "Closing must restore normal inset mode")
	assert(main_camera.cull_mask == 3, "Closing the split screen must restore the main camera")
	assert(view.size.is_equal_approx(minimap_rect.size), "Inset must finish at minimap size")
	assert(view._viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Hidden inset must stop rendering")
	main_camera.queue_free()

	view.show_shot(tee, tee + Vector3(0.0, 2.0, -1.0), Vector3(20.0, 0.0, -220.0))
	view.hide_shot(true)
	assert(not view.visible, "Disabling the overhead tee shot must immediately hide the split view")
	assert(not view._main_camera_render_suppressed, "Disabling the overhead tee shot must restore normal course rendering")

	print("PASS: Tee-shot view uses an elevated rear perspective and can be disabled immediately.")
	quit(0)
