# The clock on a park level: a round of a set length (two minutes) that starts when you first roll off, counts down, and when it runs out
# the result is shown for a while and a fresh round waits for you to start rolling again. `update` says when each of those happened;
# what to show is main.gd's business.
class_name ParkTimer
extends RefCounted

enum State { WAITING, RUNNING, DONE }

const RESULT_SECONDS := 10.0   # how long the result is up before the next round is ready

var length: float
var state := State.WAITING
var left: float                # seconds still to go
var _shown := 0.0              # how long the result has been up


func _init(seconds: float) -> void:
	length = seconds
	left = seconds


# Points count while a round is on (before it starts there is nothing to count, and once it is over the result is already settled).
func counting() -> bool:
	return state != State.DONE


# Once a frame while riding. `moving`: the skater is rolling or in the air. Returns "start", "end", "again" or "".
func update(dt: float, moving: bool) -> String:
	match state:
		State.WAITING:
			if moving:
				state = State.RUNNING
				left = length
				return "start"
		State.RUNNING:
			left -= dt
			if left <= 0.0:
				left = 0.0
				state = State.DONE
				_shown = 0.0
				return "end"
		State.DONE:
			_shown += dt
			if _shown >= RESULT_SECONDS:
				state = State.WAITING
				left = length
				return "again"
	return ""


# 102.3 -> "1:43" (rounded up, so it reads 0:00 only when time is really up).
func text() -> String:
	var whole := int(ceil(maxf(left, 0.0)))
	return "%d:%02d" % [whole / 60, whole % 60]
