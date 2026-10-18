# Puts the player on the board. The play space (rig) is bolted to the board: it goes wherever the board goes, turns
# when it turns and tilts with whatever the board is lying on, so ramps, walls and rails all swing the whole world
# around you. On a flat screen the camera sits at eye height over the deck looking down the board; the mouse turns the view.
class_name PlayerRig
extends RefCounted

const T = Config.Tuning
const BOARD = Config.Board
const RIDER = Config.Rider

var rig: Node3D
var camera: Camera3D
var sim: Skater
var up := Vector3.UP        # the up the view is actually using: the board's, eased
var fade := 0.0
var fade_rect: ColorRect
var look_yaw := 0.0
var look_pitch := 0.0


func _init(p_rig: Node3D, p_camera: Camera3D, p_sim: Skater, p_fade_rect: ColorRect) -> void:
	rig = p_rig
	camera = p_camera
	sim = p_sim
	fade_rect = p_fade_rect
	camera.rotation_order = EULER_ORDER_YXZ


func turn_view(dx: float, dy: float) -> void:
	look_yaw -= dx * 0.003
	look_pitch = clampf(look_pitch - dy * 0.003, -1.45, 1.45)


func update(dt: float) -> void:
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

	# Rig attitude = the board's frame (heading + eased up); on a flat screen the view looks down the board (turned round after a shove-it).
	var board_q := sim.board_quaternion(false, up)
	var turn := Quaternion(Vector3.UP, PI if sim.switched else 0.0)
	rig.global_transform = Transform3D(Basis(board_q * turn), pivot)
	camera.position = Vector3(0.0, RIDER.eyeHeightDesktop, 0.0)
	camera.rotation = Vector3(look_pitch, look_yaw, 0.0)

	# Fade to black while a bail plays out, then back in at the respawn.
	var fade_target := 1.0 if (sim.mode == Skater.Mode.BAIL and sim.bail_time > 0.5) else 0.0
	fade += (fade_target - fade) * (1.0 - exp(-(6.0 if fade_target > 0.0 else 5.0) * dt))
	fade_rect.visible = fade > 0.01
	fade_rect.color.a = fade
