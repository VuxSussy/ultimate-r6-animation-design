-- Original heavy choreography after watching Capcom Great Sword and DS3 Greatsword footage.
local Clip = require(script.Parent.R6Clip)
local M = {}
M.PACK = "HeavySwordCombo4"
M.TIP = Vector3.new(0, -1, -5.5)
M.REFERENCE = {
	brief = "slash-reference.json",
	visualBrief = "heavy-reference.json",
	adaptations = "Observed Capcom Great Sword low finish/lift and DS3 Greatsword whole-body load, broad release and counter-load; see timestamped heavy-reference.json. SwordSlash supplies only measured R6 mechanics. Original poses with deliberate phase-specific support-hand release; not commercial keys or a frame retarget. Retimed post-hit travel/recovery for visible mass, subject to R6 floor/body/grip checks.",
}
M.WEAPON = {
	name = "HeavyGreatsword",
	archetype = "heavy",
	parent = "Right Arm",
	grip = CFrame.new(0, -1, 0),
	tip = { 0, 0, -5.5 },
	offhand = { part = "Left Arm", point = { 0, 0, 0.65 }, maxError = 0.42 },
	geometry = {
		{ name = "Grip", size = { 0.22, 0.22, 1.4 }, cf = CFrame.new(0, 0, 0.4), color = { 0.16, 0.19, 0.24 } },
		{ name = "Pommel", size = { 0.4, 0.4, 0.3 }, cf = CFrame.new(0, 0, 1.15), color = { 0.67, 0.52, 0.3 } },
		{ name = "Guard", size = { 1.9, 0.23, 0.2 }, cf = CFrame.new(0, 0, -0.35), color = { 0.67, 0.52, 0.3 } },
		{ name = "Blade", size = { 0.85, 0.2, 4.5 }, cf = CFrame.new(0, 0, -2.7), color = { 0.67, 0.74, 0.83 } },
		{
			name = "BladePoint",
			size = { 0.58, 0.18, 0.55 },
			cf = CFrame.new(0, 0, -5.225),
			color = { 0.77, 0.84, 0.91 },
		},
		{ name = "Fuller", size = { 0.15, 0.215, 4.15 }, cf = CFrame.new(0, 0, -2.7), color = { 0.3, 0.4, 0.52 } },
	},
}
local function leg(a)
	a.space = "root"
	a.ground = true
	a.hips = 0.22
	return a
end
local function held(twist, lean, up, lunge, raise, swing, slide, front, rear)
	return {
		Torso = { twist = twist, lean = lean, pos = { up = up, forward = lunge } },
		Head = { turn = -twist * 0.45, nod = lean * 0.2 },
		RightArm = {
			raise = raise,
			spread = -55,
			swing = swing,
			pos = { forward = slide + swing * 0.015, right = -0.06 },
		},
		LeftArm = {
			raise = raise - 22,
			spread = -55,
			swing = -swing,
			pos = {
				forward = slide - 0.05 - swing * 0.015,
				right = 0.06 + math.abs(swing) * 0.009,
				up = -0.16 * math.sin(math.rad(raise + 20)),
			},
		},
		LeftLeg = leg({ raise = front, spread = 10, twist = -8 }),
		RightLeg = leg({ raise = rear, spread = 11, twist = -18, pos = { forward = -0.1 } }),
	}
end
local function released(p)
	p.RightArm.spread = 18
	p.RightArm.pos = { forward = 0.1 }
	p.LeftArm = { raise = -35, spread = 35, swing = -25, pos = { forward = -0.15 } }
	return p
end
local G = released(held(-15, 6, -0.025, 0, -8, 0, 0.1, 9, -10))
local dragL = released(held(78, 20, -0.025, 0.34, 3, 20, 0.1, 18, -18))
local dragR = released(held(-78, 18, -0.025, 0.3, 1, -15, 0.1, 18, -18))
M.Guard = G
local function begin(name, start)
	local c = Clip.new(name)
	c:key(0, start, "sineInOut")
	c:key(3, start, "sineInOut")
	return c
end
local function finish(c, grip, load, hit, follow, recoverEnd, stop)
	c:marker(grip, "Grip")
	c:marker(hit + 4, "Release")
	c:marker(load, "TrailOn")
	c:marker(hit, "Hit")
	c:marker(follow, "TrailOff")
	c:marker(follow, "Overswing")
	c:marker(recoverEnd - 10, "Cancel")
	c:lead("Head", -2)
	c.meta = {
		limb = "RightArm",
		tip = M.TIP,
		arc = true,
		contactHeight = { -2, 2 },
		overhead = true,
		strike = { load, hit },
		hit = hit,
		hitstop = stop,
		gripWindows = { { grip, hit + 4 } },
		heavy = {
			gripStyle = "regrip",
			load = load,
			followThrough = follow,
			recoverEnd = recoverEnd,
			minLoad = 20,
			minPostArc = 65,
			minBodyTurn = 85,
			minPostBodyTurn = 30,
			minRecovery = 20,
			minReleaseDistance = 0.8,
		},
	}
	return c
