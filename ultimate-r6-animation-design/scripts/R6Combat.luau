-- R6Combat: a small client-side combat animator for R6. An M1 string with input buffering and
-- cancel windows, directional dashes with a real burst of travel, block, hit reactions and
-- hit-stop, all timed from the clips' markers ("Hit", "Cancel", "Go").
--
--   local combat = R6Combat.new(character, {
--       animations = { Jab = "rbxassetid://...", Cross = animObject, ... },   -- or KeyframeSequences in Studio
--       moves = R6Combat.movesFrom(CombatMoves),                              -- timing and gameplay numbers
--       onHit = function(name, meta) remote:FireServer(name) end,           -- VFX, sound, shake, server
--   })
--   combat:attack()            -- next hit of the string (or queued if pressed during a recovery)
--   combat:dash("Forward")     -- "Forward" | "Back" | "Left" | "Right" | a world Vector3
--   combat:block(true/false)
--   combat:react(heavy)        -- play a hit reaction (call when the server says you were hit)
--
-- The client animates at once (no waiting on the server) so input feels instant; the server
-- decides hits, damage and cooldowns from its own clock and the HumanoidRootPart, never from the
-- drawn limbs. See references/combat.md for the server side.

local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local TweenService = game:GetService("TweenService")

local R6Combat = {}
R6Combat.__index = R6Combat

R6Combat.DEFAULTS = {
	-- a slot may list variants, picked at random without repeating ("random M1 combos"):
	-- combo = { { "Jab", "JabHigh" }, "Cross", ... }
	combo = { "Jab", "Cross", "Hook", "Uppercut" },
	comboReset = 0.9, -- seconds idle before the string starts over
	buffer = 0.25, -- a press this long before the cancel window opens is kept
	dashCooldown = 0.55,
	-- crossfades: hits start hard (a pose change on the first frame reads as instant), the way out
	-- of a move blends; 0.1-0.15 s between hits of a string keeps them from smearing together
	fade = { attack = 0.04, dash = 0.06, block = 0.1, react = 0, out = 0.15 },
	idle = "Stance", -- false when R6Locomotion owns idle, walk and run (it shows Stance while fighting)
	-- Wind-up highlight (a YouTube combat system): the attacker flashes for the chamber, a
	-- telegraph the target can read. false to turn off; meta.windup = { fromFrame, toFrame }.
	windup = { color = Color3.fromRGB(255, 214, 150), fill = 0.45, fade = 0.12 },
}

-- Pull the meta tables out of CombatMoves (or any table of clip builders).
function R6Combat.movesFrom(CombatMoves)
	local out = {}
	for _, name in CombatMoves.LIST do
		local ok, clip = pcall(CombatMoves[name])
		if ok and clip then
			out[name] = clip.meta or {}
			out[name].fps = clip.fps
		end
	end
	return out
end

local function toAnimation(source)
	if typeof(source) == "Instance" then
		if source:IsA("Animation") then
			return source
		elseif source:IsA("KeyframeSequence") then
			-- Studio only: a temporary id for testing before the clip is published
			local anim = Instance.new("Animation")
			anim.AnimationId = KeyframeSequenceProvider:RegisterKeyframeSequence(source)
			return anim
		end
	elseif type(source) == "string" then
		local anim = Instance.new("Animation")
		anim.AnimationId = string.match(source, "^%d+$") and ("rbxassetid://" .. source) or source
		return anim
	end
	error("Animation source must be an Animation, a KeyframeSequence or an asset id", 3)
end

function R6Combat.new(character, opts)
	opts = opts or {}
	local self = setmetatable({}, R6Combat)
	self.character = character
	self.root = character:WaitForChild("HumanoidRootPart")
	self.humanoid = character:WaitForChild("Humanoid")
	self.animator = self.humanoid:FindFirstChildOfClass("Animator")
	if not self.animator then
		self.animator = Instance.new("Animator")
		self.animator.Parent = self.humanoid
	end
	self.cfg = table.clone(R6Combat.DEFAULTS)
	for k, v in opts.config or {} do
		self.cfg[k] = v
	end
	self.moves = opts.moves or {}
	self.onHit = opts.onHit
	self.tracks = {}
	for name, source in opts.animations or {} do
		local track = self.animator:LoadAnimation(toAnimation(source))
		local meta = self.moves[name] or {}
		track.Priority = meta.blocking and Enum.AnimationPriority.Action2
			or meta.reaction and Enum.AnimationPriority.Action3
			or name == self.cfg.idle and Enum.AnimationPriority.Idle
			or Enum.AnimationPriority.Action
		self.tracks[name] = track
	end
	self.comboIndex = 0
	self.lastPick = {}
	self.lastHitAt = -math.huge
	self.current = nil -- { name, track, meta, startedAt, cancelOpen }
	self.queued = nil
	self.dashReadyAt = 0
	self.blocking = false
	self.connections = {}

	-- the dash burst: a plane velocity on the root, so gravity still works
	local attachment = self.root:FindFirstChild("RootAttachment")
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Name = "RootAttachment"
		attachment.Parent = self.root
	end
	local lv = Instance.new("LinearVelocity")
	lv.Name = "R6CombatDash"
	lv.Attachment0 = attachment
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	lv.PrimaryTangentAxis = Vector3.xAxis
	lv.SecondaryTangentAxis = Vector3.zAxis
	lv.MaxForce = math.huge
	lv.Enabled = false
	lv.Parent = self.root
	self.dashVelocity = lv

	local idle = self.tracks[self.cfg.idle]
	if idle then
		idle.Looped = true
		idle:Play(0.2)
	end
	return self
