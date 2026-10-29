-- Fixed-grip authoring pipeline. No per-pack builder, preview or measurement boilerplate.
local E = require("./env")
local U = require("./pack_support")
local R, fs = E.roblox, E.fs
local S = require("@lune/serde")
local Clip, Rig, Sequence, Study = E.load("R6Clip"), E.load("R6Rig"), E.load("Sequence"), E.load("R6Study")
local Quality = E.load("R6Quality")
local path, out = E.args[1], E.args[2]
assert(path and out, "usage: lune run pack <Moves.luau> <output> [--three=local-three.min.js] [--verbose]")
local provider = U.loadFile(path)
local base = string.match(path, "^(.*)/[^/]+$") or "."
local ref = assert(provider.REFERENCE, "reference brief and adaptations required")
local brief = S.decode("json", fs.readFile(base .. "/" .. ref.brief))
assert(brief.schema == 1 and brief.sourceHash and #brief.clips > 0, "invalid reference brief")
assert(type(ref.adaptations) == "string" and #ref.adaptations > 0, "describe reference adaptations")
local config = provider.WEAPON
if config and config.archetype == "heavy" then
	assert(ref.visualBrief, "heavy weapon requires watched heavy-specific footage before keying")
	local visual = S.decode("json", fs.readFile(base .. "/" .. ref.visualBrief))
	assert(visual.schema == 1 and visual.archetype == "heavy" and visual.observedOn, "invalid heavy visual brief")
	local viewed = 0
	for _, source in visual.sources or {} do
		if source.status == "viewed" then
			assert(source.url and source.title and source.creator and source.rig, "heavy source provenance missing")
			assert(source.observations and #source.observations >= 3, "record load, cut and recovery observations")
			for _, observation in source.observations do
				assert(
					type(observation.seconds) == "number"
						and type(observation.note) == "string"
						and #observation.note > 0,
					"timestamped visual observation required"
				)
			end
			viewed += 1
		end
	end
	assert(viewed > 0, "a listing or unrelated slash cannot establish heavy style")
end
if config then
	assert(not config.joints, "use an extra-joint adapter for animated weapons")
	local actual = config.grip * R.Vector3.new(table.unpack(config.tip))
	assert(provider.TIP and (provider.TIP - actual).Magnitude < 0.001, "weapon asset/grip and meta.tip disagree")
end
local built = provider.build()
assert(#provider.LIST > 0, "empty pack")
local packName = assert(provider.PACK, "PACK name required")
local folder = R.Instance.new("Folder")
folder.Name = packName .. "Animations"
local reports, preview, items = {}, {}, {}
local combo = { name = packName, fps = 60, loop = false, priority = "Action", frames = {}, markers = {}, leads = {} }
local offset = 0
for index, name in provider.LIST do
	local m = assert(built[name], "missing move " .. name)
	local b, meta = m.baked, m.meta
	assert(b.fps == 60 and not b.loop, "pack combos need non-looping 60 FPS clips")
	local audit = Quality.audit(b, meta, provider.BODY_SIZES)
	assert(audit.ok, name .. ": " .. table.concat(audit.notes, "; "))
	local hits = 0
	for _, mk in b.markers do
		assert(mk.frame >= 0 and mk.frame <= b.frames[#b.frames].frame, "marker outside clip")
		if mk.name == "Hit" then
			hits += 1
			assert(mk.frame == meta.hit, "meta.hit disagrees with Hit marker")
		end
	end
	assert(hits == 1 and meta.hit, "each attack must declare exactly one Hit")
	if config and config.archetype == "heavy" then
		assert(meta.heavy, "heavy weapon needs an explicit mass/overswing profile")
	end
	if meta.gripWindows then
		assert(#meta.gripWindows > 0, "empty grip windows")
		local previous = -1
		for _, range in meta.gripWindows do
			assert(
				range[1] >= 0 and range[1] < range[2] and range[2] <= b.frames[#b.frames].frame and range[1] > previous,
				"invalid grip windows"
			)
			previous = range[2]
			for marker, frame in { Grip = range[1], Release = range[2] } do
				local found = false
				for _, mk in b.markers do
					if mk.name == marker and mk.frame == frame then
						found = true
					end
				end
				assert(found, "grip windows need matching Grip/Release markers")
			end
		end
		assert(U.isGripping(meta, meta.hit), "powered Hit must be in a gripping phase")
	end
	local world = Clip.world(b)
	local maxGrip, maxTipSpeed, minBladeHeight = 0, 0, math.huge
	local lastTip
	local maxReleased = 0
	for _, w in world do
		if config then
			local tip = w.parts[config.parent] * provider.TIP
			if lastTip then
				maxTipSpeed = math.max(maxTipSpeed, (tip - lastTip).Magnitude * 60)
			end
			lastTip = tip
			-- Every blade sample must clear the floor, not just its endpoint at Hit.
			for step = 0, 8 do
				local localPoint = config.grip * (R.Vector3.new(table.unpack(config.tip)) * (step / 8))
				minBladeHeight = math.min(minBladeHeight, (w.parts[config.parent] * localPoint).Y + 3)
			end
			for _, g in config.geometry do
				for _, x in { -0.5, 0.5 } do
					for _, y in { -0.5, 0.5 } do
						for _, z in { -0.5, 0.5 } do
							local corner = R.Vector3.new(x * g.size[1], y * g.size[2], z * g.size[3])
							local p = w.parts[config.parent] * config.grip * g.cf * corner
							minBladeHeight = math.min(minBladeHeight, p.Y + 3)
						end
					end
				end
			end
			if config.offhand then
				local want = w.parts[config.parent] * (config.grip * R.Vector3.new(table.unpack(config.offhand.point)))
				local hand = Rig.tip(config.offhand.part, w.parts[config.offhand.part])
				if U.isGripping(meta, w.frame) then
					maxGrip = math.max(maxGrip, (hand - want).Magnitude)
				else
					maxReleased = math.max(maxReleased, (hand - want).Magnitude)
				end
			end
		end
	end
	if config and config.offhand then
		assert(
			maxGrip <= config.offhand.maxError,
			string.format("%s off-hand leaves grip: %.3f > %.3f", name, maxGrip, config.offhand.maxError)
		)
	end
	if config then
		assert(minBladeHeight >= -0.08, string.format("%s blade enters floor: %.3f", name, minBladeHeight))
	end
	local heavyReport
	if meta.heavy then
		local h = meta.heavy
		assert(
			U.isGripping(meta, h.load) and U.isGripping(meta, meta.hit + 3),
			"heavy power phase needs both hands on the grip"
		)
		local fol = world[h.followThrough + 1].parts
		local desired = fol[config.parent] * (config.grip * R.Vector3.new(table.unpack(config.offhand.point)))
		local releaseAtFollow = (Rig.tip(config.offhand.part, fol[config.offhand.part]) - desired).Magnitude
		if h.gripStyle == "regrip" then
			assert(not U.isGripping(meta, h.followThrough), "regrip profile needs a declared release phase")
			assert(releaseAtFollow >= h.minReleaseDistance, "support hand does not visibly release at overswing")
		end
		assert(
			h.load >= h.minLoad
				and h.load < meta.hit
				and meta.hit < h.followThrough
				and h.followThrough < h.recoverEnd
				and h.recoverEnd <= b.frames[#b.frames].frame,
			"heavy phase timing invalid"
		)
		local postArc = 0
		for f = meta.hit + 1, h.followThrough do
			local a = world[f].parts[config.parent].LookVector
			local z = world[f + 1].parts[config.parent].LookVector
			postArc += math.deg(math.acos(math.clamp(a:Dot(z), -1, 1)))
		end
		local bodyTurn = Sequence.angleBetween(world[h.load + 1].parts.Torso, world[h.followThrough + 1].parts.Torso)
		local postBody = Sequence.angleBetween(world[meta.hit + 1].parts.Torso, world[h.followThrough + 1].parts.Torso)
		assert(
			postArc >= h.minPostArc,
			string.format("%s heavy post-hit blade arc too compact: %.1f < %.1f", name, postArc, h.minPostArc)
		)
		assert(bodyTurn >= h.minBodyTurn, string.format("%s heavy trunk commitment too small: %.1f", name, bodyTurn))
		assert(
			postBody >= h.minPostBodyTurn,
			string.format("%s heavy post-hit trunk travel too small: %.1f", name, postBody)
		)
		assert(h.recoverEnd - h.followThrough >= h.minRecovery, "heavy recovery is cut short")
		if h.gripStyle == "regrip" then
			assert(maxReleased >= h.minReleaseDistance, "support hand never visibly releases in the declared phase")
		end
		heavyReport = {
			gripStyle = h.gripStyle,
			followThrough = h.followThrough,
			recoverEnd = h.recoverEnd,
			loadFrames = h.load,
			postHitBladeArc = postArc,
			bodyTurn = bodyTurn,
			postHitBodyTurn = postBody,
			recoveryFrames = h.recoverEnd - h.followThrough,
			maxReleasedDistance = maxReleased,
			releaseAtFollow = releaseAtFollow,
			minReleaseDistance = h.minReleaseDistance,
		}
	end
	local aliases = { LeftArm = "Left Arm", RightArm = "Right Arm", LeftLeg = "Left Leg", RightLeg = "Right Leg" }
	local strikePart = config and config.parent or aliases[meta.limb] or "Right Arm"
	local at = world[meta.hit + 1].parts
	local tip = at[strikePart] * (provider.TIP or Rig.TIP[strikePart])
	local ks = Clip.toKeyframeSequence(b, { reduce = false })
	local measured =
		Study.measure(Sequence.read(ks), { tips = provider.TIP and { [strikePart] = provider.TIP } or nil })
	if table.find(E.args, "--verbose") then
		print(Study.format(measured))
	end
	reports[name] = {
		ok = true,
		heavy = heavyReport,
		gripWindows = meta.gripWindows,
		metrics = audit.metrics,
		notes = audit.notes,
		length = b.frames[#b.frames].frame,
		limb = strikePart,
		hit = meta.hit,
		hold = measured.strikes[strikePart] and measured.strikes[strikePart].hold,
		hitstop = meta.hitstop or 0,
		tip = { x = tip.X, y = tip.Y, forward = -tip.Z },
		maxOffhandError = maxGrip,
		minBladeHeight = minBladeHeight,
		maxTipSpeed = maxTipSpeed,
		study = measured,
	}
	print(string.format("[pack] %s PASS / hit %df / reach %.2f / grip %.3f", name, meta.hit, -tip.Z, maxGrip))
	if index > 1 then
		local previous = combo.frames[#combo.frames]
		for _, part in Rig.ORDER do
			assert(
				Sequence.angleBetween(previous.transforms[part], b.frames[1].transforms[part]) < 0.01,
				"rotation seam before " .. name
			)
			assert(
				(previous.transforms[part].Position - b.frames[1].transforms[part].Position).Magnitude < 0.001,
				"position seam before " .. name
			)
		end
	end
	combo.budget = b.budget
	for j, fr in b.frames do
		if index == 1 or j > 1 then
			table.insert(
				combo.frames,
				{ frame = offset + fr.frame, time = (offset + fr.frame) / 60, transforms = fr.transforms }
			)
		end
	end
	table.insert(combo.markers, { frame = offset, time = offset / 60, name = "Move" .. index, value = name })
	for _, mk in b.markers do
		table.insert(
			combo.markers,
			{ frame = offset + mk.frame, time = (offset + mk.frame) / 60, name = mk.name, value = tostring(index) }
		)
	end
	offset += b.frames[#b.frames].frame
	table.insert(items, { baked = b, ks = ks, meta = meta, index = index })
end
local ca = Quality.audit(combo, {}, provider.BODY_SIZES)
assert(ca.ok, table.concat(ca.notes, "; "))
reports[packName] = { ok = true, length = offset, metrics = ca.metrics, notes = ca.notes }
table.insert(items, 1, { baked = combo, ks = Clip.toKeyframeSequence(combo, { reduce = false }), meta = {}, index = 0 })
for _, item in items do
	local b = item.baked
	item.ks.Parent = folder
	local data = {
		name = b.name,
		fps = 60,
		loop = false,
		limb = item.meta.limb or "RightArm",
		hitstop = item.meta.hitstop or 0,
		markers = {},
		frames = {},
	}
	for _, mk in b.markers do
		table.insert(data.markers, { frame = mk.frame, name = mk.name, value = mk.value })
	end
	for _, w in Clip.world(b) do
		local frame = {}
		for _, part in Rig.ORDER do
			frame[part] = { w.parts[part]:GetComponents() }
		end
		table.insert(data.frames, frame)
	end
	table.insert(preview, data)
end
local bytes = R.serializeModel({ folder })
local decoded = R.deserializeModel(bytes)[1]
assert(#decoded:GetChildren() == #items, "missing exported sequence")
for _, item in items do
	local seq = Sequence.read(assert(decoded:FindFirstChild(item.baked.name)))
	local hits = 0
	for _, mk in seq.markers do
		if mk.name == "Hit" then
			hits += 1
		end
	end
	assert(hits == (item.index == 0 and #provider.LIST or 1), "Hit marker round trip")
	local function markerCounts(markers)
		local counts = {}
		for _, mk in markers do
			local k = mk.name .. ":" .. math.floor((mk.time or mk.t) * 60 + 0.5) .. ":" .. tostring(mk.value or "")
			counts[k] = (counts[k] or 0) + 1
		end
		return counts
	end
	local expectedMarkers, actualMarkers = markerCounts(item.baked.markers), markerCounts(seq.markers)
	for k, n in expectedMarkers do
		assert(actualMarkers[k] == n, "marker time/value lost in export")
	end
	for k, n in actualMarkers do
		assert(expectedMarkers[k] == n, "unexpected marker in export")
	end

	for _, fr in item.baked.frames do
		local played = Sequence.sample(seq, fr.time)
		for _, part in Rig.ORDER do
			assert(Sequence.angleBetween(played[part], fr.transforms[part]) < 0.02, "export rotation mismatch")
			assert((played[part].Position - fr.transforms[part].Position).Magnitude < 0.001, "export position mismatch")
		end
	end
end
local here = string.match(debug.info(1, "s"), "^(.*)[/\\][^/\\]*$") or "."
local page = fs.readFile(here .. "/preview.html")
page = string.gsub(page, "__CLIPS__", function()
	return S.encode("json", preview)
end)
local webConfig = config
		and {
			parent = config.parent,
			grip = { config.grip:GetComponents() },
			tip = { provider.TIP.X, provider.TIP.Y, provider.TIP.Z },
			geometry = U.geometry(config),
			offhand = config.offhand,
		}
	or nil
page = string.gsub(page, "const WEAPON = null;", function()
	return "const WEAPON = " .. S.encode("json", webConfig) .. ";"
end)
for i = 3, #E.args do
	local three = string.match(E.args[i], "^%-%-three=(.+)$")
	if three then
		local embedded = "<script>" .. fs.readFile(three) .. "</script>"
		page = string.gsub(
			page,
			'<script src="https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js"></script>',
			function()
				return embedded
			end
		)
	end
end
local function jsonSafe(v)
	if typeof(v) == "Vector3" then
		return { v.X, v.Y, v.Z }
	end
	if type(v) == "table" then
		local t = {}
		for k, x in v do
			t[k] = jsonSafe(x)
		end
		return t
	end
	return v
end
-- Write only after validation: a rejected build leaves a previous successful export untouched.
fs.writeDir(out)
fs.writeDir(out .. "/attacks")
fs.writeFile(out .. "/" .. packName .. ".rbxm", bytes)
for _, item in items do
	if item.index > 0 then
		fs.writeFile(out .. "/attacks/" .. item.baked.name .. ".rbxm", R.serializeModel({ item.ks:Clone() }))
	end
end
fs.writeFile(out .. "/clips.json", S.encode("json", preview))
fs.writeFile(out .. "/weapon.json", S.encode("json", webConfig))
fs.writeFile(out .. "/audit.json", S.encode("json", jsonSafe(reports), true))
fs.writeFile(
	out .. "/reference.json",
	S.encode("json", {
		measurement = brief,
		visual = ref.visualBrief and S.decode("json", fs.readFile(base .. "/" .. ref.visualBrief)) or nil,
		adaptations = ref.adaptations,
	}, true)
)
fs.writeFile(out .. "/preview.html", page)
if config then
	fs.writeFile(out .. "/PreviewWeapon.rbxm", R.serializeModel({ U.weapon(config) }))
end
print(
	string.format(
		"[pack] PASS / %d attacks + combo / %.3fs / seams + RBXM round trip / %s",
		#provider.LIST,
		offset / 60,
		out
	)
)
