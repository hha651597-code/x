#!/bin/zsh
# usage: tools/test_all.sh [pattern]   Runs every tracked *_test.gd once through sd_test.sh (one small real window each),
# then the three stage runners. Prints a PASS or FAIL line per test and a total; exits non-zero if any failed.
# A pattern (grep -E on the path) limits the run. Window tests can flake under load: rerun a failure alone before trusting it.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
CAP=(); command -v gtimeout >/dev/null && CAP=(gtimeout 420)
tests=("${(@f)$(git ls-files | grep -E '_test\.gd$' | grep -v -E '^scripts/sprites/sprite_test\.gd$|^scripts/stages3d/tests/(stage_test|stage_path_test)\.gd$' | grep -E "${1:-.}")}")
pass=0; fail=0
run() {
	local name="$1"; shift
	local out; out="$("$@" 2>&1)"
	if [ $? = 0 ]; then
		pass=$((pass + 1)); echo "PASS $name"
	else
		fail=$((fail + 1)); echo "FAIL $name"; print -r -- "$out" | tail -n 6 | sed 's/^/     /'
	fi
}
for t in $tests; do
	[ -n "$t" ] && TEST="res://$t" MAXLINES=400 run "$t" $CAP zsh tools/sd_test.sh
done
for r in stage_test stage_path stage_void; do
	[ -z "$1" ] && MAXLINES=60 run "tools/$r.sh" $CAP zsh tools/$r.sh
done
echo "total: $pass pass, $fail fail"
[ $fail = 0 ]