end

function R6Combat:_busy()
	local c = self.current
	return c and c.track.IsPlaying and not c.cancelOpen
end

function R6Combat:_play(name, fade)
	local track = self.tracks[name]
	if not track then
		warn("R6Combat: no animation loaded for " .. name)
		return nil
	end
	local meta = self.moves[name] or {}
	if self.current and self.current.track ~= track and self.current.track.IsPlaying then
		self.current.track:Stop(fade)
	end
	for _, c in self.current and self.current.marks or {} do
		c:Disconnect()
	end
	local entry = { name = name, track = track, meta = meta, startedAt = os.clock(), cancelOpen = false, marks = {} }
	self.current = entry

	table.insert(entry.marks, track:GetMarkerReachedSignal("Hit"):Connect(function()
		self:_onHit(entry)
	end))
	table.insert(entry.marks, track:GetMarkerReachedSignal("Cancel"):Connect(function()
		entry.cancelOpen = true
		self:_drain()
	end))
	table.insert(entry.marks, track:GetMarkerReachedSignal("Go"):Connect(function()
		self:_burst(entry)
	end))
	table.insert(entry.marks, track.Stopped:Connect(function()
		if self.current == entry then
			entry.cancelOpen = true
			self:_drain()
		end
	end))
	track:Play(fade, 1, 1)
	return entry
end

-- Hit-stop: freeze the attacker's clip for a beat at contact (the eye keeps that pose). The pose
-- is held by the clip's own keyframe at the marker, so a 0 speed holds cleanly.
function R6Combat:_onHit(entry)
	local meta = entry.meta
	if meta.hitstop and meta.hitstop > 0 then
		local track = entry.track
		track:AdjustSpeed(0)
		task.delay(meta.hitstop, function()
			if track.IsPlaying then
				track:AdjustSpeed(1)
			end
		end)
	end
	self.lastHitAt = os.clock()
	if self.onHit then
		task.spawn(self.onHit, entry.name, meta, entry.track)
	end
end

function R6Combat:_drain()
	local q = self.queued
	if q and os.clock() - q.at <= self.cfg.buffer + 0.6 then
		self.queued = nil
		q.run()
	else
		self.queued = nil
	end
end

function R6Combat:attack()
	if self.blocking then
		return false
	end
	if self:_busy() then
		self.queued = { at = os.clock(), run = function()
			self:attack()
		end }
		return false
	end
	if os.clock() - self.lastHitAt > self.cfg.comboReset then
		self.comboIndex = 0
	end
	self.comboIndex = self.comboIndex % #self.cfg.combo + 1
	local name = self:_pick(self.comboIndex)
	local entry = self:_play(name, self.comboIndex == 1 and self.cfg.fade.attack or 0.1)
	if entry then
		self:_windup(entry)
	end
	if self.comboIndex == #self.cfg.combo then
		self.comboIndex = 0
	end
	return entry ~= nil
end

-- A combo slot is a name or a list of variants; never the same variant twice in a row.
function R6Combat:_pick(index)
	local slot = self.cfg.combo[index]
	if type(slot) ~= "table" then
		return slot
	end
	local choices = {}
	for _, name in slot do
		if self.tracks[name] and name ~= self.lastPick[index] then
			table.insert(choices, name)
		end
	end
	local name = #choices > 0 and choices[math.random(#choices)] or slot[1]
	self.lastPick[index] = name
	return name
end

function R6Combat:_windup(entry)
	local cfg, window = self.cfg.windup, entry.meta.windup
	if not cfg or not window then
		return
	end
	local h = self.highlight
	if not h then
		h = Instance.new("Highlight")
		h.Name = "R6CombatWindup"
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.OutlineTransparency = 1
		h.Parent = self.character
		self.highlight = h
	end
	h.FillColor = cfg.color
	h.FillTransparency = cfg.fill
	h.Enabled = true
	local fps = entry.meta.fps or 60
	task.delay(window[2] / fps, function()
		if self.current ~= entry then
			h.Enabled = false
			return
		end
		local tween = TweenService:Create(h, TweenInfo.new(cfg.fade, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FillTransparency = 1 })
		tween.Completed:Once(function()
			h.Enabled = false
		end)
		tween:Play()
	end)
