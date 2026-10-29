-- MageMoves: a two-handed fireball cast for R6, made with the ultimate-r6-animation-design skill's
-- new-move protocol (references/new-moves.md), not by reposing the kit's punches.
--
-- Reference sheet
--   1. "Human Spellcasting Animations FREE" (Kevin Iglesias, kevdev.itch.io), HumanM
--      MagicAttackDirect2H01: real mocap of a two-hand cast, converted to R6 with
--      `lune run mocap ... --action=HumanM@MagicAttackDirect2H01 --end=1.6 --in-place`.
--      Taken: the timing and every key pose below (frames 0-96 of the 1.6 s take).
--   2. The same pack, HumanF MagicAttackDirect2H01 (a second performance): confirms the timing
--      (release f43-48 in both) and the depth (lean 43-45, drop 0.58-0.68).
--   Left out: the take's looping tail after 1.6 s (a cyclic modifier in the file).
-- What the reference showed (not what a guess would have made): the cast is a throw from over
-- the head, not a push from the chest. Dip (f0-12), arms sweep up wide (f12-30), load behind the
-- head with the body arched back (f30-43), throw both hands forward and down in 4-5 frames while
-- the body folds 45 degrees and drops 0.7 stud (f43-54), hold (f54-62), stand back up (f62-96).
-- R6-ified on top: both palms pushed 0.6 stud out of the shoulders at the release, the arch and
-- the fold deepened by about 15%, legs on the pelvis and on the floor, the throw accelerating into
-- release.

local R6Clip = require(script.Parent.R6Clip)

local MageMoves = {}

local merge = R6Clip.merge

