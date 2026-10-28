-- SwordMoves: a right-handed sword slash for R6, made with the ultimate-r6-animation-design skill.
-- The sword sits in a Tool's default grip (RightGrip), so its blade stands out of the fist along
-- the arm's front: the blade tip is Vector3.new(0, -1, -BLADE) in the Right Arm's space.
--
-- Reference first (lune run study ... --tip="Right Arm:0,-1,-4"):
--   Creator Store "Slash Animations Testing for Soldier R6" (asset 127875309409617, rig + 1 clip):
--   0.667 s; chamber at f10, the blade crosses the centre line in front at f18 (45%), 7-frame
--   release, 7-frame hold, fastest 192 studs/s; at contact the torso is turned 43 degrees, leans
--   25 and the blade tip is 4.9 studs out.
--   "R6 Punch Animations Fighting Combo Moveset" (80460719695191) "Swing" clips: hit at 43-50%,
--   releases of 9-10 frames, but they turn the sword with their own Handle Motor6D (a weapon
--   joint), so only their timing was used.
-- The slash: upper right to lower left (a diagonal cut), body wound right, then turned through.

local R6Clip = require(script.Parent.R6Clip)
local CombatMoves = require(script.Parent.CombatMoves)

local SwordMoves = {}

local V = Vector3.new
local merge, leg = R6Clip.merge, CombatMoves.leg

SwordMoves.BLADE = 4
SwordMoves.TIP = V(0, -1, -SwordMoves.BLADE)

-- Sword guard: blade forward and up from the right hip, off hand open in front, a light sink.
SwordMoves.Guard = {
	Torso = { twist = -15, lean = 6, pos = { up = -0.3 } },
	Head = { nod = 5, turn = 6 },
	RightArm = { raise = 35, swing = 20, spread = 5, pos = { forward = 0.1 } },
	LeftArm = { raise = 55, swing = 30, spread = 5, pos = { forward = 0.1 } },
	LeftLeg = leg({ raise = 14, spread = 4, twist = -10 }),
	RightLeg = leg({ raise = -16, spread = 6, twist = -25 }),
}
local G = SwordMoves.Guard

function SwordMoves.SwordGuard()
	local c = R6Clip.new("SwordGuard", { loop = true, priority = "Idle" })
	c:key(0, G, "sineInOut")
	c:key(40, merge(G, { Torso = { lean = 7.5, pos = { up = -0.35 } }, RightArm = { raise = 38 }, Head = { nod = 6 } }), "sineInOut")
	c:key(80, G)
	c:lead("Head", -4)
	c:lead("RightArm", -2)
	c:lead("LeftArm", -3)
	c.meta = {}
	return c
end

function SwordMoves.SwordSlash()
	local c = R6Clip.new("SwordSlash")
	c:key(0, G, "snap") -- the press reads on the first frame

	-- wind up: body turned right and back, sword cocked behind the head, off hand out at the target
	local chamber = merge(G, {
		Torso = { twist = -40, lean = -4, pos = { up = -0.4, forward = -0.15 } },
		Head = { nod = 4, turn = 16 },
		RightArm = { raise = 165, spread = 35, swing = 0, pos = { forward = -0.1, up = 0.2 } },
		LeftArm = { raise = 80, swing = 25, spread = 0, pos = { forward = 0.2 } },
		LeftLeg = leg({ raise = 10, spread = 4, twist = -10 }),
		RightLeg = leg({ raise = -14, spread = 6, twist = -30 }),
	})
	c:key(9, chamber, "sineInOut")
	-- hang: keeps loading for two frames before the cut
	-- the cut accelerates into contact (the reference's blade peaks 3 frames before the hit)
	c:key(11, merge(chamber, { Torso = { twist = -43, lean = -5 }, RightArm = { raise = 168, spread = 37 } }), "quadIn")

	-- the cut passes overhead in front of the right shoulder, blade high
	c:key(14, merge(G, {
		Torso = { twist = -5, lean = 12, pos = { up = -0.42, forward = 0.2 } },
		Head = { nod = 6, turn = 4 },
		RightArm = { raise = 100, spread = 25, swing = 15, pos = { forward = 0.4 } },
		LeftArm = { raise = 40, swing = 20, spread = 10, pos = { forward = 0 } },
		LeftLeg = leg({ raise = 22, spread = 4, twist = -8 }),
		RightLeg = leg({ raise = -24, spread = 6, twist = -20, pos = { forward = -0.15 } }),
	}), "linear")

	-- contact: the blade crosses the centre line at chest height, 5.5 studs out; shoulder thrown in,
	-- off hand yanked back to the hip
	local contact = merge(G, {
		Torso = { twist = 35, lean = 24, pos = { up = -0.45, forward = 0.4 } },
		Head = { nod = 8, turn = -14 },
		RightArm = { raise = 55, spread = 5, swing = -25, pos = { forward = 0.6 } },
		LeftArm = { raise = -20, spread = 15, pos = { forward = -0.25 } },
		LeftLeg = leg({ raise = 30, spread = 5, twist = -5 }),
		RightLeg = leg({ raise = -30, spread = 7, twist = 10, pos = { forward = -0.25 } }),
	})
	c:key(17, contact, "sineInOut")

	-- follow-through: the blade keeps going down to the left, the body turns past, then holds
	local follow = merge(contact, {
		Torso = { twist = 55, lean = 28, pos = { up = -0.5, forward = 0.45 } },
		Head = { nod = 10, turn = -18 },
		RightArm = { raise = 5, spread = -5, swing = 45, pos = { forward = 0.5 } },
		LeftArm = { raise = -28, spread = 18 },
	})
	c:key(22, follow, { settle = 0.1 })
	c:key(29, merge(follow, { Torso = { twist = 58, lean = 29 }, RightArm = { swing = 48 } }), { recover = 0.12 })
	c:key(42, G)

	c:marker(17, "Hit")
	c:marker(29, "Cancel")
	c:lead("Torso", 1)
	c:lead("Head", -2)
	c:lead("LeftArm", -1)
	c.meta = {
		limb = "RightArm",
		tip = SwordMoves.TIP,
		arc = true,
		windup = { 0, 11 },
		strike = { 11, 17 },
		hit = 17,
		active = { 16, 20 },
		cancel = 29,
		hitstop = 0.09,
		damage = 1.4,
	}
	return c
end

SwordMoves.LIST = { "SwordGuard", "SwordSlash" }

function SwordMoves.build()
	local out = {}
	for _, name in SwordMoves.LIST do
		local c = SwordMoves[name]()
		out[name] = { clip = c, baked = c:bake(), meta = c.meta }
	end
	return out
end

return SwordMoves
