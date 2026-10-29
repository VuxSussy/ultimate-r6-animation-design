---
name: ultimate-r6-animation-design
description: Create, repair, convert and preview Roblox R6 animations, weapon combos and movement packs. Uses measured references, keyed angles and short limb slides without IK; validates timing, body commitment, joints, legs and export. Applies to six-part rigs, KeyframeSequences and AnimSaves, including R15-to-R6 conversion.
---

# Ultimate R6 Animation Design

Build expressive R6 motion from references, then prove the exported result. R6 has no elbows,
knees or spine: key named joint angles plus short `pos` slides. Do not introduce IK aims,
planted-leg solvers or a procedural FK/IK system.

## Route once

Read this entrypoint once per task; retain a short working brief. Open only relevant sections
of references. Re-read when the source changes, context is lost or a failure needs detail.

| Need | Read when needed |
| --- | --- |
| Find/measure a source; fallback grammar | [reference-first.md](references/reference-first.md), §§1–5; measured tables §6 |
| First-time posing, unfamiliar angle/space or slide issue | [posing.md](references/posing.md), §§1–4 |
| Timing, weight or an animation that feels weak | [weight-and-feel.md](references/weight-and-feel.md), relevant section |
| Heavy sword / greatsword | [heavy-weapons.md](references/heavy-weapons.md) before keying; mass/overswing/recovery and phase-dependent grip |
| Weapon attack | [combat.md](references/combat.md), §§1, 8–9 |
| Mage casting | [staff-casting.md](references/staff-casting.md) before keying; actual casting footage required |
| Runtime combat/locomotion, service wiring | [runtime-workflows.md](references/runtime-workflows.md); [combat.md](references/combat.md) §§3–7 |
| R15 conversion | [r15-to-r6.md](references/r15-to-r6.md) |
| Thigh hidden inside torso, crouch/tuck artifacts | [body-clearance.md](references/body-clearance.md) |
| First clip example | [authoring-example.md](references/authoring-example.md) |
| A known failure or nonstandard weapon joint | [troubleshooting.md](references/troubleshooting.md) |
| Provenance | [sources.md](references/sources.md) |
| Reusable pack commands/schema | [pack-tools.md](references/pack-tools.md) |

## Reference before poses

Search in order: user files/AnimSaves, Creator Store R6 clips, converted R15, R6 video.
Use the first suitable accessible source; strip every script from third-party models before
parenting. A listing is discovery, not a measured or viewed reference. When none is accessible,
use the user's R6 movement grammar and explicitly document the fallback and adaptations.
For spellcasting and heavy weapons, also watch footage of that exact action/archetype before posing.
Save URLs, timestamps and observed load/strike/follow-through/recovery; a listing or unrelated slash cannot satisfy this step. See the corresponding route.

Measure sources with `tools/measure.luau` (compact output, complete report saved), or `study`
for key extraction/fitting. Keep a brief: source and content fingerprint, selected clips, rig/grip,
intent, load/hit/release/hold frames, torso twist/lean/drop/lunge, limb slides and tip reach.
Reuse a saved measurement only while the source fingerprint, selection, tool versions and grip
match. A source for a slash does not establish two-hand grip or heavy-sword timing: state those
adaptations and verify them independently. Compare generated measurements to the source;
explain deviations from its strike proportions, ~20% torso range or ~0.5-stud tip placement.

## Authoring invariants

- Space: +X right, +Y up, −Z forward; standing floor y=−3 relative to HumanoidRootPart.
- Named angles: torso lean/twist/tilt, head nod/turn/tilt; limbs raise/spread/swing/twist.
  `pos={forward,up,right}` slides in the parent. Head should stay on the neck.
- Arms ≤1.0 stud, legs ≤1.5, head ≤0.15 by default. Increase budgets only for an explicit user
  preference or a measured source, explaining the exception. Never relax a check merely to pass.
- Legs use `space="root"` on the pelvis (default hips=0.35); grounded support uses `ground=true`.
  Keep legs apart and uncrossed. Do not telescope a visible thigh into the torso to fake a knee bend;
  use a shallower stance when necessary. Use `meta.stride` only for actual passing footwork.
- Key guard → preparation/load → release → contact → readable hold → follow-through/recovery.
  Adapt the preparation to the technique: a thrust need not have a sword-swing wind-up.
- Easing shapes the segment **leaving** a key. Named angles interpolate as numbers. For swords,
  accelerate with `quadIn` into contact; a long blade amplifies speed. Head/free arm may trail;
  two hands holding one weapon must remain on the grip during declared gripping phases. A heavy style may intentionally release/regrip; require explicit windows and markers.
- No pops outside declared strike/Snap windows. Hit should agree with the visible tip within
  2 frames, hold 4–6+ readable frames and normally occur 20–50% through the move.
  Straight punches need body commitment (reference reach 2.3–4.2 studs, torso turn 30–110°);
  weapon/casting moves use their own measured geometry and contact/aim tests.
- Raw rotations and runtime fades take the shortest path; avoid >180° transitions. Match combo
  endpoints. Never key HumanoidRootPart for travel; gameplay owns root movement.
- For fixed grip, `meta.tip` must describe the actual blade point in arm space. A separately
  animated weapon needs its own exported channel and geometry checks; six-body-joint audit
  alone cannot validate that weapon. Keep all intentional overhead exceptions explicit.

## Build, verify, look

Prefer the reusable `tools/pack.luau` for fixed-grip packs. Supply a move provider/configuration;
do not rewrite a builder, renderer or playtest harness for every combo. Use an adapter when a
rig genuinely needs extra joints, preserving the same quality gates.

Required: every new clip passes **`R6Quality.audit`** (original motion audit plus oriented
thigh/torso clearance on every frame, with actual body sizes for custom rigs); study agrees with the reference or documented
adaptations; marker times/order, combo seams, actual weapon tip, slide budgets and export round
trip pass. For two-hand weapons measure off-hand/grip distance throughout gripping phases and verify declared release/regrip transitions. Heavy weapons also need visible load, full overswing and recovery; use the heavy-specific route, not merely slower katana timing. Inspect front,
side and full-speed movement. A numeric PASS with bad visuals is unfinished.

Run `lune run check`, `lune run check_quality` and Selene on the skill modules once for the unchanged tool version in a
task. Lint new modules/harnesses too. After edits, re-run affected checks; broaden to the full
suite when shared math/export changes or failures justify it. Do not skip mandatory gates.

When Studio is accessible, play/pose a real R6 rig and read tip/soles at markers. Lock player
controls for measurements. Use `pack_demo` for an existing pack instead of recreating a harness.
If access fails, inspect the blocker and make one relevant recovery attempt; avoid repeated
unchanged timeouts or closing unrelated user work. Save the demo and state that engine testing
is unconfirmed. Only real engine results justify “playtest passed”. Registration IDs are Studio
local; a published game needs uploaded AnimationIds.

## Context and delivery

Default tool output is status, relevant numbers, errors and artifact paths. Full measurements,
code, frames and logs stay on disk; open only the section needed to resolve a decision/failure.
Use `--verbose` deliberately. Keep source search, pose work, export and tests scoped to the request.

For an animation pack, deliver the clips/combo, usable rig/grip instructions, preview and concise
validation/provenance. Reuse a demo when needed to verify or when requested. Do not add a combat
controller, networking, damage system or additional effects unless needed or requested.
Report source/fallback, hit/hold/hit-stop, reach/body commitment, largest slides, audit and what
was actually seen/tested. Save detailed numbers in the pack; keep the user-facing reply concise.
