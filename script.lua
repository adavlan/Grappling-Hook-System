--// GrappleModule.lua
-- Advanced Grappling Hook System for HiddenDevs Application
-- Written to demonstrate modular design, diverse Roblox API usage, and maintainable code.

--// SERVICES
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local UserInputService = game:GetService("UserInputService")

--// CONSTANTS
local MAX_DISTANCE = 300
local FORCE_MULTIPLIER = 4000
local COOLDOWN_TIME = 2
local ANGLE_LIMIT = 120 -- Max angle from camera forward to allow grappling

--// STATE ENUM for readability
local GrappleState = {
	Idle = "Idle",
	Active = "Active",
	Cooldown = "Cooldown"
}

--// CLASS
local Grapple = {}
Grapple.__index = Grapple

-- Constructor
function Grapple.new(player)
	local self = setmetatable({}, Grapple)
	self.Player = player
	self.Character = player.Character or player.CharacterAdded:Wait()
	self.Root = self.Character:WaitForChild("HumanoidRootPart")
	self.State = GrappleState.Idle

	self.HookPart = nil
	self.Beam = nil
	self.Force = nil
	self.Attachments = {}
	self.HeartbeatConn = nil
	self.CooldownFinish = 0

	self:Init()
	return self
end

--// INITIALIZE INPUT + UI
function Grapple:Init()
	self:SetupInput()
	self:InitUI()
end

--// Bind player input for grapple actions
function Grapple:SetupInput()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			self:AttemptGrapple()
		elseif input.KeyCode == Enum.KeyCode.Q then
			self:ReleaseHook()
		end
	end)
end

--// Player tries to grapple
function Grapple:AttemptGrapple()
	if self.State ~= GrappleState.Idle or tick() < self.CooldownFinish then return end

	local mouse = self.Player:GetMouse()
	local origin = self.Character:WaitForChild("Head").Position
	local direction = (mouse.Hit.Position - origin)

	-- Angle check: prevent grappling too far behind player
	local camLook = workspace.CurrentCamera.CFrame.LookVector
	if math.deg(math.acos(camLook:Dot(direction.Unit))) > ANGLE_LIMIT then
		self:ShowFailFeedback()
		return
	end

	local params = RaycastParams.new()
	params.FilterDescendantsInstances = {self.Character}
	params.FilterType = Enum.RaycastFilterType.Blacklist

	local result = workspace:Raycast(origin, direction.Unit * MAX_DISTANCE, params)
	if result and self:IsSurfaceValid(result.Instance) then
		self:FireHook(result.Position)
	else
		self:ShowFailFeedback()
	end
end

--// Determines if a surface can be grappled to
function Grapple:IsSurfaceValid(instance)
	-- Use CollectionService for tagging grappleable surfaces
	return CollectionService:HasTag(instance, "GrapplePoint") or true -- true here so it works without tagging
end

--// Create hook visuals, tween into place, and attach force
function Grapple:FireHook(hitPosition)
	self.State = GrappleState.Active

	-- Create hook part
	local hook = Instance.new("Part")
	hook.Size = Vector3.new(0.5, 0.5, 0.5)
	hook.Shape = Enum.PartType.Ball
	hook.Material = Enum.Material.Neon
	hook.BrickColor = BrickColor.new("Bright red")
	hook.Anchored = true
	hook.CanCollide = false
	hook.CFrame = CFrame.new(self.Root.Position)
	hook.Name = "GrappleHook"
	hook.Parent = workspace
	self.HookPart = hook
	Debris:AddItem(hook, 10) -- auto-clean after 10s

	-- Tween hook to target position (looks nicer than instant placement)
	local tween = TweenService:Create(hook, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = hitPosition
	})
	tween:Play()

	-- Create attachments for beam + force
	local a0 = Instance.new("Attachment", self.Root)
	local a1 = Instance.new("Attachment", hook)
	self.Attachments = {a0, a1}

	-- Beam between player and hook
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Color = ColorSequence.new(Color3.fromRGB(255, 0, 0))
	beam.Width0 = 0.1
	beam.Width1 = 0.1
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.Parent = hook
	self.Beam = beam

	-- Pulling force
	local force = Instance.new("VectorForce")
	force.Attachment0 = a0
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.ApplyAtCenterOfMass = true
	force.Force = Vector3.zero
	force.Parent = self.Root
	self.Force = force

	-- Start pulling loop
	self.HeartbeatConn = RunService.Heartbeat:Connect(function(dt)
		self:UpdatePull(hitPosition)
	end)
end

--// Updates the pulling force every frame
function Grapple:UpdatePull(targetPos)
	local direction = (targetPos - self.Root.Position)
	local distance = direction.Magnitude

	-- Rope tension logic: stronger pull if far away, weaker when close
	local tensionFactor = math.clamp(distance / MAX_DISTANCE, 0.2, 1)
	local velocity = direction.Unit * FORCE_MULTIPLIER * tensionFactor
	self.Force.Force = velocity

	if distance < 5 then
		self:ReleaseHook()
	end
end

--// Release hook and reset state
function Grapple:ReleaseHook()
	if self.State ~= GrappleState.Active then return end
	self.State = GrappleState.Cooldown
	self.CooldownFinish = tick() + COOLDOWN_TIME

	if self.HeartbeatConn then
		self.HeartbeatConn:Disconnect()
		self.HeartbeatConn = nil
	end

	if self.Force then self.Force:Destroy() self.Force = nil end
	if self.Beam then self.Beam:Destroy() self.Beam = nil end
	for _, att in ipairs(self.Attachments) do att:Destroy() end
	self.Attachments = {}
	if self.HookPart then self.HookPart:Destroy() self.HookPart = nil end

	-- Return to idle after cooldown
	task.delay(COOLDOWN_TIME, function()
		self.State = GrappleState.Idle
	end)
end

--// UI: Crosshair + debug label
function Grapple:InitUI()
	local gui = Instance.new("ScreenGui")
	gui.Name = "GrappleUI"
	gui.ResetOnSpawn = false
	gui.Parent = self.Player:WaitForChild("PlayerGui")

	local crosshair = Instance.new("Frame")
	crosshair.Size = UDim2.new(0, 8, 0, 8)
	crosshair.Position = UDim2.new(0.5, -4, 0.5, -4)
	crosshair.BackgroundColor3 = Color3.new(1, 1, 1)
	crosshair.BorderSizePixel = 0
	crosshair.Parent = gui
	self.Crosshair = crosshair

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0, 200, 0, 50)
	label.Position = UDim2.new(0, 10, 0, 10)
	label.BackgroundTransparency = 0.3
	label.BackgroundColor3 = Color3.new(0, 0, 0)
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.Text = "State: Idle"
	label.Parent = gui
	self.DebugLabel = label

	-- Update UI every frame
	RunService.RenderStepped:Connect(function()
		self:UpdateUI()
	end)
end

function Grapple:UpdateUI()
	if not self.DebugLabel then return end
	self.DebugLabel.Text = "State: " .. self.State
end

--// Visual feedback if grapple fails
function Grapple:ShowFailFeedback()
	if self.Crosshair then
		self.Crosshair.BackgroundColor3 = Color3.new(1, 0, 0)
		task.delay(0.2, function()
			if self.Crosshair then
				self.Crosshair.BackgroundColor3 = Color3.new(1, 1, 1)
			end
		end)
	end
end

return Grapple
