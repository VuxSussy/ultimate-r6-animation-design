# Ultimate R6 Animation Design

A Claude skill for designing, fixing, converting and running Roblox R6 animations. The goal is
animation with force and commitment: not stiff like plastic, and not cramped or timid.

## What changed in this version (2026-10-28)

1. **Reference first.** For any animation, first look for an R6 version of the same move: your
   files, the Creator Store (through Studio MCP), converted R15 clips, video. Measure it with
   `lune run study` and imitate the numbers. With no R6 version, follow the movement of Arczi's
   *Ultimate R6 Movement System*.
2. **No IK, no FK.** No more `aim` keys, `planted` leg solving or `headCounter`, and no `R6Layers`
   module with its FK+IK / FK / IK / None modes. A clip plays exactly as keyed.
3. **Parts may leave the torso a short way.** Every part takes `pos` to slide out of its socket.
   Budgets measured from Arczi's file and R6 punch packs: arms up to 1.0 stud, legs 1.5 (mostly
   riding up into the torso instead of bending a knee), head 0.15 (rotation only).
4. **Legs never cross.** Legs hang from a "pelvis" that takes only 35% of the torso's turn
   (`space = "root"`), and `ground = true` slides them so the soles stay on the floor. The audit
   flags legs passing through each other or forming an X from the side or the front.
5. **A "timid" audit.** A straight punch must turn the torso 40 degrees or more and put the fist at
   least 2.8 studs in front of the root. References: torso 30-110 degrees, fist 2.3-4.2 studs out.
6. **New Idle, Walk, Run** (`Locomotion.luau`), imitating Arczi's `idle v2`, `walk v3`, `run v4`
   (walk within 4.8 degrees, run 3.9), with the `R6Locomotion` driver: walking at 12 studs/s plays
   the walk at speed / 14.5, holding Shift to run at 27 plays the run at 1.3, walking backwards
   plays the walk in reverse, and after a fight action the guard shows for 3 s before idle.
7. **Dashes, per your notes:** the arms swing back while dashing; side dashes no longer hold a
   guard; the back dash ends in a grounded kneel (one leg forward, one stretched behind, the lead
   hand on the ground, the rear arm flung back).
8. **The 13 combat moves were rebuilt** from the reference measurements. Compared with the old
   kit: jab reach 3.39 studs (was 2.93), cross 3.28 (was 2.60), torso turn 50/58 degrees (was
   40/24), shoulder slide 0.7 stud (was 0).
9. **Fixed arms spinning the long way.** R6Clip used to blend rotations the shortest way, so an
   arm flung back (raise -55) coming home to the guard (150) went backwards over the head (193
   degrees apart). R6Clip now interpolates the named angles. The audit gained an `overhead` check
   (a fist above the shoulders and behind the back) and an `export` check (the exported file plays
   the same as the clip when Roblox does its own blending).
10. **Climb, jump, fall, three landings and a wall run.** Climb, jump, fall and the landings imitate
    Arczi's clips; the landing is picked by fall height (under 4 studs light, 4-15 short, over 15
    long). The wall run imitates the Creator Store "R6 Parkour Animations" pack and comes with an
    `R6WallRun` module so it really runs: jump next to a wall while moving fast to run along it for
    about 1.4 s; jump again to kick off.
11. **Weapons.** The audit and `study` can measure from a weapon's tip (`meta.tip`, `--tip`), tested
    by building a sword slash (`sword/`).
12. **The skill records its own mistakes** ("Mistakes this skill has made" in SKILL.md): each with
    its fix and the automatic check that now stops it.

## In this folder

