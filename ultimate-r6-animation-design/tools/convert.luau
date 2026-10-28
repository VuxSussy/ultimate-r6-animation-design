-- Convert R15 KeyframeSequences to R6, offline, and measure both.
--   lune run convert <file.rbxm|.rbxmx|.rbxl> <outDir> [name ...] [--blend=0..1] [--no-ground]
-- Writes <outDir>/<name> R6.rbxm (KeyframeSequence), <outDir>/eclipse/<name> R6.json and
-- <outDir>/preview.html, and prints the source and result analysis plus the audit.
local Env = require("./env")
local roblox = Env.roblox
local fs = Env.fs

local file, outDir = Env.args[1], Env.args[2]
if not file or not outDir then
	error("usage: lune run convert <file> <outDir> [name ...] [--blend=x] [--no-ground]", 0)
end
local names, opts = {}, {}
for i = 3, #Env.args do
	local a = Env.args[i]
	local blend = string.match(a, "^%-%-blend=([%d%.]+)$")
	if blend then
		opts.armBlend = tonumber(blend)
	elseif a == "--no-ground" then
		opts.ground = false
	else
		names[a] = true
	end
end

local R6Rig = Env.load("R6Rig")
local R6Clip = Env.load("R6Clip")
local Sequence = Env.load("Sequence")
local R15ToR6 = Env.load("R15ToR6")

local bytes = fs.readFile(file)
local roots
local ok, result = pcall(roblox.deserializeModel, bytes)
if ok then
	roots = result
else
	roots = roblox.deserializePlace(bytes):GetChildren()
end

local function isR15(ks)
	for _, d in ks:GetDescendants() do
		if d.ClassName == "Pose" and (d.Name == "UpperTorso" or d.Name == "LowerTorso") then
			return true
		end
	end
	return false
end

fs.writeDir(outDir)
fs.writeDir(outDir .. "/eclipse")
local here = string.match(debug.info(1, "s"), "^(.*)[/\\][^/\\]*$") or "."
local preview = {}
local count = 0

local function json(v)
	local t = type(v)
	if t == "table" then
		if #v > 0 or next(v) == nil then
			local parts = {}
			for _, x in v do
				table.insert(parts, json(x))
			end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		local keys = {}
		for k in v do
			table.insert(keys, tostring(k))
		end
		table.sort(keys)
		local parts = {}
		for _, k in keys do
			table.insert(parts, string.format("%q:%s", k, json(v[k])))
		end
		return "{" .. table.concat(parts, ",") .. "}"
	elseif t == "number" then
		return (v ~= v or math.abs(v) == math.huge) and "0" or string.format("%.4g", v)
	elseif t == "string" then
		return string.format("%q", v)
	elseif t == "boolean" then
		return tostring(v)
	end
	return "null"
end

for _, root in roots do
	local list = root.ClassName == "KeyframeSequence" and { root } or root:GetDescendants()
	for _, ks in list do
		if ks.ClassName ~= "KeyframeSequence" or not isR15(ks) then
			continue
		end
		if next(names) and not names[ks.Name] then
			continue
		end
		count += 1
		print("== source  " .. Sequence.format(Sequence.analyze(Sequence.read(ks))))
		local baked = R15ToR6.convert(ks, table.clone(opts))
		local out = R6Clip.toKeyframeSequence(baked)
		print("== R6      " .. Sequence.format(Sequence.analyze(Sequence.read(out))))
		local audit = R6Clip.audit(baked, { airborne = true })
		print("   audit: " .. (audit.ok and "ok" or table.concat(audit.notes, "; ")))
		fs.writeFile(outDir .. "/" .. baked.name .. ".rbxm", roblox.serializeModel({ out }))
		fs.writeFile(outDir .. "/eclipse/" .. baked.name .. ".json", json(R6Clip.toEclipse(baked)))

		local frames = {}
		for _, w in R6Clip.world(baked) do
			local parts = {}
			for _, part in R6Rig.ORDER do
				local c = { w.parts[part]:GetComponents() }
				for i, x in c do
					c[i] = math.floor(x * 10000 + 0.5) / 10000
				end
				parts[part] = c
			end
			table.insert(frames, parts)
		end
		local markers = {}
		for _, m in baked.markers do
			table.insert(markers, { frame = math.floor(m.frame + 0.5), name = m.name })
		end
		table.insert(preview, { name = baked.name, loop = baked.loop, fps = baked.fps, limb = "", hitstop = 0, markers = markers, frames = frames })
	end
end

local template = fs.readFile(here .. "/preview.html")
fs.writeFile(outDir .. "/preview.html", (string.gsub(template, "__CLIPS__", function()
	return json(preview)
end)))
print(string.format("[convert] %d R15 clip(s) -> %s", count, outDir))
