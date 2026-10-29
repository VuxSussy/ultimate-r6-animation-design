# Read a humanoid motion-capture file (FBX, BVH, GLB/GLTF) with Blender and write its body points
# per frame as JSON, for `lune run mocap` to turn into an R6 clip. Runs headless:
#
#   /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --disable-autoexec \
#       --python mocap_points.py -- <in.fbx|.bvh|.glb|.blend> <out.json> [--fps=60] [--start=s] [--end=s] [--action=name]
#   ... -- <in> --list      prints the file's actions (name, frames, seconds) and exits
# A .blend is opened as is (never with its scripts: keep --disable-autoexec); pick the take with
# --action when the file holds several.
#
# Points are in Roblox character space (studs, +X right, +Y up, -Z forward), scaled so the standing
# hip-to-floor height is 2 studs (an R6 leg) and turned so frame 0 faces -Z. Bones are found by
# name (Mixamo, Rokoko, CMU BVH, Unreal/Unity humanoids, VRM); pass --map=Role:BoneName to override,
# e.g. --map=LeftHand:hand.L. Roles: Hips Chest Neck Head LeftUpperArm LeftForeArm LeftHand
# LeftUpLeg LeftLeg LeftFoot LeftToe (and Right...).

import bpy, json, math, re, sys
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if len(argv) < 2 and "--list" not in argv:
    raise SystemExit("usage: Blender -b --python mocap_points.py -- <in> <out.json> [--fps=60] [--start=s] [--end=s]")
src = argv[0]
out = argv[1] if len(argv) > 1 and not argv[1].startswith("--") else None
opts = {}
overrides = {}
for a in argv[2:]:
    m = re.match(r"--(\w+)=(.*)", a)
    if m:
        if m.group(1) == "map":
            role, bone = m.group(2).split(":", 1)
            overrides[role] = bone
        else:
            opts[m.group(1)] = m.group(2)
fps = float(opts.get("fps", 60))

low = src.lower()
if low.endswith(".blend"):
    bpy.ops.wm.open_mainfile(filepath=src, load_ui=False)
else:
    bpy.ops.wm.read_factory_settings(use_empty=True)
if low.endswith(".blend"):
    pass
elif low.endswith(".fbx"):
    bpy.ops.import_scene.fbx(filepath=src, automatic_bone_orientation=True)
elif low.endswith(".bvh"):
    bpy.ops.import_anim.bvh(filepath=src, update_scene_fps=True, update_scene_duration=True)
elif low.endswith(".glb") or low.endswith(".gltf"):
    bpy.ops.import_scene.gltf(filepath=src)
else:
    raise SystemExit("unsupported file: " + src)

scene_fps = bpy.context.scene.render.fps / bpy.context.scene.render.fps_base
if "--list" in argv:
    for act in bpy.data.actions:
        a, b = act.frame_range
        print("[mocap_points] action %-40s frames %4d-%-4d %.2f s" % (act.name, a, b, (b - a) / scene_fps))
    raise SystemExit(0)
arms = [o for o in bpy.context.scene.objects if o.type == "ARMATURE"]
if not arms:
    raise SystemExit("no armature in " + src)
# the rig with the most bones is the body (files often hold props or helper rigs too)
arm = max(arms, key=lambda o: len(o.data.bones))
if arm.animation_data is None:
    arm.animation_data_create()
if "action" in opts:
    act = bpy.data.actions[opts["action"]]
    arm.animation_data.action = act
    # Blender 4.4+ slotted actions: bind the action's first slot to this rig
    if hasattr(arm.animation_data, "action_slot") and getattr(act, "slots", None) and len(act.slots) > 0:
        arm.animation_data.action_slot = act.slots[0]
action = arm.animation_data.action if arm.animation_data else None
if action is None:
    raise SystemExit("the armature has no animation")
scene = bpy.context.scene
f0, f1 = action.frame_range
src_fps = scene.render.fps / scene.render.fps_base

# role -> patterns tried in order on a normalised bone name (prefixes like "mixamorig:" stripped,
# lower case, no spaces/underscores/dots/dashes). Side markers: left/l/_l/.l handled by `side`.
ROLES = {
    "Hips": ["hips", "pelvis", "root", "hip"],
    "Chest": ["upperchest", "chest", "spine3", "spine2", "spine02", "spine1", "spine01", "spine"],
    "Neck": ["neck1", "neck01", "neck"],
    "Head": ["head"],
    "UpperArm": ["upperarm", "arm"],
    "ForeArm": ["forearm", "lowerarm", "elbow"],
    "Hand": ["hand", "wrist"],
    "UpLeg": ["upleg", "upperleg", "thigh"],
    "Leg": ["leg", "lowerleg", "calf", "shin", "knee"],
    "Foot": ["foot", "ankle"],
    "Toe": ["toebase", "toe", "ball"],
}


def norm(name):
    name = name.split(":")[-1].split("|")[-1]
    return re.sub(r"[\s_.\-]", "", name.lower())


