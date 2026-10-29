-- A blade above the head can line up in X before the real chest-height impact.
local E = require("./env")
local R = E.roblox
local Rig, Clip = E.load("R6Rig"), E.load("R6Clip")
local V, C = R.Vector3.new, R.CFrame.new
local b = {
	name = "height-regression",
	fps = 60,
	loop = false,
	priority = "Action",
	leads = {},
	frames = {},
	markers = { { frame = 18, name = "Hit", time = 18 / 60 } },
}
local tip = V(0, -1, -4)
for f = 0, 24 do
	local transforms = {}
	for _, part in Rig.ORDER do
		transforms[part] = R.CFrame.identity
	end
	local p = f == 10 and V(0, 4, -2) or (f == 18 and V(0.05, 0, -4) or V(1.5, 0, -3))
	local arm = C(p - tip)
	local j = Rig.JOINTS["Right Arm"]
	transforms["Right Arm"] = j.C0:Inverse() * arm * j.C1
	table.insert(b.frames, { frame = f, time = f / 60, transforms = transforms })
end
local m = { limb = "RightArm", tip = tip, arc = true, strike = { 0, 24 }, overhead = true }
assert(Clip.audit(b, m).metrics.crossFrame == 10, "legacy sweep behavior changed")
m.contactHeight = { -1, 1 }
assert(Clip.audit(b, m).metrics.crossFrame == 18, "high blade incorrectly treated as chest-height contact")
m.contactHeight = { 5, 6 }
assert(not Clip.audit(b, m).metrics.crossFrame, "no valid target-height contact must be rejected")
m.contactHeight = { 1, -1 }
assert(not pcall(function()
	Clip.audit(b, m)
end), "invalid target band accepted")
print("[contact] 4 passed / legacy behavior + target band + missing contact + invalid bounds")