end

local DIRECTIONS = {
	Forward = Vector3.new(0, 0, -1),
	Back = Vector3.new(0, 0, 1),
	Left = Vector3.new(-1, 0, 0),
	Right = Vector3.new(1, 0, 0),
}

function R6Combat:dash(direction)
	local now = os.clock()
	if now < self.dashReadyAt or self.blocking then
		return false
	end
	if self:_busy() then
		self.queued = { at = now, run = function()
			self:dash(direction)
		end }
		return false
	end
	local name, world
	if typeof(direction) == "Vector3" then
		local flat = Vector3.new(direction.X, 0, direction.Z)
		if flat.Magnitude < 1e-3 then
			return false
		end
		world = flat.Unit
		local localDir = self.root.CFrame:VectorToObjectSpace(world)
		if math.abs(localDir.Z) >= math.abs(localDir.X) then
			name = localDir.Z < 0 and "Forward" or "Back"
		else
			name = localDir.X < 0 and "Left" or "Right"
		end
	else
		name = direction
		world = self.root.CFrame:VectorToWorldSpace(DIRECTIONS[direction] or DIRECTIONS.Forward)
	end
	local entry = self:_play("Dash" .. name, self.cfg.fade.dash)
	if not entry then
		return false
	end
	entry.dashDirection = world
	self.dashReadyAt = now + self.cfg.dashCooldown
	if entry.meta.go then
		-- the burst waits for the clip's "Go" marker (after the crouch); the delay is a safety net
		task.delay(entry.meta.go / (entry.meta.fps or 60) + 0.05, self._burst, self, entry)
	else
		task.defer(self._burst, self, entry)
	end
	return true
end

-- The travel of a dash: fast out, braking to a stop, distance exact. v(t) = v0 (1 - t/T)^2
-- covers v0 T / 3, so v0 = 3 D / T.
function R6Combat:_burst(entry)
	if entry.burst then
		return
	end
	entry.burst = true
	local travel = entry.meta.dash or { distance = 14, time = 0.2 }
	local dir = entry.dashDirection or self.root.CFrame.LookVector
	local v0 = 3 * travel.distance / travel.time
	local lv = self.dashVelocity
	local started = os.clock()
	lv.Enabled = true
	local conn
	conn = game:GetService("RunService").PreSimulation:Connect(function()
		local u = (os.clock() - started) / travel.time
		if u >= 1 or self.current ~= entry then
			lv.Enabled = false
			conn:Disconnect()
			return
		end
		local v = dir * v0 * (1 - u) ^ 2
		lv.PlaneVelocity = Vector2.new(v.X, v.Z)
	end)
	table.insert(self.connections, conn)
end

function R6Combat:block(on)
	if on == self.blocking then
		return
	end
	self.blocking = on
	if on then
		local entry = self:_play("Block", self.cfg.fade.block)
		if entry then
			entry.track.Looped = true
		end
	elseif self.current and self.current.name == "Block" then
		self.current.track:Stop(self.cfg.fade.out)
		self.current = nil
	end
end

-- Reactions cut in hard (no fade): the struck pose on the very next frame sells the hit.
function R6Combat:react(heavy)
	self.queued = nil
	self.blocking = false
	return self:_play(heavy and "HitHeavy" or "HitLight", self.cfg.fade.react)
end

function R6Combat:stop()
	if self.current then
		self.current.track:Stop(self.cfg.fade.out)
		self.current = nil
	end
	self.queued = nil
end

function R6Combat:Destroy()
	self:stop()
	for _, c in self.connections do
		c:Disconnect()
	end
	if self.dashVelocity then
		self.dashVelocity:Destroy()
	end
	if self.highlight then
		self.highlight:Destroy()
	end
	for _, track in self.tracks do
		track:Destroy()
	end
end

-- Server-side helper: the hit shape of a strike, from the attacker's root (never the drawn fist).
-- Returns the Humanoids inside a box `range` studs in front of the root, excluding the attacker.
function R6Combat.query(attacker, range, size)
	local root = attacker:FindFirstChild("HumanoidRootPart")
	if not root then
		return {}
	end
	range, size = range or 4, size or Vector3.new(4, 5, 4)
	local box = root.CFrame * CFrame.new(0, 0, -range / 2 - 0.5)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { attacker }
	local hit, seen = {}, {}
	for _, part in workspace:GetPartBoundsInBox(box, Vector3.new(size.X, size.Y, range + size.Z / 2), params) do
		local model = part:FindFirstAncestorOfClass("Model")
		local humanoid = model and model:FindFirstChildOfClass("Humanoid")
		if humanoid and not seen[humanoid] and humanoid.Health > 0 then
			seen[humanoid] = true
			table.insert(hit, humanoid)
		end
	end
	return hit
end

return R6Combat
