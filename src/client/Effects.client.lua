-- Atmosphere and fear: role-based vision, heartbeat when the Abomination is near, camera
-- shake, lightning through the windows, flickering emergency lights, the hiding-spot peek
-- camera, and the Abomination's senses (revealed heartbeats, footstep ripples).
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local ToClient = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ToClient")

local function role()
	return player:GetAttribute("Role")
end

---------------------------------------------------------------------------
-- Sounds (only the ones with ids filled in Config.Sounds)
---------------------------------------------------------------------------
local sounds = {}
for name, id in pairs(Config.Sounds) do
	if id ~= "" then
		local s = Instance.new("Sound")
		s.Name = name
		s.SoundId = id
		s.Volume = 0.7
		s.Looped = name == "ambience" or name == "heartbeat"
		s.Parent = SoundService
		sounds[name] = s
	end
end
local function play(name, volume)
	local s = sounds[name]
	if s then
		s.Volume = volume or 0.7
		if not s.Looped then
			s:Play()
		elseif not s.IsPlaying then
			s:Play()
		end
	end
end
if sounds.ambience then
	sounds.ambience.Volume = 0.35
	sounds.ambience:Play()
end

-- 3D sound at a point in the world: louder the closer you are to it
local function playAt(name, position, volume, pitch)
	local template = sounds[name]
	if not template then
		return
	end
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Position = position
	local sound = template:Clone()
	sound.Looped = false
	sound.Volume = volume or 1
	sound.PlaybackSpeed = pitch or 1
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 20
	sound.RollOffMaxDistance = 320
	sound.Parent = anchor
	anchor.Parent = Workspace
	sound:Play()
	task.delay(8, function()
		anchor:Destroy()
	end)
end

---------------------------------------------------------------------------
-- Role vision
---------------------------------------------------------------------------
local grade = Instance.new("ColorCorrectionEffect")
grade.Name = "RoleVision"
grade.Parent = Lighting
local baseAmbient = Lighting.Ambient

local VISION = {
	civilian = { tint = Color3.fromRGB(200, 210, 230), saturation = -0.4, contrast = 0.12, brightness = 0.01, ambient = Color3.fromRGB(16, 16, 22) },
	abomination = { tint = Color3.fromRGB(255, 235, 150), saturation = -0.6, contrast = 0.25, brightness = 0.04, ambient = Color3.fromRGB(28, 26, 18) },
	hulk = { tint = Color3.fromRGB(215, 255, 205), saturation = -0.3, contrast = 0.15, brightness = 0.02, ambient = Color3.fromRGB(20, 24, 18) },
}
local function applyVision()
	local v = VISION[role()]
	if v then
		grade.TintColor = v.tint
		grade.Saturation = v.saturation
		grade.Contrast = v.contrast
		grade.Brightness = v.brightness
		baseAmbient = v.ambient
	else
		grade.TintColor = Color3.new(1, 1, 1)
		grade.Saturation = 0
		grade.Contrast = 0
		grade.Brightness = 0
		baseAmbient = Color3.fromRGB(6, 6, 9)
	end
	Lighting.Ambient = baseAmbient
end
player:GetAttributeChangedSignal("Role"):Connect(applyVision)
applyVision()

---------------------------------------------------------------------------
-- Screen overlays: red vignette (heartbeat), flash
---------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "Fear"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = -1
gui.Parent = player:WaitForChild("PlayerGui")

local vignette = {}
for _, spec in ipairs({
	{ UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.22), 90 },
	{ UDim2.fromScale(0, 0.78), UDim2.fromScale(1, 0.22), 270 },
	{ UDim2.fromScale(0, 0), UDim2.fromScale(0.18, 1), 0 },
	{ UDim2.fromScale(0.82, 0), UDim2.fromScale(0.18, 1), 180 },
}) do
	local f = Instance.new("Frame")
	f.Position = spec[1]
	f.Size = spec[2]
	f.BorderSizePixel = 0
	f.BackgroundColor3 = Color3.fromRGB(160, 0, 0)
	f.BackgroundTransparency = 1
	local g = Instance.new("UIGradient")
	g.Rotation = spec[3]
	g.Transparency = NumberSequence.new(0, 1)
	g.Parent = f
	f.Parent = gui
	table.insert(vignette, f)
end

local flash = Instance.new("Frame")
flash.Size = UDim2.fromScale(1, 1)
flash.BorderSizePixel = 0
flash.BackgroundColor3 = Color3.new(1, 1, 1)
flash.BackgroundTransparency = 1
flash.Parent = gui
local function screenFlash(color, strength, seconds)
	flash.BackgroundColor3 = color
	flash.BackgroundTransparency = 1 - strength
	TweenService:Create(flash, TweenInfo.new(seconds or 0.4), { BackgroundTransparency = 1 }):Play()
