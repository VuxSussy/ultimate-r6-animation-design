-- Measure clips the way the house grammar (the user's R6 movement system) is held:
--   lune run house <movement-system.rbxm> [yours.rbxm] [ClipName ...]
-- For every KeyframeSequence (or only the named ones), over the whole clip: how far the body drops,
-- how far it leans, where the face looks in the world, how far each leg rides into the torso, and
-- where the feet stand (forward of the root, out from the centre). Run it on the movement system to
-- see its ranges, then on your clip next to them. R6Clip.HOUSE holds the rules taken from these
-- numbers, and R6Clip.audit checks them.
local Env = require("./env")
local roblox, fs = Env.roblox, Env.fs
local R6Rig = Env.load("R6Rig")
local Sequence = Env.load("Sequence")
local Vector3 = roblox.Vector3

local files, names = {}, {}
for _, a in Env.args do
	if string.match(a, "%.rbxm$") or string.match(a, "%.rbxl$") then
		table.insert(files, a)
	else
		names[a] = true
	end
end
if #files == 0 then
	error("usage: lune run house <movement-system.rbxm> [yours.rbxm] [ClipName ...]", 0)
end
local filter = next(names) ~= nil

local function range()
	return { math.huge, -math.huge }
end
local function add(r, v)
	r[1], r[2] = math.min(r[1], v), math.max(r[2], v)
end
local function show(r, fmt)
	return string.format(fmt .. "..%s", r[1], string.format(fmt, r[2]))
end

print("clip             drop          lean (deg)    face (deg)    bury L        bury R        feet fwd L    feet fwd R    feet out")
for _, path in files do
	print("[" .. (string.match(path, "([^/\\]+)$") or path) .. "]")
	local data = fs.readFile(path)
	local roots = string.match(path, "%.rbxl$") and { roblox.deserializePlace(data) } or roblox.deserializeModel(data)
	for _, root in roots do
		local all = root:GetDescendants()
		table.insert(all, 1, root)
		for _, d in all do
			if d.ClassName == "KeyframeSequence" and (not filter or names[d.Name]) then
				local seq = Sequence.read(d)
				local r = { drop = range(), lean = range(), face = range(), buryL = range(), buryR = range(), fwdL = range(), fwdR = range(), out = range() }
				for i = 0, math.floor(seq.length * 60 + 0.5) do
					local w = R6Rig.fk(Sequence.sample(seq, math.min(i / 60, seq.length)))
					local t = w.Torso
					add(r.drop, -t.Position.Y)
					add(r.lean, math.deg(math.asin(math.clamp(-t.UpVector.Z, -1, 1))))
					add(r.face, math.deg(math.asin(math.clamp(w.Head.LookVector.Y, -1, 1))))
					for _, side in { "L", "R" } do
						local leg = side == "L" and "Left Leg" or "Right Leg"
						add(r["bury" .. side], t:PointToObjectSpace(w[leg] * Vector3.new(0, 1, 0)).Y + 1)
						local sole = w[leg] * Vector3.new(0, -1, 0)
						add(r["fwd" .. side], -sole.Z)
						add(r.out, math.abs(sole.X))
					end
				end
				print(string.format(
					"%-16s %-13s %-13s %-13s %-13s %-13s %-13s %-13s %s",
					string.sub(d.Name, 1, 16),
					show(r.drop, "%.2f"),
					show(r.lean, "%.0f"),
					show(r.face, "%.0f"),
					show(r.buryL, "%.2f"),
					show(r.buryR, "%.2f"),
					show(r.fwdL, "%+.2f"),
					show(r.fwdR, "%+.2f"),
					show(r.out, "%.2f")
				))
			end
		end
	end
end
