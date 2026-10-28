-- R15ToR6: learn from R15 animations and put them on an R6 body.
--
-- Joint-by-joint copying does not work (R15 has 15 parts, R6 has 6; an R6 arm has no elbow). So
-- the R15 clip is played forward (FK) into body points: shoulders, elbows, wrists, hips, knees,
-- ankles, the chest and the head. Then each R6 part is solved to match them:
--   Torso  takes the orientation of the shoulder line over the hip line (chest twist and hip sway
--          both survive), plus the pelvis offset
--   Head   copies the R15 head's orientation
--   Arms   point at the R15 wrist ("reach") or along the R15 upper arm ("silhouette"), or anything
--          between (opts.armBlend), then slide out of the socket (up to opts.armSlide) so the fist
--          lands on the R15 fist
--   Legs   point at the R15 sole, then ride up into the torso (up to opts.legSlide) so the sole
--          lands on the R15 sole: bent R15 knees become the R6 telescoping leg, the way Arczi's
--          movement clips crouch. There is no IK; this is a per-frame copy of the R15 points.
-- Roll comes from the R15 hand and foot, so held tools keep pointing the right way.
--
-- Two ways to feed it:
--   R15ToR6.convert(ks, opts)                 reads the KeyframeSequence with Sequence (offline-safe;
--                                             legacy easing styles are approximated)
--   R15ToR6.convertSampled(frames, opts)      frames = {{ time, transforms = { [jointName] = Transform } }}
--                                             sampled from a playing Animator in Studio: exact
-- Both return an R6Clip-style baked clip: feed it to R6Clip.toKeyframeSequence / toEclipse / audit.

local R6Rig = require(script.Parent.R6Rig)
local Sequence = require(script.Parent.Sequence)

local R15ToR6 = {}

local function cf(...)
	return CFrame.new(...)
end

-- The stock R15 block rig (Roblox's default R15 proportions, as shipped in Studio's rig builder).
-- Keyed by Part1 name. Pass opts.joints from a real rig for scaled or Rthro bodies.
R15ToR6.JOINTS = {
	LowerTorso = { motor = "Root", part0 = "HumanoidRootPart", C0 = cf(0, -1, 0), C1 = cf(0, -0.2, 0) },
	UpperTorso = { motor = "Waist", part0 = "LowerTorso", C0 = cf(0, 0.2, 0), C1 = cf(0, -0.8, 0) },
	Head = { motor = "Neck", part0 = "UpperTorso", C0 = cf(0, 0.8, 0), C1 = cf(0, -0.5, 0) },
	LeftUpperArm = { motor = "LeftShoulder", part0 = "UpperTorso", C0 = cf(-1, 0.563, 0), C1 = cf(0.5, 0.3943, 0) },
	LeftLowerArm = { motor = "LeftElbow", part0 = "LeftUpperArm", C0 = cf(0, -0.3341, 0), C1 = cf(0, 0.2587, 0) },
	LeftHand = { motor = "LeftWrist", part0 = "LeftLowerArm", C0 = cf(0, -0.5009, 0), C1 = cf(0, 0.125, 0) },
	RightUpperArm = { motor = "RightShoulder", part0 = "UpperTorso", C0 = cf(1, 0.563, 0), C1 = cf(-0.5, 0.3943, 0) },
	RightLowerArm = { motor = "RightElbow", part0 = "RightUpperArm", C0 = cf(0, -0.3342, 0), C1 = cf(0, 0.2586, 0) },
	RightHand = { motor = "RightWrist", part0 = "RightLowerArm", C0 = cf(0, -0.5009, 0), C1 = cf(0, 0.125, 0) },
	LeftUpperLeg = { motor = "LeftHip", part0 = "LowerTorso", C0 = cf(-0.5, -0.2, 0), C1 = cf(0, 0.4208, 0) },
	LeftLowerLeg = { motor = "LeftKnee", part0 = "LeftUpperLeg", C0 = cf(0, -0.4011, 0), C1 = cf(0, 0.379, 0) },
	LeftFoot = { motor = "LeftAnkle", part0 = "LeftLowerLeg", C0 = cf(0, -0.5472, 0), C1 = cf(0, 0.1019, 0) },
	RightUpperLeg = { motor = "RightHip", part0 = "LowerTorso", C0 = cf(0.5, -0.2, 0), C1 = cf(0, 0.4208, 0) },
	RightLowerLeg = { motor = "RightKnee", part0 = "RightUpperLeg", C0 = cf(0, -0.4009, 0), C1 = cf(0, 0.3792, 0) },
	RightFoot = { motor = "RightAnkle", part0 = "RightLowerLeg", C0 = cf(0, -0.5472, 0), C1 = cf(0, 0.1019, 0) },
}

