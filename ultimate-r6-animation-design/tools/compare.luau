-- Compare your clip with its reference, frame by frame:
--   lune run compare <reference.rbxm> <yours.rbxm> [refClip] [yourClip] [--stretch]
-- (refClip "" or "-" takes the first clip in the reference file.)
-- Prints, at 10 moments and at the worst frame: each arm's and leg's direction difference (the
-- limb's own axis, degrees), how far each fist and each foot moved from where it started compared
-- with the reference (studs), and the torso's lean and drop. --stretch maps the reference's length
-- onto yours (when you retimed the whole clip); otherwise frames are compared at the same time.
-- Use it after every R6-ifying pass: the differences you meant (a deeper fold, palms pushed out)
-- show up as such, and anything you did not mean shows up too.
local Env = require("./env")
local roblox, fs = Env.roblox, Env.fs

local R6Rig = Env.load("R6Rig")
local Sequence = Env.load("Sequence")

local args, stretch = {}, false
for _, a in Env.args do
	if a == "--stretch" then
		stretch = true
	else
		table.insert(args, a)
	end
end
if #args < 2 then
	error("usage: lune run compare <reference.rbxm> <yours.rbxm> [refClip] [yourClip] [--stretch]", 0)
end

local function load(path, name)
	if name == "" or name == "-" then
		name = nil -- "" or "-": the first clip in the file
	end
	local data = fs.readFile(path)
	local roots = string.match(path, "%.rbxl$") and { roblox.deserializePlace(data) } or roblox.deserializeModel(data)
	for _, root in roots do
		local all = root:GetDescendants()
		table.insert(all, 1, root)
		for _, d in all do
			if d.ClassName == "KeyframeSequence" and (not name or d.Name == name) then
				return Sequence.read(d)
			end
		end
	end
	error("no KeyframeSequence" .. (name and (" named " .. name) or "") .. " in " .. path, 0)
end

local ref = load(args[1], args[3])
local mine = load(args[2], args[4])
local steps = math.floor(mine.length * 60 + 0.5)
local Vector3 = roblox.Vector3

local function pose(seq, t)
	return R6Rig.fk(Sequence.sample(seq, t))
end
local refStart, mineStart = pose(ref, 0), pose(mine, 0)
local LIMBS = { "Left Arm", "Right Arm", "Left Leg", "Right Leg" }

local function measure(i)
	local t = i / 60
	local tr = stretch and t * ref.length / math.max(mine.length, 1e-6) or math.min(t, ref.length)
	local a, b = pose(ref, tr), pose(mine, t)
	local row = { frame = i }
	for _, part in LIMBS do
		local da, db = -a[part].UpVector, -b[part].UpVector
		row[part] = math.deg(math.acos(math.clamp(da:Dot(db), -1, 1)))
		local moveA = R6Rig.tip(part, a[part]) - R6Rig.tip(part, refStart[part])
		local moveB = R6Rig.tip(part, b[part]) - R6Rig.tip(part, mineStart[part])
		row[part .. " tip"] = (moveB - moveA).Magnitude
	end
	local function lean(w)
		return math.deg(math.acos(math.clamp(w.Torso.UpVector.Y, -1, 1)))
	end
	row.lean = lean(b) - lean(a)
	row.drop = -(b.Torso.Position.Y - a.Torso.Position.Y)
	return row
end

print(string.format("reference %s (%.2f s) vs yours %s (%.2f s)%s", ref.name, ref.length, mine.name, mine.length, stretch and ", stretched" or ""))
print("frame  | direction difference (deg)     | tip travel difference (studs)  | torso")
print("       |  LArm  RArm  LLeg  RLeg        |  LFist RFist LSole RSole       | lean  drop")
local worst = { frame = 0, score = -1 }
local rows = {}
for i = 0, steps do
	local r = measure(i)
	rows[i] = r
	local score = 0
	for _, part in LIMBS do
		score = math.max(score, r[part] / 30, r[part .. " tip"] / 0.6)
	end
	if score > worst.score then
		worst = { frame = i, score = score }
	end
end
local function line(r, tag)
	print(string.format(
		"%s%-5d | %5.0f %5.0f %5.0f %5.0f        | %5.2f %5.2f %5.2f %5.2f       | %+4.0f %+5.2f",
		tag or "f",
		r.frame,
		r["Left Arm"],
		r["Right Arm"],
		r["Left Leg"],
		r["Right Leg"],
		r["Left Arm tip"],
		r["Right Arm tip"],
		r["Left Leg tip"],
		r["Right Leg tip"],
		r.lean,
		r.drop
	))
end
for k = 0, 9 do
	line(rows[math.floor(k * steps / 9 + 0.5)])
end
line(rows[worst.frame], "worst f")
local feet = math.max(rows[worst.frame]["Left Leg tip"], rows[worst.frame]["Right Leg tip"])
print(feet > 0.25 and "feet: a sole travels differently from the reference's by more than 0.25 stud: a planted foot skating, or a step that changed" or "feet: soles track the reference within 0.25 stud")
