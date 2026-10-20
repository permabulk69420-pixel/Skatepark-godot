# Every number that decides how the skateboarding feels lives here. Metres, seconds, radians.
# (Started as the web build's config.js; it has been tuned since and no longer matches it.)
class_name Config

class Board:
	# Measured from RIFT_Skateboard.glb (origin on the ground between the wheels, nose toward -Z).
	const deckTop := 0.145  # standing surface above the origin
	const deckBottom := 0.084  # underside of the deck, what a boardslide rides on
	const truckBottom := 0.014  # bottom of the hangers, what a 50-50 rides on
	const wheelRadius := 0.026
	const wheelHalfTrack := 0.082
	const wheelHalfBase := 0.239
	const length := 0.81
	const width := 0.208  # (measured from the model; the trucks are the same width)

class Tuning:
	const gravity := 9.81
	const maxSubstep := 1.0 / 120.0

	# Rolling and pushing
	const rollFriction := 0.16  # m/s² of constant bearing drag
	const airDrag := 0.003  # × speed² deceleration
	const lateralGrip := 11.0  # 1/s, how fast sideways slip dies on the ground
	const pushImpulse := 1.9  # m/s per kick at standstill
	const pushMaxSpeed := 7.4  # kicks fade out as you approach this
	const pushInterval := 0.62
	const pushDrain := 14.0  # m/s² the kick is applied at
	const brakeDecel := 5.2
	const driveThreshold := 0.5

	# Steering
	const maxYawRate := 2.1
	const maxLateralAccel := 7.5  # limits turn rate as speed rises
	const steerSpeedRef := 1.4  # below this speed the trucks barely bite
	const pivotRate := 0.9  # tail-pivot turning when nearly stopped
	const airSpinRate := 5.2
	const airSpinDeadzone := 0.4
	const airSpinResponse := 14.0

	# Ollie
	const popMin := 3.05  # m/s along the surface normal for a tap (~0.47 m)
	const popMax := 4.0  # full charge (~0.82 m)
	const popChargeTime := 0.42
	const popBodyHold := 0.55  # how long a hold keeps charging the crouch visual
	const popAnimTime := 0.38
	const popUpBias := 2.0  # pop direction leans from the surface normal towards straight up as the surface steepens (n.y^this)

	# Flips: the flip button in the air plus the stick left (kickflip) or right (heelflip), one full turn of the board.
	const flipTime := 0.46  # seconds for the board to turn all the way round
	const flipMinAir := 0.05  # seconds in the air before a flip can start
	const flipCleanRoll := 0.7  # landing within this many radians (~40°) of flat is a clean landing
	const flipBailRoll := 1.9  # further than this (~110°) from flat and you bail; in between is a sketchy landing
	const flipSketchySpeed := 0.7  # share of your speed kept on a sketchy landing
	# Board-trick controls (trick-controls.js): press B and push the stick, either order; fires the instant both are there.
	const shuvTime := 0.32  # seconds for the board to spin the half turn
	const trickStick := 0.4  # how far the stick must be pushed (raw radius) to count as a direction
	const trickWindow := 0.4  # B and the push can be this far apart, either way round; also how long a pick waits to leave the ground
	const shuvClean := 0.6  # landing within this many radians of straight (or straight round) is clean
	const shuvBail := 1.05  # further than this (~60°) from straight and you bail; in between is sketchy

	# Ground following
	const maxStep := 0.08  # free rise allowed per step before it counts as a wall
	const maxSlopeTan := 1.7  # plus this × horizontal travel (≈60°) beyond what the board's own climb explains
	const steepNormalY := 0.55  # surfaces steeper than this are tracked with rays along the board's normal, not straight down
	const wallProbe := 0.33  # how far ahead of the board centre a wall is noticed
	const edgeGrace := 0.3  # seconds after rolling off an edge when the trailing wheels are ignored
	const freezeBail := 0.35  # seconds airborne without moving at all (wedged in the geometry) before it bails out
	const popWheelFree := 0.14  # seconds after an ollie when only the middle of the board can land it (the wheels are still inside a slope ahead)
	const sweepSupportReach := 0.3  # a wheel touching down only counts as a landing if the ground under the board's middle is within this much of it…
	const sweepSupportDrop := 0.3  # …(not more than this far lower: the middle hanging out over a drop means the board only caught the edge)
	const sweepLandMinNormalY := 0.2  # the centre of the board lands on any surface at least this far from vertical
	const steepContact := 0.12  # on a steep wall a wheel counts as touching within this of the surface
	const steepLeave := 0.07  # average hover above the wall beyond this and the board has left it
	const wheelAgreement := 0.85  # any single wheel's surface this far (≈32°) off the fitted plane means a lip, not a slope
	const hugTime := 0.7  # a drop-in rider leans into the wall for this long after rolling off the lip
	const hugMaxSpeed := 3.0
	const hugReach := 1.0
	const hugDamp := 9.0
	const planeAgreement := 0.92  # wheel plane vs the surfaces they hit: below this the wheels straddle an edge
	const crestMinNormalY := 0.3  # the ground under the middle of the board may be this steep (≈72°) and still count as a ramp, not a wall, at a crest
	const crestDeckNormalY := 0.9  # ground this flat under the middle of the board, past a steep slope, is a deck: over the lip you fly
	const crestLeave := 0.03
	const wallCos := 0.45  # a surface this much steeper than the one you are on counts as a wall
	const snapDistance := 0.05  # stay glued to the ground within this
	const transitionKeep := 0.8  # how much speed survives a sudden change of surface angle
	const wallBailSpeed := 3.4  # m/s into a wall that throws you off
	const wallEventSpeed := 0.7  # below this a bump makes no noise
	const landMaxAngle := 0.78  # rad (45°) board-vs-travel misalignment that still lands
	const landAngleMinSpeed := 3.0
	const wallLandFrom := 0.9  # surfaces steeper than this (normal y) are ridden when you land on them…
	const wallLandSpan := 0.5  # …fully by this much steeper
	const wallLandKeep := 0.75  # share of the speed that would have gone into the wall that carries on down it
	const landBailImpact := 13.0  # m/s into the ground
	const bounds := {"x": 54.6, "z": 46.3}
	const killY := -12.0

	# Grinding
	const grindAlign := 0.52  # rad (30°) from parallel for a 50-50
	const slideAlign := 0.52  # rad (30°) from perpendicular for a boardslide
	const grindReach := 0.10  # a rail this far outside the board's edge still catches (both kinds)
	const truckLateral := Config.Board.width / 2.0 + grindReach  # 50-50: the rail anywhere under the width of the board, plus the reach, each side
	const slideLateral := Config.Board.length / 2.0 + grindReach  # boardslide: the rail anywhere along the length of the board, plus the reach, each end
	const catchBelow := 0.12
	const catchAbove := 0.09
	const catchMaxRise := 1.6
	const grindMinSpeed := 0.9
	const magnetReach := 0.7  # press grind within this far (horizontally) of a coping, up the wall or on the deck, and it latches on…
	const magnetBelow := 0.9  # …if the board is no more than this far below the lip…
	const magnetAbove := 0.2  # …or this far above it
	const magnetMinSpeed := 1.5  # …and is moving along it at least this fast (m/s)
	const magnetTruckAngle := 0.8  # heading within this (rad) of parallel to the coping is a 50-50, otherwise a boardslide
	const grindArmWindow := 0.55  # one press of the grind button catches the first rail or coping the board touches in this many seconds
	const grindStallSpeed := 0.35
	const copingSlideMinSpeed := 2.2  # a coping boardslide needs this much speed along the lip to catch
	const copingSlideEnd := 1.2  # …and ends (into the pit) if it slows below this
	const copingDropIn := 1.0  # m/s into the pit when it ends
	const grindCooldown := 0.3
	const grindFriction := {"rail": 0.5, "coping": 0.7, "ledge": 1.1}
	const grindAlignRate := 14.0
	const exitAlignRate := 7.0
	const exitAlignTime := 0.35
	# Balance: bal'' = instab·bal + wobble + control·stick − damp·bal'
	const balInstab0 := 2.0
	const balInstabGrow := 0.35
	const balInstabMax := 6.5
	const balWobble := 1.25
	const balControl := 7.5
	const balDamp := 1.4
	const balEntryScale := 0.8
	# Nosegrind / 5-0: in a 50-50, hold the stick up (front truck on the rail, tail up) or down (back truck, nose up).
	const variantStick := 0.55  # stick deflection that picks a nose grind or a 5-0
	const variantRelease := 0.35  # back inside this and it is a 50-50 again (in between it stays as it was)
	const variantTilt := 0.24  # rad the board pitches on the rail
	const variantResponse := 12.0  # 1/s: how fast the board rocks onto the one truck
	const variantHard := 1.3  # balance instability × this at the full variant: harder than a 50-50
	const variantDrag := 0.25  # extra rail friction at the full variant
	const variantMinTime := 0.3  # seconds in a variant before the trick takes its name
	const balMaxTilt := 0.34  # board lean at the edge of the meter
	const railTopOffset := {"rail": 1, "coping": 1, "ledge": -0.9}  # × path radius above the stored line (ledge lines sit just above their surface)

	# Pumping with the stick: holding forward on a curved surface (a transition, a bank) pumps it, the same way forward pushes
	# on the flat. This is how you build the speed to reach a lip and air out of it.
	const autoPump := 3.4  # m/s² of speed at full curvature
	const autoPumpMaxSpeed := 10.5  # no more pumping beyond this

	# Pumping: standing up out of a squat while on a curved surface adds speed (VR: your real knees do it)
	const pumpGain := 3.2  # m/s² of speed per m/s of extension, on a fully curved surface
	const pumpMaxAccel := 4.5
	const pumpRefTime := 2.5  # seconds the "standing height" baseline takes to follow your head
	const pumpResponse := 14.0  # smoothing of the head's vertical speed
	const pumpCurve := 0.22  # 1 - surface normal y at which the pump is at full strength
	const pumpEventSpeed := 0.18  # speed gained in one stand-up worth a haptic tick

	# Airs at a lip stay inside the pipe at any speed unless an ollie near the lip is
	# accompanied by forward input. Speed still determines whether you reach the lip.
	const passPopWindow := 0.45  # only a recent ollie can initiate an intentional lip exit
	const passHoldMax := 4.0
	const passHoldDrain := 2.0
	const lipZone := 3.2  # how far from a lip (horizontally) this applies
	const lipHoldDist := 0.28  # an air that should stay is held this far inside the lip line, against the wall, so it rides back down the face
	const lipSpring := 60.0
	const lipDamp := 15.0
	const lipMaxAccel := 30.0
	const lipOutwardAccel := 12.0
	const lipOutwardSpeed := 2.6  # an air that earned it is sent this fast out over the lip
	const lipOutwardZone := 2.5  # …while it is within this of the lip line

	# In the air the board keeps the tilt it left the surface with (come out of a wall vertical and you stay vertical) and
	# eases towards whatever it is about to land on, faster the closer that gets.
	const airTiltFar := 0.9  # 1/s while far from anything
	const airTiltNear := 7.0  # 1/s as the landing surface gets close
	const airTiltReach := 3.0  # metres below which "close" starts

	# Axle stall / rock to fakie: catching coping square-on while almost stopped
	const stallLateral := 0.3
	const stallIntoPit := 0.6  # heading over the coping this fast towards the drop is a drop-in, not a stall
	const stallCooldown := 1.4  # after rocking out of a stall you cannot catch that same lip again for this long
	const stallMaxVertical := 1.4  # no stall catch while moving this fast up or down
	const stallBackSpeed := 1.9
	const stallBlockHold := 0.5  # holding forward this long means you are going over, so no stall catch       // pop off a stall and you roll back down the way you came, this fast
	const stallPopScale := 0.55
	const stallAutoRock := 0.8  # a stall held this long rocks back in by itself (no pop needed), instead of ending in a balance bail

	# Loops (loop.js). Rolling onto the curved part of a loop's track, the board follows the track; it falls (a bail) wherever the
	# track would have to pull it on: speed² × curvature less than the part of gravity pulling it off, upside down.
	const loopEnterNy := 0.97  # the track counts as the loop where its normal has tilted past this (before that it is plain ground)
	const loopFriction := 0.35  # × the ground's rolling drag and air drag: a smooth ply track
	const loopPump := 2.6  # m/s² from holding forward on the bottom half of the loop (pumping it)
	const loopGrip := 0.0  # m/s² of "stick" before the board falls off upside down (0: plain physics)
	const loopSteer := 0.7  # m/s of drift across the track at full stick
	const loopEdge := 0.3  # the board's middle keeps at least this far from the edge of the track
	const loopPopNy := 0.6  # ollie out of the loop only where the track is at least this flat

	# Backflips and frontflips: in the air, while grabbing, hold the stick back (backflip) or forward (frontflip). Deliberately hard to
	# start by accident: most of the way over, close to straight back/forward, and held a moment first. Spin and flip can then combine.
	const bodyFlipStick := 0.75  # how far the stick must be pushed (of 1) to start one
	const bodyFlipCone := 0.4886921905584123  # …within this of straight back or forward (a diagonal or sideways push stays a spin)
	const bodyFlipDelay := 0.15  # seconds it has to be held there before you start turning over
	const bodyFlipKeep := 0.45  # once started, you keep turning while the stick is at least this far back/forward (diagonals included)
	const bodyFlipRate := 6.3  # rad/s at full turn (a whole flip in about a second)
	const bodyFlipResponse := 7.0  # 1/s: how quickly the turn speeds up and slows down
	const bodyFlipClean := 0.6  # landing within this (rad, ~35°) of upright is clean…
	const bodyFlipBail := 1.3  # …beyond this (~75°) you slam; in between it is sketchy

	# Manuals. Flick the stick forward then back (quickly) for a manual; back then forward for a nose manual. Then balance it with
	# forward/back on the stick, like a grind meter. Ollie out of it, or let it run out of speed.
	const flickThreshold := 0.5  # how far the stick has to go either way to count as a flick
	const flickWindow := 0.55  # seconds between the two halves of the flick
	const manualQueueWindow := 0.7  # a manual asked for in the air (or just before landing) starts when you land, if it was this recent
	const manualMinSpeed := 1.5  # you need to be rolling to start one
	const manualEndSpeed := 0.7  # below this a manual runs out
	const manualTilt := 0.26  # rad the board sits at when balanced (≈15°)
	const manualMaxTilt := 0.24  # extra rad at the edge of the meter
	const manualDrag := 0.45  # m/s² extra drag on one pair of wheels
	const manualSteer := 0.7  # turning is weaker while balancing
	const manualInstab0 := 1.6
	const manualInstabGrow := 0.2
	const manualInstabMax := 4.5
	const manualWobble := 0.9
	const manualControl := 6.5
	const manualDamp := 1.6

	# Bail
	const bailTime := 1.25
	const bailFallDrop := 0.8

