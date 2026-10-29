local Run = game:GetService("RunService")
local Http = game:GetService("HttpService")
local player = game.Players.LocalPlayer
local rig = script.Parent
local root = rig:WaitForChild("HumanoidRootPart")
local hum = rig:WaitForChild("Humanoid")
root.Anchored = true
root.CFrame = CFrame.new(0, 3, 0)
hum.WalkSpeed = 0
hum.AutoRotate = false
local lib = game.ReplicatedStorage:WaitForChild("PackPreview")
local cfg = Http:JSONDecode(lib.Manifest.Value)
Run.PreSimulation:Wait()
if cfg.weapon then
	local weapon = lib.PreviewWeapon:Clone()
	local arm = rig[cfg.weapon.parent]
	local grip = CFrame.new(table.unpack(cfg.weapon.grip))
	for _, p in weapon:GetChildren() do
		local offset = grip * p.CFrame
		p.CFrame = arm.CFrame * offset
		local w = Instance.new("Weld")
		w.Part0 = arm
		w.Part1 = p
		w.C0 = offset
		w.Parent = p
	end
	weapon.Parent = rig
end
local camera = workspace.CurrentCamera
camera.CameraType = Enum.CameraType.Scriptable
local angles = {
	CFrame.lookAt(Vector3.new(14, 10, -14), Vector3.new(0, 4, -1.5)),
	CFrame.lookAt(Vector3.new(0, 8, -21), Vector3.new(0, 4, -1.5)),
	CFrame.lookAt(Vector3.new(20, 7, -1.5), Vector3.new(0, 4, -1.5)),
}
local angle = 1
camera.CFrame = angles[angle]
game:GetService("UserInputService").InputBegan:Connect(function(key, processed)
	if not processed and key.KeyCode == Enum.KeyCode.C then
		angle = angle % 3 + 1
		camera.CFrame = angles[angle]
	end
end)
local gui = Instance.new("ScreenGui")
gui.Name = "PackPreview"
gui.Parent = player:WaitForChild("PlayerGui")
local label = Instance.new("TextLabel")
label.Size = UDim2.fromOffset(440, 140)
label.Position = UDim2.fromOffset(18, 70)
label.BackgroundColor3 = Color3.fromRGB(18, 25, 36)
label.BackgroundTransparency = 0.08
label.BorderSizePixel = 0
label.TextColor3 = Color3.fromRGB(224, 235, 247)
label.Font = Enum.Font.Code
label.TextSize = 16
label.TextWrapped = true
label.Parent = gui
local status, move = "Loading tracks...", ""
local function update()
	label.Text = cfg.name .. " / R6\n" .. status .. "\n" .. move .. "\nC: camera"
end
update()
local animator = hum:WaitForChild("Animator")
local tracks = {}
local active, hits, samples, pending, measure
local releaseSamples = {}
local names = { cfg.name, table.unpack(cfg.moves) }
for _, name in names do
	local anim = Instance.new("Animation")
	anim.AnimationId = game:GetService("KeyframeSequenceProvider"):RegisterKeyframeSequence(lib.Animations[name])
	local t = animator:LoadAnimation(anim)
	t.Priority = Enum.AnimationPriority.Action
	t.Looped = false
	tracks[name] = t
	for i = 1, #cfg.moves do
		t:GetMarkerReachedSignal("Move" .. i):Connect(function()
			move = cfg.moves[i]
			update()
		end)
	end

	t:GetMarkerReachedSignal("Overswing"):Connect(function()
		if active ~= t or not measure or not cfg.weapon or not cfg.weapon.offhand then
			return
		end
		local profile = cfg.audit[name].heavy
		if not profile or profile.gripStyle ~= "regrip" then
			return
		end
		pending += 1
		t:AdjustSpeed(0)
		task.spawn(function()
			Run.PreSimulation:Wait()
			Run.PreSimulation:Wait()
			local index = table.find(cfg.moves, name)
			local o = cfg.weapon.offhand
			local arm = rig[cfg.weapon.parent]
			local want = arm.CFrame * (CFrame.new(table.unpack(cfg.weapon.grip)) * Vector3.new(table.unpack(o.point)))
			local error = ((rig[o.part].CFrame * Vector3.new(0, -1, 0)) - want).Magnitude
			table.insert(releaseSamples, { index = index, distance = error })
			print("[R6PackRelease] " .. Http:JSONEncode({ index = index, distance = error }))
			pending -= 1
			t:AdjustSpeed(1)
		end)
	end)
	t:GetMarkerReachedSignal("Hit"):Connect(function(value)
		if active ~= t then
			return
		end
		local index = name == cfg.name and tonumber(value) or table.find(cfg.moves, name)
		table.insert(hits, index)
		if not measure then
			return
		end
		pending += 1
		t:AdjustSpeed(0)
		task.spawn(function()
			Run.PreSimulation:Wait()
			Run.PreSimulation:Wait()
			local arm = rig[cfg.weapon and cfg.weapon.parent or cfg.audit[cfg.moves[index]].limb]
			local tip = root.CFrame:PointToObjectSpace(
				arm.CFrame * Vector3.new(table.unpack(cfg.weapon and cfg.weapon.tip or { 0, -1, 0 }))
			)
			local expected = cfg.audit[cfg.moves[index]].tip
			local gripError = 0
			if cfg.weapon and cfg.weapon.offhand then
				local o = cfg.weapon.offhand
				local want = arm.CFrame
					* (CFrame.new(table.unpack(cfg.weapon.grip)) * Vector3.new(table.unpack(o.point)))
				gripError = ((rig[o.part].CFrame * Vector3.new(0, -1, 0)) - want).Magnitude
			end
			local m = {
				index = index,
				sampleFrame = t.TimePosition * 60,
				forward = -tip.Z,
				x = tip.X,
				y = tip.Y,
				tipError = (tip - Vector3.new(expected.x, expected.y, -expected.forward)).Magnitude,
				offhandError = gripError,
				soleL = (rig["Left Leg"].CFrame * Vector3.new(0, -1, 0)).Y,
				soleR = (rig["Right Leg"].CFrame * Vector3.new(0, -1, 0)).Y,
			}
			table.insert(samples, m)
			print("[R6PackSample] " .. Http:JSONEncode(m))
			pending -= 1
			t:AdjustSpeed(1)
		end)
	end)