end

local whisper = Instance.new("TextLabel")
whisper.AnchorPoint = Vector2.new(0.5, 0)
whisper.Position = UDim2.fromScale(0.5, 0.72)
whisper.Size = UDim2.new(0.6, 0, 0, 30)
whisper.BackgroundTransparency = 1
whisper.Font = Enum.Font.Antique
whisper.TextSize = 26
whisper.TextColor3 = Color3.fromRGB(220, 60, 50)
whisper.TextTransparency = 1
whisper.Text = ""
whisper.Parent = gui

---------------------------------------------------------------------------
-- Camera shake
---------------------------------------------------------------------------
local shake = 0
local function addShake(amount)
	shake = math.min(3, shake + amount)
end
local function shakeFrom(position, power, range)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local from = if root then root.Position else camera.CFrame.Position
	local d = (from - position).Magnitude
	if d < range then
		addShake(power * (1 - d / range))
	end
end

---------------------------------------------------------------------------
-- Hiding camera: peek out through the slats
---------------------------------------------------------------------------
local hiddenAt = nil
local yaw, pitch = 0, 0
local slats = Instance.new("Frame")
slats.Size = UDim2.fromScale(1, 1)
slats.BackgroundTransparency = 1
slats.Visible = false
slats.Parent = gui
for k = 0, 6 do
	local bar = Instance.new("Frame")
	bar.BorderSizePixel = 0
	bar.BackgroundColor3 = Color3.fromRGB(5, 5, 6)
	bar.Position = UDim2.fromScale(0, k / 7)
	bar.Size = UDim2.new(1, 0, 1 / 7, -18)
	bar.Parent = slats
end
local hint = Instance.new("TextLabel")
hint.AnchorPoint = Vector2.new(0.5, 1)
hint.Position = UDim2.new(0.5, 0, 1, -20)
hint.Size = UDim2.new(0.6, 0, 0, 24)
hint.BackgroundTransparency = 1
hint.Font = Enum.Font.GothamBold
hint.TextSize = 16
hint.TextColor3 = Color3.fromRGB(200, 200, 200)
hint.Text = "Hiding... stay still.   Space / E to get out"
hint.Parent = slats

UserInputService.InputChanged:Connect(function(input)
	if hiddenAt and input.UserInputType == Enum.UserInputType.MouseMovement then
		yaw = math.clamp(yaw - input.Delta.X * 0.004, -0.6, 0.6)
		pitch = math.clamp(pitch - input.Delta.Y * 0.004, -0.35, 0.35)
	end
end)

---------------------------------------------------------------------------
-- The Abomination's senses: revealed heartbeats and footstep ripples
---------------------------------------------------------------------------
local function heartMarker(position, seconds)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Position = position
	anchor.Parent = Workspace
	local bill = Instance.new("BillboardGui")
	bill.Size = UDim2.fromOffset(60, 60)
	bill.AlwaysOnTop = true
	bill.LightInfluence = 0
	local heart = Instance.new("TextLabel")
	heart.Size = UDim2.fromScale(1, 1)
	heart.BackgroundTransparency = 1
	heart.TextScaled = true
	heart.Text = "❤️"
	heart.Parent = bill
	bill.Parent = anchor
	task.spawn(function()
		local start = os.clock()
		while os.clock() - start < seconds do
			local beat = math.abs(math.sin((os.clock() - start) * 7))
			bill.Size = UDim2.fromOffset(40 + beat * 30, 40 + beat * 30)
			RunService.RenderStepped:Wait()
		end
		anchor:Destroy()
	end)
end

