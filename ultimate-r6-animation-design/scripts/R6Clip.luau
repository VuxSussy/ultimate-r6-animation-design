-- R6Clip: build R6 animations from key poses, in code, with weight.
--
--   local clip = R6Clip.new("Jab")
--   clip:key(0,  Guard, "snap")                          -- ease shapes the segment LEAVING the key
--   clip:key(8,  { Torso = { twist = -55, lean = 24, pos = { forward = 0.5, up = -0.35 } },
--                  LeftArm = { raise = 92, swing = 22, pos = { forward = 0.7 } } }, { settle = 0.12 })
--   clip:marker(8, "Hit")
--   clip:lead("Torso", 1)                                -- torso moves 1 frame before the rest (overlap)
--   local baked = clip:bake()                            -- 60 fps, every frame
--   print(R6Clip.audit(baked).notes)                     -- fix until empty
--   local ks = R6Clip.toKeyframeSequence(baked)          -- AnimSaves-ready KeyframeSequence
--   local json = R6Clip.toEclipse(baked)                 -- for the Eclipse Animator MCP save_animation tool
--
-- What you key is what plays. There is no IK and no solver: no aim targets, no planted-leg fitting,
-- no head counter. Each part entry is
--   named angles (R6Rig.rotation, degrees): Torso lean/twist/tilt, Head nod/turn/tilt,
--                limbs raise/spread/swing/twist
--   pos = { forward, up, right }  studs. On the torso: the body against the root (drop, lunge). On
--                a limb or the head: the part slides out of its socket. This is how R6 gets reach and
--                force: the movement system's run throws the arms 0.7 stud along their swing, battlegrounds punches
--                push the striking shoulder 0.5-1.4 stud at the target, legs ride up 0.5-1.5 stud
--                into the torso when the body sinks (R6 has no knees). Budgets: R6Rig.GAP.
--   space = "root"  (legs) hang the leg from a pelvis that takes only `hips` (default 0.35) of the
--                torso's turn and lean, and slide the hip socket to that pelvis: the chest can twist
--                60 degrees without swinging the feet around or crossing the legs. Once per key.
--   ground = true  (legs) every frame, slide the leg straight up or down (root space) until its
--                sole is on the floor: the telescoping-leg trick. Translation only, the leg's angle
--                is yours. Between a grounded key and a free one it fades in or out.
--   transform = CFrame  a raw joint Transform (pasted from another tool or a measured clip)
--   ease       overrides the key's ease for this part
-- Parts missing from a key are not keyed there: they move between the keys that name them.

local R6Rig = require(script.Parent.R6Rig)
local Ease = require(script.Parent.Ease)
local Sequence = require(script.Parent.Sequence)

local R6Clip = {}
R6Clip.__index = R6Clip

local ALIAS = {
	RightArm = "Right Arm",
	LeftArm = "Left Arm",
	RightLeg = "Right Leg",
	LeftLeg = "Left Leg",
}

local function partName(name)
	local part = ALIAS[name] or name
	if not R6Rig.JOINTS[part] then
		error("Not an R6 part: " .. tostring(name), 3)
	end
	return part
end

local function checkEntry(part, entry)
	if entry.aim or entry.pole or entry.free then
		error(string.format("R6Clip: %s uses aim/pole/free, which were removed (no IK). Key angles and pos instead.", part), 4)
	end
	if (entry.space or entry.ground) and part ~= "Right Leg" and part ~= "Left Leg" then
		error(string.format("R6Clip: space/ground are for legs only (%s)", part), 4)
	end
end

-- opts: fps (60), loop, priority ("Action"), budget (part -> studs, overrides R6Rig.GAP),
--       meta (anything: move data for the combat runtime travels with the clip)
function R6Clip.new(name, opts)
	opts = opts or {}
	local budget = table.clone(R6Rig.GAP)
	for part, studs in opts.budget or {} do
		budget[partName(part)] = studs
	end
	return setmetatable({
		name = name,
		fps = opts.fps or 60,
		loop = opts.loop or false,
		priority = opts.priority or "Action",
		budget = budget,
		meta = opts.meta or {},
		keys = {},
		markers = {},
		leads = {},
		_cache = {},
		_rootCache = {},
	}, R6Clip)
end

-- Deep copy of a pose with overrides merged in: R6Clip.merge(Guard, { Torso = { lean = 20 } })
-- Named angles merge field by field; `pos` merges by axis; a `transform` replaces the whole entry.
function R6Clip.merge(base, over)
	local out = {}
	for part, entry in base or {} do
		local e = table.clone(entry)
		if e.pos then
			e.pos = table.clone(e.pos)
		end
		out[ALIAS[part] or part] = e
	end
	for part, entry in over or {} do
		local name = ALIAS[part] or part
		local into = out[name]
		if into and not into.transform and not entry.transform then
			for k, v in entry do
				if k == "pos" and into.pos then
					local p = table.clone(into.pos)
					for axis, studs in v do
						p[axis] = studs
					end
					into.pos = p
				else
					into[k] = v
				end
			end
		else
			out[name] = table.clone(entry)
		end
	end
	return out