R15ToR6.ORDER = {
	"LowerTorso",
	"UpperTorso",
	"Head",
	"LeftUpperArm",
	"LeftLowerArm",
	"LeftHand",
	"RightUpperArm",
	"RightLowerArm",
	"RightHand",
	"LeftUpperLeg",
	"LeftLowerLeg",
	"LeftFoot",
	"RightUpperLeg",
	"RightLowerLeg",
	"RightFoot",
}

-- Read the joints of a real R15 rig (Motor6Ds), keyed by Part1 name.
function R15ToR6.jointsFromModel(model)
	local out = {}
	for name, j in R15ToR6.JOINTS do
		local part = model:FindFirstChild(name)
		local motor = part and part:FindFirstChild(j.motor)
		if motor and motor:IsA("Motor6D") then
			out[name] = { motor = j.motor, part0 = motor.Part0.Name, C0 = motor.C0, C1 = motor.C1 }
		else
			out[name] = j
		end
	end
	return out
end

-- R15 forward kinematics in root space. transforms: Part1 name -> Transform.
function R15ToR6.fk(transforms, joints)
	joints = joints or R15ToR6.JOINTS
	local world = { HumanoidRootPart = CFrame.identity }
	for _, name in R15ToR6.ORDER do
		local j = joints[name]
		local parent = world[j.part0]
		world[name] = parent * j.C0 * (transforms[name] or CFrame.identity) * j.C1:Inverse()
	end
	return world
end

local function jointPos(world, joints, name)
	local j = joints[name]
	return (world[j.part0] * j.C0).Position
end

-- Body points of a posed R15 body (root space).
function R15ToR6.points(world, joints)
	joints = joints or R15ToR6.JOINTS
	local p = {}
	for _, s in { "Left", "Right" } do
		p[s .. "Shoulder"] = jointPos(world, joints, s .. "UpperArm")
		p[s .. "Elbow"] = jointPos(world, joints, s .. "LowerArm")
		p[s .. "Wrist"] = jointPos(world, joints, s .. "Hand")
		p[s .. "Fist"] = world[s .. "Hand"] * Vector3.new(0, -0.15, 0)
		p[s .. "Hip"] = jointPos(world, joints, s .. "UpperLeg")
		p[s .. "Knee"] = jointPos(world, joints, s .. "LowerLeg")
		p[s .. "Ankle"] = jointPos(world, joints, s .. "Foot")
		p[s .. "Sole"] = world[s .. "Foot"] * Vector3.new(0, -0.15, 0)
	end
	p.Pelvis = world.LowerTorso.Position
	return p
end

local function frameFrom(right, up)
	up = up.Unit
	right = (right - up * right:Dot(up))
	if right.Magnitude < 1e-4 then
		right = Vector3.xAxis
	end
	right = right.Unit
	local back = right:Cross(up)
	return CFrame.fromMatrix(Vector3.zero, right, up, back)
end

-- The R6 parts a joint name stands for, so sampled Animator transforms can be keyed by motor name.
local MOTOR_TO_PART = {}
for name, j in R15ToR6.JOINTS do
	MOTOR_TO_PART[j.motor] = name
end

local DEFAULTS = {
	armBlend = 0, -- 0 = point at the wrist (reach), 1 = follow the upper arm (silhouette)
	armSlide = 0.8, -- studs an arm may slide out of its socket to put the fist on the R15 fist
	legSlide = 1.5, -- studs a leg may ride into / out of the torso to put the sole on the R15 sole
	ground = true, -- false: legs only point, never slide
	hips = 1, -- share of the R15 pelvis's turn the R6 hips take (lower it when a source turns its
	-- pelvis side-on and the one-stud-wide R6 legs read crossed; the audit's legs notes say when)
	floor = -3, -- R15 and R6 stock bodies both stand with the floor 3 studs under the root
}