| Path | What it is |
|---|---|
| `ultimate-r6-animation-design/` | the skill: `SKILL.md`, `references/`, `scripts/`, `tools/`, `evals/` |
| `output/ultimate-r6-animation-design.skill` | the packaged skill to install (press **Save skill** when Claude sends the file) |
| `output/R6CombatPack.rbxm` | 24 ready R6 animations (13 combat + 11 movement); drag them into a rig's `AnimSaves` |
| `output/eclipse/*.json` | the same 24 animations as JSON for Eclipse-Animator-MCP's `save_animation` tool |
| `output/preview.html` | 3D preview: play/pause, 0.25x, frame by frame, limb trails, hit-stop |
| `sword/` | the skill's test: a `SwordSlash` (+ `SwordGuard`) made by following the skill's workflow; `lune run build` writes `sword/out/` (rbxm, Eclipse JSON, preview) |
| `studio/R6TestPlace.rbxl` | test place (Fists / Sword toggle at the bottom left, or key 1): modules, an R6 StarterCharacter, the harness, a wall to run on, a truss to climb, 10- and 30-stud ledges |

References in `ultimate-r6-animation-design/references/`:
- `reference-first.md`: where to find references, loading them safely, measuring with `study`,
  how to imitate, and measured tables for Arczi's clips and the R6 punch packs.
- `posing.md`: the R6 rig, named angles, `pos`, slide budgets, legs on a pelvis, why there is no IK.
- `weight-and-feel.md`, `combat.md`, `r15-to-r6.md`, `sources.md`.

## Common commands (run in `ultimate-r6-animation-design/tools/`)

Measure every R6 animation in a file to imitate it (timing, strike frames, torso turn / drop /
lunge, how far parts leave their sockets):

```bash
lune run study "~/Downloads/Ultimate R6 Movement System.rbxm"
```

Print a reference clip's poses at chosen frames, as R6Clip key tables ready to paste:

```bash
lune run study "~/Downloads/Ultimate R6 Movement System.rbxm" "walk v3" --keys=0,6,12,18,24
```

Run the 192 tests:

```bash
lune run check
```

Rebuild the animation pack, the Eclipse JSON and the preview page:

```bash
lune run build ../../output
```

Convert R15 clips in an `.rbxm` or `.rbxl` file to R6:

```bash
lune run convert <file.rbxl> ../../output/converted <clip name>
```

Lint the Luau code with selene:

```bash
selene --config selene.toml ../scripts
```

## Tested and not tested

- 192 tests pass, selene is clean, and all 24 clips pass the audit.
- **Real playtests** (the Claude_R6_Preview place, an R6 character), with numbers read from the
  engine's own parts:
  - The 4-hit combo plays in order, even when pressed 0.12 s apart.
  - Jab reach 3.33 studs with the torso at -52 degrees; cross 3.20 studs at 54 degrees.
  - Soles stay on the floor (0.04 stud at most off), hips at least 0.97 stud apart, no crossed legs.
  - Hit-stop takes the clip to speed 0 and back to 1. Attacks are refused while blocking.
  - Dashes travel as designed: forward 16.5 studs, back 12.5, left/right 13.4.
  - Idle / Walk / Run / Stance switch by speed: walk at 0.83, run at 1.3, backwards at -0.83.
  - Jump, fall, climb, wall run: a jump in place lands light (fell 0.3 stud), a 10-stud ledge
    lands short (7.7), a 30-stud ledge lands long (27). Climb plays at 0.70 (8.4 studs/s / 12) and
    pauses when the climber stops. The wall run holds 1.4 s along 37 studs of wall. Kicking off
    the wall with the jump key was not tested (the test calls cannot press keys).
  - Sword mode: M1 plays SwordSlash with the blade showing; at the Hit marker the blade tip is 5.7
    studs out on the centre line. The toggle was switched by command, not by clicking the button.
- The new dash and movement poses were posed on rigs and viewed in Studio frame by frame, not
  watched at full speed.
- `studio/R6TestPlace.rbxl` could not be opened in Studio by command (Studio hung while opening
  the file), so the test content was loaded into the Claude_R6_Preview place instead; its old
  contents are in `ServerStorage.OldR6Test_backup`.
- R15 conversion of `SingleCross`: the R15 source itself turns its pelvis about 90 degrees for
  frames 8-13, so the R6 legs pass 0.6 stud apart and the audit flags it. Those frames need
  re-keying by hand.