end
function M.Heavy01_Diagonal()
	local c = begin("Heavy01_Diagonal", G)
	c:key(10, released(held(-32, 5, -0.025, -0.05, 25, -10, 0.1, 10, -12)), "sineInOut")
	c:key(22, held(-52, -5, -0.02, -0.1, 140, -8, 0.08, 10, -12), "sineInOut")
	local load = held(-62, -6, -0.025, -0.1, 155, -10, 0.08, 10, -13)
	c:key(29, load, "sineInOut")
	c:key(32, load, "quadIn")
	c:key(36, held(-12, 12, -0.04, 0.16, 95, -10, 0.23, 15, -16), "linear")
	local hit = held(35, 24, -0.055, 0.44, 32, -38.3, 0.3, 18, -19)
	c:key(40, hit, "sineInOut")
	c:key(44, hit, "sineInOut")
	c:key(66, dragL, "sineInOut")
	c:key(76, dragL, "sineInOut")
	c:key(102, dragL)
	return finish(c, 22, 32, 40, 66, 102, 0.12)
end
function M.Heavy02_ReturnSweep()
	local c = begin("Heavy02_ReturnSweep", dragL)
	c:key(18, held(62, 12, -0.025, 0.16, 32, 20, 0.08, 14, -16), "sineInOut")
	local load = held(65, 10, -0.025, 0.08, 30, 25, 0.1, 13, -15)
	c:key(25, load, "sineInOut")
	c:key(28, load, "quadIn")
	c:key(34, held(5, 18, -0.04, 0.28, 28, 10, 0.3, 17, -18), "linear")
	local hit = held(-35, 20, -0.045, 0.44, 28, 41, 0.35, 18, -19)
	c:key(40, hit, "sineInOut")
	c:key(44, hit, "sineInOut")
	c:key(66, dragR, "sineInOut")
	c:key(78, dragR, "sineInOut")
	c:key(104, dragR)
	return finish(c, 18, 28, 40, 66, 104, 0.13)
end
function M.Heavy03_Rising()
	local c = begin("Heavy03_Rising", dragR)
	c:key(22, held(-62, 13, -0.025, 0.02, 16, -8, 0.05, 15, -17), "sineInOut")
	local load = held(-65, 14, -0.025, 0, 16, -8, 0.05, 15, -17)
	c:key(27, load, "sineInOut")
	c:key(30, load, "quadIn")
	c:key(37, held(-8, 18, -0.04, 0.26, 27, -5, 0.25, 17, -18), "linear")
	local hit = held(35, 18, -0.04, 0.44, 40, -40, 0.3, 18, -19)
	c:key(44, hit, "sineInOut")
	c:key(48, hit, "sineInOut")
	c:key(72, released(held(78, -3, -0.015, 0.34, 130, 8, 0.1, 14, -16)), "sineInOut")
	c:key(88, dragL, "sineInOut")
	c:key(110, dragL)
	return finish(c, 22, 30, 44, 72, 110, 0.14)
end
function M.Heavy04_OverheadCleave()
	local c = begin("Heavy04_OverheadCleave", dragL)
	c:key(16, released(held(30, 4, -0.02, 0.06, 45, 0, 0.1, 12, -14)), "sineInOut")
	c:key(28, held(-40, -4, -0.02, -0.05, 135, 0, 0.08, 12, -14), "sineInOut")
	local load = held(-60, -8, -0.015, -0.12, 165, 5, 0.06, 11, -14)
	c:key(37, load, "sineInOut")
	c:key(42, load, "quadIn")
	c:key(50, held(-12, 14, -0.04, 0.25, 92, -5, 0.3, 16, -18), "linear")
	local hit = held(35, 27, -0.05, 0.62, 36, -40, 0.32, 19, -20)
	c:key(58, hit, "sineInOut")
	c:key(62, hit, "sineInOut")
	c:key(86, dragL, "sineInOut")
	c:key(104, dragL, { recover = 0.1 })
	c:key(134, G, "sineInOut")
	c:key(136, G)
	return finish(c, 28, 42, 58, 86, 136, 0.18)
end
M.LIST = { "Heavy01_Diagonal", "Heavy02_ReturnSweep", "Heavy03_Rising", "Heavy04_OverheadCleave" }
function M.build()
	local out = {}
	for _, name in M.LIST do
		local c = M[name]()
		out[name] = { clip = c, baked = c:bake(), meta = c.meta }
	end
	return out
end
return M
