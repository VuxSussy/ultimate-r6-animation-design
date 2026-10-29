-- Build, audit and measure the mage clips with the skill's modules, then write
--   out/MageMoves.rbxm   KeyframeSequences (drag into a rig's AnimSaves)
--   out/eclipse/*.json    for the Eclipse Animator MCP save_animation tool
--   out/preview.html      the skill's 3D preview
-- Run from this folder:  lune run build
local Env = require("../ultimate-r6-animation-design/tools/env")
local roblox, fs = Env.roblox, Env.fs
local luau = require("@lune/luau")

local R6Rig = Env.load("R6Rig")
local R6Clip = Env.load("R6Clip")
local Sequence = Env.load("Sequence")
local R6Study = Env.load("R6Study")

-- load MageMoves.luau with `require(script.Parent.X)` resolving to the skill's modules
local source = fs.readFile("MageMoves.luau")
local MageMoves = luau.load(source, {
	debugName = "MageMoves",
	environment = setmetatable({
		script = { Parent = setmetatable({}, { __index = function(_, name)
			return { __module = name }
		end }) },
		require = function(target)
			return Env.load(target.__module)
		end,
		CFrame = roblox.CFrame,
		Vector3 = roblox.Vector3,
	}, { __index = _G }),
})()

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
		return string.format("%.4g", v)
	elseif t == "string" then
		return string.format("%q", v)
	elseif t == "boolean" then
		return tostring(v)
	end
	return "null"
end

fs.writeDir("out/eclipse")
local built = MageMoves.build()
local folder = roblox.Instance.new("Folder")
folder.Name = "MageMoves"
local preview, notes = {}, 0
for _, name in MageMoves.LIST do
	local m = built[name]
	local audit = R6Clip.audit(m.baked, m.meta)
	print(string.format("%-11s %s", name, audit.ok and "audit ok" or "AUDIT NOTES"))
	for _, n in audit.notes do
		print("    - " .. n)
		notes += 1
	end
	local metrics = {}
	for k, v in audit.metrics do
		if type(v) == "number" then
			table.insert(metrics, string.format("%s=%.3g", k, v))
		end
	end
	table.sort(metrics)
	print("    " .. table.concat(metrics, " "))

	local ks = R6Clip.toKeyframeSequence(m.baked)
	ks.Parent = folder
	fs.writeFile("out/eclipse/" .. name .. ".json", json(R6Clip.toEclipse(m.baked)))

		local report = R6Study.measure(Sequence.read(ks))
	if name == "MageFireball" then
		print(R6Study.format(report))
	end

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
fs.writeFile("out/MageMoves.rbxm", roblox.serializeModel({ folder }))
local template = fs.readFile("../ultimate-r6-animation-design/tools/preview.html")
fs.writeFile("out/preview.html", (string.gsub(template, "__CLIPS__", function()
	return json(preview)
end)))
print(string.format("[mage] %d clips, %d audit notes -> out/", #preview, notes))
