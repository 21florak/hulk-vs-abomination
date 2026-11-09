-- Input for every role:
--   Giants:    Click / F = Smash   ·   Q = Roar (Abomination) / Thunderclap (Hulk)   ·   R = Leap
--   Civilians: Shift = Sprint (makes noise)   ·   F = Flashlight   ·   Space / E = leave a hiding spot
-- Phones get on-screen buttons. Prompts that don't fit your role are hidden.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Input = Remotes:WaitForChild("Input")
local ToClient = Remotes:WaitForChild("ToClient")

local hidden = false
local sprinting = false
local stamina = Config.Civilian.stamina
local localCooldowns = {}

local function role()
	return player:GetAttribute("Role")
end

local function parts()
	local character = player.Character
	return character, character and character:FindFirstChildOfClass("Humanoid"), character and character:FindFirstChild("HumanoidRootPart")
end

local function ready(key, seconds)
	local now = os.clock()
	if (localCooldowns[key] or 0) > now then
		return false
	end
	localCooldowns[key] = now + seconds
	return true
end

-- A big overhead swing for the local giant (visual only)
local function swing()
	local character = parts()
	local arm = character and character:FindFirstChild("RightUpperArm")
	local shoulder = arm and arm:FindFirstChild("RightShoulder")
	if not shoulder then
		return
	end
	task.spawn(function()
		local start = os.clock()
		while os.clock() - start < 0.35 do
			local t = (os.clock() - start) / 0.35
			shoulder.Transform = CFrame.Angles(math.rad(150) * math.sin(t * math.pi), 0, 0)
			RunService.RenderStepped:Wait()
		end
		shoulder.Transform = CFrame.identity
	end)
end

local function smash()
	local r = role()
	if r ~= "hulk" and r ~= "abomination" then
		return
	end
	local cfg = if r == "hulk" then Config.Hulk else Config.Abomination
	if not ready("smash", cfg.smashCooldown) then
		return
	end
	swing()
	local _, _, root = parts()
	if root then
		root.AssemblyLinearVelocity += root.CFrame.LookVector * 25
	end
	Input:FireServer("smash")
end

local function special()
	local r = role()
	if r == "hulk" then
		Input:FireServer("clap")
	elseif r == "abomination" then
		Input:FireServer("roar")
	end
end

local function leap()
	local r = role()
	if r ~= "hulk" and r ~= "abomination" then
		return
	end
	local cfg = if r == "hulk" then Config.Hulk else Config.Abomination
	if not ready("leap", cfg.leapCooldown) then
		return
	end
	local _, humanoid, root = parts()
	if root and humanoid and humanoid.WalkSpeed > 0 then
		local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
		root.AssemblyLinearVelocity = look.Unit * 75 + Vector3.new(0, 85, 0)
		Input:FireServer("leap")
	end
end

---------------------------------------------------------------------------
-- Bindings (rebuilt whenever your role changes)
---------------------------------------------------------------------------
local bound = {}
local function bind(name, fn, title, ...)
	ContextActionService:BindAction(name, function(_, state)
		if state == Enum.UserInputState.Begin then
			fn()
		end
		return Enum.ContextActionResult.Sink
	end, true, ...)
	ContextActionService:SetTitle(name, title)
	table.insert(bound, name)
end

local function unbindAll()
	for _, name in ipairs(bound) do
		ContextActionService:UnbindAction(name)
	end
	table.clear(bound)
	ContextActionService:UnbindAction("Sprint")
end

local function updatePrompts()
	local r = role()
	local facility = workspace:FindFirstChild("Facility")
	for _, d in ipairs(facility and facility:GetDescendants() or {}) do
		if d:IsA("ProximityPrompt") then
			if d.Name == "HidePrompt" then
				d.Enabled = r == "civilian" and not hidden
			elseif d.Name == "SearchPrompt" then
				d.Enabled = r == "abomination"
			end
		end
	end
end

local function applyRole()
	unbindAll()
	local r = role()
	if r == "hulk" or r == "abomination" then
		bind("GiantSmash", smash, "Smash", Enum.KeyCode.F, Enum.KeyCode.ButtonR2)
		bind("GiantSpecial", special, if r == "hulk" then "Clap" else "Roar", Enum.KeyCode.Q, Enum.KeyCode.ButtonX)
		bind("GiantLeap", leap, "Leap", Enum.KeyCode.R, Enum.KeyCode.ButtonY)
	elseif r == "civilian" then
		bind("Flashlight", function()
			Input:FireServer("flashlight")
		end, "Light", Enum.KeyCode.F, Enum.KeyCode.ButtonY)
		ContextActionService:BindAction("Sprint", function(_, state)
			sprinting = state == Enum.UserInputState.Begin
			return Enum.ContextActionResult.Pass
		end, true, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)
		ContextActionService:SetTitle("Sprint", "Run")
	end
	updatePrompts()
end
player:GetAttributeChangedSignal("Role"):Connect(applyRole)
applyRole()

-- New hiding spots appear every round
workspace.ChildAdded:Connect(function(child)
	if child.Name == "Facility" then
		task.wait(1)
		updatePrompts()
	end
end)

-- Left click smashes for giants
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		smash()
	elseif hidden and (input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.E) then
		Input:FireServer("leave")
	end
end)

-- Leaving a hiding spot on phones: tap the jump button
UserInputService.JumpRequest:Connect(function()
	if hidden then
		Input:FireServer("leave")
	end
end)

ToClient.OnClientEvent:Connect(function(kind)
	if kind == "Hidden" then
		hidden = true
		updatePrompts()
	elseif kind == "Unhidden" then
		hidden = false
		updatePrompts()
	end
end)

---------------------------------------------------------------------------
-- Sprint + stamina (civilians)
---------------------------------------------------------------------------
RunService.Heartbeat:Connect(function(dt)
	if role() ~= "civilian" then
		return
	end
	local _, humanoid = parts()
	if not humanoid or humanoid.WalkSpeed == 0 then
		return
	end
	local moving = humanoid.MoveDirection.Magnitude > 0.1
	if sprinting and moving and stamina > 0 then
		stamina = math.max(0, stamina - Config.Civilian.sprintDrain * dt)
		humanoid.WalkSpeed = Config.Civilian.sprintSpeed
	else
		stamina = math.min(Config.Civilian.stamina, stamina + Config.Civilian.staminaRegen * dt)
		humanoid.WalkSpeed = Config.Civilian.walkSpeed
	end
	player:SetAttribute("Stamina", math.floor(stamina))
end)

-- Show only the prompts that make sense for you
ProximityPromptService.PromptShown:Connect(function(prompt)
	if prompt.Name == "HidePrompt" and (role() ~= "civilian" or hidden) then
		prompt.Enabled = false
	elseif prompt.Name == "SearchPrompt" and role() ~= "abomination" then
		prompt.Enabled = false
	end
end)
