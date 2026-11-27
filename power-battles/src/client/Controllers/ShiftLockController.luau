-- Forced shift lock while in a match: mouse locked to centre, camera offset over the right
-- shoulder, character always faces where the camera looks. Off in menus and during POTG.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Combat = require(Shared.Config.Combat)
local State = require(script.Parent.Parent.ClientState)
local MovementController = require(script.Parent.MovementController)

local LocalPlayer = Players.LocalPlayer

local ShiftLockController = {}

local wasActive = false

local function isActive(): boolean
	if not State.InMatch() or State.POTGPlaying or State.ResultsShowing then
		return false
	end
	local character = LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function step()
	local character = LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart
	local active = isActive()

	if active and humanoid and root then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
		humanoid.AutoRotate = false
		humanoid.CameraOffset = humanoid.CameraOffset:Lerp(Combat.ShiftLockOffset, 0.25)
		if not MovementController.IsRagdolled() and not root.Anchored then
			local look = Workspace.CurrentCamera.CFrame.LookVector
			local flat = Vector3.new(look.X, 0, look.Z)
			if flat.Magnitude > 0.01 then
				root.CFrame = CFrame.lookAt(root.Position, root.Position + flat.Unit)
			end
		end
		wasActive = true
	elseif wasActive then
		wasActive = false
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
		if humanoid then
			humanoid.AutoRotate = true
			humanoid.CameraOffset = Vector3.zero
		end
	end
end

function ShiftLockController.Init()
	RunService:BindToRenderStep("PowerBattlesShiftLock", Enum.RenderPriority.Camera.Value + 1, step)
	local function applySensitivity()
		UserInputService.MouseDeltaSensitivity = State.Settings().Sensitivity or 1
	end
	State.DataChanged:Connect(applySensitivity)
	applySensitivity()
end

return ShiftLockController
