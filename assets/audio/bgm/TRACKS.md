# Background music tracks

The game's music is the **real Blue Archive Original Soundtrack**.
Every file was downloaded from the Blue Archive wiki's soundtrack page, https://bluearchive.wiki/wiki/Soundtrack (audio hosted on `static.wikitide.net`),
then converted: silence trimmed, a 1.5 s equal-power loop crossfade (tail into intro), two-pass `loudnorm` to -18 LUFS (TP -1.5),
44.1 kHz stereo Ogg Vorbis (libvorbis VBR quality 0.4, about 128 kbps). The last 1.5 s of every file is already the crossfade back into the intro, so `Bgm`
plays each one as `AudioStreamOggVorbis` with `loop = true` and `loop_offset = 1.5` (gapless). The wiki-hosted source files are 72 kbps stereo Vorbis.

| id / file | Title | OST no. | Composer | Role in game | Length | Source file |
|---|---|---|---|---|---|---|
| `constant-moderato.ogg` | Constant Moderato | 1 | Mitsukiyo | Main theme (lobby) | 2:16 (136.8 s) | https://static.wikitide.net/bluearchivewiki/7/71/Track_1_Mitsukiyo_Constant_Moderato.ogg |
| `unwelcome-school.ogg` | Unwelcome School | 7 | Mitsukiyo | Main theme (lobby) | 1:59 (119.8 s) | https://static.wikitide.net/bluearchivewiki/4/40/Track_7_Mitsukiyo_Unwelcome_School.ogg |
| `pachad.ogg` | PACHAD | 182 | Nor | Fight theme | 1:50 (110.3 s) | https://static.wikitide.net/bluearchivewiki/b/b9/Track_182_Nor_PACHAD.ogg |
| `dark-shadows.ogg` | Dark Shadows | 181 | KARUT | Fight theme | 1:53 (113.5 s) | https://static.wikitide.net/bluearchivewiki/6/60/Track_181_KARUT_Dark_Shadows.ogg |
| `out-of-control.ogg` | Out of Control | 48 | KARUT | Fight theme | 2:09 (129.4 s) | https://static.wikitide.net/bluearchivewiki/f/f5/Track_48_KARUT_Out_of_Control.ogg |
| `step-of-terror.ogg` | Step of Terror | 157 | KARUT | Fight theme | 1:04 (64.5 s) | https://static.wikitide.net/bluearchivewiki/9/9e/Track_157_KARUT_Step_of_Terror.ogg |
| `mechanical-jungle.ogg` | Mechanical JUNGLE | 18 | KARUT | Fight theme | 2:01 (121.4 s) | https://static.wikitide.net/bluearchivewiki/d/de/Track_18_KARUT_Mechanical_JUNGLE.ogg |
| `virtual-storm.ogg` | Virtual Storm | 19 | KARUT | Fight theme | 2:03 (123.6 s) | https://static.wikitide.net/bluearchivewiki/c/ca/Track_19_KARUT_Virtual_Storm.ogg |
| `alert.ogg` | Alert | 29 | KARUT | Fight theme | 1:56 (116.7 s) | https://static.wikitide.net/bluearchivewiki/6/69/Track_29_KARUT_Alert.ogg |
| `crossfire.ogg` | CrossFire | 30 | KARUT | Fight theme | 1:49 (109.8 s) | https://static.wikitide.net/bluearchivewiki/d/d4/Track_30_KARUT_CrossFire.ogg |
| `aoharu.ogg` | Aoharu | 34 | Nor | Upbeat theme | 1:47 (107.0 s) | https://static.wikitide.net/bluearchivewiki/2/21/Track_34_Nor_Aoharu.ogg |
| `signal-of-abydos.ogg` | Signal of Abydos | 45 | Nor | Upbeat theme | 1:53 (113.5 s) | https://static.wikitide.net/bluearchivewiki/1/1f/Track_45_Nor_Signal_of_Abydos.ogg |
| `final-destination-of-ark.ogg` | Final Destination of Ark | 156 | KARUT | Fight theme | 2:02 (122.2 s) | https://static.wikitide.net/bluearchivewiki/6/65/Track_156_KARUT_Final_Destination_of_Ark.ogg |
| `fury-of-set.ogg` | Fury of Set | 212 | KARUT | Fight theme | 2:05 (125.8 s) | https://static.wikitide.net/bluearchivewiki/b/b6/Track_212_KARUT_Fury_of_Set.ogg |

Notes:

- Lengths are of the converted files (the original wiki clips are 1:10-2:18; silence at the ends was trimmed and the 1.5 s loop crossfade is part of the length).
- `pachad`, `dark-shadows`, `out-of-control` and `step-of-terror` (the wiki lists PACHAD in capitals).
- `constant-moderato` is the lobby / main theme (OST track 1), `unwelcome-school` the second main-theme track (OST track 7). 'auto' plays `constant-moderato` on menus, select screens and results; `unwelcome-school` is selectable on the stage select and in the Extras jukebox.
- 'auto' during a fight picks a battle track by stage (`Bgm.STAGE_TRACKS`, with a hash fallback), see `scripts/core/bgm.gd`.
