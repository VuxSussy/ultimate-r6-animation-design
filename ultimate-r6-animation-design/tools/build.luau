-- Build the combat pack offline, audit it, and write:
--   <out>/R6CombatPack.rbxm      KeyframeSequences (drag into a rig's AnimSaves, or Explorer)
--   <out>/eclipse/<Move>.json    for the Eclipse Animator MCP save_animation tool
--   <out>/preview.html           a 3D viewer of every clip (open in any browser)
-- Run from tools/:  lune run build -- ../../output
local Env = require("./env")
local roblox = Env.roblox
local fs = Env.fs

local outDir = Env.args[1] or "../../output"
local only = Env.args[2]

local R6Rig = Env.load("R6Rig")
local R6Clip = Env.load("R6Clip")
local R6Quality = Env.load("R6Quality")
local CombatMoves = Env.load("CombatMoves")
local Locomotion = Env.load("Locomotion")

local function json(v, indent)
	indent = indent or ""
	local t = type(v)
	if t == "table" then
		if #v > 0 or next(v) == nil then
			local parts = {}
			for _, x in v do
				table.insert(parts, json(x, indent))
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
			table.insert(parts, string.format("%q:%s", k, json(v[k], indent)))
		end
		return "{" .. table.concat(parts, ",") .. "}"
	elseif t == "number" then
		if v ~= v or v == math.huge or v == -math.huge then
			return "0"
		end
		return string.format("%.4g", v)
	elseif t == "string" then
		return string.format("%q", v)
	elseif t == "boolean" then
		return tostring(v)
	end
	return "null"
end

fs.writeDir(outDir)
fs.writeDir(outDir .. "/eclipse")

local moves = CombatMoves.build()
local names = table.clone(CombatMoves.LIST)
for name, m in Locomotion.build() do
	moves[name] = m
end
for _, name in Locomotion.LIST do
	table.insert(names, name)
end
local folder = roblox.Instance.new("Folder")
folder.Name = "R6CombatPack"
local preview = {}
local failures = 0

for _, name in names do
	if only and only ~= name then
		continue
	end
	local m = moves[name]
	local audit = R6Quality.audit(m.baked, m.meta)
	local metrics = {}
	for k, v in audit.metrics do
		if type(v) == "table" then
			for part, x in v do
				local value = type(x) == "table" and x.depth or x
				table.insert(metrics, string.format("%s.%s=%s", k, string.gsub(part, " ", ""), type(value) == "number" and string.format("%.3g", value) or tostring(value)))
			end
		else
			table.insert(metrics, string.format("%s=%s", k, typeof(v) == "number" and string.format("%.3g", v) or tostring(v)))
		end
	end
	table.sort(metrics)
	print(string.format("%-12s %s  %s", name, audit.ok and "ok  " or "WARN", table.concat(metrics, " ")))
	for _, note in audit.notes do
		print("    - " .. note)
		failures += 1
	end

	assert(audit.ok, name .. ": " .. table.concat(audit.notes, "; "))
	local ks = R6Clip.toKeyframeSequence(m.baked)
	ks.Parent = folder
	fs.writeFile(outDir .. "/eclipse/" .. name .. ".json", json(R6Clip.toEclipse(m.baked)))

	local frames = {}
	for _, w in R6Clip.world(m.baked) do
		local parts = {}
		for _, part in R6Rig.ORDER do
			local c = { w.parts[part]:GetComponents() }
			for i, v in c do
				c[i] = math.floor(v * 10000 + 0.5) / 10000
			end
			parts[part] = c
		end
		table.insert(frames, parts)
	end
	local markers = {}
	for _, mk in m.baked.markers do
		table.insert(markers, { frame = mk.frame, name = mk.name })
	end
	table.insert(preview, {
		name = name,
		loop = m.baked.loop,
		fps = m.baked.fps,
		limb = m.meta.limb or "",
		hitstop = m.meta.hitstop or 0,
		markers = markers,
		frames = frames,
	})
end

fs.writeFile(outDir .. "/R6CombatPack.rbxm", roblox.serializeModel({ folder }))

local here = string.match(debug.info(1, "s"), "^(.*)[/\\][^/\\]*$") or "."
local template = fs.readFile(here .. "/preview.html")
local page = string.gsub(template, "__CLIPS__", function()
	return json(preview)
end)
fs.writeFile(outDir .. "/preview.html", page)

print(string.format("[build] %d clips, %d audit notes -> %s", #preview, failures, outDir))
