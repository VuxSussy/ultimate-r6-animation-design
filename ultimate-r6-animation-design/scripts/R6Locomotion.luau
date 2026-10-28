-- R6Locomotion: picks the body's movement clip from what the character is really doing, the way
-- the reference movement system's Animate and FallSystem scripts do it. Client side, one per character.
--
--   local loco = R6Locomotion.new(character, {
--       animations = { Idle, Walk, Run, Stance, Climb, Jump, Fall, Land, LandShort, LandLong,
--                      WallRunLeft, WallRunRight },   -- ids, Animations or KeyframeSequences; any may be missing
--   })
--   loco:combat()             -- call on every attack, dash or block: the guard Stance shows for a while
--   loco:wallRun("Left")      -- R6WallRun calls this; nil when the wall run ends
--   loco:setAnimation("Idle", swordGuard)   -- swap a clip (a weapon's guard, say); takes over at once
--   loco:destroy()
--
-- In order of precedence:
--   wall run    WallRunLeft / WallRunRight while R6WallRun says so
--   landing     after a fall, by the height fallen since Freefall began (the movement system's tiers): under 4 studs
--               Land, 4-15 LandShort, over 15 LandLong; it plays out unless the body moves off
--   climbing    Climb at vertical speed / 12 (paused when the climber stops, reversed going down)
--   airborne    Jump once on take-off, then Fall
--   ground      Idle (or the guard Stance for 3 s after a fight action), Walk at speed / 14.5
--               (reversed walking backwards), Run at 1.3 once WalkSpeed reaches 20 (movement system: walk 12,
--               Shift sprint 27)
-- Blends from the movement system: idle -> walk 0.25 s, walk -> idle 0.30, walk -> run 0.18, run -> walk 0.22.
-- Attacks (Action priority) play over all of this.
-- Replace Roblox's default Animate (an empty LocalScript named "Animate" in StarterCharacterScripts
-- does it): it plays its own walk and, on start, stops every track it finds.
-- Fades between two clips blend rotations the short way: a fade between poses more than 180
-- degrees apart (an arm flung back into an arm overhead) swings through the back. Keep such pairs
-- apart, or fade fast.

local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local RunService = game:GetService("RunService")

local R6Locomotion = {}
R6Locomotion.__index = R6Locomotion

R6Locomotion.DEFAULTS = {
	moving = 0.75, -- studs/s below which the body stands
	sprintThreshold = 20, -- WalkSpeed at or above this means sprinting (the movement system's crouch script)
	walkRate = 14.5, -- studs/s that play the walk at 1x
	runRate = 1.3,
	climbRate = 12, -- climbing studs/s that play the climb at 1x
	minRate = 0.35,
	maxRate = 1.6,
	combatHold = 3, -- seconds the guard Stance replaces Idle after a fight action
	landTiers = { 4, 15 }, -- studs fallen: below the first Land, below the second LandShort, else LandLong
	landHold = { Land = 0.25, LandShort = 0.45, LandLong = 0.65 }, -- seconds a landing owns the body
	landCut = 0.12, -- moving off this soon after landing cuts a landing short
	fade = 0.2,
	fades = {
		Idle = { Walk = 0.25, Run = 0.25, Stance = 0.2 },
		Stance = { Walk = 0.2, Run = 0.2, Idle = 0.4 },
		Walk = { Idle = 0.3, Stance = 0.25, Run = 0.18 },
		Run = { Walk = 0.22, Idle = 0.3, Stance = 0.25 },
		Jump = { Fall = 0.15 },
		Fall = { Land = 0.04, LandShort = 0.04, LandLong = 0.04 },
	},
}

local LOOPED = { Idle = true, Stance = true, Walk = true, Run = true, Climb = true, Fall = true, WallRunLeft = true, WallRunRight = true }

local function toAnimation(source)
	if typeof(source) == "Instance" then
		if source:IsA("Animation") then
			return source
		elseif source:IsA("KeyframeSequence") then
			local anim = Instance.new("Animation")
			anim.AnimationId = KeyframeSequenceProvider:RegisterKeyframeSequence(source)
			return anim
		end
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = tostring(source)
	return anim
end

function R6Locomotion.new(character, opts)
	opts = opts or {}
	local self = setmetatable({}, R6Locomotion)
	self.character = character
	self.humanoid = character:WaitForChild("Humanoid")
	self.root = character:WaitForChild("HumanoidRootPart")
	self.cfg = table.clone(R6Locomotion.DEFAULTS)
	for k, v in opts.config or {} do
		self.cfg[k] = v
	end
	local animator = self.humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = self.humanoid
	end
	self.animator = animator
	self.tracks = {}
	self.loaded = {}
	for name, source in opts.animations or {} do
		self.tracks[name] = self:_load(name, source)
	end
	self.lastCombat = -math.huge
	self.state = nil
	self.landing = nil -- { name, untilTime, at }
	self.wallSide = nil
	self.jumpedAt = -math.huge
	self.connections = {
		RunService.PreSimulation:Connect(function()
			self:_step()
		end),
		self.humanoid.StateChanged:Connect(function(old, new)
			self:_stateChanged(old, new)
		end),
	}
	self:_step()
	return self
end

function R6Locomotion:_load(name, source)
	local track = self.loaded[source]
	if not track then
		track = self.animator:LoadAnimation(toAnimation(source))
		self.loaded[source] = track
	end
	track.Priority = (name == "Idle" or name == "Stance") and Enum.AnimationPriority.Idle or Enum.AnimationPriority.Movement
	track.Looped = LOOPED[name] or false
	return track
end

-- Swap the clip behind a state; if that state is showing, the new clip fades in now.
function R6Locomotion:setAnimation(name, source)
	local old = self.tracks[name]
	local track = self:_load(name, source)
	if old == track then
		return
	end
	self.tracks[name] = track
	if self.state == name then
		if old then
			old:Stop(0.2)
		end
		track:Play(0.2)
	end
end

function R6Locomotion:combat()
	self.lastCombat = os.clock()
end

function R6Locomotion:wallRun(side)
	self.wallSide = side
end

local AIR = {
	[Enum.HumanoidStateType.Freefall] = true,
	[Enum.HumanoidStateType.Jumping] = true,
	[Enum.HumanoidStateType.FallingDown] = true,
}

function R6Locomotion:_stateChanged(old, new)
	if new == Enum.HumanoidStateType.Jumping then
		self.jumpedAt = os.clock()
	end
	if new == Enum.HumanoidStateType.Freefall then
		self.fallFrom = self.root.Position.Y -- the movement system measures from where the fall begins
	elseif AIR[old] and not AIR[new] and new ~= Enum.HumanoidStateType.Climbing and self.fallFrom then
		local fallen = self.fallFrom - self.root.Position.Y
		self.fallFrom = nil
		local tiers = self.cfg.landTiers
		local name = fallen < tiers[1] and "Land" or fallen < tiers[2] and "LandShort" or "LandLong"
		if self.tracks[name] and not self.wallSide then
			local now = os.clock()
			self.landing = { name = name, at = now, untilTime = now + (self.cfg.landHold[name] or 0.3) }
			self.lastFall = fallen
		end
	elseif new == Enum.HumanoidStateType.Climbing then
		self.fallFrom = nil
	end
end

-- The ground clip and its rate, from the root's speed and the WalkSpeed (sprint).
function R6Locomotion:_ground(speed, flat)
	if speed <= self.cfg.moving or self.humanoid.MoveDirection.Magnitude < 0.05 then
		local fighting = os.clock() - self.lastCombat < self.cfg.combatHold and self.tracks.Stance
		return fighting and "Stance" or "Idle", 1
	end
	if self.humanoid.WalkSpeed >= self.cfg.sprintThreshold and self.tracks.Run then
		return "Run", self.cfg.runRate
	end
	local rate = math.clamp(speed / self.cfg.walkRate, self.cfg.minRate, self.cfg.maxRate)
	if flat:Dot(self.root.CFrame.LookVector) < -0.3 * speed then
		rate = -rate -- walking backwards: the walk runs in reverse
	end
	return "Walk", rate
end

function R6Locomotion:_choose()
	local v = self.root.AssemblyLinearVelocity
	local flat = Vector3.new(v.X, 0, v.Z)
	local speed = flat.Magnitude
	local state = self.humanoid:GetState()
	local now = os.clock()

	if self.wallSide and self.tracks["WallRun" .. self.wallSide] then
		return "WallRun" .. self.wallSide, 1
	end
	local landing = self.landing
	if landing then
		local moving = speed > self.cfg.moving and self.humanoid.MoveDirection.Magnitude > 0.05
		if now < landing.untilTime and not (moving and now - landing.at > self.cfg.landCut and landing.name == "Land") then
			return landing.name, 1
		end
		self.landing = nil
	end
	if state == Enum.HumanoidStateType.Climbing and self.tracks.Climb then
		return "Climb", v.Y / self.cfg.climbRate
	end
	if AIR[state] then
		local jump = self.tracks.Jump
		if jump and now - self.jumpedAt < jump.Length then
			return "Jump", 1
		end
		if self.tracks.Fall then
			return "Fall", 1
		end
	end
	return self:_ground(speed, flat)
end

function R6Locomotion:_step()
	local name, rate = self:_choose()
	local track = self.tracks[name]
	if not track then
		return
	end
	if name ~= self.state then
		local from = self.state
		local fade = from and (self.cfg.fades[from] or {})[name] or self.cfg.fade
		if from and self.tracks[from] then
			self.tracks[from]:Stop(fade)
		end
		track:Play(fade, 1, rate)
		self.state = name
	elseif not track.IsPlaying and LOOPED[name] then
		-- something stopped it from outside (Roblox's default Animate stops every track it finds
		-- when it starts): take it back
		track:Play(0.1, 1, rate)
	elseif math.abs(track.Speed - rate) > 0.02 then
		track:AdjustSpeed(rate)
	end
end

function R6Locomotion:destroy()
	for _, c in self.connections do
		c:Disconnect()
	end
	self.connections = {}
	for _, track in self.tracks do
		track:Stop(0.2)
	end
end

return R6Locomotion
