# Puts the player on the board. The play space (rig) is bolted to the board: it goes wherever the board goes, turns
# when it turns and tilts with whatever the board is lying on, so ramps, walls and rails all swing the whole world
# around you. Inside it the headset keeps its real position over the deck, and you face the way you would standing on a real
# board: side-on to travel, never forward. On a flat screen the camera sits at eye height looking down the board instead, and the
# mouse turns the view.
class_name PlayerRig
extends RefCounted

const T = Config.Tuning
const BOARD = Config.Board
const RIDER = Config.Rider

var rig: Node3D                 # XROrigin3D in the headset, a plain Node3D on a flat screen
var camera: Camera3D            # XRCamera3D in the headset
var sim: Skater
var vr := false
var up := Vector3.UP            # the up the view is actually using: the board's, eased
var anchor := Vector2.ZERO      # where the head was, in play-space metres, when you "stood on the board"
var yaw_cal := 0.0              # which way the head faced then, relative to the play space
var calibrated := false
var settle_frames := 0
var fade := 0.0
var fade_rect: ColorRect        # flat-screen fade
var fade_mesh: MeshInstance3D   # headset fade: a black quad just in front of the eyes
var look_yaw := 0.0
var look_pitch := 0.0


func _init(p_rig: Node3D, p_camera: Camera3D, p_sim: Skater, p_fade_rect: ColorRect, p_vr: bool = false) -> void:
	rig = p_rig
	camera = p_camera
	sim = p_sim
	fade_rect = p_fade_rect
	vr = p_vr
	camera.rotation_order = EULER_ORDER_YXZ
	if vr:
		fade_mesh = _make_fade_mesh()
		camera.add_child(fade_mesh)


static func _make_fade_mesh() -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0, 0, 0, 0)
	material.no_depth_test = true
	material.render_priority = 127
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var quad := QuadMesh.new()
	quad.size = Vector2(3.0, 3.0)
	var mesh := MeshInstance3D.new()
	mesh.mesh = quad
	mesh.material_override = material
	mesh.position = Vector3(0.0, 0.0, -0.12)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.extra_cull_margin = 16384.0
	mesh.visible = false
	return mesh


# Flat-screen look-around.
func turn_view(dx: float, dy: float) -> void:
	look_yaw -= dx * 0.003
	look_pitch = clampf(look_pitch - dy * 0.003, -1.45, 1.45)


# Call when a session starts, or any time the player wants the board re-centred under them.
func request_calibration() -> void:
	calibrated = false
	settle_frames = 0


func calibrate() -> void:
	anchor = Vector2(camera.position.x, camera.position.z)
	yaw_cal = camera.transform.basis.get_euler(EULER_ORDER_YXZ).y
	calibrated = true


func update(dt: float) -> void:
	if not calibrated:
		up = sim.up
	if vr:
		if not calibrated:
			# Give tracking a moment to settle before reading where the head is.
			settle_frames += 1
			if settle_frames > 24 and camera.position.y > 0.4:
				calibrate()
	elif not calibrated:
		anchor = Vector2.ZERO
		yaw_cal = 0.0
		calibrated = true

	# Feet on the deck, dropping with a crouch (and, in a bail, falling away from the board). Everything is measured
	# along the board's own up so it stays right on a wall.
	var drop := sim.crouch
	if sim.mode == Skater.Mode.BAIL:
		var e := clampf(sim.bail_time / 0.35, 0.0, 1.0)
		drop += T.bailFallDrop * e * e * (3.0 - 2.0 * e)
	# Ease into changes of surface angle: gentle slopes are smoothed, steep walls are followed almost rigidly.
	var tilt := acos(clampf(sim.up.y, -1.0, 1.0))
	var steep := smoothstep(RIDER.tiltGentleAngle, RIDER.tiltSteepAngle, tilt)
	var rate: float = RIDER.tiltRateGentle + (RIDER.tiltRateSteep - RIDER.tiltRateGentle) * steep
	if sim.mode == Skater.Mode.GRIND or sim.mode == Skater.Mode.BAIL or sim.manual != null:
		rate = RIDER.tiltRateGrind
	if dt > 1.0:
		up = sim.up
	up = up.lerp(sim.up, 1.0 - exp(-rate * dt)).normalized()
	var pivot := sim.pos + up * (BOARD.deckTop - drop + sim.manual_lift)

	# Rig attitude = the board's frame (heading + eased up), then turned so the player's calibrated gaze is the stance direction
	# (side-on in the headset, down the board on a flat screen, turned round after a shove-it).
	var board_q := sim.board_quaternion(false, up)
	var facing := sim.face_offset if vr else (PI if sim.switched else 0.0)
	var basis := Basis(board_q * Quaternion(Vector3.UP, facing - yaw_cal))
	# Rig origin so the calibrated head position sits over the board centre.
	var local := basis * Vector3(anchor.x, 0.0, anchor.y)
	rig.global_transform = Transform3D(basis, pivot - local)
	if not vr:
		camera.position = Vector3(0.0, RIDER.eyeHeightDesktop, 0.0)
		camera.rotation = Vector3(look_pitch, look_yaw, 0.0)

	# Fade to black while a bail plays out, then back in at the respawn.
	var fade_target := 1.0 if (sim.mode == Skater.Mode.BAIL and sim.bail_time > 0.5) else 0.0
	fade += (fade_target - fade) * (1.0 - exp(-(6.0 if fade_target > 0.0 else 5.0) * dt))
	if vr:
		fade_mesh.visible = fade > 0.01
		(fade_mesh.material_override as StandardMaterial3D).albedo_color.a = fade
	else:
		fade_rect.visible = fade > 0.01
		fade_rect.color.a = fade
