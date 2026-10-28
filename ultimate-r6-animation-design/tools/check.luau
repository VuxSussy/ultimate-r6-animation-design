-- Offline checks for the skill's math. Run from tools/:  lune run check
local Env = require("./env")
local roblox = Env.roblox
local CFrame, Vector3 = roblox.CFrame, roblox.Vector3

local passed, failed = 0, 0
local function check(name, ok, detail)
	if ok then
		passed += 1
	else
		failed += 1
		print("FAIL " .. name .. (detail and ("  " .. tostring(detail)) or ""))
	end
end
local function near(a, b, eps)
	return math.abs(a - b) <= (eps or 1e-4)
end
local function deg(a, b)
	return math.deg(math.acos(math.clamp(a.Unit:Dot(b.Unit), -1, 1)))
end

-- every module compiles
for _, name in Env.list() do
	local ok, err = pcall(Env.compile, name)
	check("compiles " .. name, ok, err)
end

local R6Rig = Env.load("R6Rig")

-- rest pose: the stock R6 layout
do
	local w = R6Rig.fk({})
	check("rest torso", (w.Torso.Position - Vector3.zero).Magnitude < 1e-5)
	check("rest head", (w.Head.Position - Vector3.new(0, 1.5, 0)).Magnitude < 1e-5, w.Head.Position)
	check("rest right arm", (w["Right Arm"].Position - Vector3.new(1.5, 0, 0)).Magnitude < 1e-5, w["Right Arm"].Position)
	check("rest left arm", (w["Left Arm"].Position - Vector3.new(-1.5, 0, 0)).Magnitude < 1e-5, w["Left Arm"].Position)
	check("rest right leg", (w["Right Leg"].Position - Vector3.new(0.5, -2, 0)).Magnitude < 1e-5, w["Right Leg"].Position)
	check("rest left leg", (w["Left Leg"].Position - Vector3.new(-0.5, -2, 0)).Magnitude < 1e-5, w["Left Leg"].Position)
	check("reach arm", near(R6Rig.reach("Right Arm"), math.sqrt(0.5 ^ 2 + 1.5 ^ 2)), R6Rig.reach("Right Arm"))
	check("reach leg", near(R6Rig.reach("Left Leg"), math.sqrt(0.5 ^ 2 + 2 ^ 2)), R6Rig.reach("Left Leg"))
end

-- named angles mean what they say
do
	local function tipAfter(part, angles)
		local w = R6Rig.fk({ [part] = R6Rig.pose(part, angles) })
		return R6Rig.tip(part, w[part]), w
	end
	for _, arm in { "Right Arm", "Left Arm" } do
		local s = R6Rig.SIDE[arm]
		local tip = tipAfter(arm, { raise = 90 })
		check(arm .. " raise 90 points forward", tip.Z < -1.2 and math.abs(tip.Y - 0.5) < 0.6, tip)
		tip = tipAfter(arm, { spread = 90 })
		check(arm .. " spread 90 points outward", tip.X * s > 2.2, tip)
		tip = tipAfter(arm, { spread = 90, swing = 90 })
		check(arm .. " spread+swing points forward", tip.Z < -1.2, tip)
		tip = tipAfter(arm, { raise = 180 })
		check(arm .. " raise 180 points up", tip.Y > 1.5, tip)
	end
	for _, leg in { "Right Leg", "Left Leg" } do
		local s = R6Rig.SIDE[leg]
		local tip = tipAfter(leg, { raise = 90 })
		check(leg .. " raise 90 kicks forward", tip.Z < -1.5, tip)
		tip = tipAfter(leg, { spread = 45 })
		check(leg .. " spread goes outward", tip.X * s > 1.0, tip)
	end
	local _, w = tipAfter("Torso", { lean = 30 })
	check("torso lean 30 moves head forward", w.Head.Position.Z < -0.5, w.Head.Position)
	_, w = tipAfter("Torso", { twist = 45 })
	check("torso twist + turns left", w.Torso.LookVector.X < -0.5, w.Torso.LookVector)
	_, w = tipAfter("Torso", { tilt = 20 })
	check("torso tilt + leans right", w.Head.Position.X > 0.3, w.Head.Position)
	local face = tipAfter("Head", { nod = 30 })
	check("head nod + looks down", face.Y < 1.5 - 0.1, face)
	_, w = tipAfter("Head", { turn = 60 })
	check("head turn + looks left", w.Head.LookVector.X < -0.5, w.Head.LookVector)
	local _, w2 = tipAfter("Torso", { pos = { forward = 1, up = -0.5 } })
	check("torso pos offset", (w2.Torso.Position - Vector3.new(0, -0.5, -1)).Magnitude < 1e-5, w2.Torso.Position)