local function ripple(position)
	local ring = Instance.new("Part")
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(255, 80, 60)
	ring.Transparency = 0.3
	ring.Size = Vector3.new(0.2, 2, 2)
	ring.CFrame = CFrame.new(position - Vector3.new(0, 2.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = Workspace
	TweenService:Create(ring, TweenInfo.new(1.2), { Size = Vector3.new(0.2, 26, 26), Transparency = 1 }):Play()
	task.delay(1.3, function()
		ring:Destroy()
	end)
end

---------------------------------------------------------------------------
-- Lights: flickering emergency lights, lightning through the windows
---------------------------------------------------------------------------
local blackout = false
local failing = false
local function emergencyLights()
	local list, tubes = {}, {}
	local facility = Workspace:FindFirstChild("Facility")
	for _, d in ipairs(facility and facility:GetDescendants() or {}) do
		if d:IsA("BasePart") and (d.Name == "EmergencyLight" or d.Name == "HallLight") then
			local light = d:FindFirstChildOfClass("Light")
			if light then
				table.insert(if d.Name == "HallLight" then tubes else list, light)
			end
		end
	end
	return list, tubes
end

-- Fluorescent tubes at the hallway ends: mostly on, with bursts of nervous flicker
local tubeState = {} -- light -> { flickerUntil, nextBurst }
local function flickerTube(light, now)
	local state = tubeState[light]
	if not state then
		state = { flickerUntil = 0, nextBurst = now + math.random() * 6 }
		tubeState[light] = state
	end
	if now >= state.nextBurst then
		state.flickerUntil = now + 0.4 + math.random() * 1.4
		state.nextBurst = now + (if blackout then 1 + math.random() * 3 else 3 + math.random() * 8)
	end
	local on
	if failing then
		on = math.random() < 0.5
	elseif now < state.flickerUntil then
		on = math.random() < 0.45
	else
		on = not blackout or math.random() < 0.8
	end
	light.Enabled = on
	if light.Parent then
		light.Parent.Transparency = if on then 0 else 0.7
	end
end

task.spawn(function()
	while true do
		task.wait(0.12)
		local lights, tubes = emergencyLights()
		local now = os.clock()
		for _, tube in ipairs(tubes) do
			if tube.Parent and tube.Parent.Material == Enum.Material.Neon then
				flickerTube(tube, now)
			end
		end
		for _, light in ipairs(lights) do
			if light.Parent and light.Parent.Material == Enum.Material.Neon then
				local on
				if failing then
					on = math.floor(os.clock() * 3) % 2 == 0 -- alarm strobe
				elseif blackout then
					on = math.random() < 0.35
				else
					on = math.random() < 0.93
				end
				light.Enabled = on
			end
		end
	end
end)

task.spawn(function()
	while true do
		task.wait(math.random(14, 30))
		local r = role()
		if r == "civilian" or r == "hulk" or r == "abomination" then
			-- two quick flashes: for a split second you can see the whole hallway
			for _ = 1, 2 do
				Lighting.Ambient = Color3.fromRGB(110, 115, 140)
				task.wait(0.07)
				Lighting.Ambient = baseAmbient
				task.wait(0.12)
			end
			task.delay(1.2, function()
				addShake(0.4) -- thunder
				play("thunder", 0.7)
			end)
		end
	end
end)

---------------------------------------------------------------------------
-- Every frame: heartbeat, shake, hiding camera
---------------------------------------------------------------------------
local function findAbomination()
	for _, other in ipairs(Players:GetPlayers()) do
		if other:GetAttribute("Role") == "abomination" and other.Character then
			return other.Character:FindFirstChild("HumanoidRootPart")
		end
	end
	for _, model in ipairs(Workspace:GetChildren()) do
		if model:IsA("Model") and model:GetAttribute("Role") == "abomination" then
			return model:FindFirstChild("HumanoidRootPart")
		end
	end
	return nil
end

-- Giant footsteps: a heavy stomp every stride while a giant is moving, from where it is
local stepTimers = {}
local function giants()
	local list = {}
	for _, model in ipairs(Workspace:GetChildren()) do
		if model:IsA("Model") and (model:GetAttribute("Role") == "abomination" or model:GetAttribute("Role") == "hulk") then
			table.insert(list, model)
		end
	end
	return list
end
task.spawn(function()
	while true do
		task.wait(0.1)
		if sounds.stomp then
			for _, model in ipairs(giants()) do
				local root = model:FindFirstChild("HumanoidRootPart")
				if root then
					local speed = (root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude
					local next = stepTimers[model] or 0
					if speed > 4 and os.clock() >= next then
						stepTimers[model] = os.clock() + math.clamp(9 / speed, 0.35, 0.8)
						local deep = if model:GetAttribute("Role") == "abomination" then 0.75 else 0.9
						playAt("stomp", root.Position - Vector3.new(0, 6, 0), 1.1, deep + math.random() * 0.08)
					end
				end
			end
		end
	end
end)

local WHISPERS = { "it's close...", "don't breathe.", "it can hear you.", "stay still...", "it's right there." }
local nextWhisper = 0

RunService:BindToRenderStep("Fear", Enum.RenderPriority.Camera.Value + 1, function(dt)
	local r = role()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")

	-- Heartbeat: civilians feel the Abomination getting closer
	local intensity = 0
	if r == "civilian" and root then
		local abom = findAbomination()
		if abom then
			local d = (abom.Position - root.Position).Magnitude
			intensity = math.clamp(1 - d / 65, 0, 1)
		end
	end
	local beat = math.abs(math.sin(os.clock() * (3 + intensity * 6)))
	for _, f in ipairs(vignette) do
		f.BackgroundTransparency = 1 - intensity * (0.45 + beat * 0.4)
	end
	if sounds.heartbeat then
		if intensity > 0.05 then
			play("heartbeat")
			sounds.heartbeat.Volume = intensity
			sounds.heartbeat.PlaybackSpeed = 0.8 + intensity * 0.8
		else
			sounds.heartbeat:Stop()
		end
	end
	if intensity > 0.55 then
		addShake(intensity * 0.02)
		if os.clock() > nextWhisper then
			nextWhisper = os.clock() + 4
			whisper.Text = WHISPERS[math.random(1, #WHISPERS)]
			whisper.TextTransparency = 0.1
			TweenService:Create(whisper, TweenInfo.new(2.5), { TextTransparency = 1 }):Play()
		end
	end

	-- Hiding camera
	if hiddenAt then
		camera.CameraType = Enum.CameraType.Scriptable
		local breathe = math.sin(os.clock() * 1.6) * 0.02
		camera.CFrame = hiddenAt * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch + breathe, 0, 0)
	end

	-- Shake
	if shake > 0.001 then
		local s = shake * 0.35
		camera.CFrame *= CFrame.new(math.random(-100, 100) / 100 * s, math.random(-100, 100) / 100 * s, 0) * CFrame.Angles(0, 0, math.random(-100, 100) / 100 * s * 0.03)
		shake = math.max(0, shake - dt * 2.2)
	end
end)

---------------------------------------------------------------------------
-- Server events
---------------------------------------------------------------------------
ToClient.OnClientEvent:Connect(function(kind, a, b, c)
	if kind == "Blast" then
		shakeFrom(a, 0.25 + math.min(c or 0, 10) * 0.05, 90)
		if (c or 0) > 0 then
			playAt("smash", a, 0.6 + math.min(c, 10) * 0.05, 0.9 + math.random() * 0.2)
		end
	elseif kind == "Smash" then
		shakeFrom(b, 0.4, 70)
		playAt("smash", b, 0.8, 0.85 + math.random() * 0.25)
	elseif kind == "Roar" then
		shakeFrom(a, 1.6, 140)
		playAt("roar", a, 1.4, 0.92 + math.random() * 0.12)
		if role() == "civilian" then
			screenFlash(Color3.fromRGB(120, 0, 0), 0.35, 1.2)
		end
	elseif kind == "Roared" then
		whisper.Text = "it sensed you."
		whisper.TextTransparency = 0
		TweenService:Create(whisper, TweenInfo.new(2.5), { TextTransparency = 1 }):Play()
	elseif kind == "Clap" then
		shakeFrom(a, 2, 120)
		screenFlash(Color3.new(1, 1, 1), 0.25, 0.5)
		playAt("smash", a, 1.4, 0.6)
		playAt("thunder", a, 0.8, 1.6)
	elseif kind == "Stomp" or kind == "Shatter" then
		shakeFrom(a, 1, 100)
		playAt(if kind == "Stomp" then "stomp" else "smash", a, 1.3, if kind == "Stomp" then 0.8 else 1.3)
	elseif kind == "Collapse" then
		shakeFrom(a, 1.4, 130)
		playAt("smash", a, 1.3, 0.7)
	elseif kind == "ChaosEvent" then
		if a == "blackout" then
			blackout = true
		elseif a == "failing" then
			failing = true
			play("alarm", 0.5)
		end
		addShake(0.8)
	elseif kind == "Hidden" then
		hiddenAt = a
		yaw, pitch = 0, 0
		slats.Visible = true
	elseif kind == "Unhidden" then
		hiddenAt = nil
		slats.Visible = false
		camera.CameraType = Enum.CameraType.Custom
	elseif kind == "Exposed" then
		addShake(2)
		play("scream", 0.8)
		screenFlash(Color3.fromRGB(255, 220, 200), 0.6, 0.6)
	elseif kind == "Caught" then
		play("scream", 1)
		screenFlash(Color3.fromRGB(150, 0, 0), 0.9, 2.5)
		addShake(3)
	elseif kind == "Reveal" then
		for _, position in ipairs(a or {}) do
			heartMarker(position, b or 2)
		end
	elseif kind == "Noise" then
		ripple(a)
	elseif kind == "State" and a.phase == "lobby" then
		blackout = false
		failing = false
		if sounds.alarm then
			sounds.alarm:Stop()
		end
	end
end)

-- Back to normal camera if you respawn
player.CharacterAdded:Connect(function()
	hiddenAt = nil
	slats.Visible = false
	camera.CameraType = Enum.CameraType.Custom
end)
