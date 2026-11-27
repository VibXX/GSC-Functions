-- Sprint (hold), dash with i-frames (server validates), double jump with ability-coloured VFX,
-- status effects (slow / root / stun), knockback and ragdoll physics for the local character.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Combat = require(Shared.Config.Combat)
local Swords = require(Shared.Config.Swords)
local Animations = require(Shared.Config.Animations)
local Keybinds = require(Shared.Config.Keybinds)
local Anim = require(Shared.Lib.Anim)
local State = require(script.Parent.Parent.ClientState)
local FxController = require(script.Parent.FxController)

local LocalPlayer = Players.LocalPlayer

local MovementController = {}

local sprinting = false
local airJumpsUsed = 0
local lastJumpRequest = 0
local dashing = false
local ragdolled = false

local function character(): Model?
	return LocalPlayer.Character
end

local function humanoid(): Humanoid?
	local c = character()
	return c and c:FindFirstChildOfClass("Humanoid")
end

local function root(): BasePart?
	local c = character()
	return c and c:FindFirstChild("HumanoidRootPart") :: BasePart
end

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

-- Movement is locked while stunned / rooted / ragdolled / anchored (countdown).
function MovementController.CanMove(): boolean
	local c, r = character(), root()
	if not c or not r or r.Anchored or ragdolled then
		return false
	end
	local now = serverNow()
	if (c:GetAttribute("StunnedUntil") or 0) > now or (c:GetAttribute("RootedUntil") or 0) > now then
		return false
	end
	return State.InMatch() and not State.POTGPlaying
end

local function applyVelocity(velocity: Vector3, duration: number)
	local r = root()
	if not r then
		return
	end
	local attachment = r:FindFirstChild("RootAttachment") :: Attachment
	if not attachment then
		return
	end
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = attachment
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.MaxForce = 1e6
	lv.VectorVelocity = velocity
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.Parent = r
	task.delay(duration, function()
		lv:Destroy()
	end)
end

local function dash()
	if dashing or not MovementController.CanMove() or State.CooldownRemaining("Dash") > 0 then
		return
	end
	local h, r = humanoid(), root()
	if not h or not r then
		return
	end
	local camera = Workspace.CurrentCamera
	local direction = h.MoveDirection
	if direction.Magnitude < 0.1 then
		local look = camera.CFrame.LookVector
		direction = Vector3.new(look.X, 0, look.Z)
	end
	direction = direction.Unit
	dashing = true
	State.StartCooldown("Dash", Combat.Dash.Cooldown)
	Net.Event("Dash"):FireServer(direction)

	-- Pick a directional animation relative to where the camera faces.
	local camFlat = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z).Unit
	local camRight = Vector3.new(camera.CFrame.RightVector.X, 0, camera.CFrame.RightVector.Z).Unit
	local forward, right = direction:Dot(camFlat), direction:Dot(camRight)
	local anim
	if math.abs(forward) >= math.abs(right) then
		anim = forward >= 0 and Animations.DashForward or Animations.DashBack
	else
		anim = right >= 0 and Animations.DashRight or Animations.DashLeft
	end
	Anim.Play(character(), anim, 0.05)

	local speed = Combat.Dash.Distance / Combat.Dash.Duration
	applyVelocity(direction * speed + Vector3.new(0, 2, 0), Combat.Dash.Duration)
	FxController.Dash(character())
	task.delay(Combat.Dash.Duration, function()
		dashing = false
	end)
end

local function doubleJump()
	local h, r = humanoid(), root()
	if not h or not r or not MovementController.CanMove() then
		return
	end
	if os.clock() - lastJumpRequest < 0.2 then
		return
	end
	lastJumpRequest = os.clock()
	local airborne = h.FloorMaterial == Enum.Material.Air
	local state = h:GetState()
	if not airborne or (state ~= Enum.HumanoidStateType.Freefall and state ~= Enum.HumanoidStateType.Jumping) then
		return
	end
	if airJumpsUsed >= Combat.AirJumps then
		return
	end
	airJumpsUsed += 1
	local v = r.AssemblyLinearVelocity
	r.AssemblyLinearVelocity = Vector3.new(v.X, Combat.DoubleJumpPower, v.Z)
	h:ChangeState(Enum.HumanoidStateType.Jumping)
	Anim.Play(character(), Animations.DoubleJump, 0.05)
	FxController.DoubleJump(character())
	Net.Event("DoubleJump"):FireServer()
end

local function onRagdoll(enabled: boolean, duration: number, velocity: Vector3)
	local h, r = humanoid(), root()
	if not h or not r then
		return
	end
	ragdolled = enabled
	if enabled then
		h:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
		h:ChangeState(Enum.HumanoidStateType.Physical)
		r.AssemblyLinearVelocity = velocity
		r.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 8
	else
		h:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
		h:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end

local function updateSpeed()
	local h, c = humanoid(), character()
	if not h or not c then
		return
	end
	if not State.InMatch() then
		return
	end
	if not MovementController.CanMove() then
		h.WalkSpeed = 0
		h.JumpPower = 0
		return
	end
	local swordId = c:GetAttribute("SwordId")
	local mult = swordId and Swords.GetStats(swordId, 1, true).MoveSpeedMultiplier or 1
	local now = serverNow()
	if (c:GetAttribute("SlowUntil") or 0) > now then
		mult *= c:GetAttribute("SlowMult") or 1
	end
	local base = (sprinting and h.MoveDirection.Magnitude > 0.1) and Combat.SprintSpeed or Combat.WalkSpeed
	h.WalkSpeed = base * mult
	h.JumpPower = Combat.JumpPower

	-- Sprint FOV kick
	local camera = Workspace.CurrentCamera
	local targetFov = State.Settings().FieldOfView + ((sprinting and h.MoveDirection.Magnitude > 0.1) and Combat.SprintFovBoost or 0)
	camera.FieldOfView += (targetFov - camera.FieldOfView) * 0.15
end

local function onCharacter(c: Model)
	airJumpsUsed = 0
	ragdolled = false
	dashing = false
	local h = c:WaitForChild("Humanoid") :: Humanoid
	h.UseJumpPower = true
	h.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Landed or new == Enum.HumanoidStateType.Running then
			airJumpsUsed = 0
		end
	end)
end

function MovementController.Init()
	Net.Event("Ragdoll").OnClientEvent:Connect(onRagdoll)
	Net.Event("Knockback").OnClientEvent:Connect(function(velocity)
		if not ragdolled and typeof(velocity) == "Vector3" then
			applyVelocity(velocity, 0.15)
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local binds = State.Binds()
		if Keybinds.Matches(input, "Sprint", binds) then
			sprinting = true
			Anim.Play(character(), Animations.Sprint, 0.2)
		elseif Keybinds.Matches(input, "Dash", binds) then
			dash()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if Keybinds.Matches(input, "Sprint", State.Binds()) then
			sprinting = false
			Anim.Stop(character(), Animations.Sprint, 0.2)
		end
	end)
	UserInputService.JumpRequest:Connect(doubleJump)

	LocalPlayer.CharacterAdded:Connect(onCharacter)
	if LocalPlayer.Character then
		task.spawn(onCharacter, LocalPlayer.Character)
	end
	RunService.Heartbeat:Connect(updateSpeed)

	-- Leaving a match: restore default FOV.
	State.ViewChanged:Connect(function()
		if not State.InMatch() then
			TweenService:Create(Workspace.CurrentCamera, TweenInfo.new(0.3), { FieldOfView = 70 }):Play()
		end
	end)
end

function MovementController.IsRagdolled(): boolean
	return ragdolled
end

return MovementController