end

-- toTransform / fromTransform round trip
do
	local r = CFrame.Angles(0.3, -0.7, 0.2)
	for _, part in R6Rig.ORDER do
		local t = R6Rig.toTransform(part, r, Vector3.new(0.1, 0.2, 0.3))
		local back, offset = R6Rig.fromTransform(part, t)
		local _, angle = (back:Inverse() * r):ToAxisAngle()
		check("round trip " .. part, math.abs(angle) < 1e-5 and (offset - Vector3.new(0.1, 0.2, 0.3)).Magnitude < 1e-5)
	end
end

-- orient (the R15 converter's pointing math): the pivot->tip line runs along the asked direction
do
	local seed = 7
	local function rnd()
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed / 2147483648
	end
	local worst = 0
	for _ = 1, 300 do
		local torsoT = R6Rig.pose("Torso", { lean = rnd() * 80 - 40, twist = rnd() * 120 - 60, tilt = rnd() * 40 - 20 })
		local base = R6Rig.fk({ Torso = torsoT })
		for _, limb in R6Rig.LIMBS do
			local dir = Vector3.new(rnd() * 8 - 4, rnd() * 8 - 4, rnd() * 8 - 4)
			local t = R6Rig.orient(limb, base.Torso, dir)
			local w = R6Rig.fk({ Torso = torsoT, [limb] = t })
			local pivot = R6Rig.pivot(limb, w.Torso)
			worst = math.max(worst, deg(R6Rig.tip(limb, w[limb]) - pivot, dir))
		end
	end
	-- CFrames are float32 (in Roblox too), so a few hundredths of a degree is the floor.
	check("orient error < 0.1 deg", worst < 0.1, worst)
	check("no IK left in R6Rig", R6Rig.aim == nil and R6Rig.plant == nil and R6Rig.softDistance == nil)
end

-- pos slides a limb out of its socket without turning it, and gap reports exactly that
do
	for _, part in { "Right Arm", "Left Arm", "Right Leg", "Left Leg", "Head" } do
		local t = R6Rig.pose(part, { raise = part == "Head" and nil or 40, pos = { forward = 0.6, up = 0.2, right = -0.1 } })
		local g = R6Rig.gap(part, t)
		check("gap = pos " .. part, (g - Vector3.new(-0.1, 0.2, -0.6)).Magnitude < 1e-4, g)
		local turned = R6Rig.pose(part, { raise = part == "Head" and nil or 40 })
		check("rotation alone has no gap " .. part, R6Rig.gap(part, turned).Magnitude < 1e-4)
		local w0 = R6Rig.fk({ [part] = turned })
		local w1 = R6Rig.fk({ [part] = t })
		local moved = w1[part].Position - w0[part].Position
		check("pos moves the whole part " .. part, (moved - Vector3.new(-0.1, 0.2, -0.6)).Magnitude < 1e-4, moved)
	end
end

-- springs: exact for any step size, settle, no overshoot when critical
do
	local a = R6Rig.Spring.new(0, 3, 0.4)
	local b = R6Rig.Spring.new(0, 3, 0.4)
	a.target, b.target = 1, 1
	a:step(0.3)
	for _ = 1, 30 do
		b:step(0.01)
	end
	check("spring step-size independent", near(a.value, b.value, 1e-6), a.value - b.value)
	local c = R6Rig.Spring.new(0, 3, 1)
	c.target = 1
	local over = false
	for _ = 1, 200 do
		if c:step(1 / 60) > 1 + 1e-9 then
			over = true
		end
	end
	check("critical spring no overshoot", not over)
	check("critical spring settles", near(c.value, 1, 1e-3), c.value)
	local v = R6Rig.Spring.new(Vector3.zero, 4, 0.5)
	v.target = Vector3.new(1, 2, 3)
	for _ = 1, 240 do
		v:step(1 / 60)
	end
	check("vector spring settles", (v.value - Vector3.new(1, 2, 3)).Magnitude < 1e-3, v.value)
end

local extra = Env.fs.isFile("check_more.luau") and require("./check_more") or nil
if extra then
	local p, f = extra(Env, check)
end

print(string.format("[check] %d passed, %d failed", passed, failed))
if failed > 0 then
	error("checks failed", 0)
end
