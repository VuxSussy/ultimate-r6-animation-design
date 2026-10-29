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
	local args = { "-b", "--factory-startup", "--python", here .. "/mocap_points.py", "--", file, pointsPath, "--fps=60" }
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

local ks = R6Clip.toKeyframeSequence(baked)
fs.writeFile(outDir .. "/" .. name .. ".rbxm", roblox.serializeModel({ ks }))
fs.writeDir(outDir .. "/eclipse")
fs.writeFile(outDir .. "/eclipse/" .. name .. ".json", serde.encode("json", R6Clip.toEclipse(baked)))

local seq = Sequence.read(ks)
print(R6Study.format(R6Study.measure(seq)))
if fit then
	local frames = R6Study.fitKeys(seq, fit)
	print(string.format("  fit within %g degrees: %d keys at frames %s", fit, #frames, table.concat(frames, ",")))
	print(R6Study.formatKeys(R6Study.keyPoses(seq, frames)))
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