-- One R15 pose (Part1 name -> Transform) -> six R6 Transforms.
function R15ToR6.solvePose(transforms, opts, state)
	opts = opts or {}
	state = state or {}
	local joints = opts.joints or R15ToR6.JOINTS
	local armBlend = opts.armBlend or DEFAULTS.armBlend
	local world = R15ToR6.fk(transforms, joints)
	local rest = state.rest or R15ToR6.points(R15ToR6.fk({}, joints), joints)
	state.rest = rest
	local p = R15ToR6.points(world, joints)

	-- torso: shoulder line for "right", hips-to-shoulders for "up"; the R6 torso centre follows the
	-- R15 pelvis offset from rest
	local shoulderMid = (p.LeftShoulder + p.RightShoulder) / 2
	local hipMid = (p.LeftHip + p.RightHip) / 2
	local torsoRot = frameFrom(p.RightShoulder - p.LeftShoulder, shoulderMid - hipMid)
	local offset = p.Pelvis - rest.Pelvis
	local out = {}
	out.Torso = R6Rig.toTransform("Torso", torsoRot, offset)
	local torso = R6Rig.fk({ Torso = out.Torso }).Torso

	-- head
	do
		local headRot = world.Head.Rotation
		local local_ = torso.Rotation:Inverse() * headRot
		out.Head = R6Rig.toTransform("Head", local_)
	end

	-- limbs: point each R6 limb the way the R15 limb points, then SLIDE it out of (or into) its
	-- socket so the fist or sole lands where the R15 one does. R6 limbs cannot bend, so the slide is
	-- what keeps a punch's reach and a crouch's feet: the arm pushes out up to opts.armSlide studs,
	-- the leg rides up into the torso (or out of it) up to opts.legSlide studs.
	local function limb(part, dir, goal, front, maxSlide)
		local t, rot = R6Rig.orient(part, torso, dir, { front = front, from = state[part] })
		state[part] = rot
		if maxSlide <= 0 then
			return t
		end
		local w = R6Rig.fk({ Torso = out.Torso, [part] = t })
		local miss = goal - R6Rig.tip(part, w[part])
		if miss.Magnitude > maxSlide then
			miss = miss.Unit * maxSlide
		end
		local _, socket = R6Rig.fromTransform(part, t)
		return R6Rig.toTransform(part, rot, socket + torso.Rotation:Inverse() * miss)
	end

	for _, side in { "Left", "Right" } do
		local part = side .. " Arm"
		local fist = p[side .. "Fist"]
		local reachDir = (fist - p[side .. "Shoulder"])
		local upperDir = (p[side .. "Elbow"] - p[side .. "Shoulder"])
		local dir = reachDir.Unit:Lerp(upperDir.Unit, armBlend)
		if dir.Magnitude < 1e-4 then
			dir = reachDir.Unit
		end
		out[part] = limb(part, dir, fist, world[side .. "Hand"].LookVector, opts.armSlide or DEFAULTS.armSlide)
	end
	-- Legs hang from the R15 pelvis, not from the R6 torso: the R6 torso takes the chest's twist,
	-- and hanging the legs from it would swap the hips front-to-back on a big turn and cross the
	-- legs into an X. So each leg points from where the R15 pelvis puts its hip to the R15 sole;
	-- the slide then carries both the hip and the sole into place.
	local restTorso = R6Rig.fk({}).Torso
	for _, side in { "Left", "Right" } do
		local part = side .. " Leg"
		local sole = p[side .. "Sole"]
		local restOffset = R6Rig.pivot(part, restTorso) - rest[side .. "Hip"]
		local pelvisRot = Sequence.blend(CFrame.identity, world.LowerTorso.Rotation, opts.hips or DEFAULTS.hips)
		local hip = (p.LeftHip + p.RightHip) / 2 + pelvisRot * (restOffset + (rest[side .. "Hip"] - (rest.LeftHip + rest.RightHip) / 2))
		local dir = sole - hip
		local slide = opts.ground == false and 0 or (opts.legSlide or DEFAULTS.legSlide)
		out[part] = limb(part, dir, sole, world[side .. "Foot"].LookVector, slide)
	end
	return out