end

-- The same pose on the other side: left and right parts swap, the torso and head turn and tilt the
-- other way, sideways slides flip. A walk or run cycle is half keys plus their mirror.
local MIRROR_PART = { ["Right Arm"] = "Left Arm", ["Left Arm"] = "Right Arm", ["Right Leg"] = "Left Leg", ["Left Leg"] = "Right Leg" }
function R6Clip.mirror(pose)
	local out = {}
	for part, entry in pose do
		local name = ALIAS[part] or part
		local e = table.clone(entry)
		if e.pos then
			e.pos = table.clone(e.pos)
			e.pos.right = e.pos.right and -e.pos.right or nil
		end
		if name == "Torso" or name == "Head" then
			for _, k in { "twist", "turn", "tilt" } do
				if e[k] then
					e[k] = -e[k]
				end
			end
		end
		out[MIRROR_PART[name] or name] = e
	end
	return out
end

function R6Clip:key(frame, pose, ease)
	local key = { frame = frame, ease = ease, parts = {} }
	for name, entry in pose do
		local part = partName(name)
		checkEntry(part, entry)
		key.parts[part] = entry
	end
	self._cache, self._rootCache = {}, {}
	for i, k in self.keys do
		if k.frame == frame then
			self.keys[i] = key
			return self
		elseif k.frame > frame then
			table.insert(self.keys, i, key)
			return self
		end
	end
	table.insert(self.keys, key)
	return self
end

function R6Clip:marker(frame, name, value)
	table.insert(self.markers, { frame = frame, name = name, value = value or "" })
	return self
end

-- frames > 0: the part moves earlier than its keys (leads); < 0: it trails (drag/overlap).
function R6Clip:lead(part, frames)
	self.leads[partName(part)] = frames
	return self
end

