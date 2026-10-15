class_name Arena
extends RefCounted
## Shared fight constants (world units = screen pixels at camera zoom 1).

const GROUND := 560.0        # world y of the floor
const HALF_W := 760.0        # fighters' centres stay within ±HALF_W
const SPRITE_H := 330.0      # drawn height of a fighter's portrait
const PUSH_W := 74.0         # the default push width (stat push_w), and the legacy width every range below was authored against
const GRAVITY := 0.8
const MOVE_SCALE := 1.3      # walk, walk back, dash and jump travel (not the vertical arc) vs the class tables; Fighter.setup applies it once
const FPS := 60.0
const ROUND_SECONDS := 60
const MAX_HP := 1000.0       # every fighter has the same HP; class differences never touch it
const MAX_METER := 100.0
const SUPER_COST := 50.0     # skill + EX: the super, a powered-up skill with no cut-in
const EX_COST := 100.0       # EX alone at a full meter: the ult (cut-in)
const CHORD := 3             # skill and EX at most this many frames apart make the super
const SUPER_DMG := 1.3
const CLOSE_RANGE := 96.0    # a light or heavy with the foe this close (legacy distance: centres minus Fighter.spacing_extra(), foe on the ground) starts the kit's close strike
const THROW_RANGE := 120.0   # light + heavy within CHORD ticks is a throw while the foe stands this close (legacy distance) on the ground
const COMMAND_RANGE := 160.0 # forward + light or heavy is the 6x command normal only this close (legacy distance), or walking in would swallow the gun normals
const GUARD_DRAIN := 0.8     # guard lost per damage of a guarded hit, before the attacker's guard damage
const AIR_BLOCK := 1.5       # an air block costs this much more chip and guard
const METER_PACE := 0.6       # share of the meter a hit, a hit taken, a block or a counter gave before the pacing pass
const JG_METER := 5.0        # meter a just guard gives
const LEVEL_DEG := 10.0      # a shot angled more than this below horizontal counts as fired down       # the generic super: every hit of the powered skill
const START_X := 230.0       # fighters start ±START_X from centre
const INTRO_SHOT := 96       # stage entry: ticks of one solo shot, P1's then P2's
const INTRO_PAN := 36        # the camera pan from P1's shot to P2's
const INTRO_WIDE_AT := 2 * INTRO_SHOT + INTRO_PAN + 1   # first tick of the wide block: the ROUND band and the HUD rails start here
const INTRO_FULL := 360      # the entry: shot, pan, shot, then the wide block; control on tick 360
const INTRO_ROUND := 120     # the wide block alone: rounds 2 and 3
const INTRO_READY := 60      # ticks of the ready beat; the whole intro of a restart and of training
const INTRO_FIGHT_LEAD := 24 # FIGHT! shows this many ticks before control in the entry and in rounds 2 and 3
const INTRO_BEAT_END := 28   # the ready beat (60 ticks of the reload) ends this many ticks before control in those two, so it finishes just before FIGHT!
const INTRO_X := 865.0       # the old run-in's start; the arenas' flat lane test still reads it
