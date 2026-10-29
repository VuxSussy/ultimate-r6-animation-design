-- MocapToR6: turn human motion capture into an R6 clip. A brand-new move (a mage's cast, a staff
-- spin, a bow draw) rarely has an R6 version to imitate, but free mocap of real people doing it
-- usually exists (Rokoko's free packs, itch.io packs, CMU, Mixamo through the user's account).
-- tools/mocap_points.py (Blender, headless) reads the FBX/BVH/GLB into body points per frame;
-- this module solves the six R6 parts from them the way the rest of the skill poses R6:
--   Torso  the shoulder line over the hip line, placed so the hips sit where the human's are
--   Head   from the neck to the top of the head
--   Arms   pointed where the human arm points (shoulder to fist, or toward the elbow with armBlend);
--          no slide by default: a human's narrow shoulders would drag R6 arms into the chest
--   Legs   each R6 foot where the human foot is (shifted out to R6's hip width), hung from a square
--          pelvis (opts.hips), riding straight up into the torso for a bent knee (up to legSlide)
-- No IK: each frame copies where the body points are.
--
--   local baked = MocapToR6.convert(doc, { name = "FireballCast", inPlace = true })
--   -- doc = the JSON from mocap_points.py, decoded: { fps, frames = {{ t, points = { Name = {x,y,z} } }} }

local R6Rig = require(script.Parent.R6Rig)
local Sequence = require(script.Parent.Sequence)

local MocapToR6 = {}

MocapToR6.DEFAULTS = {
	armBlend = 0, -- 0: point at the fist, 1: follow the upper arm (keeps a bent-arm silhouette)
	armSlide = 0, -- studs an arm may slide to reach the scaled human fist (0 = direction only)
	legSlide = 1.5,
	hips = 0, -- share of the torso's turn and lean the R6 hips follow (R6Clip's pelvis); a human's
	-- small hip turn on R6's 2-stud-wide hips crosses the legs, so by default the hips stay square
	inPlace = false, -- true: drop the body's sideways and forward travel (keep only the height)
	maxTravel = 1.5, -- otherwise, travel against the first frame is kept up to this many studs
}

local function v3(t)
	return Vector3.new(t[1], t[2], t[3])
end

-- a rotation whose X runs along `right` and Y along `up` (Y wins; right is made perpendicular)
local function frameFrom(right, up)
	up = up.Unit
	right = right - up * right:Dot(up)
	if right.Magnitude < 1e-4 then
		right = Vector3.xAxis
	end
	right = right.Unit
	return CFrame.fromMatrix(Vector3.zero, right, up, right:Cross(up))
end