function R6Clip:length()
	local last = self.keys[#self.keys]
	return last and last.frame or 0
end

-- The two keys around `frame` that name `part`, and the eased alpha between them.
function R6Clip:_segment(part, frame)
	local before, after
	for _, k in self.keys do
		local entry = k.parts[part]
		if entry then
			if k.frame <= frame then
				before = { frame = k.frame, entry = entry, ease = entry.ease or k.ease }
			elseif not after then
				after = { frame = k.frame, entry = entry, ease = entry.ease or k.ease }
			end
		end
	end
	if not before and not after then
		return nil
	end
	if not before then
		return after, after, 0
	elseif not after then
		return before, before, 0
	end
	local u = (frame - before.frame) / (after.frame - before.frame)
	return before, after, Ease.get(before.ease)(u)
end

local blend = Sequence.blend

local function offsetOf(entry)
	local p = entry.pos
	return p and Vector3.new(p.right or 0, p.up or 0, -(p.forward or 0)) or Vector3.zero
end

local function clampFrame(clip, f)
	local len = clip:length()
	if clip.loop and len > 0 then
		return f % len
	end
	return math.clamp(f, 0, len)
end

-- Between two keys of named angles, the ANGLES are interpolated, not the rotations. A rotation
-- blend always takes the shortest way round: an arm going from raise -55 (flung back) to 138 (guard)
-- is 193 degrees apart, so the "short" way swings it backwards over the head. Interpolating raise
-- -55 -> 0 -> 90 -> 138 takes the path the keys describe, down and forward.
local ANGLES = { "lean", "twist", "tilt", "nod", "turn", "raise", "spread", "swing" }
local function lerpEntry(a, b, alpha)
	local out = {}
	for _, k in ANGLES do
		if a[k] or b[k] then
			out[k] = (a[k] or 0) + ((b[k] or 0) - (a[k] or 0)) * alpha
		end
	end
	if a.pos or b.pos then
		local pa, pb = a.pos or {}, b.pos or {}
		out.pos = {}
		for _, axis in { "forward", "up", "right" } do
			out.pos[axis] = (pa[axis] or 0) + ((pb[axis] or 0) - (pa[axis] or 0)) * alpha
		end
	end
	return out
end
R6Clip.lerpEntry = lerpEntry

local function named(entry)
	return not entry.transform and entry.space ~= "root"
end

function R6Clip:_torso(frame)
	local a, b, alpha = self:_segment("Torso", frame)
	if not a then
		return CFrame.identity
	end
	if a ~= b and named(a.entry) and named(b.entry) then
		return R6Rig.pose("Torso", lerpEntry(a.entry, b.entry, alpha))
	end
	local ta = a.entry.transform or R6Rig.pose("Torso", a.entry)
	local tb = b.entry.transform or R6Rig.pose("Torso", b.entry)
	return blend(ta, tb, alpha)
end

-- A key's entry -> joint Transform, worked out once per key. A root-space leg needs the torso as it
-- will be when that key plays (leads shift the torso against the leg).
function R6Clip:_entry(part, entry, keyFrame)
	local cached = self._cache[entry]
	if cached then
		return cached
	end
	local t
	if entry.transform then
		t = entry.transform
	elseif entry.space == "root" then
		-- The legs hang from a pelvis that takes only `hips` (default 0.35) of the torso's turn and
		-- lean, the way real hips turn less than the shoulders. The hip socket is slid to where that
		-- pelvis puts it, so a torso twisted 60 degrees does not swap the hips front-to-back and
		-- cross the legs. Translation and a fixed rotation per key: no solver.
		local at = clampFrame(self, keyFrame - (self.leads[part] or 0) + (self.leads.Torso or 0))
		local torsoT = self:_torso(at)
		local torsoRot = R6Rig.fromTransform("Torso", torsoT)
		local torso = R6Rig.fk({ Torso = torsoT }).Torso
		local pelvisRot = blend(CFrame.identity, torso.Rotation, entry.hips or 0.35)
		local hipC0 = R6Rig.JOINTS[part].C0.Position
		local slide = (CFrame.new(torso.Position) * pelvisRot) * hipC0 - torso * hipC0
		local rot = pelvisRot * R6Rig.rotation(part, entry)
		t = R6Rig.toTransform(part, torsoRot:Inverse() * rot, torsoRot:Inverse() * (offsetOf(entry) + slide))
		local j = R6Rig.JOINTS[part]
		self._cache[entry] = t
		self._rootCache[entry] = torso * j.C0 * t * j.C1:Inverse() -- the leg in root space
		return t
	else
		t = R6Rig.pose(part, entry)
	end
	self._cache[entry] = t
	return t
end

-- Slide a leg straight up or down (root space) so its sole sits on the floor. Translation only:
-- the leg rides into or out of the torso, its angle never changes. weight 0..1 fades it in and out
-- between a grounded key and a free one.
local function grounded(part, legT, torsoT, weight)
	local w = R6Rig.fk({ Torso = torsoT, [part] = legT })
	local lift = -(R6Rig.tip(part, w[part]).Y + R6Rig.ROOT_HEIGHT) * weight
	if math.abs(lift) < 1e-5 then
		return legT
	end
	local torsoRot = R6Rig.fromTransform("Torso", torsoT)
	local r0 = R6Rig.JOINTS[part].C0.Rotation
	return r0:Inverse() * CFrame.new(torsoRot:Inverse() * Vector3.new(0, lift, 0)) * r0 * legT
end

-- All six joint Transforms at a (fractional) frame.
function R6Clip:sample(frame)
	local out = {}
	out.Torso = self:_torso(clampFrame(self, frame + (self.leads.Torso or 0)))
	for _, part in R6Rig.ORDER do
		if part ~= "Torso" then
			local f = clampFrame(self, frame + (self.leads[part] or 0))
			local a, b, alpha = self:_segment(part, f)
			if a then
				local t
				if a.entry.space == "root" and b.entry.space == "root" and a ~= b then
					-- blend the leg where it lives (against the root), then hang it from this frame's
					-- torso: a fast torso swing between keys cannot drag the legs through each other
					self:_entry(part, a.entry, a.frame)
					self:_entry(part, b.entry, b.frame)
					local leg = blend(self._rootCache[a.entry], self._rootCache[b.entry], alpha)
					local j = R6Rig.JOINTS[part]
					local torso = R6Rig.fk({ Torso = out.Torso }).Torso
					t = j.C0:Inverse() * torso:Inverse() * leg * j.C1
				elseif a ~= b and named(a.entry) and named(b.entry) then
					t = R6Rig.pose(part, lerpEntry(a.entry, b.entry, alpha))
				else
					t = blend(self:_entry(part, a.entry, a.frame), self:_entry(part, b.entry, b.frame), alpha)
				end
				local weight = (a.entry.ground and 1 - alpha or 0) + (b.entry.ground and alpha or 0)
				if a == b then
					weight = a.entry.ground and 1 or 0
				end
				if weight > 0 then
					t = grounded(part, t, out.Torso, math.clamp(weight, 0, 1))
				end
				out[part] = t
			else
				out[part] = CFrame.identity
			end
		end
	end
	return out
end

-- opts.step: sample every N frames (1 = every 60 fps frame; 5 = 12 poses a second "on twos")
-- opts.stepped: hold each sample (Constant easing) instead of sliding between them
function R6Clip:bake(opts)
	opts = opts or {}
	local step = opts.step or 1
	local len = self:length()
	-- parts that trail (negative lead) finish after the last key: run on until they land
	if not self.loop then
		for _, frames in self.leads do
			len = math.max(len, self:length() - frames)
		end
	end
	local frames = {}
	local f = 0
	while f <= len + 1e-6 do
		table.insert(frames, { frame = f, time = f / self.fps, transforms = self:sample(f) })
		f += step
	end
	if frames[#frames].frame < len - 1e-6 then
		table.insert(frames, { frame = len, time = len / self.fps, transforms = self:sample(len) })
	end
	local markers = {}
	for _, m in self.markers do
		table.insert(markers, { frame = m.frame, time = m.frame / self.fps, name = m.name, value = m.value })
	end
	return {
		name = self.name,
		fps = self.fps,
		loop = self.loop,
		priority = self.priority,
		stepped = opts.stepped or false,
		frames = frames,
		markers = markers,
		meta = self.meta,
		budget = self.budget,
		leads = table.clone(self.leads),
	}
end

-- Drop keys that straight interpolation between their neighbours reproduces (Ramer-Douglas-Peucker
-- per part). tolerance in degrees (default 0.25, below what the eye sees), studs/10 for offsets.
local angle = Sequence.angleBetween

function R6Clip.reduce(baked, tolerance)
	tolerance = tolerance or 0.25
	local forced = {}
	for _, m in baked.markers do
		forced[m.time] = true
	end
	local tracks = {}
	for _, part in R6Rig.ORDER do
		local samples = {}
		for _, fr in baked.frames do
			table.insert(samples, { time = fr.time, cf = fr.transforms[part] or CFrame.identity })
		end
		local keep = { [1] = true, [#samples] = true }
		local function split(i, j)
			if j - i < 2 then
				return
			end
			local worst, at = 0, nil
			for k = i + 1, j - 1 do
				local u = (samples[k].time - samples[i].time) / (samples[j].time - samples[i].time)
				local guess = blend(samples[i].cf, samples[j].cf, u)
				local err = angle(guess, samples[k].cf) + (guess.Position - samples[k].cf.Position).Magnitude * 10
				if err > worst then
					worst, at = err, k
				end
			end
			if worst > tolerance then
				keep[at] = true
				split(i, at)
				split(at, j)
			end
		end
		split(1, #samples)
		local track = {}
		for i, s in samples do
			if keep[i] or forced[s.time] or baked.stepped then
				table.insert(track, s)
			end
		end
		tracks[part] = track
	end
	return tracks
end

-- Baked clip -> KeyframeSequence (Roblox Instance). opts.reduce (default true) thins keys first.
function R6Clip.toKeyframeSequence(baked, opts)
	opts = opts or {}
	local tracks
	if opts.reduce == false then
		tracks = {}
		for _, part in R6Rig.ORDER do
			tracks[part] = {}
			for _, fr in baked.frames do
				table.insert(tracks[part], { time = fr.time, cf = fr.transforms[part] or CFrame.identity })
			end
		end
	else
		tracks = R6Clip.reduce(baked, opts.tolerance)
	end

	local byTime = {}
	local function at(time)
		local key = math.floor(time * 10000 + 0.5)
		byTime[key] = byTime[key] or { time = time, poses = {} }
		return byTime[key]
	end
	for part, track in tracks do
		for _, s in track do
			local x = s.cf.XVector.X + s.cf.Position.X
			if x ~= x then
				-- a NaN Pose plays as a silent rest pose in Roblox; fail loudly instead
				error(string.format("R6Clip: NaN in %s at %.3fs of %s", part, s.time, baked.name), 2)
			end
			at(s.time).poses[part] = s.cf
		end
	end
	for _, m in baked.markers do
		at(m.time)
	end

	local ks = Instance.new("KeyframeSequence")
	ks.Name = baked.name
	ks.Loop = baked.loop
	ks.Priority = Enum.AnimationPriority[baked.priority]
	local style = baked.stepped and Enum.PoseEasingStyle.Constant or Enum.PoseEasingStyle.Linear

	local times = {}
	for _, entry in byTime do
		table.insert(times, entry)
	end
	table.sort(times, function(a, b)
		return a.time < b.time
	end)
	for _, entry in times do
		local kf = Instance.new("Keyframe")
		kf.Time = entry.time
		local root = Instance.new("Pose")
		root.Name = "HumanoidRootPart"
		root.Weight = 0
		root.Parent = kf
		local torso = Instance.new("Pose")
		torso.Name = "Torso"
		torso.Weight = entry.poses.Torso and 1 or 0
		torso.CFrame = entry.poses.Torso or CFrame.identity
		torso.EasingStyle = style
		torso.EasingDirection = Enum.PoseEasingDirection.In
		torso.Parent = root
		for _, part in { "Head", "Right Arm", "Left Arm", "Right Leg", "Left Leg" } do
			local cf = entry.poses[part]
			if cf then
				local pose = Instance.new("Pose")
				pose.Name = part
				pose.Weight = 1
				pose.CFrame = cf
				pose.EasingStyle = style
				pose.EasingDirection = Enum.PoseEasingDirection.In
				pose.Parent = torso
			end
		end
		for _, m in baked.markers do
			if math.abs(m.time - entry.time) < 1e-4 then
				local marker = Instance.new("KeyframeMarker")
				marker.Name = m.name
				marker.Value = m.value
				marker.Parent = kf
			end
		end
		kf.Parent = ks
	end
	return ks
end

-- Baked clip -> the JSON the Eclipse Animator MCP save_animation tool takes.
function R6Clip.toEclipse(baked, opts)
	opts = opts or {}
	local tracks = R6Clip.reduce(baked, opts.tolerance)
	local byTime = {}
	for part, track in tracks do
		for _, s in track do
			local key = math.floor(s.time * 10000 + 0.5)
			byTime[key] = byTime[key] or { time = s.time, poses = {} }
			local rx, ry, rz = s.cf:ToEulerAnglesXYZ()
			local p = s.cf.Position
			local function r(x)
				return math.floor(x * 1000 + 0.5) / 1000
			end
			byTime[key].poses[part] = {
				rot = { r(math.deg(rx)), r(math.deg(ry)), r(math.deg(rz)) },
				pos = { r(p.X), r(p.Y), r(p.Z) },
				easing = baked.stepped and "Constant" or "Linear",
			}
		end
	end
	local keyframes = {}
	for _, k in byTime do
		table.insert(keyframes, k)
	end
	table.sort(keyframes, function(a, b)
		return a.time < b.time
	end)
	return { name = baked.name, loop = baked.loop, priority = baked.priority, keyframes = keyframes }
end

-- Character-space CFrame of every part on every baked frame (for previews and audits).
function R6Clip.world(baked)
	local out = {}
	for _, fr in baked.frames do
		table.insert(out, { time = fr.time, frame = fr.frame, parts = R6Rig.fk(fr.transforms) })
	end
	return out
end

-- The shape of a strike in frames, to compare against a reference clip or video:
--   load     frames from the start to the deepest chamber (where the release begins)
--   release  frames from the deepest chamber until the tip covers 90% of its travel
--   hold     frames the tip then stays within 15% of its extreme
--   back     frames from the end of the hold until the tip is 90% of the way home
--   lean     degrees the torso leans from upright at the extreme
--   rearPull studs the other arm's fist moves back, relative to the chest, during the release
-- limb: "LeftArm" etc.; dir: strike direction in character space (default forward).
function R6Clip.profile(baked, limb, dir, tipPoint)
	limb = ALIAS[limb] or limb
	dir = dir or Vector3.new(0, 0, -1)
	local other = ({ ["Left Arm"] = "Right Arm", ["Right Arm"] = "Left Arm" })[limb]
	local world = R6Clip.world(baked)
	local ext, rear = {}, {}
	for i, w in world do
		ext[i] = (tipPoint and w.parts[limb] * tipPoint or R6Rig.tip(limb, w.parts[limb])):Dot(dir)
		-- the rear hand is judged against the chest, not the floor: the body lunges forward under it
		local torso = w.parts.Torso
		rear[i] = other and torso:PointToObjectSpace(R6Rig.tip(other, w.parts[other])):Dot(torso:VectorToObjectSpace(dir)) or 0
	end
	local n = #ext
	local peakI = 1
	for i = 1, n do
		if ext[i] > ext[peakI] + 1e-4 then
			peakI = i
		end
	end
	local lowI = 1
	for i = 1, peakI do
		if ext[i] < ext[lowI] - 1e-4 then
			lowI = i
		end
	end
	local low, peak = ext[lowI], ext[peakI]
	local span = math.max(peak - low, 1e-6)
	local arrive = peakI
	for i = lowI, peakI do
		if ext[i] >= low + 0.9 * span then
			arrive = i
			break
		end
	end
	local holdEnd = arrive
	while holdEnd < n and ext[holdEnd + 1] >= peak - 0.15 * span do
		holdEnd += 1
	end
	local home = n
	local base = ext[n] -- the guard it returns to (the first frame may already be loading)
	for i = holdEnd, n do
		if ext[i] <= base + 0.1 * (peak - base) then
			home = i
			break
		end
	end
	local torsoUp = world[peakI].parts.Torso.UpVector
	return {
		load = lowI - 1,
		release = arrive - lowI,
		hold = holdEnd - arrive,
		back = home - holdEnd,
		lean = math.deg(math.acos(math.clamp(torsoUp.Y, -1, 1))),
		rearPull = rear[lowI] - rear[arrive],
		extremeFrame = peakI - 1,
		reach = span,
	}
end

-- The hard rules, checked on numbers instead of eyes:
--   pops      no part jumps in one frame (a spike against its neighbours, or over maxStep = 90
--             degrees) unless a "Snap" marker or the meta.strike window covers it
--   contact   the striking limb is at its most extended within 2 frames of the "Hit" marker
--   placement the hit lands 15-60% into the move (short before, long after)
--   hold      the strike reads for 4+ frames
--   commit    a straight punch puts the whole body behind it: the fist ends at least
--             meta.minReach (2.4) studs in front of the root and the torso turns at least
--             meta.minTwist (25) degrees into it. Timid, tucked-in strikes fail here.
--   gap       no part leaves its socket further than its budget (R6Rig.GAP, clip opts.budget)
--   legs      the two legs never cross or pass through each other (centre lines 0.75+ apart), and
--             never form an X seen from the side or the front (meta.stride: walks and runs pass
--             their legs on purpose, only the front view is checked)
--   overhead  no fist swings above the shoulders AND behind the back unless meta.overhead says the
--             move means it: that is the "long way round" a rotation blend takes between poses
--             more than 180 degrees apart (an arm flung back coming home over the head)
--   export    the KeyframeSequence export, played the way Roblox plays it (shortest-way blends
--             between the kept keys), reproduces the clip within 1 degree
--   feet      soles stay on the floor (y = -3) unless meta.airborne; both off it needs meta.hop.
--             The note says how far to slide the leg (pos.up) or to set ground = true.
-- meta.limb names the striking part; meta.tip, a point in that part's space, is where it strikes
-- from when it holds a weapon (a sword in a Tool's default grip: Vector3.new(0, -1, -blade), the
-- blade standing out of the fist along the arm's front). Returns { ok, notes = {...}, metrics = {...} }.
function R6Clip.audit(baked, meta)
	meta = meta or baked.meta or {}
	local notes, metrics = {}, {}
	local world = R6Clip.world(baked)
	local snaps = {}
	for _, m in baked.markers do
		if m.name == "Snap" then
			snaps[math.floor(m.frame + 0.5)] = true
		end
	end
	-- the strike itself (chamber -> contact) is meant to be fast; only pops elsewhere count. Parts
	-- that lead strike earlier and parts that trail strike later, so the window widens by both.
	local leadMost, trailMost = 0, 0
	for _, frames in baked.leads or {} do
		leadMost, trailMost = math.max(leadMost, frames), math.max(trailMost, -frames)
	end
	for _, window in { meta.strike } do
		for f = window[1] + 1 - leadMost, window[2] + trailMost do
			snaps[f] = true
		end
	end

	-- Measured on what the eye sees (each part's turn in character space), not on joint angles.
	-- A pop is a spike: a frame that turns far more than the frames on either side of it, or an
	-- absurd turn in one frame. Fast but continuous motion is the strike doing its job.
	local steps = {}
	for i = 2, #baked.frames do
		local a, b = baked.frames[i - 1], baked.frames[i]
		local frameGap = math.max(1, b.frame - a.frame)
		steps[i] = {}
		for _, part in R6Rig.ORDER do
			local step = angle(world[i - 1].parts[part], world[i].parts[part]) / frameGap
			local slide = (world[i - 1].parts[part].Position - world[i].parts[part].Position).Magnitude / frameGap
			step = math.max(step, slide * 40) -- a 0.5-stud jump in one frame reads like a 20-degree pop
			if step ~= step then
				table.insert(notes, "NaN in " .. part .. " at frame " .. b.frame)
				step = 0
			end
			steps[i][part] = step
		end
	end
	local worstStep = 0
	for i = 2, #baked.frames do
		local frame = math.floor(baked.frames[i].frame + 0.5)
		for _, part in R6Rig.ORDER do
			local step = steps[i][part]
			worstStep = math.max(worstStep, step)
			local before = steps[i - 1] and steps[i - 1][part] or 0
			local after = steps[i + 1] and steps[i + 1][part] or 0
			local spike = step > (meta.popMin or 20) and step > 2.2 * math.max(before, after, 1)
			local absurd = step > (meta.maxStep or 90)
			if (spike or absurd) and not snaps[frame] and not baked.stepped then
				table.insert(notes, string.format("pop: %s jumps %.0f in one frame at frame %d (neighbours %.0f, %.0f)", part, step, frame, before, after))
			end
		end
	end
	metrics.worstDegPerFrame = worstStep

	-- sockets: how far each part slides out, against its budget
	local budget = baked.budget or R6Rig.GAP
	metrics.gap = {}
	for _, part in R6Rig.ORDER do
		if part ~= "Torso" then
			local most, at = 0, 0
			for _, fr in baked.frames do
				local g = R6Rig.gap(part, fr.transforms[part] or CFrame.identity).Magnitude
				if g > most then
					most, at = g, fr.frame
				end
			end
			metrics.gap[part] = most
			if budget[part] and most > budget[part] + 1e-3 then
				table.insert(notes, string.format("gap: %s leaves its socket by %.2f studs at frame %d (budget %.2f)", part, most, at, budget[part]))
			end
		end
	end

	local hit
	for _, m in baked.markers do
		if m.name == "Hit" then
			hit = m.frame
			break
		end
	end
	local function frameAt(f)
		for i, w in world do
			if math.abs(w.frame - f) < 0.5 then
				return i, w
			end
		end
		return nil
	end
	local function strikeTip(limb, cf)
		return meta.tip and cf * meta.tip or R6Rig.tip(limb, cf)
	end
	if hit and meta.limb and meta.arc then
		-- a sweeping strike (hook, roundhouse) lands where the tip crosses the centre line in front
		local limb = ALIAS[meta.limb] or meta.limb
		local bestFrame, bestX = nil, math.huge
		for _, w in world do
			local tip = strikeTip(limb, w.parts[limb])
			if math.abs(w.frame - hit) <= 8 and tip.Z < -0.8 and math.abs(tip.X) < bestX then
				bestX, bestFrame = math.abs(tip.X), w.frame
			end
		end
		metrics.crossFrame = bestFrame
		if not bestFrame or bestX > 0.6 then
			table.insert(notes, "contact: the sweeping limb never crosses the centre line in front near the hit")
		elseif math.abs(bestFrame - hit) > 2 then
			table.insert(notes, string.format("contact: %s crosses the centre line at frame %d, the Hit marker is at %d", limb, bestFrame, hit))
		end
	elseif hit and meta.limb then
		local limb = ALIAS[meta.limb] or meta.limb
		local best, bestFrame, atHit = -math.huge, nil, nil
		local dir = meta.direction or Vector3.new(0, 0, -1)
		for _, w in world do
			local reachOut = strikeTip(limb, w.parts[limb]):Dot(dir)
			if reachOut > best + 1e-4 then
				best, bestFrame = reachOut, w.frame
			end
			if math.abs(w.frame - hit) < 0.5 then
				atHit = reachOut
			end
		end
		metrics.extremeFrame = bestFrame
		metrics.reachAtHit = atHit
		-- creeping a hair further while the hit holds is fine; arriving late is not
		local late = atHit and best - atHit > 0.1
		if bestFrame and math.abs(bestFrame - hit) > 2 and late then
			table.insert(notes, string.format("contact: %s is most extended at frame %d, the Hit marker is at %d", limb, bestFrame, hit))
		end
		local len = baked.frames[#baked.frames].frame
		metrics.hitShare = len > 0 and hit / len or 0
		if not baked.loop and (metrics.hitShare < 0.15 or metrics.hitShare > 0.6) then
			table.insert(notes, string.format("placement: the hit lands %.0f%% into the move (aim for 20-50%%)", metrics.hitShare * 100))
		end
		-- the strike should hold: 4+ frames near the extreme around the hit
		local holdFrames = 0
		for i = 2, #baked.frames do
			local fr = baked.frames[i]
			if fr.frame >= hit and fr.frame <= hit + 12 then
				if angle(world[i - 1].parts[limb], world[i].parts[limb]) < 2.5 then
					holdFrames += 1
				end
			end
		end
		metrics.holdFrames = holdFrames
		if holdFrames < 3 then
			table.insert(notes, "hold: the strike barely holds after the hit (want 4-6 readable frames)")
		end
		-- commitment: a straight arm strike forward needs the body behind it
		local straight = (limb == "Left Arm" or limb == "Right Arm") and dir.Z < -0.7
		local _, w = frameAt(hit)
		if straight and w and not meta.noCommit then
			local torso = w.parts.Torso
			local twist = math.deg(math.atan2(-torso.LookVector.X, -torso.LookVector.Z))
			metrics.twistAtHit, metrics.lungeAtHit = twist, -torso.Position.Z
			local minReach, minTwist = meta.minReach or 2.4, meta.minTwist or 25
			if atHit and atHit < minReach then
				table.insert(notes, string.format("commit: the fist ends only %.2f studs in front at the hit (want %.1f+; R6 punch references end 2.3-4.2): turn the torso in, lunge, push the shoulder out with pos.forward", atHit, minReach))
			end
			if math.abs(twist) < minTwist then
				table.insert(notes, string.format("commit: the torso is turned only %.0f degrees into the punch (want %d+; references 30-110)", math.abs(twist), minTwist))
			end
		end
	end

	-- legs: two blocks a stud wide whose centre lines come closer than legGap (0.75) are passing
	-- through each other: an X from the side, or one leg inside the other from the front
	do
		local function closest(p1, q1, p2, q2)
			local d1, d2, r = q1 - p1, q2 - p2, p1 - p2
			local a, e, f = d1:Dot(d1), d2:Dot(d2), d2:Dot(r)
			local c, b = d1:Dot(r), d1:Dot(d2)
			local denom = a * e - b * b
			local s1 = denom > 1e-9 and math.clamp((b * f - c * e) / denom, 0, 1) or 0
			local t1 = math.clamp((b * s1 + f) / e, 0, 1)
			s1 = math.clamp((b * t1 - c) / a, 0, 1)
			return ((p1 + d1 * s1) - (p2 + d2 * t1)).Magnitude
		end
		local nearest, at = math.huge, 0
		local scissor, scissorAt, scissorView = 0, nil, nil
		for _, w in world do
			local l, r = w.parts["Left Leg"], w.parts["Right Leg"]
			local d = closest(l * Vector3.new(0, 0.9, 0), l * Vector3.new(0, -0.9, 0), r * Vector3.new(0, 0.9, 0), r * Vector3.new(0, -0.9, 0))
			if d < nearest then
				nearest, at = d, w.frame
			end
			-- seen from the side (Z) or the front (X): the hips in one order, the soles in the other,
			-- both by a clear margin, is an X
			local hipL, hipR = l * Vector3.new(0, 1, 0), r * Vector3.new(0, 1, 0)
			local soleL, soleR = R6Rig.tip("Left Leg", l), R6Rig.tip("Right Leg", r)
			-- a stride (walk, run) passes one leg past the other seen from the side on purpose:
			-- only the front view counts there
			local views = meta.stride and { { "front", "X" } } or { { "side", "Z" }, { "front", "X" } }
			for _, view in views do
				local axis = view[2]
				local hips, soles = hipL[axis] - hipR[axis], soleL[axis] - soleR[axis]
				local amount = math.min(math.abs(hips), math.abs(soles))
				if hips * soles < 0 and amount > 0.3 and amount > scissor then
					scissor, scissorAt, scissorView = amount, w.frame, view[1]
				end
			end
		end
		metrics.legGap = nearest
		if not meta.legsMayCross then
			if nearest < (meta.legGap or 0.75) then
				table.insert(notes, string.format("legs: the legs pass through each other at frame %d (centre lines %.2f studs apart; use space = \"root\" legs or spread them)", at, nearest))
			end
			if scissorAt then
				table.insert(notes, string.format("legs: the legs cross into an X seen from the %s at frame %d (by %.2f studs): the hips are in one order and the feet in the other; keep the legs on a pelvis (space = \"root\", hips 0.2-0.5) or step the feet the other way", scissorView, scissorAt, scissor))
			end
		end
	end

	-- overhead: above the shoulders and behind the back at once
	if not meta.overhead then
		local worst, at, arm = 0, nil, nil
		for _, w in world do
			for _, part in { "Left Arm", "Right Arm" } do
				local p = w.parts.Torso:PointToObjectSpace(R6Rig.tip(part, w.parts[part]))
				local score = math.min(p.Y - 1, p.Z - 0.3)
				if score > worst then
					worst, at, arm = score, w.frame, part
				end
			end
		end
		if at then
			table.insert(notes, string.format("overhead: %s swings over the head behind the back at frame %d (by %.2f studs). If it is not meant, two keys are more than 180 degrees apart and the blend took the long way round: key named angles (R6Clip interpolates those) or add a passing key; if it is meant, set meta.overhead", arm, at, worst))
		end
	end

	-- export: what Roblox will play from the exported keys
	do
		local tracks = R6Clip.reduce(baked)
		local worst, at, worstPart = 0, nil, nil
		for _, part in R6Rig.ORDER do
			local track = tracks[part]
			local k = 1
			for _, fr in baked.frames do
				while track[k + 1] and track[k + 1].time < fr.time - 1e-6 do
					k += 1
				end
				local a, b = track[k], track[k + 1] or track[k]
				local u = b.time > a.time and math.clamp((fr.time - a.time) / (b.time - a.time), 0, 1) or 0
				local played = blend(a.cf, b.cf, u)
				local err = angle(played, fr.transforms[part] or CFrame.identity)
				if err > worst then
					worst, at, worstPart = err, fr.frame, part
				end
			end
		end
		metrics.exportError = worst
		if worst > 1 then
			table.insert(notes, string.format("export: the exported keys play %s %.1f degrees off the clip at frame %d", worstPart, worst, at))
		end
	end

	if not meta.airborne then
		local dig, digAt, digLeg, hover, hoverAt = 0, 0, nil, 0, 0
		for _, w in world do
			local lowest = math.huge
			for _, leg in { "Right Leg", "Left Leg" } do
				local y = R6Rig.tip(leg, w.parts[leg]).Y + R6Rig.ROOT_HEIGHT
				lowest = math.min(lowest, y)
				if -y > dig then
					dig, digAt, digLeg = -y, w.frame, leg
				end
			end
			if lowest > hover then
				hover, hoverAt = lowest, w.frame
			end
		end
		metrics.dig, metrics.hover = dig, hover
		if dig > 0.1 then
			table.insert(notes, string.format("feet: %s sinks %.2f studs into the floor at frame %d (slide it up: pos.up +%.2f there, or ground = true)", digLeg, dig, digAt, dig))
		end
		if hover > 0.25 and not meta.hop then
			table.insert(notes, string.format("feet: both soles leave the floor by %.2f studs at frame %d (slide a leg down, or set meta.hop)", hover, hoverAt))
		end
	end
	return { ok = #notes == 0, notes = notes, metrics = metrics }
end

return R6Clip
