-- R6WallRun: a small client wall run that drives the WallRunLeft / WallRunRight clips. Airborne,
-- moving fast and next to a wall on one side, the character runs along the wall for up to
-- `time` seconds, sinking slowly; jump to kick off it. Gameplay is yours to tune; this exists so
-- the clips play against a real wall.
--
--   local wall = R6WallRun.new(character, { locomotion = loco })   -- R6Locomotion shows the clips
--   wall:destroy()

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local R6WallRun = {}
R6WallRun.__index = R6WallRun

R6WallRun.DEFAULTS = {
	reach = 2.4, -- studs from the root to a wall at the side
	minSpeed = 14, -- horizontal studs/s needed to catch a wall
	speed = 26, -- studs/s along the wall
	time = 1.4, -- longest run, seconds
	lift = 6, -- least upward studs/s at the start (the jump's own rise is kept up to maxLift)
	maxLift = 16,
	sink = 8,
	cooldown = 0.35, -- seconds after a run before the next can start
	clearance = 1.5, -- studs the feet must be off the ground before a wall can be caught
	kick = { away = 28, up = 42, along = 12 }, -- jumping off
}

function R6WallRun.new(character, opts)
	opts = opts or {}
	local self = setmetatable({}, R6WallRun)
	self.character = character
	self.humanoid = character:WaitForChild("Humanoid")
	self.root = character:WaitForChild("HumanoidRootPart")
	self.locomotion = opts.locomotion
	self.cfg = table.clone(R6WallRun.DEFAULTS)
	for k, v in opts.config or {} do
		self.cfg[k] = v
	end
	self.params = RaycastParams.new()
	self.params.FilterType = Enum.RaycastFilterType.Exclude
	self.params.FilterDescendantsInstances = { character }
	self.readyAt = 0
	self.connections = {
		RunService.PreSimulation:Connect(function()
			self:_step()
		end),
		UserInputService.JumpRequest:Connect(function()
			if self.run then
				self:_kick()
			end
		end),
	}
	return self
end

local AIR = { [Enum.HumanoidStateType.Freefall] = true, [Enum.HumanoidStateType.Jumping] = true }

-- A wall on `dir` (a world vector to the side), or nil. Walls stand up: the normal is mostly flat.
function R6WallRun:_wall(dir)
	local hit = workspace:Raycast(self.root.Position, dir * self.cfg.reach, self.params)
	if hit and math.abs(hit.Normal.Y) < 0.3 then
		return hit
	end
	return nil
end

function R6WallRun:_start(side, hit, v)
	local normal = Vector3.new(hit.Normal.X, 0, hit.Normal.Z).Unit
	local flat = Vector3.new(v.X, 0, v.Z)
	local along = flat - normal * flat:Dot(normal)
	if along.Magnitude < 1e-3 then
		return
	end
	local lift = math.clamp(v.Y, self.cfg.lift, self.cfg.maxLift)
	self.run = { side = side, normal = normal, along = along.Unit, started = os.clock(), lift = lift }
	self.humanoid.AutoRotate = false
	if self.locomotion then
		self.locomotion:wallRun(side)
	end
end

function R6WallRun:_stop()
	self.run = nil
	self.readyAt = os.clock() + self.cfg.cooldown
	self.humanoid.AutoRotate = true
	if self.locomotion then
		self.locomotion:wallRun(nil)
	end
end

function R6WallRun:_kick()
	local run = self.run
	local k = self.cfg.kick
	self:_stop()
	self.root.AssemblyLinearVelocity = run.normal * k.away + Vector3.yAxis * k.up + run.along * k.along
end

function R6WallRun:_step()
	local v = self.root.AssemblyLinearVelocity
	local run = self.run
	if run then
		local t = os.clock() - run.started
		local side = run.side == "Right" and self.root.CFrame.RightVector or -self.root.CFrame.RightVector
		if t > self.cfg.time or not AIR[self.humanoid:GetState()] or not self:_wall(side) then
			self:_stop()
			return
		end
		local u = t / self.cfg.time
		local vy = run.lift + (-self.cfg.sink - run.lift) * u
		self.root.AssemblyLinearVelocity = run.along * self.cfg.speed + Vector3.yAxis * vy - run.normal * 2
		self.root.CFrame = CFrame.lookAt(self.root.Position, self.root.Position + run.along)
		return
	end
	-- only once really in the air: in the Jumping frame the jump's push is not applied yet, and a
	-- body that close to the floor is "landed" again a frame later
	if os.clock() < self.readyAt or self.humanoid:GetState() ~= Enum.HumanoidStateType.Freefall then
		return
	end
	local below = workspace:Raycast(self.root.Position, Vector3.new(0, -(3 + self.cfg.clearance), 0), self.params)
	if below then
		return
	end
	if Vector3.new(v.X, 0, v.Z).Magnitude < self.cfg.minSpeed then
		return
	end
	local right = self.root.CFrame.RightVector
	local hitR, hitL = self:_wall(right), self:_wall(-right)
	if hitR then
		self:_start("Right", hitR, v)
	elseif hitL then
		self:_start("Left", hitL, v)
	end
end

function R6WallRun:destroy()
	if self.run then
		self:_stop()
	end
	for _, c in self.connections do
		c:Disconnect()
	end
	self.connections = {}
end

return R6WallRun
