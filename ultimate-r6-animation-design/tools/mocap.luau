-- Turn a human motion-capture file into an R6 reference clip:
--   lune run mocap <in.fbx|.bvh|.glb|points.json> <outDir> [name] [--start=s] [--end=s] [--in-place]
--                  [--arm-blend=0..1] [--arm-slide=studs] [--fit=4] [--blender=/path/to/Blender]
-- A mocap file goes through Blender (headless, tools/mocap_points.py) into body points first; a
-- .json of body points is used as is. Writes <outDir>/<name>.rbxm (KeyframeSequence),
-- <outDir>/eclipse/<name>.json and <outDir>/preview.html, prints the audit and the study report,
-- and with --fit prints the fewest R6Clip keys that rebuild it (the start of an imitation).
-- The result is a REFERENCE: measure it, key your own clip from it, then stylise for R6.
local Env = require("./env")
local roblox, fs = Env.roblox, Env.fs
local process = require("@lune/process")
local serde = require("@lune/serde")

local file, outDir = Env.args[1], Env.args[2]
if not file or not outDir then
	error("usage: lune run mocap <in.fbx|.bvh|.glb|points.json> <outDir> [name] [--start=s] [--end=s] [--in-place] [--fit=4]", 0)
end
local opts, name, passthrough, fit = {}, nil, {}, nil
local blender = "/Applications/Blender.app/Contents/MacOS/Blender"
for i = 3, #Env.args do
	local a = Env.args[i]
	local k, v = string.match(a, "^%-%-([%w%-]+)=(.+)$")
	if a == "--in-place" then
		opts.inPlace = true
	elseif k == "start" or k == "end" or k == "action" or k == "map" then
		table.insert(passthrough, a)
	elseif k == "arm-blend" then
		opts.armBlend = tonumber(v)
	elseif k == "arm-slide" then
		opts.armSlide = tonumber(v)
	elseif k == "leg-slide" then
		opts.legSlide = tonumber(v)
	elseif k == "fit" then
		fit = tonumber(v)
	elseif k == "blender" then
		blender = v
	elseif not k then
		name = a
	end
end
name = name or (string.match(file, "([^/\\]+)%.%w+$") or "Mocap")
opts.name = name

local here = string.match(debug.info(1, "s"), "^(.*)[/\\][^/\\]*$") or "."
fs.writeDir(outDir)
local pointsPath = file
if not string.match(string.lower(file), "%.json$") then
	pointsPath = outDir .. "/" .. name .. ".points.json"
	local args = { "-b", "--factory-startup", "--disable-autoexec", "--python", here .. "/mocap_points.py", "--", file, pointsPath, "--fps=60" }
	for _, a in passthrough do
		table.insert(args, a)
	end
	local result = process.exec(blender, args)
	local line = string.match(result.stdout, "%[mocap_points%][^\n]*")
	if not result.ok or not line then
		error("Blender could not read " .. file .. ":\n" .. result.stdout .. result.stderr, 0)
	end
	print(line)
end

local R6Rig = Env.load("R6Rig")
local R6Clip = Env.load("R6Clip")
local Sequence = Env.load("Sequence")
local R6Study = Env.load("R6Study")
local MocapToR6 = Env.load("MocapToR6")

