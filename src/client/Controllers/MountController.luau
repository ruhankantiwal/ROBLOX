--[[
	MountController: ride your Alpha.
	  PC       R toggles the mount, left click attacks while riding
	  Mobile   RIDE / ⚔️ buttons in the HUD
	  Gamepad  ButtonY toggles, ButtonR2 attacks
	The rider plays the sit pose borrowed from the default Animate script,
	so no animation uploads are needed.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)

local HUD = require(script.Parent.Parent.UI.HUD)

local LOCAL = Players.LocalPlayer

local MountController = { mounted = false }

local sitTrack: AnimationTrack? = nil
local lastAttack = 0

local function playSit(on: boolean)
	if sitTrack then
		sitTrack:Stop(0.2)
		sitTrack = nil
	end
	if not on then
		return
	end
	local character = LOCAL.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	local animate = character and character:FindFirstChild("Animate")
	local sit = animate and animate:FindFirstChild("sit")
	local anim = sit and sit:FindFirstChildOfClass("Animation")
	if animator and anim then
		local track = animator:LoadAnimation(anim)
		track.Priority = Enum.AnimationPriority.Action
		track.Looped = true
		track:Play(0.2)
		sitTrack = track
	end
end

function MountController.Toggle()
	Net.Event("ToggleMount"):FireServer()
end

function MountController.Attack()
	if not MountController.mounted or os.clock() - lastAttack < 0.15 then
		return
	end
	lastAttack = os.clock()
	local camera = workspace.CurrentCamera
	local aim = camera.CFrame.LookVector
	local mouse = UserInputService:GetMouseLocation()
	if UserInputService.MouseEnabled then
		local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
		local character = LOCAL.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			-- aim at where the cursor ray crosses the rider's height
			local t = if math.abs(ray.Direction.Y) > 1e-3 then (root.Position.Y - 2 - ray.Origin.Y) / ray.Direction.Y else 0
			if t > 0 then
				local hit = ray.Origin + ray.Direction * t
				aim = hit - root.Position
			end
		end
	end
	Net.Event("MountAttack"):FireServer(Vector3.new(aim.X, 0, aim.Z))
end

function MountController.Start()
	HUD.OnRideToggle = MountController.Toggle
	HUD.OnMountAttack = MountController.Attack

	Net.Event("MountState").OnClientEvent:Connect(function(userId, info)
		if userId ~= LOCAL.UserId then
			return
		end
		MountController.mounted = info ~= nil
		HUD.SetMounted(MountController.mounted)
		playSit(MountController.mounted)
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.R or input.KeyCode == Enum.KeyCode.ButtonY then
			MountController.Toggle()
		elseif MountController.mounted and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2) then
			MountController.Attack()
		end
	end)
	LOCAL.CharacterAdded:Connect(function()
		MountController.mounted = false
		HUD.SetMounted(false)
		sitTrack = nil
	end)
end

return MountController