-- One frame's body points (Vector3s) -> six R6 Transforms. rest: the first frame's points.
function MocapToR6.solvePose(p, rest, opts, state)
	opts = opts or {}
	state = state or {}
	local out = {}

	local hipMid = (p.LeftHip + p.RightHip) / 2
	local shoulderMid = (p.LeftShoulder + p.RightShoulder) / 2
	local torsoRot = frameFrom(p.RightShoulder - p.LeftShoulder, shoulderMid - hipMid)
	-- the R6 hip pivots sit 1 stud below the torso centre: put that line on the human hips
	local centre = hipMid + torsoRot * Vector3.new(0, 1, 0)
	local restCentre = (rest.LeftHip + rest.RightHip) / 2 + Vector3.new(0, 1, 0)
	local travel = centre - Vector3.new(restCentre.X, 0, restCentre.Z)
	local flat = Vector3.new(travel.X, 0, travel.Z)
	if opts.inPlace then
		flat = Vector3.zero
	elseif flat.Magnitude > (opts.maxTravel or MocapToR6.DEFAULTS.maxTravel) then
		flat = flat.Unit * (opts.maxTravel or MocapToR6.DEFAULTS.maxTravel)
	end
	local offset = Vector3.new(flat.X, travel.Y, flat.Z)
	out.Torso = R6Rig.toTransform("Torso", torsoRot, offset)
	local torso = R6Rig.fk({ Torso = out.Torso }).Torso

	-- head
	if p.Neck and p.HeadTop then
		local headRot = frameFrom(p.RightShoulder - p.LeftShoulder, p.HeadTop - p.Neck)
		out.Head = R6Rig.toTransform("Head", torso.Rotation:Inverse() * headRot)
	end

	-- arms: direction from the human shoulder
	local armBlend = opts.armBlend or MocapToR6.DEFAULTS.armBlend
	local armSlide = opts.armSlide or MocapToR6.DEFAULTS.armSlide
	for _, side in { "Left", "Right" } do
		local part = side .. " Arm"
		local toFist = p[side .. "Fist"] - p[side .. "Shoulder"]
		local toElbow = p[side .. "Elbow"] - p[side .. "Shoulder"]
		local dir = toFist.Unit:Lerp(toElbow.Unit, armBlend)
		if dir.Magnitude < 1e-4 then
			dir = toFist.Unit
		end
		local t, rot = R6Rig.orient(part, torso, dir, { front = torso.LookVector, from = state[part] })
		state[part] = rot
		if armSlide > 0 then
			-- reach as far as the human arm does, in R6 arm lengths, from the R6 shoulder
			local restLen = (rest[side .. "Fist"] - rest[side .. "Shoulder"]).Magnitude
			local goal = R6Rig.pivot(part, torso) + toFist * (R6Rig.reach(part) / math.max(restLen, 1e-3))
			local w = R6Rig.fk({ Torso = out.Torso, [part] = t })
			local miss = goal - R6Rig.tip(part, w[part])
			if miss.Magnitude > armSlide then
				miss = miss.Unit * armSlide
			end
			local _, socket = R6Rig.fromTransform(part, t)
			t = R6Rig.toTransform(part, rot, socket + torso.Rotation:Inverse() * miss)
		end
		out[part] = t
	end

	-- legs: each R6 foot on the human's foot (shifted out to R6's hip width), hung from a pelvis
	local legSlide = opts.legSlide or MocapToR6.DEFAULTS.legSlide
	-- the pelvis the legs hang from: the torso's position, a share of its rotation
	-- centred on the torso's own hip line (where the human hips are), turned only by that share
	local pelvisRot = Sequence.blend(CFrame.identity, torso.Rotation, opts.hips or MocapToR6.DEFAULTS.hips)
	local pelvis = CFrame.new(torso * Vector3.new(0, -1, 0)) * pelvisRot * CFrame.new(0, 1, 0)
	for _, side in { "Left", "Right" } do
		local part = side .. " Leg"
		local sole = p[side .. "Sole"]
		-- the R6 foot goes where the human foot is (planted feet stay planted, no skating as the
		-- body folds), moved sideways by the difference between R6's wide hips and the human's
		local restTip = R6Rig.tip(part, R6Rig.fk({})[part])
		local hipRot = frameFrom(p.RightHip - p.LeftHip, Vector3.yAxis)
		local pivot = pelvis * R6Rig.JOINTS[part].C0.Position
		local goal = sole + hipRot * (restTip - rest[side .. "Sole"])
		local front = p[side .. "Toe"] and (p[side .. "Toe"] - p[side .. "Ankle"]) or torso.LookVector
		-- aim so the sole lands on the goal's floor position (x, z); the leg then rides straight
		-- up into the torso (or out of it) for the height, never along its own slant: a front leg
		-- slid along its slant puts its top behind the back leg's and crosses them from the side
		local reach = R6Rig.reach(part)
		local flatGoal = Vector3.new(goal.X - pivot.X, 0, goal.Z - pivot.Z)
		local across = math.min(flatGoal.Magnitude, reach * 0.98)
		local flatDir = flatGoal.Magnitude > 1e-4 and flatGoal.Unit or Vector3.zero
		local dir = flatDir * across - Vector3.yAxis * math.sqrt(reach * reach - across * across)
		local t, rot = R6Rig.orient(part, torso, dir, { front = Vector3.new(front.X, 0, front.Z), from = state[part] })
		state[part] = rot
		-- slide the socket from the torso's hip to the pelvis's, then up/down for the height
		local socketSlide = pivot - R6Rig.pivot(part, torso)
		local w = R6Rig.fk({ Torso = out.Torso, [part] = t })
		local lift = math.clamp(goal.Y - (R6Rig.tip(part, w[part]) + socketSlide).Y, -legSlide, legSlide)
		local _, socket = R6Rig.fromTransform(part, t)
		out[part] = R6Rig.toTransform(part, rot, socket + torso.Rotation:Inverse() * (socketSlide + Vector3.new(0, lift, 0)))
	end
	return out
end

-- The decoded JSON of mocap_points.py -> an R6Clip-style baked clip (feed R6Clip.audit,
-- toKeyframeSequence, toEclipse). Soles are put under each ankle at the first frame's ankle height.
function MocapToR6.convert(doc, opts)
	opts = opts or {}
	local fps = opts.fps or 60
	local samples = {}
	for _, f in doc.frames do
		local p = {}
		for name, xyz in f.points do
			p[name] = v3(xyz)
		end
		table.insert(samples, { t = f.t, p = p })
	end
	if #samples == 0 then
		error("MocapToR6: no frames", 2)
	end
	-- soles: under each ankle by its standing height
	local first = samples[1].p
	for _, side in { "Left", "Right" } do
		local h = first[side .. "Ankle"].Y + R6Rig.ROOT_HEIGHT
		for _, s in samples do
			s.p[side .. "Sole"] = s.p[side .. "Ankle"] - Vector3.new(0, h, 0)
		end
	end
	local rest = samples[1].p
	-- resample to the clip rate, blending neighbours
	local length = samples[#samples].t
	local frames, state = {}, {}
	local count = math.max(1, math.floor(length * fps + 0.5))
	local k = 1
	for i = 0, count do
		local t = math.min(i / fps, length)
		while samples[k + 1] and samples[k + 1].t < t do
			k += 1
		end
		local a, b = samples[k], samples[k + 1] or samples[k]
		local u = b.t > a.t and (t - a.t) / (b.t - a.t) or 0
		local p = {}
		for name, va in a.p do
			p[name] = va:Lerp(b.p[name] or va, u)
		end
		table.insert(frames, { frame = i, time = t, transforms = MocapToR6.solvePose(p, rest, opts, state) })
	end
	local slide = opts.legSlide or MocapToR6.DEFAULTS.legSlide
	return {
		name = opts.name or "Mocap",
		fps = fps,
		loop = opts.loop or false,
		priority = opts.priority or "Action",
		stepped = false,
		frames = frames,
		markers = {},
		meta = { airborne = opts.airborne },
		budget = { ["Right Arm"] = 1.0, ["Left Arm"] = 1.0, ["Right Leg"] = slide, ["Left Leg"] = slide, Head = 0.15 },
		leads = {},
		source = doc.source,
	}
end

MocapToR6.blend = Sequence.blend

return MocapToR6
