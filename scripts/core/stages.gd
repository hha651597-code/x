class_name Stages
extends RefCounted
## Stage + BGM data for the stage select. `plate` is relative to assets/ba/ (400x300 official plates).
## `map` (a folder in assets/ba/stages) and `times` mark a 3D arena; entries without them keep the 2D plate.
## The select shows the stages in one row, then the "random" slot.

const LIST := [
	{"id": "gehenna-night", "school": "Gehenna Academy", "name": "Gehenna Slum Streets", "plate": "bg/BG_Gehenna_Collection.jpg", "map": "gehennaslum", "times": ["day", "night"]},
]
const RANDOM := {"id": "random", "school": "Kivotos", "name": "Random", "plate": ""}

## The BGM bar cycles through these ("auto" lets the stage pick); every id is a track in Bgm.TRACKS (real Blue Archive OST,
## assets/audio/bgm/TRACKS.md).
const BGM := [
	{"id": "auto", "name": "AUTO"},
	{"id": "pachad", "name": "Pachad"},
	{"id": "dark-shadows", "name": "Dark Shadows"},
	{"id": "out-of-control", "name": "Out of Control"},
	{"id": "step-of-terror", "name": "Step of Terror"},
	{"id": "constant-moderato", "name": "Constant Moderato"},
	{"id": "unwelcome-school", "name": "Unwelcome School"},
	{"id": "mechanical-jungle", "name": "Mechanical JUNGLE"},
	{"id": "virtual-storm", "name": "Virtual Storm"},
	{"id": "alert", "name": "Alert"},
	{"id": "crossfire", "name": "CrossFire"},
	{"id": "aoharu", "name": "Aoharu"},
	{"id": "signal-of-abydos", "name": "Signal of Abydos"},
	{"id": "final-destination-of-ark", "name": "Final Destination of Ark"},
	{"id": "fury-of-set", "name": "Fury of Set"},
]
