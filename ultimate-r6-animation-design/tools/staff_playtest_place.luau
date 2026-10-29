local E=require("./env")
local R,fs=E.roblox,E.fs
local root=R.deserializePlace(fs.readFile("../../../../work/base-playtest.rbxl"))
local world=root:GetService("Workspace")
for _,obj in world:GetChildren() do
 if obj.Name~="Baseplate" and obj.Name~="Camera" and not obj:IsA("Terrain") then obj:Destroy()end
end
local pack=R.deserializeModel(fs.readFile("../../../../outputs/StaffMageCombo4/StaffMageCombo4.rbxm"))[1]
pack.Name="StaffComboPack" pack.Parent=root:GetService("ReplicatedStorage")
local template=R.deserializeModel(fs.readFile("../../../../outputs/StaffMageCombo4/PreviewStaff.rbxm"))[1]
template.Parent=root:GetService("ReplicatedStorage")
local attach=R.Instance.new("ModuleScript") attach.Name="AttachStaff" attach.Source=fs.readFile("../../../../outputs/StaffMageCombo4/source/AttachStaff.luau") attach.Parent=root:GetService("ReplicatedStorage")
local starter=root:GetService("StarterPlayer")
if not starter:FindFirstChild("StarterPlayerScripts") then local p=R.Instance.new("StarterPlayerScripts") p.Parent=starter end
starter.StarterCharacter.HumanoidRootPart.CFrame=R.CFrame.new(0,3,0)
starter.StarterCharacterScripts.R6Test.Source=fs.readFile("../../../../work/staff-playtest-client.luau")
local light=root:GetService("Lighting") light.ClockTime=14 light.Brightness=2 light.Ambient=R.Color3.fromRGB(150,155,170)
fs.writeFile("../../../../outputs/StaffMageCombo4/StaffMage-Playtest.rbxl",R.serializePlace(root))
require("@lune/luau").compile(fs.readFile("../../../../work/staff-playtest-client.luau"))
print("Staff playtest place written and harness compiled")
