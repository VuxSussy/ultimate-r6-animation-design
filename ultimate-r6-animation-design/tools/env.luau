-- Loads the skill's Roblox ModuleScripts (../scripts/*.luau) inside Lune, with Lune's Roblox types
-- standing in for the engine's. `require(script.Parent.X)` inside a module resolves to scripts/X.luau.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local process = require("@lune/process")

local here = string.match(debug.info(1, "s"), "^(.*)[/\\][^/\\]*$") or "."
local scriptsDir = here .. "/../scripts"

local env = {}
local loaded = {}

local parentProxy = setmetatable({}, {
	__index = function(_, name)
		return { __module = name }
	end,
})

local function load(name)
	if loaded[name] then
		return loaded[name]
	end
	local path = scriptsDir .. "/" .. name .. ".luau"
	local source = fs.readFile(path)
	local moduleEnv = setmetatable({
		script = { Name = name, Parent = parentProxy },
		require = function(target)
			if type(target) == "table" and target.__module then
				return load(target.__module)
			end
			return require(target)
		end,
		CFrame = roblox.CFrame,
		Vector3 = roblox.Vector3,
		Vector2 = roblox.Vector2,
		Color3 = roblox.Color3,
		NumberSequence = roblox.NumberSequence,
		Instance = roblox.Instance,
		Enum = roblox.Enum,
		typeof = typeof,
	}, { __index = env })
	local chunk = luau.load(source, { debugName = name, environment = moduleEnv })
	local result = chunk()
	loaded[name] = result
	return result
end

-- Syntax/compile check only, for modules that need live engine services to run.
local function compile(name)
	local source = fs.readFile(scriptsDir .. "/" .. name .. ".luau")
	luau.compile(source)
	return true
end

local function listModules()
	local out = {}
	for _, file in fs.readDir(scriptsDir) do
		local name = string.match(file, "^(.+)%.luau$")
		if name then
			table.insert(out, name)
		end
	end
	table.sort(out)
	return out
end

return {
	load = load,
	compile = compile,
	list = listModules,
	roblox = roblox,
	args = process.args,
	fs = fs,
}
