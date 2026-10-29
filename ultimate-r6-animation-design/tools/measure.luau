-- Full reports stay in JSON. Reuse only content/selection/grip/tool-identical measurements.
local E = require("./env")
local R, fs = E.roblox, E.fs
local S = require("@lune/serde")
local file, out = E.args[1], E.args[2]
assert(
	file and out,
	"usage: lune run measure <file.rbxm|rbxl> <brief.json> [clip names] [--tip=Right Arm:0,-1,-4] [--verbose]"
)
local selected, tipSpec, verbose = {}, {}, false
for i = 3, #E.args do
	local p, x, y, z = string.match(E.args[i], "^%-%-tip=([%a ]+):([%-%d%.]+),([%-%d%.]+),([%-%d%.]+)$")
	if p then
		tipSpec = { part = p, point = { tonumber(x), tonumber(y), tonumber(z) } }
	elseif E.args[i] == "--verbose" then
		verbose = true
	else
		table.insert(selected, E.args[i])
	end
end
table.sort(selected)
local here = string.match(debug.info(1, "s"), "^(.*)[/\\][^/\\]*$") or "."
local tools = ""
for _, name in { "R6Study", "R6Rig", "Sequence" } do
	tools ..= fs.readFile(here .. "/../scripts/" .. name .. ".luau")
end
tools ..= fs.readFile(here .. "/measure.luau") .. fs.readFile(here .. "/rokit.toml")
local bytes = fs.readFile(file)
local key = S.hash("sha256", bytes .. S.encode("json", selected) .. S.encode("json", tipSpec) .. tools)
if fs.isFile(out) then
	local saved = S.decode("json", fs.readFile(out))
	if saved.cacheKey == key then
		print("[measure] cache HIT / " .. #saved.clips .. " clips / " .. out)
		return
	end
end
local Study, Sequence, Rig = E.load("R6Study"), E.load("Sequence"), E.load("R6Rig")
local roots = string.match(file, "%.rbxl$") and { R.deserializePlace(bytes) } or R.deserializeModel(bytes)
local function clean(v)
	if typeof(v) == "Vector3" then
		return { v.X, v.Y, v.Z }
	end
	if type(v) == "table" then
		local outTable = {}
		for k, x in v do
			outTable[k] = clean(x)
		end
		return outTable
	end
	return v
end
local reports = {}
for _, root in roots do
	local objects = { root }
	for _, d in root:GetDescendants() do
		table.insert(objects, d)
	end
	for _, ks in objects do
		if ks:IsA("KeyframeSequence") and (#selected == 0 or table.find(selected, ks.Name)) then
			local seq = Sequence.read(ks)
			if
				not (
					seq.tracks["Right Arm"]
					or seq.tracks["Left Arm"]
					or seq.tracks["Right Leg"]
					or seq.tracks["Left Leg"]
				)
			then
				continue
			end
			local model = ks.Parent and ks.Parent.Parent
			local joints = model and model:IsA("Model") and model:FindFirstChild("Torso") and Rig.fromModel(model)
				or nil
			local tips = tipSpec.part and { [tipSpec.part] = R.Vector3.new(table.unpack(tipSpec.point)) } or nil
			local report = Study.measure(seq, { joints = joints, tips = tips })
			table.insert(reports, clean(report))
			if verbose then
				print(Study.format(report))
			else
				print(
					string.format(
						"[measure] %s / %df / drop %.2f / lunge %.2f",
						report.name,
						report.frames,
						report.torso.drop,
						report.torso.lunge
					)
				)
			end
		end
	end
end
assert(#reports > 0, "no selected R6 clips found")
for _, name in selected do
	local found = false
	for _, report in reports do
		if report.name == name then
			found = true
		end
	end
	assert(found, "selected clip not found: " .. name)
end
fs.writeFile(
	out,
	S.encode(
		"json",
		{
			schema = 1,
			source = file,
			sourceHash = S.hash("sha256", bytes),
			cacheKey = key,
			selected = selected,
			tip = tipSpec,
			clips = reports,
		},
		true
	)
)
print("[measure] saved / " .. out)