end
local function play(name)
	active = tracks[name]
	active:Play(0, 1, 1)
	local deadline = os.clock() + cfg.seconds + 8
	while (active.IsPlaying or pending > 0) and os.clock() < deadline do
		Run.Heartbeat:Wait()
	end
	assert(not active.IsPlaying and pending == 0, "animation or sampling timed out")
end
local function ordered()
	assert(#hits == #cfg.moves, "wrong Hit count")
	for i, index in hits do
		assert(index == i, "wrong Hit order")
	end
end
task.wait(1)
local ok, err = pcall(function()
	hits = {}
	samples = {}
	pending = 0
	measure = false
	status = "Checking combined track..."
	update()
	local before = os.clock()
	play(cfg.name)
	local elapsed = os.clock() - before
	ordered()
	assert(math.abs(elapsed - cfg.seconds) < 0.25, "combined duration mismatch")
	local combined = table.clone(hits)
	hits = {}
	measure = true
	status = "Checking individual tracks..."
	update()
	for _, name in cfg.moves do
		move = name
		update()
		play(name)
	end
	ordered()
	assert(#samples == #cfg.moves, "missing engine samples")
	for _, m in samples do
		assert(m.tipError < 0.12, "engine blade tip differs from export")
		assert(math.abs(m.soleL) < 0.08 and math.abs(m.soleR) < 0.08, "feet off floor")
		if cfg.weapon and cfg.weapon.offhand then
			assert(m.offhandError < cfg.weapon.offhand.maxError, "off-hand leaves grip")
		end
	end
	local seen = {}
	for _, r in releaseSamples do
		assert(
			not seen[r.index] and r.distance >= cfg.audit[cfg.moves[r.index]].heavy.minReleaseDistance,
			"support hand does not release at overswing"
		)
		seen[r.index] = true
	end
	local heavyCount = 0
	for _, name in cfg.moves do
		if cfg.audit[name].heavy and cfg.audit[name].heavy.gripStyle == "regrip" then
			heavyCount += 1
		end
	end
	assert(#releaseSamples == heavyCount, "missing overswing release samples")
	local result = {
		releases = releaseSamples,
		pack = cfg.name,
		combinedSeconds = elapsed,
		combinedHits = combined,
		separateHits = hits,
		samples = samples,
	}
	rig:SetAttribute("R6PackTestPassed", true)
	rig:SetAttribute("R6PackTestResults", Http:JSONEncode(result))
	print("[R6PackTest] PASS " .. Http:JSONEncode(result))
	status = "ALL TESTS PASSED / replaying 1x"
	update()
end)
if not ok then
	status = "FAIL: " .. tostring(err)
	update()
	warn("[R6PackTest] FAIL " .. tostring(err))
	return
end
measure = false
while rig.Parent do
	hits = {}
	pending = 0
	play(cfg.name)
	task.wait(0.65)
end