def side_of(raw):
    n = raw.split(":")[-1].lower()
    if re.search(r"(^|[^a-z])l([^a-z]|$)|left", n) or re.search(r"[._\-]l$", n):
        return "Left"
    if re.search(r"(^|[^a-z])r([^a-z]|$)|right", n) or re.search(r"[._\-]r$", n):
        return "Right"
    return None


def strip_side(raw):
    # drop the side marker from the raw name, then normalise: "LeftLeg" -> "leg", "upperarm_l" ->
    # "upperarm", "L_Hand" -> "hand"; a bare leading/trailing l/r only counts next to a separator
    n = raw.split(":")[-1].split("|")[-1]
    n = re.sub(r"(?i)left|right", "", n)
    n = re.sub(r"(?i)^[lr][\s_.\-]", "", n)
    n = re.sub(r"(?i)[\s_.\-][lr]$", "", n)
    return norm(n)


bones = arm.pose.bones
found = {}
for role, patterns in ROLES.items():
    sided = role in ("UpperArm", "ForeArm", "Hand", "UpLeg", "Leg", "Foot", "Toe")
    for side in (["Left", "Right"] if sided else [None]):
        key = (side or "") + role
        if key in overrides:
            found[key] = overrides[key]
            continue
        for pat in patterns:
            hit = None
            for b in bones:
                if sided and side_of(b.name) != side:
                    continue
                if not sided and side_of(b.name) is not None:
                    continue
                n = strip_side(b.name) if sided else norm(b.name)
                # exact role names first ("arm" must not match "forearm")
                n = re.sub(r"\d+$", "", n) if pat in ("arm", "leg", "spine", "neck") else n
                if n == pat or n.endswith(pat) and pat not in ("arm", "leg"):
                    hit = b.name
                    break
            if hit:
                found[key] = hit
                break

need = ["Hips", "Head", "LeftUpperArm", "LeftForeArm", "LeftHand", "RightUpperArm", "RightForeArm",
        "RightHand", "LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg", "RightLeg", "RightFoot"]
missing = [r for r in need if r not in found]
if missing:
    raise SystemExit("could not find bones for %s; bones are: %s; pass --map=Role:BoneName" % (
        missing, ", ".join(b.name for b in bones)))

M = arm.matrix_world


def head(role):
    return M @ bones[found[role]].head


def tail(role):
    return M @ bones[found[role]].tail


# Blender world (Z up) -> Roblox axes (Y up), a proper rotation: (x, y, z) -> (-x, z, y)
def rb(v):
    return Vector((-v.x, v.z, v.y))


def sample():
    p = {}
    p["Pelvis"] = head("Hips")
    p["Neck"] = head("Neck") if "Neck" in found else head("Head")
    p["HeadTop"] = tail("Head")
    for s in ("Left", "Right"):
        p[s + "Shoulder"] = head(s + "UpperArm")
        p[s + "Elbow"] = head(s + "ForeArm")
        p[s + "Wrist"] = head(s + "Hand")
        hand_dir = tail(s + "Hand") - head(s + "Hand")
        # the fist sits a hand's length past the wrist, along the hand bone
        p[s + "Fist"] = head(s + "Hand") + hand_dir.normalized() * max(hand_dir.length, 0.08)
        p[s + "Hip"] = head(s + "UpLeg")
        p[s + "Knee"] = head(s + "Leg")
        p[s + "Ankle"] = head(s + "Foot")
        p[s + "Toe"] = head(s + "Toe") if (s + "Toe") in found else tail(s + "Foot")
    return {k: rb(v) for k, v in p.items()}


start = float(opts.get("start", 0))
end = float(opts.get("end", (f1 - f0) / src_fps))
frames = []
t = start
while t <= end + 1e-6:
    scene.frame_set(int(math.floor(f0 + t * src_fps)), subframe=(f0 + t * src_fps) % 1)
    frames.append((t - start, sample()))
    t += 1.0 / fps

# normalise: floor, scale, facing, all from the first frame
first = frames[0][1]
floor = min(min(first["LeftToe"].y, first["LeftAnkle"].y), min(first["RightToe"].y, first["RightAnkle"].y))
hip_y = (first["LeftHip"].y + first["RightHip"].y) / 2
scale = 2.0 / max(hip_y - floor, 1e-3)
right = first["RightHip"] - first["LeftHip"]
yaw = math.atan2(right.z, right.x)  # turn so the hip line runs along +X
c, s_ = math.cos(yaw), math.sin(yaw)
origin = Vector((first["Pelvis"].x, floor, first["Pelvis"].z))


def fix(v):
    d = v - origin
    x, z = d.x * c + d.z * s_, -d.x * s_ + d.z * c
    # root space: the HumanoidRootPart stands 3 studs above the floor
    return [round(x * scale, 4), round(d.y * scale - 3, 4), round(z * scale, 4)]


doc = {
    "source": src,
    "fps": fps,
    "scale": scale,
    "bones": found,
    "frames": [{"t": round(t, 4), "points": {k: fix(v) for k, v in p.items()}} for t, p in frames],
}
with open(out, "w") as fh:
    json.dump(doc, fh)
print("[mocap_points] %d frames, scale %.3f, bones %s -> %s" % (len(frames), scale, found, out))
