-- Reuse an existing pack plus an R6 base place; never fabricate an engine PASS offline.
local E = require("./env")
local U = require("./pack_support")
local R, fs = E.roblox, E.fs
local S = require("@lune/serde")
local path, out, base = E.args[1], E.args[2], E.args[3]
assert(path and out and base, "usage: lune run pack_demo <Moves.luau> <pack output> <base.rbxl>")
local M = U.loadFile(path)
local place = R.deserializePlace(fs.readFile(base))
local world = place:GetService("Workspace")
for _, o in world:GetChildren() do
	if o.Name ~= "Baseplate" and o.Name ~= "Camera" and not o:IsA("Terrain") then
		o:Destroy()
	end
end
local rep = place:GetService("ReplicatedStorage")
for _, o in rep:GetChildren() do
	o:Destroy()
end
local lib = R.Instance.new("Folder")
lib.Name = "PackPreview"
lib.Parent = rep
local clips = R.deserializeModel(fs.readFile(out .. "/" .. M.PACK .. ".rbxm"))[1]
clips.Name = "Animations"
clips.Parent = lib
local weapon = S.decode("json", fs.readFile(out .. "/weapon.json"))
if M.WEAPON then
	local model = R.deserializeModel(fs.readFile(out .. "/PreviewWeapon.rbxm"))[1]
	model.Name = "PreviewWeapon"
	model.Parent = lib
end
local audit = S.decode("json", fs.readFile(out .. "/audit.json"))
local manifest = R.Instance.new("StringValue")
manifest.Name = "Manifest"
manifest.Value = S.encode(
	"json",
	{ name = M.PACK, moves = M.LIST, seconds = audit[M.PACK].length / 60, weapon = weapon, audit = audit }
)
manifest.Parent = lib
local here = string.match(debug.info(1, "s"), "^(.*)[/\\][^/\\]*$") or "."
local starter = place:GetService("StarterPlayer")
if not starter:FindFirstChild("StarterPlayerScripts") then
	R.Instance.new("StarterPlayerScripts").Parent = starter
end
local scripts = starter:FindFirstChild("StarterCharacterScripts")
if not scripts then
	scripts = R.Instance.new("StarterCharacterScripts")
	scripts.Parent = starter
end
for _, o in scripts:GetChildren() do
	o:Destroy()
end
local animate = R.Instance.new("LocalScript")
animate.Name = "Animate"
animate.Parent = scripts
local client = R.Instance.new("LocalScript")
client.Name = "PackDemo"
client.Source = fs.readFile(here .. "/../assets/PackDemo.client.luau")
require("@lune/luau").compile(client.Source)
client.Parent = scripts
local rig = starter.StarterCharacter:Clone()
rig.Name = M.PACK .. "Rig"
for _, d in rig:GetDescendants() do
	if d:IsA("LuaSourceContainer") or d.Name == "AnimSaves" then
		d:Destroy()
	end
end
if M.WEAPON then
	U.weapon(M.WEAPON, rig)
end
local saves = clips:Clone()
saves.Name = "AnimSaves"
saves.Parent = rig
fs.writeFile(out .. "/" .. M.PACK .. "-Rig.rbxm", R.serializeModel({ rig }))
fs.writeFile(out .. "/" .. M.PACK .. "-Demo.rbxl", R.serializePlace(place))
print("[demo] compiled / rig + place / " .. out)