class Rider:
	# How much the view eases into a change of surface angle. Small tilts (a fun box, a bank edge) are smoothed so they do
	# not snap the camera; steep ones (a half-pipe wall) are followed almost rigidly so the world still swings with you.
	const tiltRateGentle := 7.0  # 1/s for slopes under ~20°
	const tiltRateSteep := 90.0  # 1/s for walls past ~50°
	const tiltGentleAngle := 0.35  # rad
	const tiltSteepAngle := 0.87  # rad
	const tiltRateGrind := 30.0
	const crouchPress := 0.07  # instant dip on press
	const crouchHold := 0.13  # settles to this while held
	const crouchSettle := 18.0
	const popRebound := 0.035
	const landCompress := 0.09
	const eyeHeightDesktop := 1.65

class Hands:
	const range := 0.38  # radians (~22°) of hand-line tilt from neutral that is a full push on the meter
	const deadzone := 0.05  # radians (~3°) of tilt that is ignored
	const restTime := 1.0  # seconds the neutral takes to follow your hands while you are rolling relaxed on the ground
	const minSpread := 0.25  # metres: hands closer than this count as this far apart, so a tiny wobble is not a big angle
	const ease := 0.25  # seconds the push takes to come in when a grind or manual starts
	const response := 25.0  # 1/s smoothing of the push

