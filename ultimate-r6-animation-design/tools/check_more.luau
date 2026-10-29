-- Checks for Ease, Sequence, R6Clip, R6Study, CombatMoves and R15ToR6. Loaded by check.luau.
return function(Env, check)
	local roblox = Env.roblox
	local CFrame, Vector3, Instance, Enum = roblox.CFrame, roblox.Vector3, roblox.Instance, roblox.Enum
	local R6Rig = Env.load("R6Rig")
	local Ease = Env.load("Ease")
	local Sequence = Env.load("Sequence")
	local R6Clip = Env.load("R6Clip")
	local CombatMoves = Env.load("CombatMoves")
	local R15ToR6 = Env.load("R15ToR6")

	-- easing: every curve starts at 0 and ends at 1
	for _, spec in { "linear", "snap", "settle", "recover", "smooth", "cubicInOut", "backOut", "elasticOut", "bounceOut", "expoIn", { bezier = { 0.42, 0, 0.58, 1 } }, { settle = 0.2 }, { back = 2 } } do
		local f = Ease.get(spec)
		local name = type(spec) == "table" and "table" or spec
		check("ease ends " .. name, math.abs(f(0)) < 1e-6 and math.abs(f(1) - 1) < 1e-6, string.format("%g %g", f(0), f(1)))
	end
	do
		local f = Ease.get("settle")
		local peak = 0
		for i = 0, 100 do
			peak = math.max(peak, f(i / 100))
		end
		check("settle overshoots about 12%", peak > 1.08 and peak < 1.16, peak)
		local r = Ease.get("recover")
		check("recover starts slow", r(0.1) < 0.02, r(0.1))
	end

	-- shortest-path blending even when ToAxisAngle reports more than 180 degrees
	do
		local a = CFrame.identity
		local b = CFrame.Angles(0, math.rad(200), 0)
		local mid = Sequence.blend(a, b, 0.5)
		check("blend takes the short way", math.abs(Sequence.angleBetween(a, mid) - 80) < 0.5, Sequence.angleBetween(a, mid))
	end

	-- every move audits clean, and KeyframeSequence export round-trips
	local moves = CombatMoves.build()
	for _, name in CombatMoves.LIST do
		local m = moves[name]
		local audit = R6Clip.audit(m.baked, m.meta)
		check("audit " .. name, audit.ok, table.concat(audit.notes, "; "))
		local ks = R6Clip.toKeyframeSequence(m.baked)
		local seq = Sequence.read(ks)
		local worst = 0
		for _, fr in m.baked.frames do
			local sample = Sequence.sample(seq, fr.time)
			for _, part in R6Rig.ORDER do
				worst = math.max(worst, Sequence.angleBetween(sample[part] or CFrame.identity, fr.transforms[part]))
			end
		end
		check("keyframes reproduce " .. name .. " within 0.5 deg", worst < 0.5, worst)
		local keys = #ks:GetChildren()
		check("keyframes no more than frames " .. name, keys <= #m.baked.frames + #m.baked.markers, string.format("%d of %d", keys, #m.baked.frames))
		local eclipse = R6Clip.toEclipse(m.baked)
		check("eclipse json " .. name, #eclipse.keyframes > 1 and eclipse.keyframes[1].poses.Torso ~= nil)
	end
	do
		local ks = R6Clip.toKeyframeSequence(moves.Jab.baked)
		local seq = Sequence.read(ks)
		check("markers survive", #seq.markers == 2 and seq.markers[1].name == "Hit", #seq.markers)
		check("priority survives", seq.priority == "Action", seq.priority)
		local stepped = R6Clip.toKeyframeSequence(CombatMoves.Jab():bake({ step = 5, stepped = true }))
		local style = nil
		for _, d in stepped:GetDescendants() do
			if d.ClassName == "Pose" and d.Weight > 0 then
				style = tostring(d.EasingStyle)
				break
			end
		end
		check("stepped export uses Constant", style and string.find(style, "Constant") ~= nil, style)
	end

	-- the punches commit like the R6 references: fist 2.3-4.2 studs out, torso turned 30-110 in,
	-- the striking shoulder pushed 0.5-1.4 out of its socket (all inside the "short" budget, <= 1)
	for _, name in { "Jab", "Cross" } do
		local m = moves[name]
		local audit = R6Clip.audit(m.baked, m.meta)
		local limb = m.meta.limb == "LeftArm" and "Left Arm" or "Right Arm"
		local summary = string.format("reach %.2f twist %.0f gap %.2f", audit.metrics.reachAtHit or 0, audit.metrics.twistAtHit or 0, audit.metrics.gap[limb])
		print("[" .. name .. "] " .. summary)
		check(name .. " fist ends 2.8+ studs in front", (audit.metrics.reachAtHit or 0) >= 2.8, summary)
		check(name .. " torso turns 40+ into it", math.abs(audit.metrics.twistAtHit or 0) >= 40, summary)
		check(name .. " shoulder leaves the socket 0.5-1.0", audit.metrics.gap[limb] >= 0.5 and audit.metrics.gap[limb] <= 1.0, summary)
	end

	-- the power jab against the references, frame by frame at 60 fps
	--   load    "cross punch" short: chamber held 8-10; the YouTube combat system's M1s: wind-up 4
	--   release cross 2-4, YouTube combat system 6-8, Creator Store punch packs 4-9 (to 90% travel)
	--   hold    at least 6; back no more than 10; lean at least 20
	do
		local p = R6Clip.profile(moves.Jab.baked, "LeftArm")
		local summary = string.format("load %d release %d hold %d back %d lean %.0f rearPull %.2f", p.load, p.release, p.hold, p.back, p.lean, p.rearPull)
		print("[jab profile] " .. summary)
		check("jab load 4-10 frames (references 4-10)", p.load >= 4 and p.load <= 10, summary)
		check("jab release 2-5 frames (references 2-9, jab at the fast end)", p.release >= 2 and p.release <= 5, summary)
		check("jab hold at least 6 frames (references 6-18)", p.hold >= 6, summary)
		check("jab snaps home within 12 frames", p.back <= 12, summary)
		check("jab body leans at least 20 deg at the extreme", p.lean >= 20, summary)
	end

	-- the audit catches a timid punch and an arm thrown too far out
	do
		local G = CombatMoves.Guard
		local timid = R6Clip.new("Timid")
		timid:key(0, G)
		timid:key(8, R6Clip.merge(G, { LeftArm = { raise = 95, swing = 0 } }), "snap")
		timid:key(16, R6Clip.merge(G, { LeftArm = { raise = 95, swing = 0 } }))
		timid:key(30, G)
		timid:marker(8, "Hit")
		local a = R6Clip.audit(timid:bake(), { limb = "LeftArm", strike = { 0, 8 } })
		local found = false
		for _, n in a.notes do
			found = found or string.find(n, "^commit") ~= nil
		end
		check("audit flags a timid punch", found, table.concat(a.notes, "; "))
		local far = R6Clip.new("Far")
		far:key(0, G)
		far:key(10, R6Clip.merge(G, { LeftArm = { pos = { forward = 1.6 } } }))
		local b = R6Clip.audit(far:bake(), {})
		local over = false
		for _, n in b.notes do
			over = over or string.find(n, "^gap: Left Arm") ~= nil
		end
		check("audit flags an arm past its budget", over, table.concat(b.notes, "; "))
		local wide = R6Clip.new("Wide", { budget = { LeftArm = 2 } })
		wide:key(0, G)
		wide:key(10, R6Clip.merge(G, { LeftArm = { pos = { forward = 1.6 } } }))
		check("clip budget raises the limit", R6Clip.audit(wide:bake(), {}).metrics.gap["Left Arm"] > 1.5 and R6Clip.audit(wide:bake(), {}).ok)
	end

	-- the crossed-legs case the user caught on the first Cross: a 60-degree torso twist over a staggered
	-- stance, with the hips turning all the way, crosses the legs into an X (the audit says so); the
	-- default pelvis (35% of the turn, sockets slid under it) keeps them a leg's width apart
	do
		local function stance(space, hips)
			local c = R6Clip.new("Twist")
			local legs = {
				LeftLeg = { raise = 24, space = space, ground = true, hips = hips },
				RightLeg = { raise = -30, space = space, ground = true, hips = hips },
			}
			c:key(0, R6Clip.merge(legs, { Torso = { twist = -45, pos = { up = -0.4 } } }), "snap")
			c:key(6, R6Clip.merge(legs, { Torso = { twist = 60, lean = 22, pos = { up = -0.45, forward = 0.6 } } }))
			c:key(20, R6Clip.merge(legs, { Torso = { twist = -25, pos = { up = -0.35 } } }))
			return R6Clip.audit(c:bake(), {})
		end
		-- hips = 1: the old behaviour, hips swapping front-to-back with a rigid root-space leg angle
		local bad, good = stance("root", 1), stance("root")
		local flagged = false
		for _, n in bad.notes do
			flagged = flagged or string.find(n, "^legs:") ~= nil
		end
		check("audit flags crossing legs", flagged, string.format("%.2f", bad.metrics.legGap))
		check("root-space legs never cross", good.metrics.legGap >= 0.75, string.format("%.2f", good.metrics.legGap))
	end

	-- locomotion: every clip audits clean, and the walk's second half mirrors its first
	do
		local Locomotion = Env.load("Locomotion")
		local loco = Locomotion.build()
		for _, name in Locomotion.LIST do
			local audit = R6Clip.audit(loco[name].baked, loco[name].meta)
			check("audit " .. name, audit.ok, table.concat(audit.notes, "; "))
		end
		local frames = loco.Walk.baked.frames
		local a, b = R6Rig.fk(frames[1].transforms), R6Rig.fk(frames[26].transforms)
		local tipL, tipR = R6Rig.tip("Left Leg", a["Left Leg"]), R6Rig.tip("Right Leg", b["Right Leg"])
		check("walk is mirror-symmetric", (tipL - Vector3.new(-tipR.X, tipR.Y, tipR.Z)).Magnitude < 0.02, (tipL - Vector3.new(-tipR.X, tipR.Y, tipR.Z)).Magnitude)
		-- the back dash ends low, kneeling: body down a stud, one sole in front and one behind
		local back = CombatMoves.DashBack():bake()
		local w = R6Rig.fk(back.frames[21].transforms)
		local front, rear = R6Rig.tip("Left Leg", w["Left Leg"]), R6Rig.tip("Right Leg", w["Right Leg"])
		check("back dash kneels", w.Torso.Position.Y < -0.9 and front.Z < -1 and rear.Z > 1.5, string.format("%.2f %.2f %.2f", w.Torso.Position.Y, front.Z, rear.Z))
	end

	-- the arms come home the way they left: after a dash flings them back, the recovery brings them
	-- down and forward to the guard, never up and over the head (a rotation blend of more than 180
	-- degrees takes the short way round, backwards over the shoulder; R6Clip interpolates the angles)
	for _, name in { "DashBack", "DashForward", "DashLeft", "DashRight" } do
		local b = CombatMoves[name]():bake()
		local over, at, arm = -math.huge, 0, ""
		for i, fr in b.frames do
			if i > 12 then
				local w = R6Rig.fk(fr.transforms)
				for _, part in { "Left Arm", "Right Arm" } do
					-- over the head = above the shoulders AND behind the back at once
					local local_ = w.Torso:PointToObjectSpace(R6Rig.tip(part, w[part]))
					local score = math.min(local_.Y - 1, local_.Z - 0.3)
					if score > over then
						over, at, arm = score, fr.frame, part
					end
				end
			end
		end
		check(name .. " arms never swing over the head on the way back", over < 0, string.format("%s fist %.2f above and behind the shoulders at f%d", arm, over, at))
	end

	-- the audit catches the long way round where it can still happen (raw transforms blend by the
	-- shortest rotation), and named-angle keys of the same poses come home the right way
	do
		local back = { raise = -55, spread = 25 }
		local guard = { raise = 150, swing = 62 }
		local raw = R6Clip.new("Raw")
		raw:key(0, { RightArm = { transform = R6Rig.pose("Right Arm", back) } })
		raw:key(14, { RightArm = { transform = R6Rig.pose("Right Arm", guard) } })
		local flagged = false
		for _, n in R6Clip.audit(raw:bake(), { airborne = true }).notes do
			flagged = flagged or string.find(n, "^overhead") ~= nil
		end
		check("audit flags an arm swinging over the head", flagged)
		local named = R6Clip.new("Named")
		named:key(0, { RightArm = back })
		named:key(14, { RightArm = guard })
		local a = R6Clip.audit(named:bake(), { airborne = true })
		check("named angles bring the arm home under, not over", a.ok, table.concat(a.notes, "; "))
	end

	-- reading angles back out of a pose stays continuous: an arm overhead is not "swing 179" next
	-- to "swing -179" (which, interpolated, would spin it a full turn)
	do
		local R6Study = Env.load("R6Study")
		local prev
		local worstJump = 0
		for i = 0, 40 do
			local raise = 120 + i * 1.5 -- up past vertical
			local e = R6Study.entry("Right Arm", R6Rig.pose("Right Arm", { raise = raise, spread = 20, swing = -5 }), prev)
			if prev then
				for _, k in { "raise", "spread", "swing" } do
					worstJump = math.max(worstJump, math.abs(e[k] - prev[k]))
				end
			end
			prev = e
		end
		check("study angles stay continuous through an overhead arm", worstJump < 10, worstJump)
	end

	-- a held weapon strikes from its own tip: meta.tip moves the contact and sweep checks out to it
	do
		local G = CombatMoves.Guard
		local c = R6Clip.new("Thrust")
		c:key(0, G)
		c:key(8, R6Clip.merge(G, { Torso = { twist = -50, lean = 22, pos = { forward = 0.5, up = -0.4 } }, LeftArm = { raise = 90, swing = -32, pos = { forward = 0.7 } } }), "snap")
		c:key(16, R6Clip.merge(G, { Torso = { twist = -50, lean = 22, pos = { forward = 0.5, up = -0.4 } }, LeftArm = { raise = 90, swing = -32, pos = { forward = 0.7 } } }))
		c:key(30, G)
		c:marker(8, "Hit")
		local b = c:bake()
		local bare = R6Clip.audit(b, { limb = "LeftArm", strike = { 0, 8 } }).metrics.reachAtHit
		-- a spear held along the arm reaches 4 studs past the fist, times how straight forward the arm
		-- points (the torso is turned and leaning, so a little less than 4)
		local armed = R6Clip.audit(b, { limb = "LeftArm", strike = { 0, 8 }, tip = Vector3.new(0, -5, 0) }).metrics.reachAtHit
		check("meta.tip measures from the weapon", armed and bare and armed - bare > 3 and armed - bare <= 4.01, string.format("%.2f vs %.2f", armed or 0, bare or 0))
		local R6Study = Env.load("R6Study")
		local seq = Sequence.read(R6Clip.toKeyframeSequence(b))
		local plain = R6Study.measure(seq)
		local withTip = R6Study.measure(seq, { tips = { ["Left Arm"] = Vector3.new(0, -1, -4) } })
		check("study sweeps follow the weapon tip", withTip.sweeps["Left Arm"].fastest > plain.sweeps["Left Arm"].fastest)
	end

	-- mocap -> R6: a human T-pose stands the R6 straight with arms level; a crouch keeps the soles on
	-- the floor by riding the legs into the torso; a fist pushed forward points the R6 arm forward;
	-- the feet stay as far apart as the R6 hips (no crossing)
	do
		local MocapToR6 = Env.load("MocapToR6")
		local function body(drop, rightFist)
			local hipY = -1 - drop
			local P = {
				Pelvis = { 0, hipY + 0.1, 0 },
				LeftHip = { -0.2, hipY, 0 }, RightHip = { 0.2, hipY, 0 },
				LeftKnee = { -0.2, hipY - 1 + drop / 2, -drop }, RightKnee = { 0.2, hipY - 1 + drop / 2, -drop },
				LeftAnkle = { -0.2, -2.87, 0 }, RightAnkle = { 0.2, -2.87, 0 },
				LeftToe = { -0.2, -3, -0.27 }, RightToe = { 0.2, -3, -0.27 },
				LeftShoulder = { -0.4, hipY + 1.1, 0 }, RightShoulder = { 0.4, hipY + 1.1, 0 },
				LeftElbow = { -1.0, hipY + 1.1, 0 }, RightElbow = { 1.0, hipY + 1.1, 0 },
				LeftFist = { -1.8, hipY + 1.1, 0 }, RightFist = rightFist or { 1.8, hipY + 1.1, 0 },
				Neck = { 0, hipY + 1.3, 0 }, HeadTop = { 0, hipY + 1.85, 0 },
			}
			return P
		end
		local doc = { fps = 30, frames = {
			{ t = 0, points = body(0) },
			{ t = 0.5, points = body(0.6, { 0.4, -1.6 + 1.1, -1.4 }) },
		} }
		local baked = MocapToR6.convert(doc, { name = "MocapTest" })
		local w0 = R6Rig.fk(baked.frames[1].transforms)
		local w1 = R6Rig.fk(baked.frames[#baked.frames].transforms)
		local tip = R6Rig.tip("Left Arm", w0["Left Arm"])
		local pivot = R6Rig.pivot("Left Arm", w0.Torso)
		check("mocap T-pose: arm level", math.abs(tip.Y - pivot.Y) < 0.05 and tip.X < pivot.X - 1.4, tip)
		local worst = 0
		for _, w in { w0, w1 } do
			for _, leg in { "Left Leg", "Right Leg" } do
				worst = math.max(worst, math.abs(R6Rig.tip(leg, w[leg]).Y + 3))
			end
		end
		check("mocap soles stay on the floor through a crouch", worst < 0.03, worst)
		local gap = R6Rig.gap("Left Leg", baked.frames[#baked.frames].transforms["Left Leg"]).Magnitude
		check("mocap crouch rides the legs into the torso", gap > 0.4 and gap <= 1.5, gap)
		local fist = R6Rig.tip("Right Arm", w1["Right Arm"]) - R6Rig.pivot("Right Arm", w1.Torso)
		check("mocap fist pushed forward points the arm forward", fist.Unit.Z < -0.6, fist.Unit)
		local a = R6Clip.audit(baked, {})
		local crossed = false
		for _, n in a.notes do
			crossed = crossed or string.find(n, "^legs") ~= nil
		end
		check("mocap legs stay apart", not crossed and a.metrics.legGap > 0.75, a.metrics.legGap)
	end

	-- the Blender half of the mocap path, when Blender is installed: a CMU-named BVH (cm, Y up, facing
	-- +Z) comes out scaled to a 2-stud leg, facing -Z, with every bone found
	do
		local fs, process = Env.fs, require("@lune/process")
		local blender = "/Applications/Blender.app/Contents/MacOS/Blender"
		if fs.isFile(blender) then
			local out = "fixtures/.synthetic_points.json"
			local r = process.exec(blender, { "-b", "--factory-startup", "--disable-autoexec", "--python", "mocap_points.py", "--", "fixtures/synthetic_cmu.bvh", out, "--fps=30" })
			local ok = r.ok and fs.isFile(out)
			check("blender reads the BVH fixture", ok, r.stderr)
			if ok then
				local doc = require("@lune/serde").decode("json", fs.readFile(out))
				fs.removeFile(out)
				local p = doc.frames[1].points
				check("mocap points: hips 2 studs over the floor", math.abs(p.LeftHip[2] + 1) < 0.02, p.LeftHip[2])
				check("mocap points: facing -Z, left is -X", p.LeftToe[3] < -0.1 and p.LeftHip[1] < 0, p.LeftToe[3])
			end
		else
			print("[check] Blender not found: skipped the mocap_points test")
		end
	end

	-- study --root-legs: torso-keyed legs (mocap, many packs) come back on the pelvis giving the same
	-- foot placement, under a torso that leans 40 and turns 20, with the legs slid in their sockets
	do
		local R6Study = Env.load("R6Study")
		local src = R6Clip.new("TorsoLegs")
		local function pose(lean, twist)
			return {
				Torso = { lean = lean, twist = twist, pos = { up = -0.4 } },
				LeftLeg = { raise = 30 + lean, spread = 4, pos = { forward = -0.2, up = 0.3 } },
				RightLeg = { raise = -10 + lean, spread = 6, pos = { up = 0.2 } },
			}
		end
		src:key(0, pose(0, 0))
		src:key(20, pose(40, 20))
		local seq = Sequence.read(R6Clip.toKeyframeSequence(src:bake()))
		for _, hips in { 0.35, 0 } do
			local keys = R6Study.keyPoses(seq, { 0, 20 }, 60, { rootLegs = true, hips = hips })
			local again = R6Clip.new("Again")
			for _, k in keys do
				-- this synthetic pose is off the floor on purpose: judge the conversion, not grounding
				k.pose["Left Leg"].ground, k.pose["Right Leg"].ground = nil, nil
				again:key(k.frame, k.pose)
			end
			local worst = 0
			for _, f in { 0, 20 } do
				local wa = R6Rig.fk(Sequence.sample(seq, f / 60))
				local wb = R6Rig.fk(again:sample(f))
				for _, leg in { "Left Leg", "Right Leg" } do
					worst = math.max(worst, (R6Rig.tip(leg, wa[leg]) - R6Rig.tip(leg, wb[leg])).Magnitude)
				end
			end
			check("study --root-legs keeps the feet where they were (hips " .. hips .. ")", worst < 0.05, worst)
		end
	end

	-- mocap: a planted foot stays planted while the body folds over it (no skating)
	do
		local MocapToR6 = Env.load("MocapToR6")
		local function body(lean)
			local up = Vector3.new(0, math.cos(math.rad(lean)), -math.sin(math.rad(lean)))
			local hip = Vector3.new(0, -1, 0)
			local function at(v)
				return { v.X, v.Y, v.Z }
			end
			local chest = hip + up * 1.1
			return {
				Pelvis = at(hip + up * 0.1), LeftHip = at(hip + Vector3.new(-0.2, 0, 0)), RightHip = at(hip + Vector3.new(0.2, 0, 0)),
				LeftAnkle = { -0.2, -2.87, -0.4 }, RightAnkle = { 0.2, -2.87, 0.3 }, LeftToe = { -0.2, -3, -0.67 }, RightToe = { 0.2, -3, 0.03 },
				LeftShoulder = at(chest + Vector3.new(-0.4, 0, 0)), RightShoulder = at(chest + Vector3.new(0.4, 0, 0)),
				LeftElbow = at(chest + Vector3.new(-0.4, -0.6, 0)), RightElbow = at(chest + Vector3.new(0.4, -0.6, 0)),
				LeftFist = at(chest + Vector3.new(-0.4, -1.4, 0)), RightFist = at(chest + Vector3.new(0.4, -1.4, 0)),
				Neck = at(chest + up * 0.2), HeadTop = at(chest + up * 0.75),
			}
		end
		local baked = MocapToR6.convert({ fps = 30, frames = { { t = 0, points = body(0) }, { t = 0.5, points = body(45) } } }, {})
		local w0, w1 = R6Rig.fk(baked.frames[1].transforms), R6Rig.fk(baked.frames[#baked.frames].transforms)
		local skate = 0
		for _, leg in { "Left Leg", "Right Leg" } do
			skate = math.max(skate, (R6Rig.tip(leg, w1[leg]) - R6Rig.tip(leg, w0[leg])).Magnitude)
		end
		check("mocap feet stay planted while the body folds 45 degrees", skate < 0.05, skate)
		local a = R6Clip.audit(baked, {})
		local crossed = false
		for _, n in a.notes do
			crossed = crossed or string.find(n, "^legs") ~= nil
		end
		check("mocap fold over a staggered stance does not cross the legs", not crossed, table.concat(a.notes, "; "))
	end

	-- R6Study reads back what R6Clip keyed: the jab's shoulder slide and its strike frame
	do
		local R6Study = Env.load("R6Study")
		local seq = Sequence.read(R6Clip.toKeyframeSequence(moves.Jab.baked))
		local r = R6Study.measure(seq)
		local audit = R6Clip.audit(moves.Jab.baked, moves.Jab.meta)
		check("study gap matches the keyed slide", math.abs(r.parts["Left Arm"].gap - audit.metrics.gap["Left Arm"]) < 0.02, r.parts["Left Arm"].gap)
		local strike
		for _, s in r.strikes do
			if s.limb == "Left Arm" then
				strike = s
			end
		end
		check("study finds the jab near its Hit marker", strike and math.abs(strike.hit - moves.Jab.meta.hit) <= 2, strike and strike.hit)
	end

	-- one part under two names in one pose ("RightLeg" from a merge, "Right Leg" added) fails loudly
	-- instead of keeping whichever the table happens to list last
	do
		local ok = pcall(function()
			R6Clip.new("Twice"):key(0, { RightLeg = { raise = 10 }, ["Right Leg"] = { raise = 20 } })
		end)
		check("a part keyed twice under two names is rejected", not ok)
	end

	-- removed IK keys fail loudly instead of silently doing nothing
	do
		local ok = pcall(function()
			R6Clip.new("Old"):key(0, { LeftArm = { aim = Vector3.new(0, 1, -4) } })
		end)
		check("aim keys are rejected", not ok)
	end

	-- root-space, grounded legs: the torso leans, twists and sinks, the soles stay on the floor and
	-- the legs keep their angle against the root (they ride up into the torso instead of bending)
	do
		local c = R6Clip.new("Sink")
		local legs = { LeftLeg = { raise = 15, space = "root", ground = true, hips = 0 }, RightLeg = { raise = -15, space = "root", ground = true, hips = 0 } }
		c:key(0, legs)
		c:key(10, R6Clip.merge(legs, { Torso = { lean = 30, twist = 40, pos = { up = -0.8 } } }))
		local worst, worstAngle = 0, 0
		local want = R6Rig.fk({ ["Left Leg"] = R6Rig.pose("Left Leg", { raise = 15 }) })["Left Leg"]
		for _, w in R6Clip.world(c:bake()) do
			for _, leg in { "Left Leg", "Right Leg" } do
				worst = math.max(worst, math.abs(R6Rig.tip(leg, w.parts[leg]).Y + 3))
			end
			worstAngle = math.max(worstAngle, Sequence.angleBetween(w.parts["Left Leg"], want))
		end
		check("grounded soles stay on the floor", worst < 0.01, worst)
		check("root-space legs with hips = 0 keep their angle", worstAngle < 0.05, worstAngle)
		local audit = R6Clip.audit(c:bake(), {})
		check("the sinking legs ride into the torso by the drop", audit.metrics.gap["Left Leg"] > 0.5 and audit.metrics.gap["Left Leg"] <= 1.5, audit.metrics.gap["Left Leg"])
	end

	-- R15 -> R6
	do
		local function seqOf(name, keys)
			local ks = Instance.new("KeyframeSequence")
			ks.Name = name
			for _, k in keys do
				local kf = Instance.new("Keyframe")
				kf.Time = k.t
				local root = Instance.new("Pose")
				root.Name = "HumanoidRootPart"
				root.Weight = 0
				root.Parent = kf
				local made = { HumanoidRootPart = root }
				for _, part in R15ToR6.ORDER do
					local pose = Instance.new("Pose")
					pose.Name = part
					pose.Weight = k.poses[part] and 1 or 0
					pose.CFrame = k.poses[part] or CFrame.identity
					pose.EasingStyle = Enum.PoseEasingStyle.Linear
					pose.Parent = made[R15ToR6.JOINTS[part].part0]
					made[part] = pose
				end
				kf.Parent = ks
			end
			return ks
		end
		local r = math.rad
		local punch = {
			RightUpperArm = CFrame.Angles(r(80), 0, 0),
			RightLowerArm = CFrame.Angles(r(50), 0, 0),
			LeftUpperArm = CFrame.Angles(r(40), 0, r(-30)),
			LeftLowerArm = CFrame.Angles(r(100), 0, 0),
			UpperTorso = CFrame.Angles(0, r(35), 0),
		}
		local crouch = {
			LowerTorso = CFrame.new(0, -0.9, 0),
			LeftUpperLeg = CFrame.Angles(r(70), 0, 0),
			LeftLowerLeg = CFrame.Angles(r(-110), 0, 0),
			RightUpperLeg = CFrame.Angles(r(20), 0, 0),
			RightLowerLeg = CFrame.Angles(r(-100), 0, 0),
		}
		for label, pose in { punch = punch, crouch = crouch } do
			local ks = seqOf(label, { { t = 0, poses = {} }, { t = 0.5, poses = pose } })
			local baked = R15ToR6.convert(ks)
			local last = baked.frames[#baked.frames].transforms
			local w6 = R6Rig.fk(last)
			local w15 = R15ToR6.fk(pose)
			local p = R15ToR6.points(w15)
			if label == "punch" then
				for _, side in { "Left", "Right" } do
					local part = side .. " Arm"
					local miss = (R6Rig.tip(part, w6[part]) - p[side .. "Fist"]).Magnitude
					check("r15->r6 " .. side .. " fist lands on the R15 fist", miss < 0.02, miss)
					check("r15->r6 " .. side .. " arm slides within budget", R6Rig.gap(part, last[part]).Magnitude <= 0.8 + 1e-3, R6Rig.gap(part, last[part]).Magnitude)
				end
				local yaw = math.deg(math.atan2(-w6.Torso.LookVector.X, -w6.Torso.LookVector.Z))
				check("r15->r6 torso keeps the chest twist", math.abs(yaw - 35) < 1, yaw)
				-- the chest twists 35 degrees over still hips: the legs stay where the R15 pelvis has them
				local legs = R6Clip.audit(baked, { airborne = true })
				check("r15->r6 legs hang from the R15 pelvis, not the twisted chest", legs.metrics.legGap > 0.9, legs.metrics.legGap)
			else
				for _, side in { "Left", "Right" } do
					local leg = side .. " Leg"
					local y6 = R6Rig.tip(leg, w6[leg]).Y
					check("r15->r6 " .. side .. " sole keeps its height", math.abs(y6 - p[side .. "Sole"].Y) < 0.03, string.format("%.3f vs %.3f", y6, p[side .. "Sole"].Y))
					check("r15->r6 " .. side .. " sole lands on the R15 sole", (R6Rig.tip(leg, w6[leg]) - p[side .. "Sole"]).Magnitude < 0.03)
				end
				check("r15->r6 pelvis drop carried", math.abs(w6.Torso.Position.Y + 0.9) < 0.05, w6.Torso.Position)
			end
			-- the synthetic R15 poses are not floor-exact themselves, so only pops are audited here
			local audit = R6Clip.audit(baked, { airborne = true, legsMayCross = true })
			check("r15->r6 " .. label .. " audits clean", audit.ok, table.concat(audit.notes, "; "))
		end
	end
end
