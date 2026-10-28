-- Measure every R6 KeyframeSequence in a file, to imitate it.
--   lune run study <file.rbxm|.rbxmx|.rbxl> [name ...] [--keys=0,12,25]
-- --keys also prints the clip's poses at those frames as R6Clip key tables (named angles + pos),
-- ready to imitate. --fit=3 picks the fewest keys that rebuild the clip within 3 degrees instead
-- (--half: only the first half of a symmetric cycle, to mirror). --tip="Right Arm:0,-1,-4" measures
-- that arm's strikes and sweeps from a held weapon's tip (here a 4-stud blade in a Tool's default grip).
-- Prints, per clip: timing, easing, torso drop/lunge/lean, each part's rotation reach and how far
-- it leaves its socket (gap), and the shape of every forward strike (chamber, hit, release, hold).
-- Only reads the file. Scripts inside it are never run.
local Env = require("./env")
local roblox = Env.roblox
local fs = Env.fs

local file = Env.args[1]
if not file then
	error("usage: lune run study <file> [name ...]", 0)
end
local names, keyFrames, fit, half, tips = {}, nil, nil, false, nil
for i = 2, #Env.args do
	local keys = string.match(Env.args[i], "^%-%-keys=([%d,]+)$")
	local tolerance = string.match(Env.args[i], "^%-%-fit=([%d%.]+)$")
	local tipPart, tx, ty, tz = string.match(Env.args[i], "^%-%-tip=([%a ]+):([%-%d%.]+),([%-%d%.]+),([%-%d%.]+)$")
	if tipPart then
		tips = tips or {}
		tips[tipPart] = roblox.Vector3.new(tonumber(tx), tonumber(ty), tonumber(tz))
	elseif tolerance then
		fit = tonumber(tolerance)
	elseif Env.args[i] == "--half" then
		half = true
	elseif keys then
		keyFrames = {}
		for f in string.gmatch(keys, "%d+") do
			table.insert(keyFrames, tonumber(f))
		end
	else
		names[Env.args[i]] = true
	end
end

local R6Rig = Env.load("R6Rig")
local Sequence = Env.load("Sequence")
local R6Study = Env.load("R6Study")

local data = fs.readFile(file)
local roots = string.match(file, "%.rbxl$") and { roblox.deserializePlace(data) } or roblox.deserializeModel(data)

local isR6 = { Torso = true, Head = true, ["Right Arm"] = true, ["Left Arm"] = true, ["Right Leg"] = true, ["Left Leg"] = true }

local count = 0
for _, root in roots do
	for _, ks in root:GetDescendants() do
		if ks.ClassName ~= "KeyframeSequence" or (next(names) and not names[ks.Name]) then
			continue
		end
		local seq = Sequence.read(ks)
		local r6 = false
		for part in seq.tracks do
			if isR6[part] and part ~= "Torso" and part ~= "Head" then
				r6 = true
			end
		end
		if not r6 then
			print(string.format("%s: not an R6 clip (parts: %s), skipped", ks:GetFullName(), table.concat((function()
				local t = {}
				for p in seq.tracks do
					table.insert(t, p)
				end
				return t
			end)(), ", ")))
			continue
		end
		-- a clip saved inside a rig's AnimSaves uses that rig's joints
		local joints
		local rig = ks.Parent and ks.Parent.Parent
		if rig and rig.ClassName == "Model" and rig:FindFirstChild("Torso") then
			joints = R6Rig.fromModel(rig)
		end
		print(R6Study.format(R6Study.measure(seq, { joints = joints, tips = tips })))
		local frames = keyFrames
		if fit then
			local total = math.floor(seq.length * 60 + 0.5)
			frames = R6Study.fitKeys(seq, fit, half and math.floor(total / 2) or nil)
			print(string.format("  fit within %g degrees: %d keys at frames %s", fit, #frames, table.concat(frames, ",")))
		end
		if frames then
			print(R6Study.formatKeys(R6Study.keyPoses(seq, frames)))
		end
		print("  from: " .. ks:GetFullName())
		print()
		count += 1
	end
end
print(count .. " R6 clip(s) measured")
