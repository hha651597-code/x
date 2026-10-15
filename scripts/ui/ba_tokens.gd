class_name BaTokens
extends RefCounted
## Blue Archive UI tokens in 1280x720 reference pixels (the game's own canvas is 2960x1440, so every real unit x 0.5).
## Measured from the game's prefabs. New UI reads every colour, radius and
## timing from here. Scripts hand a colour to a shader as a uniform where it needs one; a .gdshader's own uniform defaults
## are not tied to this file.

# Shape
const SHEAR := 0.1763            # tan(10 deg): every plate, bar, button and card leans this much (px per px of height)
const R_CARD := 11.0             # popups and cards
const SHADOW_A := 0.30
const SHADOW_FALL := 7.0         # px below the plate
const SHADOW_SIDE := 3.0         # px at the sides; none above

# Time (seconds)
const BRACKET_HALF := 0.7        # one half cycle of the selection pulse
const BRACKET_LO := 0.7          # alpha at the pulse trough
const WHIP_FAST := 7.0 / 60.0    # the fast leg of an entrance
const WHIP_SETTLE := 25.0 / 60.0
const WHIP_SHARE := 0.88         # share of the travel covered by the fast leg
const STAGGER := 2.0 / 60.0      # between neighbouring items of one entrance

# Ink and outlines
const INK := Color("2C4564")
const LABEL_INK := Color("153757")
const GAUGE_EMPTY := Color("182442")
const HEAD_OUTLINE := Color("314665")
const NUM_OUTLINE := Color("144E8C")
const WHITE := Color("FFFFFF")

# Sides: P1 red, P2 blue (BA's flat values)
const P1 := Color("D63636")
const P2 := Color("00A0FF")
const P1_LIGHT := Color("EE8E8E") # derived, not measured: lighter side tints for slabs
const P2_LIGHT := Color("7FD0FF")
const THUMB_A := Color("FFF3E3")

# Signals
const COST := Color("00AEFF")
const FLASH := Color("00FFFA")
const BRACKET := Color("FFEA00")
const CONFIRM := Color("FEE600")
const ALERT := Color("FF4A31")

# Surfaces
const FACET_A := Color("E1F3FA")
const FACET_C := Color("CDEAF4")
const SKY_TOP := Color("2E98FE")
const SKY_BOT := Color("A7E5FE")

# Plates and fields
const NAVY := Color("0B2547")             # gauge tracks, the scrim's dark end, navy ribbons
const PLATE_NAVY := Color("062D51")       # the arena timer plate
const PLATE_LOW := Color("A95670")        # the timer plate in its last seconds, sampled from BA's render
const GUARD_FULL := Color("EAF6FF")       # guard gauge fill while it is healthy
const CARD_TINT := [Color("FFC4CB"), Color("B9E2FF")]   # portrait and assist card tint per side: P1 pink, P2 ice blue
const CARD_DISABLED := Color("D3D7DD")    # the assist card while it cools down
const CONFIRM_PLATE := Color("F6E94B")    # the yellow plate: selected pause row, gallery tab and button
const CONFIRM_INK := Color("4B2116")      # label on it
const CYAN_PLATE := Color("77DEFF")       # the blue plate: SUPER tier, result buttons, pause value caps
const GREY_OFF := Color("D6D6D6")         # a switched-off option: its plate
const GREY_OFF_EDGE := Color("8A8A8A")    # and its label outline
const LABEL_EDGE := Color("39436F")       # outline of the white italic HUD labels
const LOSER_FIELD := Color("FFE1DA")      # the result screen's loser half
const KO_SATURATION := 0.25               # the HUD card's ko face: colour left in it
const KO_DIM := Color(0.8, 0.8, 0.8)      # and its darkening
const BAND_BLUE := Color("0062D6")        # the ROUND and TRAINING band
const BAND_DRAW := Color("4D6F93")        # the same band on a draw
const PEACH := Color("FFBE8A")            # the WARNING word's tint
const SLAM_ACCENT := Color("2f8fff")      # the slam wipe's stripe unless a call passes its own
const SELECT_INK := Color("1a2130")       # SelectFrames text ink
const TRAIN_BTN := {                      # input-history disc colour per move type
	"light": Color("5fd0ff"), "heavy": Color("ff9a3c"), "skill": Color("6be07e"),
	"ex": Color("ffd23c"), "assist": Color("c58bff"), "dash": Color("b8c4d6"),
}

# Attack types
const ATK_EXPLOSIVE := Color("F24C4C")
const ATK_MYSTIC := Color("51A2F3")
const ATK_PIERCING := Color("F3B745")
const ATK_SONIC := Color("BA61D7")
const ATK_OTHER := Color("8A97A8")   # a roster attack type with no entry above

static func side(slot: int) -> Color:
	return P1 if slot == 1 else P2

## Pixels of horizontal lean over a height `h`.
static func shear_px(h: float) -> float:
	return SHEAR * h

static func alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * a)
