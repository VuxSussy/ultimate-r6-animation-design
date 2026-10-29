local E = require("./env")
local R, fs = E.roblox, E.fs
local luau = require("@lune/luau")
local M = {}
function M.loadFile(path)
	return luau.load(fs.readFile(path), {
		debugName = path,
		environment = {
			script = {
				Parent = setmetatable({}, {
					__index = function(_, n)
						return { __module = n }
					end,
				}),
			},
			require = function(t)
				return E.load(t.__module)
			end,
			CFrame = R.CFrame,
			Vector3 = R.Vector3,
			Color3 = R.Color3,
			Instance = R.Instance,
			Enum = R.Enum,
		},
	})()
end
function M.weapon(config, character)
	assert(config.parent and config.grip and config.tip, "fixed weapon needs parent, grip and tip")
	assert(not config.joints, "animated weapons need an extra-joint adapter")
	local model = R.Instance.new("Model")
	model.Name = config.name or "PreviewWeapon"
	local owner = character and assert(character:FindFirstChild(config.parent), "missing weapon parent")
	for _, g in config.geometry do
		local p = R.Instance.new("Part")
		p.Name = g.name
		p.Size = R.Vector3.new(table.unpack(g.size))
		p.Color = R.Color3.new(table.unpack(g.color))
		p.Material = R.Enum.Material.Metal
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		if g.shape then
			p.Shape = R.Enum.PartType[g.shape]
		end
		local offset = config.grip * g.cf
		p.CFrame = owner and owner.CFrame * offset or g.cf
		if owner then
			local w = R.Instance.new("Weld")
			w.Part0 = owner
			w.Part1 = p
			w.C0 = offset
			w.Parent = p
		end
		p.Parent = model
	end
	if character then
		model.Parent = character
	end
	return model
end
function M.geometry(config)
	local out = {}
	if config then
		for _, g in config.geometry do
			table.insert(out, {
				name = g.name,
				parent = config.parent,
				size = g.size,
				color = g.color,
				cf = { g.cf:GetComponents() },
				shape = g.shape or "Block",
			})
		end
	end
	return out
end
function M.isGripping(meta, frame)
	if not meta.gripWindows then
		return true
	end
	for _, range in meta.gripWindows do
		if frame >= range[1] and frame <= range[2] then
			return true
		end
	end
	return false
end
return M
