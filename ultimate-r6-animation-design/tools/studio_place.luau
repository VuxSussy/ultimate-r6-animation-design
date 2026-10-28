-- Build a self-contained Studio test place offline:  lune run studio_place <out.rbxl> [extra.luau ...]
-- Extra ModuleScripts (e.g. a project's SwordMoves.luau) go into the same R6Animation folder; when a
-- SwordMoves module is there, the harness gets a Fists / Sword toggle (on-screen button or key 1).
-- It holds the skill's modules (ReplicatedStorage.R6Animation), an anchored R6 rig to play clips on
-- in edit mode (Workspace.R6TestRig), a few steps, an R6 StarterCharacter, and a LocalScript
-- harness (StarterCharacterScripts.R6Test) that wires R6Combat to the 13 kit clips and takes
-- commands through the character's "R6Cmd" attribute:
--   attack | dash:<Forward|Back|Left|Right> | block:on | block:off | react:light | react:heavy
-- Results land in character attributes (Hits, LastHit, SpeedAtHit, SpeedAfterStop, ...).
-- Open the file in Studio; nothing here touches any other place.
local Env = require("./env")
local roblox = Env.roblox
local fs = Env.fs
local Instance, CFrame, Vector3, Enum, Color3 = roblox.Instance, roblox.CFrame, roblox.Vector3, roblox.Enum, roblox.Color3

local out = Env.args[1] or "R6TestPlace.rbxl"
local here = string.match(debug.info(1, "s"), "^(.*)[/\\][^/\\]*$") or "."
local R6Rig = Env.load("R6Rig")

local game = Instance.new("DataModel")
local workspace = game:GetService("Workspace")
local replicated = game:GetService("ReplicatedStorage")
local starterPlayer = game:GetService("StarterPlayer")
local lighting = game:GetService("Lighting")
lighting.ClockTime = 14

local function part(name, size, cf, color, anchored, parent)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Anchored = anchored
	p.Color = color
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- ground, spawn, a few steps
part("Baseplate", Vector3.new(256, 1, 256), CFrame.new(0, -0.5, 0), Color3.fromRGB(99, 95, 98), true, workspace)
local spawn = Instance.new("SpawnLocation")
spawn.Name = "Spawn"
spawn.Size = Vector3.new(6, 1, 6)
spawn.CFrame = CFrame.new(0, 0.5, 20)
spawn.Anchored = true
spawn.Neutral = true
spawn.Parent = workspace
local stairs = Instance.new("Model")
stairs.Name = "Stairs"
stairs.Parent = workspace
for i = 1, 6 do
	part("Step" .. i, Vector3.new(10, i * 0.8, 2), CFrame.new(0, i * 0.4, -6 - i * 2), Color3.fromRGB(160, 140, 120), true, stairs)
end

-- a wall to run on, a truss to climb, towers to fall from (landing tiers: under 4, 4-15, over 15)
part("Wall", Vector3.new(2, 24, 90), CFrame.new(30, 12, -10), Color3.fromRGB(120, 130, 150), true, workspace)
local truss = Instance.new("TrussPart")
truss.Name = "ClimbTruss"
truss.Size = Vector3.new(2, 30, 2)
truss.CFrame = CFrame.new(-14, 15, 0)
truss.Anchored = true
truss.Parent = workspace
part("LedgeLow", Vector3.new(8, 1, 8), CFrame.new(-30, 9.5, 20), Color3.fromRGB(150, 120, 90), true, workspace)
part("LedgeHigh", Vector3.new(8, 1, 8), CFrame.new(-30, 29.5, -10), Color3.fromRGB(150, 90, 90), true, workspace)
part("TrussTop", Vector3.new(6, 1, 6), CFrame.new(-14, 30.5, -3), Color3.fromRGB(120, 120, 120), true, workspace)

-- an R6 body built from the skill's own joint table
local SIZES = {
	HumanoidRootPart = Vector3.new(2, 2, 1),
	Torso = Vector3.new(2, 2, 1),
	Head = Vector3.new(2, 1, 1),
	["Right Arm"] = Vector3.new(1, 2, 1),
	["Left Arm"] = Vector3.new(1, 2, 1),
	["Right Leg"] = Vector3.new(1, 2, 1),
	["Left Leg"] = Vector3.new(1, 2, 1),
}
local COLORS = {
	Torso = Color3.fromRGB(13, 105, 172),
	Head = Color3.fromRGB(245, 205, 48),
	["Right Arm"] = Color3.fromRGB(245, 205, 48),
	["Left Arm"] = Color3.fromRGB(245, 205, 48),
	["Right Leg"] = Color3.fromRGB(75, 151, 75),
	["Left Leg"] = Color3.fromRGB(75, 151, 75),
}
local function r6Body(name, rootCF, anchored)
	local model = Instance.new("Model")
	model.Name = name
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.HipHeight = 0
	local animator = Instance.new("Animator")
	animator.Parent = humanoid
	humanoid.Parent = model
	local parts = {}
	local world = R6Rig.fk({}, rootCF)
	for partName, size in SIZES do
		local cf = partName == "HumanoidRootPart" and rootCF or world[partName]
		local p = part(partName, size, cf, COLORS[partName] or Color3.new(1, 1, 1), anchored and partName == "HumanoidRootPart", model)
		p.CanCollide = partName == "Torso" or partName == "Head"
		if partName == "HumanoidRootPart" then
			p.Transparency = 1
		end
		parts[partName] = p
	end
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Head
	mesh.Scale = Vector3.new(1.25, 1.25, 1.25)
	mesh.Parent = parts.Head
	for partName, j in R6Rig.JOINTS do
		local m = Instance.new("Motor6D")
		m.Name = j.motor
		m.Part0 = parts[j.part0]
		m.Part1 = parts[partName]
		m.C0 = j.C0
		m.C1 = j.C1
		m.MaxVelocity = 0.1
		m.Parent = parts[j.part0]
	end
	local att = Instance.new("Attachment")
	att.Name = "RootAttachment"
	att.Parent = parts.HumanoidRootPart
	local animSaves = Instance.new("Model")
	animSaves.Name = "AnimSaves"
	animSaves.Parent = model
	model.PrimaryPart = parts.HumanoidRootPart
	return model
end

r6Body("R6TestRig", CFrame.new(20, 3, 0), true).Parent = workspace
r6Body("StarterCharacter", CFrame.new(0, 3, 20), false).Parent = starterPlayer

-- the modules
local folder = Instance.new("Folder")
folder.Name = "R6Animation"
folder.Parent = replicated
for _, name in Env.list() do
	local ms = Instance.new("ModuleScript")
	ms.Name = name
	ms.Source = fs.readFile(here .. "/../scripts/" .. name .. ".luau")
	ms.Parent = folder
end
for i = 2, #Env.args do
	local path = Env.args[i]
	local ms = Instance.new("ModuleScript")
	ms.Name = string.match(path, "([^/\\]+)%.luau$")
	ms.Source = fs.readFile(path)
	ms.Parent = folder
	print("[studio_place] + module " .. ms.Name)
end

-- the harness
local scripts = starterPlayer:FindFirstChild("StarterCharacterScripts") or Instance.new("StarterCharacterScripts")
scripts.Parent = starterPlayer
local harness = Instance.new("LocalScript")
harness.Name = "R6Test"
harness.Source = [[
local RS = game:GetService("ReplicatedStorage")
local lib = RS:WaitForChild("R6Animation")
local R6Clip = require(lib.R6Clip)
local CombatMoves = require(lib.CombatMoves)
local R6Combat = require(lib.R6Combat)
local Locomotion = require(lib.Locomotion)
local R6Locomotion = require(lib.R6Locomotion)
local R6WallRun = require(lib.R6WallRun)
local UIS = game:GetService("UserInputService")

local character = script.Parent
local humanoid = character:WaitForChild("Humanoid")
-- the default Animate script would fight our idle/walk/run
local default = character:FindFirstChild("Animate")
if default then
	default:Destroy()
end
for _, track in humanoid:WaitForChild("Animator"):GetPlayingAnimationTracks() do
	track:Stop(0)
end
local built = CombatMoves.build()
local animations = {}
for name, m in built do
	animations[name] = R6Clip.toKeyframeSequence(m.baked)
end
local loco = {}
for name, m in Locomotion.build() do
	loco[name] = R6Clip.toKeyframeSequence(m.baked)
end
loco.Stance = animations.Stance
local locomotion = R6Locomotion.new(character, { animations = loco })
R6WallRun.new(character, { locomotion = locomotion })
-- what the body did, for tests: every movement clip it switched to, and the last fall height
local seen = {}
humanoid.StateChanged:Connect(function(_, new)
	character:SetAttribute("HumanoidState", new.Name)
end)
-- The movement system's speeds: walk 12, Shift to sprint at 27
humanoid.WalkSpeed = 12
UIS.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.LeftShift then
		humanoid.WalkSpeed = 27
	end
end)
UIS.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift then
		humanoid.WalkSpeed = 12
	end
end)
-- Sword mode (when the project's SwordMoves module is present): its own R6Combat whose M1 is the
-- sword slash, the sword guard as idle, and a visible blade in the default grip.
local SwordMovesModule = lib:FindFirstChild("SwordMoves")
local sword
if SwordMovesModule then
	local SwordMoves = require(SwordMovesModule)
	sword = { animations = {}, moves = R6Combat.movesFrom(SwordMoves) }
	for name, m in SwordMoves.build() do
		sword.animations[name] = R6Clip.toKeyframeSequence(m.baked)
	end
	local blade = Instance.new("Part")
	blade.Name = "SwordBlade"
	blade.Size = Vector3.new(0.2, 0.5, SwordMoves.BLADE)
	blade.Color = Color3.fromRGB(220, 225, 235)
	blade.Material = Enum.Material.Metal
	blade.CanCollide, blade.CanQuery, blade.CanTouch, blade.Massless = false, false, false, true
	blade.Transparency = 1
	local weld = Instance.new("Weld")
	weld.Part0 = character:WaitForChild("Right Arm")
	weld.Part1 = blade
	weld.C0 = CFrame.new(0, -1, -SwordMoves.BLADE / 2) -- out of the fist along the arm's front (a Tool's default grip)
	weld.Parent = blade
	blade.Parent = character
	sword.blade = blade
end

local hits = 0
local log = {}
local root = character:WaitForChild("HumanoidRootPart")
local LIMB = { LeftArm = "Left Arm", RightArm = "Right Arm", LeftLeg = "Left Leg", RightLeg = "Right Leg" }
-- what the drawn body does at the hit, read from the real parts (so slides and grounding are
-- checked in the engine, not in the skill's own math)
local function measure(name, meta)
	local limb = character:FindFirstChild(LIMB[meta.limb or ""] or "")
	local function rootSpace(v)
		return root.CFrame:PointToObjectSpace(v)
	end
	local out = { name = name }
	if limb then
		local tip = rootSpace(limb.CFrame * Vector3.new(0, -1, 0))
		out.reach = -tip.Z
	end
	local look = root.CFrame:VectorToObjectSpace(character.Torso.CFrame.LookVector)
	out.twist = math.deg(math.atan2(-look.X, -look.Z))
	out.soleL = rootSpace(character["Left Leg"].CFrame * Vector3.new(0, -1, 0)).Y + 3
	out.soleR = rootSpace(character["Right Leg"].CFrame * Vector3.new(0, -1, 0)).Y + 3
	local hipL = rootSpace(character["Left Leg"].CFrame * Vector3.new(0, 1, 0))
	local hipR = rootSpace(character["Right Leg"].CFrame * Vector3.new(0, 1, 0))
	out.hipsApart = (hipL - hipR).Magnitude
	return out
end
local combat, fists
fists = R6Combat.new(character, {
	animations = animations,
	moves = R6Combat.movesFrom(CombatMoves),
	config = { idle = false },
	onHit = function(name, meta, track)
		hits += 1
		character:SetAttribute("Hits", hits)
		character:SetAttribute("LastHit", name)
		character:SetAttribute("SpeedAtHit", track.Speed)
		local m = measure(name, meta)
		table.insert(log, string.format("%s reach=%.2f twist=%.0f soles=%.2f/%.2f hips=%.2f", name, m.reach or -1, m.twist, m.soleL, m.soleR, m.hipsApart))
		character:SetAttribute("HitLog", table.concat(log, " | "))
		task.delay((meta.hitstop or 0) + 0.05, function()
			character:SetAttribute("SpeedAfterStop", track.Speed)
		end)
	end,
})
combat = fists

local mode = "Fists"
local function setMode(new)
	if not sword or new == mode then
		return
	end
	mode = new
	combat:block(false)
	combat = new == "Sword" and sword.combat or fists
	sword.blade.Transparency = new == "Sword" and 0 or 1
	locomotion:setAnimation("Idle", new == "Sword" and sword.animations.SwordGuard or loco.Idle)
	locomotion:setAnimation("Stance", new == "Sword" and sword.animations.SwordGuard or loco.Stance)
	character:SetAttribute("WeaponMode", new)
end
if sword then
	local swordAnimations = table.clone(animations)
	for name, ks in sword.animations do
		swordAnimations[name] = ks
	end
	local moves = R6Combat.movesFrom(CombatMoves)
	for name, meta in sword.moves do
		moves[name] = meta
	end
	sword.combat = R6Combat.new(character, {
		animations = swordAnimations,
		moves = moves,
		config = { idle = false, combo = { "SwordSlash" } },
		onHit = function(name, meta, track)
			hits += 1
			character:SetAttribute("Hits", hits)
			character:SetAttribute("LastHit", name)
		end,
	})
	-- the toggle: an on-screen button, or key 1
	local gui = Instance.new("ScreenGui")
	gui.Name = "WeaponToggle"
	gui.ResetOnSpawn = false
	local button = Instance.new("TextButton")
	button.Size = UDim2.fromOffset(230, 46)
	button.Position = UDim2.new(0, 16, 1, -140)
	button.BackgroundColor3 = Color3.fromRGB(45, 55, 65)
	button.TextColor3 = Color3.fromRGB(235, 225, 199)
	button.Font = Enum.Font.GothamMedium
	button.TextSize = 17
	button.Parent = gui
	local function label()
		button.Text = (mode == "Sword" and "Weapon: Sword" or "Weapon: Fists") .. "  [1]"
	end
	button.Activated:Connect(function()
		setMode(mode == "Sword" and "Fists" or "Sword")
		label()
	end)
	UIS.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.One then
			setMode(mode == "Sword" and "Fists" or "Sword")
			label()
		end
	end)
	label()
	gui.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
	character:SetAttribute("WeaponMode", mode)
end

character:GetAttributeChangedSignal("R6Cmd"):Connect(function()
	local cmd = character:GetAttribute("R6Cmd") or ""
	local verb, arg = string.match(cmd, "^(%w+):?([%w%+]*)")
	locomotion:combat()
	if verb == "attack" then
		character:SetAttribute("Attacked", combat:attack())
	elseif verb == "dash" then
		local from = root.Position
		local look = root.CFrame.LookVector
		local ok = combat:dash(arg ~= "" and arg or "Forward")
		character:SetAttribute("Dashed", ok)
		task.delay(0.6, function()
			local moved = root.Position - from
			character:SetAttribute("DashTravel", string.format("%s %.2f studs (forward %.2f)", arg, Vector3.new(moved.X, 0, moved.Z).Magnitude, moved:Dot(look)))
		end)
	elseif verb == "block" then
		combat:block(arg == "on")
	elseif verb == "react" then
		combat:react(arg == "heavy")
	elseif verb == "mode" then
		setMode(arg)
	end
	character:SetAttribute("R6Cmd", nil)
end)
character:SetAttribute("LocoState", "")
game:GetService("RunService").Heartbeat:Connect(function()
	if character:GetAttribute("LocoState") ~= locomotion.state then
		character:SetAttribute("LocoState", locomotion.state)
		table.insert(seen, tostring(locomotion.state))
		if #seen > 40 then
			table.remove(seen, 1)
		end
		character:SetAttribute("LocoSeen", table.concat(seen, ">"))
		character:SetAttribute("LastFall", locomotion.lastFall)
	end
end)
character:SetAttribute("R6TestReady", true)
]]
harness.Parent = scripts
-- an empty Animate replaces Roblox's default one, which would play its own walk over ours and
-- stop every playing track when it starts
local animate = Instance.new("LocalScript")
animate.Name = "Animate"
animate.Source = "-- intentionally empty: R6Locomotion (in R6Test) animates this character"
animate.Parent = scripts

fs.writeFile(out, roblox.serializePlace(game))
print("[studio_place] wrote " .. out)
