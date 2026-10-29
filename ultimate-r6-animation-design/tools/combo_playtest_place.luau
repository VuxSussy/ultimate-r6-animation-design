local E=require("./env")
local R,fs=E.roblox,E.fs
local root=R.deserializePlace(fs.readFile("../../../../work/base-playtest.rbxl"))
local world=root:GetService("Workspace")
for _,obj in world:GetChildren() do
 if obj.Name~="Baseplate" and obj.Name~="Camera" and not obj:IsA("Terrain") then obj:Destroy()end
end
local pack=R.deserializeModel(fs.readFile("../../../../outputs/SwordCombo4.rbxm"))[1]
pack.Name="SwordComboPack" pack.Parent=root:GetService("ReplicatedStorage")
local starter=root:GetService("StarterPlayer")
starter.StarterCharacter.HumanoidRootPart.CFrame=R.CFrame.new(0,3,0)
starter.StarterCharacterScripts.R6Test.Source=fs.readFile("../../../../work/playtest-client.luau")
local light=root:GetService("Lighting") light.ClockTime=14 light.Brightness=2 light.Ambient=R.Color3.fromRGB(150,155,170)
fs.writeFile("../../../../outputs/SwordCombo4-Playtest.rbxl",R.serializePlace(root))
print("Playtest place written")