-- Key poses read from reference 1 at the phase boundaries (`lune run study ... --keys= --root-legs`:
-- legs on a square pelvis (`--hips=0`), grounded, exactly the reference's foot placement: the
-- performer's small hip turn crossed R6's 2-stud-wide hips into an X from the side).
local REF = {
	[0] = {
		Torso = { lean = -1, twist = 0.5, tilt = 1.4 },
		Head = { tilt = -3.3, nod = 7.7, turn = 0.2 },
		RightArm = { raise = 14.9, spread = 15.3, swing = 9.7 },
		LeftArm = { raise = 29.6, spread = 36, swing = 34.6 },
		RightLeg = { raise = -2.8, spread = 1, swing = -10, space = "root", ground = true, hips = 0, pos = { forward = 0.02, up = 0.01, right = -0.02 } },
		LeftLeg = { raise = -5.5, spread = 0.3, swing = -19.7, space = "root", ground = true, hips = 0, pos = { forward = 0.02, up = -0.01, right = -0.02 } },
	},
	[12] = {
		Torso = { lean = 8.2, twist = 3.3, tilt = -0.6, pos = { up = -0.13 } },
		Head = { tilt = -0.2, nod = 0.3 },
		RightArm = { raise = 16.4, spread = 12.5, swing = 9.6 },
		LeftArm = { raise = 31.3, spread = 19.8, swing = 22.3 },
		RightLeg = { raise = 1, spread = -1.6, swing = -10.9, space = "root", ground = true, hips = 0, pos = { forward = -0.14, up = 0.11, right = 0.02 } },
		LeftLeg = { raise = -1.2, spread = -0.1, swing = -20.7, space = "root", ground = true, hips = 0, pos = { forward = -0.14, up = 0.12, right = 0.02 } },
	},
	[18] = {
		Torso = { lean = 12.4, twist = 6.5, tilt = -0.8, pos = { up = -0.1 } },
		Head = { tilt = 1.7, nod = -6.8, turn = 0.2 },
		RightArm = { raise = 22.1, spread = 42.4, swing = 34.1 },
		LeftArm = { raise = 23.8, spread = 52, swing = 48.5 },
		RightLeg = { raise = 2.6, spread = -2.9, swing = -11.5, space = "root", ground = true, hips = 0, pos = { forward = -0.21, up = 0.07, right = 0.04 } },
		LeftLeg = { raise = 0.7, spread = -0.4, swing = -21.2, space = "root", ground = true, hips = 0, pos = { forward = -0.21, up = 0.1, right = 0.04 } },
	},
	[22] = {
		Torso = { lean = 13.4, twist = 9.2, tilt = -0.5, pos = { up = -0.07 } },
		Head = { tilt = 2.6, nod = -12.7, turn = 0.3 },
		RightArm = { raise = -9.7, spread = 80.2, swing = 48 },
		LeftArm = { raise = -19.3, spread = 84.7, swing = 54.8 },
		RightLeg = { raise = 2.9, spread = -3.5, swing = -11.6, space = "root", ground = true, hips = 0, pos = { forward = -0.23, up = 0.03, right = 0.05 } },
		LeftLeg = { raise = 1.1, spread = -0.4, swing = -21.3, space = "root", ground = true, hips = 0, pos = { forward = -0.23, up = 0.06, right = 0.05 } },
	},
	[26] = {
		Torso = { lean = 8.7, twist = 10.7, tilt = -0.5, pos = { up = -0.03 } },
		Head = { tilt = 3.3, nod = -13.3, turn = 0.2 },
		RightArm = { raise = -26, spread = 109.1, swing = 29.7 },
		LeftArm = { raise = -30.1, spread = 117.5, swing = 25.9 },
		RightLeg = { raise = 1, spread = -3.1, swing = -11, space = "root", ground = true, hips = 0, pos = { forward = -0.15, right = 0.04 } },
		LeftLeg = { raise = -0.8, swing = -20.7, space = "root", ground = true, hips = 0, pos = { forward = -0.15, up = 0.03, right = 0.04 } },
	},
	[30] = {
		Torso = { lean = -1.7, twist = 11.1, tilt = -0.4 },
		Head = { tilt = 4, nod = -5.3, turn = 0.1 },
		RightArm = { raise = -22.2, spread = 138, swing = 9.4 },
		LeftArm = { raise = -6.7, spread = 140.8, swing = 2.5 },
		RightLeg = { raise = -3.9, spread = -1.5, swing = -9.6, space = "root", ground = true, hips = 0, pos = { forward = 0.03, up = -0.03 } },
		LeftLeg = { raise = -6, spread = 0.7, swing = -19.6, space = "root", ground = true, hips = 0, pos = { forward = 0.03, up = -0.01 } },
	},
	[34] = {
		Torso = { lean = -12.9, twist = 11.3, tilt = -0.1, pos = { up = -0.01 } },
		Head = { tilt = 4.4, nod = 4.1 },
		RightArm = { raise = -9.6, spread = 157.4, swing = 0.7 },
		LeftArm = { raise = 4.4, spread = 152.8, swing = -0.7 },
		RightLeg = { raise = -8.8, spread = 0.4, swing = -8.5, space = "root", ground = true, hips = 0, pos = { forward = 0.22, up = -0.01, right = -0.04 } },
		LeftLeg = { raise = -11.3, spread = 1, swing = -18.4, space = "root", ground = true, hips = 0, pos = { forward = 0.22, up = -0.02, right = -0.04 } },
	},
	[38] = {
		Torso = { lean = -19.8, twist = 11.1, tilt = 0.1, pos = { up = -0.04 } },
		Head = { tilt = 4.4, nod = 8.5 },
		RightArm = { raise = -5.8, spread = 161.9 },
		LeftArm = { raise = 5.7, spread = 158.4, swing = -0.3 },
		RightLeg = { raise = -11.8, spread = 1.5, swing = -8, space = "root", ground = true, hips = 0, pos = { forward = 0.33, up = 0.01, right = -0.07 } },
		LeftLeg = { raise = -14.5, spread = 1.2, swing = -17.8, space = "root", ground = true, hips = 0, pos = { forward = 0.33, up = -0.01, right = -0.07 } },
	},
	[43] = {
		Torso = { lean = -14.3, twist = 14.1, tilt = -0.4, pos = { up = -0.1 } },
		Head = { tilt = 4.3, nod = 1.4 },
		RightArm = { raise = 8.6, spread = 168.5, swing = 1 },
		LeftArm = { raise = 25.1, spread = 159.1, swing = -1 },
		RightLeg = { raise = -8.4, spread = 0.2, swing = -4.4, space = "root", ground = true, hips = 0, pos = { forward = 0.24, up = 0.08, right = -0.05 } },
		LeftLeg = { raise = -5, spread = -0.8, swing = -16.2, space = "root", ground = true, hips = 0, pos = { forward = 0.24, up = 0.12, right = -0.05 } },
	},
	[47] = {
		Torso = { lean = 25.3, twist = 11.1, tilt = -0.4, pos = { up = -0.37 } },
		Head = { tilt = 4.5, nod = -18.3, turn = 0.1 },
		RightArm = { raise = -51.9, spread = 177, swing = -12.3 },
		LeftArm = { raise = -11.4, spread = 160.3, swing = 0.3 },
		RightLeg = { raise = 11.6, spread = -4.5, swing = -1.1, space = "root", ground = true, hips = 0, pos = { forward = -0.42, up = 0.29, right = 0.09 } },
		LeftLeg = { raise = 27, spread = -7.1, swing = -19.9, space = "root", ground = true, hips = 0, pos = { forward = -0.42, up = 0.11, right = 0.09 } },
	},
	[54] = {
		Torso = { lean = 44.6, twist = 8.3, tilt = -2, pos = { up = -0.66 } },
		Head = { tilt = 3.6, nod = -7.5, turn = 0.2 },
		RightArm = { raise = -47.2, spread = 175.7, swing = -10.5 },
		LeftArm = { raise = -44.9, spread = 163.9, swing = -1.6 },
		RightLeg = { raise = 19.2, spread = -6.7, swing = -3.8, space = "root", ground = true, hips = 0, pos = { forward = -0.69, up = 0.48, right = 0.14 } },
		LeftLeg = { raise = 35.4, spread = -11.8, swing = -25.2, space = "root", ground = true, hips = 0, pos = { forward = -0.69, up = 0.17, right = 0.14 } },
	},
	[62] = {
		Torso = { lean = 45, twist = 9.3, tilt = -1.2, pos = { up = -0.67 } },
		Head = { tilt = 2.3, nod = -1.5 },
		RightArm = { raise = -51.6, spread = 175.4, swing = -10.9 },
		LeftArm = { raise = -49.7, spread = 167.1, swing = -4.3 },
		RightLeg = { raise = 19.3, spread = -6.4, swing = -4.2, space = "root", ground = true, hips = 0, pos = { forward = -0.69, up = 0.49, right = 0.14 } },
		LeftLeg = { raise = 35.7, spread = -11.9, swing = -25.3, space = "root", ground = true, hips = 0, pos = { forward = -0.69, up = 0.18, right = 0.14 } },
	},
	[67] = {
		Torso = { lean = 42, twist = 8.1, tilt = -1.5, pos = { up = -0.6 } },
		Head = { tilt = 1.2, nod = -0.3 },
		RightArm = { raise = -60.2, spread = 170.8, swing = -8.1 },
		LeftArm = { raise = -57.5, spread = 165.3, swing = -3.2 },
		RightLeg = { raise = 17.5, spread = -6.5, swing = -6.8, space = "root", ground = true, hips = 0, pos = { forward = -0.66, up = 0.44, right = 0.12 } },
		LeftLeg = { raise = 34.5, spread = -11.3, swing = -24.6, space = "root", ground = true, hips = 0, pos = { forward = -0.66, up = 0.13, right = 0.12 } },
	},
	[72] = {
		Torso = { lean = 35.3, twist = 5.6, tilt = -1.8, pos = { up = -0.47 } },
		Head = { tilt = -0.5, nod = 0.8 },
		RightArm = { raise = -61.9, spread = 103.4, swing = 54.9 },
		LeftArm = { raise = -65.8, spread = 126.4, swing = 32.8 },
		RightLeg = { raise = 13.5, spread = -6, swing = -10.8, space = "root", ground = true, hips = 0, pos = { forward = -0.57, up = 0.35, right = 0.09 } },
		LeftLeg = { raise = 32, spread = -10.2, swing = -22.9, space = "root", ground = true, hips = 0, pos = { forward = -0.57, up = 0.07, right = 0.09 } },
	},
	[76] = {
		Torso = { lean = 27.9, twist = 3, tilt = -1.6, pos = { up = -0.35 } },
		Head = { tilt = -1.8, nod = 1.7, turn = -0.1 },
		RightArm = { raise = 17, spread = 67.4, swing = 75.9 },
		LeftArm = { raise = -30.5, spread = 79.9, swing = 73.9 },
		RightLeg = { raise = 9.9, spread = -4.6, swing = -12.7, space = "root", ground = true, hips = 0, pos = { forward = -0.47, up = 0.27, right = 0.05 } },
		LeftLeg = { raise = 28.8, spread = -9, swing = -21.1, space = "root", ground = true, hips = 0, pos = { forward = -0.46, up = 0.01, right = 0.05 } },
	},
	[79] = {
		Torso = { lean = 21.9, twist = 1.1, tilt = -1.2, pos = { up = -0.27 } },
		Head = { tilt = -2.7, nod = 2.4, turn = -0.1 },
		RightArm = { raise = 40.2, spread = 46.1, swing = 53.6 },
		LeftArm = { raise = 6.2, spread = 69.6, swing = 72.6 },
		RightLeg = { raise = 7.1, spread = -3.2, swing = -12.7, space = "root", ground = true, hips = 0, pos = { forward = -0.37, up = 0.22, right = 0.03 } },
		LeftLeg = { raise = 25.9, spread = -8, swing = -19.6, space = "root", ground = true, hips = 0, pos = { forward = -0.37, up = -0.02, right = 0.03 } },
	},
	[84] = {
		Torso = { lean = 12.2, twist = -1.4, tilt = -0.2, pos = { up = -0.15 } },
		Head = { tilt = -3.6, nod = 3.9, turn = -0.1 },
		RightArm = { raise = 31.9, spread = 22.4, swing = 24.5 },
		LeftArm = { raise = 27.8, spread = 55.1, swing = 57.6 },
		RightLeg = { raise = 3.1, spread = -1, swing = -11.5, space = "root", ground = true, hips = 0, pos = { forward = -0.21, up = 0.14 } },
		LeftLeg = { raise = 18.3, spread = -5.8, swing = -17.7, space = "root", ground = true, hips = 0, pos = { forward = -0.21 } },
	},
	[90] = {
		Torso = { lean = 2.9, twist = -0.7, tilt = 1.1, pos = { up = -0.06 } },
		Head = { tilt = -3.6, nod = 6.4 },
		RightArm = { raise = 17.1, spread = 16, swing = 11.4 },
		LeftArm = { raise = 33.1, spread = 41, swing = 42.7 },
		RightLeg = { raise = -1.3, spread = 0.6, swing = -10.4, space = "root", ground = true, hips = 0, pos = { forward = -0.05, up = 0.06, right = -0.02 } },
		LeftLeg = { raise = 2.4, spread = -1.8, swing = -18.3, space = "root", ground = true, hips = 0, pos = { forward = -0.05, up = 0.06, right = -0.02 } },
	},
	[96] = {
		Torso = { lean = -1, twist = 0.5, tilt = 1.4 },
		Head = { tilt = -3.3, nod = 7.7, turn = 0.2 },
		RightArm = { raise = 14.9, spread = 15.3, swing = 9.7 },
		LeftArm = { raise = 29.6, spread = 36, swing = 34.6 },
		RightLeg = { raise = -2.8, spread = 1, swing = -10, space = "root", ground = true, hips = 0, pos = { forward = 0.02, up = 0.01, right = -0.02 } },
		LeftLeg = { raise = -5.5, spread = 0.3, swing = -19.7, space = "root", ground = true, hips = 0, pos = { forward = 0.02, up = -0.01, right = -0.02 } },
	},
}

