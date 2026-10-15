#!/bin/zsh
# usage: tools/hud_facade_shots.sh [state ...]   Runs the hud_facade_*.json capture step files in real 1280x720 windows (the wide one at 1600x900)
# and leaves the pictures in /tmp/ba-hud-out/facade. With no argument it runs every state.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
SHOTS=scripts/fight/tools/shots
STATES=("$@")
[ ${#STATES[@]} -eq 0 ] && STATES=(start stages combo_p1 combo_p2 block just_guard guard_crush lowhp_ex ko_win assist training training_overlay pause_versus pause_training last10 ult_freeze result wide)
for s in $STATES; do
	f=$SHOTS/hud_facade_$s.json
	[ -f $f ] || continue
	echo "== $s"
	case $s in
		last10) HUD_DEMO=time10 zsh tools/run.sh $f ;;
		wide) zsh tools/run.sh $f --resolution 1600x900 ;;
		*) zsh tools/run.sh $f ;;
	esac
done