local doc = serde.decode("json", fs.readFile(pointsPath))
local baked = MocapToR6.convert(doc, opts)
local audit = R6Clip.audit(baked, { airborne = false, stride = true })
print(string.format("%s: %d frames (%.2f s) from %s", name, #baked.frames, baked.frames[#baked.frames].time, file))
print(audit.ok and "audit ok" or "audit notes (a reference keeps the source's own habits; fix them in your own clip):")
for _, n in audit.notes do
	print("  - " .. n)
end

-- hands and feet against the human's at 8 moments through the take: each arm's direction from its
-- shoulder, and each foot's travel from where it stood
do
	local Vector3 = roblox.Vector3
	local world = R6Clip.world(baked)
	local first = doc.frames[1].points
	local function hp(f, name)
		local t = f.points[name]
		return Vector3.new(t[1], t[2], t[3])
	end
	print("hands and feet vs the human: each arm's direction from its shoulder (degrees), and how far")
	print("each foot moved from where it stood, R6 against human (studs):")
	print("  frame   L fist  R fist  L sole  R sole")
	local worst = { 0, 0, 0, 0 }
	local n = #world
	for i = 1, n do
		local w = world[i]
		local f = doc.frames[math.min(#doc.frames, math.floor(w.time * doc.fps + 0.5) + 1)]
		local d = {}
		for j, spec in { { "Left Arm", "LeftFist" }, { "Right Arm", "RightFist" } } do
			-- compare directions from the shoulders (R6 shoulders are wider than a human's)
			local r6 = R6Rig.tip(spec[1], w.parts[spec[1]]) - R6Rig.pivot(spec[1], w.parts.Torso)
			local side = j == 1 and "Left" or "Right"
			local human = hp(f, spec[2]) - hp(f, side .. "Shoulder")
			d[j] = math.deg(math.acos(math.clamp(r6.Unit:Dot(human.Unit), -1, 1)))
		end
		for j, spec in { { "Left Leg", "Left" }, { "Right Leg", "Right" } } do
			-- how far each foot has moved from where it stood, R6 against human
			local sole = R6Rig.tip(spec[1], w.parts[spec[1]]) - R6Rig.tip(spec[1], world[1].parts[spec[1]])
			local humanSole = hp(f, spec[2] .. "Ankle") - hp(doc.frames[1], spec[2] .. "Ankle")
			d[j + 2] = (sole - humanSole).Magnitude
		end
		for j = 1, 4 do
			worst[j] = math.max(worst[j], d[j])
		end
		if (i - 1) % math.max(1, math.floor(n / 8)) == 0 then
			print(string.format("  f%-5d %5.0f°  %5.0f°  %5.2f   %5.2f", w.frame, d[1], d[2], d[3], d[4]))
		end
	end
	print(string.format("  worst   %5.0f°  %5.0f°  %5.2f   %5.2f   (arms: direction from the shoulder; feet: studs)", worst[1], worst[2], worst[3], worst[4]))
end

local ks = R6Clip.toKeyframeSequence(baked)
fs.writeFile(outDir .. "/" .. name .. ".rbxm", roblox.serializeModel({ ks }))
fs.writeDir(outDir .. "/eclipse")
fs.writeFile(outDir .. "/eclipse/" .. name .. ".json", serde.encode("json", R6Clip.toEclipse(baked)))

local seq = Sequence.read(ks)
print(R6Study.format(R6Study.measure(seq)))
if fit then
	local frames = R6Study.fitKeys(seq, fit)
	print(string.format("  fit within %g degrees: %d keys at frames %s", fit, #frames, table.concat(frames, ",")))
	-- mocap legs are keyed against the torso: hand them over on the pelvis, ready for R6Clip
	print(R6Study.formatKeys(R6Study.keyPoses(seq, frames, 60, { rootLegs = true })))
end

-- preview
local framesOut = {}
for _, w in R6Clip.world(baked) do
	local parts = {}
	for _, part in R6Rig.ORDER do
		local c = { w.parts[part]:GetComponents() }
		for j, x in c do
			c[j] = math.floor(x * 10000 + 0.5) / 10000
		end
		parts[part] = c
	end
	table.insert(framesOut, parts)
end
local clips = { { name = name, loop = false, fps = baked.fps, limb = "", hitstop = 0, markers = {}, frames = framesOut } }
local template = fs.readFile(here .. "/preview.html")
fs.writeFile(outDir .. "/preview.html", (string.gsub(template, "__CLIPS__", function()
	return serde.encode("json", clips)
end)))
print(string.format("[mocap] wrote %s/%s.rbxm, eclipse JSON and preview.html", outDir, name))