end

local function bakedFrom(name, frames, opts, meta)
	return {
		name = name,
		fps = opts.fps or 60,
		loop = opts.loop or false,
		priority = opts.priority or "Action",
		stepped = false,
		frames = frames,
		markers = opts.markers or {},
		meta = meta or {},
		budget = { ["Right Arm"] = opts.armSlide or DEFAULTS.armSlide, ["Left Arm"] = opts.armSlide or DEFAULTS.armSlide, ["Right Leg"] = opts.legSlide or DEFAULTS.legSlide, ["Left Leg"] = opts.legSlide or DEFAULTS.legSlide, Head = 0.15 },
	}
end

-- Convert from a KeyframeSequence (offline-safe). opts: fps (60), armBlend, ground, joints, name.
function R15ToR6.convert(ks, opts)
	opts = opts or {}
	local seq = Sequence.read(ks)
	local fps = opts.fps or 60
	local frames, state = {}, {}
	local count = math.max(1, math.floor(seq.length * fps + 0.5))
	for i = 0, count do
		local t = math.min(seq.length, i / fps)
		local sample = Sequence.sample(seq, t)
		table.insert(frames, { frame = i, time = t, transforms = R15ToR6.solvePose(sample, opts, state) })
	end
	local markers = {}
	for _, m in seq.markers do
		table.insert(markers, { frame = m.t * fps, time = m.t, name = m.name, value = m.value })
	end
	opts.markers = markers
	opts.loop = seq.loop
	opts.priority = seq.priority
	return bakedFrom(opts.name or (seq.name .. " R6"), frames, opts)
end

-- Convert frames sampled from a playing Animator: {{ time, transforms = { [motorOrPartName] = Transform } }}.
function R15ToR6.convertSampled(sampled, opts)
	opts = opts or {}
	local frames, state = {}, {}
	for i, s in sampled do
		local byPart = {}
		for key, t in s.transforms do
			byPart[MOTOR_TO_PART[key] or key] = t
		end
		table.insert(frames, { frame = i - 1, time = s.time, transforms = R15ToR6.solvePose(byPart, opts, state) })
	end
	return bakedFrom(opts.name or "Converted R6", frames, opts)
end

-- Studio only: play an R15 KeyframeSequence on an R15 rig and sample its joints exactly.
-- rig: an R15 Model with a Humanoid/AnimationController; runs in edit mode from a plugin or the
-- command bar / MCP (needs Animator:StepAnimations, plugin security).
function R15ToR6.sampleInStudio(rig, ks, fps)
	fps = fps or 60
	local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
	local controller = rig:FindFirstChildWhichIsA("Humanoid") or rig:FindFirstChildWhichIsA("AnimationController")
	local animator = controller:FindFirstChildWhichIsA("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = controller
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = KeyframeSequenceProvider:RegisterKeyframeSequence(ks)
	local track = animator:LoadAnimation(anim)
	track:Play(0)
	local deadline = os.clock() + 5
	while track.Length <= 0 and os.clock() < deadline do
		task.wait()
	end
	local length = 0
	for _, kf in ks:GetKeyframes() do
		length = math.max(length, kf.Time)
	end
	local motors = {}
	for _, d in rig:GetDescendants() do
		if d:IsA("Motor6D") and d.Part1 then
			motors[d.Part1.Name] = d
		end
	end
	local frames = {}
	for i = 0, math.max(1, math.floor(length * fps + 0.5)) do
		local t = math.min(i / fps, length)
		track.TimePosition = t
		animator:StepAnimations(0)
		local transforms = {}
		for name, m in motors do
			transforms[name] = m.Transform
		end
		table.insert(frames, { time = t, transforms = transforms })
	end
	track:Stop(0)
	for _, m in motors do
		m.Transform = CFrame.identity
	end
	return frames
end

return R15ToR6