-- R6 touches per key: deeper arch and fold, palms out of the shoulders, honest feet
local TOUCH = {
	[38] = { Torso = { lean = -24 } },
	[43] = { Torso = { lean = -18 } },
	[47] = { Torso = { lean = 30, pos = { up = -0.42 } }, RightArm = { pos = { forward = 0.6 } }, LeftArm = { pos = { forward = 0.6 } } },
	[54] = { Torso = { lean = 52, pos = { up = -0.76 } }, RightArm = { pos = { forward = 0.6 } }, LeftArm = { pos = { forward = 0.6 } } },
	[62] = { Torso = { lean = 51, pos = { up = -0.74 } }, RightArm = { pos = { forward = 0.5 } }, LeftArm = { pos = { forward = 0.5 } } },
	[72] = { RightArm = { pos = { forward = 0.2 } }, LeftArm = { pos = { forward = 0.2 } } },
}

-- the ease leaving each key
local EASE = {
	[0] = "sineInOut", -- dip
	[12] = "sineInOut", -- arms start up
	[18] = "linear",
	[22] = "linear", -- sweep up through
	[26] = "linear",
	[30] = "sineInOut", -- arch back
	[34] = "sineInOut",
	[38] = "sineInOut", -- hang at the top of the load
	[43] = "quadIn", -- the throw accelerates into release (a long lever: do not snap out of the hang)
	[47] = "sineInOut", -- the fold keeps going
	[54] = "sineInOut", -- hold
	[62] = "sineInOut",
	[67] = "linear", -- the arms swing a wide arc on the way back: keys every few frames follow it
	[72] = "linear",
	[76] = "linear",
	[79] = "linear",
	[84] = "sineInOut",
	[90] = "sineInOut",
}

function MageMoves.MageFireball(opts)
	opts = opts or {}
	local c = R6Clip.new("MageFireball")
	for frame, pose in REF do
		local p = opts.raw and pose or merge(pose, TOUCH[frame] or {})
		c:key(frame, p, EASE[frame])
	end
	c:marker(47, "Cast") -- spawn the fireball here
	c:marker(72, "Cancel")
	c.meta = {
		overhead = true, -- the load reaches back over the head on purpose
		windup = { 0, 43 },
		strike = { 43, 54 },
		cast = 47,
		cancel = 72,
	}
	return c
end

MageMoves.LIST = { "MageFireball" }

function MageMoves.build()
	local out = {}
	for _, name in MageMoves.LIST do
		local c = MageMoves[name]()
		out[name] = { clip = c, baked = c:bake(), meta = c.meta }
	end
	return out
end

return MageMoves
