-- On-screen UI: round status, role reveal, giant health, chaos meter, civilian meters,
-- announcements, results, costume shop and spectating.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ToClient = Remotes:WaitForChild("ToClient")
local ShopRF = Remotes:WaitForChild("Shop")

local GREEN = Color3.fromRGB(90, 200, 60)
local RED = Color3.fromRGB(220, 50, 40)
local BG = Color3.fromRGB(12, 12, 16)
local TEXT = Color3.fromRGB(235, 235, 240)

local function new(class, props, children)
	local inst = Instance.new(class)
	for k, v in pairs(props or {}) do
		if k ~= "Parent" then
			inst[k] = v
		end
	end
	for _, c in ipairs(children or {}) do
		c.Parent = inst
	end
	inst.Parent = props and props.Parent
	return inst
end
local function corner(r)
	return new("UICorner", { CornerRadius = UDim.new(0, r or 8) })
end
local function label(props)
	local defaults = { BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextColor3 = TEXT, TextSize = 16, TextWrapped = true, RichText = true }
	for k, v in pairs(props) do
		defaults[k] = v
	end
	return new("TextLabel", defaults)
end

local gui = new("ScreenGui", { Name = "LockdownHUD", ResetOnSpawn = false, IgnoreGuiInset = false, Parent = player:WaitForChild("PlayerGui") })

---------------------------------------------------------------------------
-- Top status bar
---------------------------------------------------------------------------
local top = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6), Size = UDim2.fromOffset(460, 54), BackgroundColor3 = BG, BackgroundTransparency = 0.2, Parent = gui }, { corner(10) })
local phaseLabel = label({ Size = UDim2.new(1, -16, 0, 24), Position = UDim2.fromOffset(8, 4), Font = Enum.Font.GothamBlack, TextSize = 18, Text = "", Parent = top })
local chaosBack = new("Frame", { Position = UDim2.new(0, 8, 0, 34), Size = UDim2.new(1, -16, 0, 12), BackgroundColor3 = Color3.fromRGB(40, 40, 45), Parent = top }, { corner(6) })
local chaosFill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.fromRGB(255, 120, 30), Parent = chaosBack }, { corner(6) })
label({ Size = UDim2.fromScale(1, 1), Text = "CHAOS", TextSize = 10, Font = Enum.Font.GothamBlack, TextColor3 = Color3.new(1, 1, 1), Parent = chaosBack })

---------------------------------------------------------------------------
-- Giant health bars (left: Hulk, right: Abomination)
---------------------------------------------------------------------------
local function hpBar(anchorX, color, name)
	local frame = new("Frame", { Visible = false, AnchorPoint = Vector2.new(anchorX, 0), Position = UDim2.new(anchorX, (anchorX == 0 and 12 or -12), 0, 70), Size = UDim2.fromOffset(240, 34), BackgroundColor3 = BG, BackgroundTransparency = 0.25, Parent = gui }, { corner(8) })
	label({ Size = UDim2.new(1, -12, 0, 14), Position = UDim2.fromOffset(6, 2), TextSize = 12, Font = Enum.Font.GothamBlack, Text = name, TextXAlignment = Enum.TextXAlignment.Left, Parent = frame })
	local back = new("Frame", { Position = UDim2.fromOffset(6, 18), Size = UDim2.new(1, -12, 0, 10), BackgroundColor3 = Color3.fromRGB(40, 40, 45), Parent = frame }, { corner(5) })
	local fill = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = color, Parent = back }, { corner(5) })
	return { frame = frame, fill = fill, name = frame:FindFirstChildOfClass("TextLabel") }
end
local bars = {
	hulk = hpBar(0, GREEN, string.upper(Config.Names.hulk)),
	abomination = hpBar(1, RED, string.upper(Config.Names.abomination)),
}

---------------------------------------------------------------------------
-- Civilian meters (stamina + flashlight) and giant cooldowns
---------------------------------------------------------------------------
local meters = new("Frame", { Visible = false, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Size = UDim2.fromOffset(300, 46), BackgroundTransparency = 1, Parent = gui })
local function meter(y, color, text)
	local back = new("Frame", { Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 18), BackgroundColor3 = Color3.fromRGB(30, 30, 35), BackgroundTransparency = 0.2, Parent = meters }, { corner(6) })
	local fill = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = color, Parent = back }, { corner(6) })
	label({ Size = UDim2.fromScale(1, 1), Text = text, TextSize = 11, Font = Enum.Font.GothamBlack, Parent = back })
	return fill
end
local staminaFill = meter(0, Color3.fromRGB(80, 170, 255), "STAMINA  (Shift to sprint — it makes noise)")
local batteryFill = meter(24, Color3.fromRGB(255, 220, 90), "FLASHLIGHT  (F) — the monster can see it")

local cooldownBox = new("Frame", { Visible = false, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Size = UDim2.fromOffset(420, 40), BackgroundTransparency = 1, Parent = gui }, { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 8) }) })
local cooldowns = {}
local function cooldownChip(key, text)
	local chip = new("Frame", { Size = UDim2.fromOffset(130, 36), BackgroundColor3 = BG, BackgroundTransparency = 0.2, Parent = cooldownBox }, { corner(8) })
	local fill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.8, Parent = chip }, { corner(8) })
	label({ Size = UDim2.fromScale(1, 1), Text = text, TextSize = 13, Font = Enum.Font.GothamBlack, Parent = chip })
	cooldowns[key] = { chip = chip, fill = fill, readyAt = 0, length = 1 }
	return chip
end

---------------------------------------------------------------------------
-- Announcements, role reveal, toasts
---------------------------------------------------------------------------
local announce = label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 120), Size = UDim2.new(0.8, 0, 0, 40), Font = Enum.Font.GothamBlack, TextSize = 26, TextStrokeTransparency = 0.3, Text = "", Parent = gui })
local announceToken = 0
local function showAnnouncement(text, style)
	announceToken += 1
	local token = announceToken
	announce.Text = text
	announce.TextColor3 = if style == "bad" then Color3.fromRGB(255, 90, 80) elseif style == "good" then Color3.fromRGB(130, 255, 120) else Color3.fromRGB(255, 220, 120)
	announce.TextTransparency = 0
	task.delay(3.5, function()
		if token == announceToken then
			TweenService:Create(announce, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
		end
	end)
end

local toast = label({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -80), Size = UDim2.new(0.6, 0, 0, 28), TextSize = 18, Text = "", TextStrokeTransparency = 0.4, Parent = gui })
local function showToast(text)
	toast.Text = text
	toast.TextTransparency = 0
	task.delay(2.5, function()
		if toast.Text == text then
			toast.TextTransparency = 1
		end
	end)
end

local reveal = new("Frame", { Visible = false, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.15, ZIndex = 20, Parent = gui })
local revealTitle = label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.new(0.9, 0, 0, 80), Font = Enum.Font.GothamBlack, TextScaled = true, ZIndex = 21, Parent = reveal })
local revealText = label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.new(0.7, 0, 0, 120), TextSize = 20, ZIndex = 21, Parent = reveal })

local ROLE_INFO = {
	civilian = { title = "YOU ARE A CIVILIAN", color = Color3.fromRGB(240, 240, 240), text = "Hide. Stay quiet. Lockers, desks, stalls, crates, vents — anything. Sprinting makes noise and your flashlight gives you away. If your hiding spot gets smashed, RUN." },
	hulk = { title = "YOU ARE " .. string.upper(Config.Names.hulk), color = GREEN, text = "Keep the " .. Config.Names.abomination .. " away from the civilians. Click / F: SMASH · Q: THUNDERCLAP (stuns) · R: LEAP. Every hit sends it crashing through walls... and destroys hiding spots. You can die." },
	abomination = { title = "YOU ARE THE " .. string.upper(Config.Names.abomination), color = RED, text = "Find every civilian. Click / F: SMASH (grabs anyone in reach) · Q: ROAR (reveals nearby civilians) · R: LEAP · hold E on a hiding spot to SEARCH. Listen for running footsteps." },
}

local function showRole(role)
	local info = ROLE_INFO[role]
	if not info then
		return
	end
	revealTitle.Text = info.title
	revealTitle.TextColor3 = info.color
	revealText.Text = info.text
	reveal.Visible = true
	revealTitle.TextTransparency = 1
	TweenService:Create(revealTitle, TweenInfo.new(0.6), { TextTransparency = 0 }):Play()
	task.delay(5, function()
		reveal.Visible = false
	end)
end

---------------------------------------------------------------------------
-- Results
---------------------------------------------------------------------------
local results = new("Frame", { Visible = false, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(460, 220), BackgroundColor3 = BG, BackgroundTransparency = 0.05, ZIndex = 15, Parent = gui }, { corner(14), new("UIStroke", { Color = Color3.fromRGB(255, 220, 120), Thickness = 2 }) })
local resultsTitle = label({ Position = UDim2.fromOffset(16, 16), Size = UDim2.new(1, -32, 0, 48), Font = Enum.Font.GothamBlack, TextScaled = true, ZIndex = 16, Parent = results })
local resultsText = label({ Position = UDim2.fromOffset(16, 70), Size = UDim2.new(1, -32, 0, 60), TextSize = 18, ZIndex = 16, Parent = results })
local rewardText = label({ Position = UDim2.fromOffset(16, 140), Size = UDim2.new(1, -32, 0, 60), Font = Enum.Font.GothamBlack, TextSize = 24, TextColor3 = Color3.fromRGB(255, 220, 90), ZIndex = 16, Parent = results })

---------------------------------------------------------------------------
-- Costume shop
---------------------------------------------------------------------------
local profile = nil
local shop = new("Frame", { Visible = false, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromScale(0.86, 0.76), BackgroundColor3 = BG, ZIndex = 10, Parent = gui }, {
	corner(14), new("UISizeConstraint", { MaxSize = Vector2.new(620, 560) }), new("UIStroke", { Color = Color3.fromRGB(150, 90, 220), Thickness = 2 }),
})
local shopTitle = label({ Position = UDim2.fromOffset(16, 10), Size = UDim2.new(1, -70, 0, 30), Font = Enum.Font.GothamBlack, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 11, Parent = shop })
local closeShop = new("TextButton", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 10), Size = UDim2.fromOffset(32, 32), BackgroundColor3 = Color3.fromRGB(50, 50, 60), Text = "✕", TextColor3 = TEXT, Font = Enum.Font.GothamBold, TextSize = 16, ZIndex = 11, Parent = shop }, { corner(8) })
local shopList = new("ScrollingFrame", { Position = UDim2.fromOffset(12, 50), Size = UDim2.new(1, -24, 1, -62), BackgroundTransparency = 1, BorderSizePixel = 0, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 6, ZIndex = 11, Parent = shop }, {
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
})
closeShop.MouseButton1Click:Connect(function()
	shop.Visible = false
end)

local function renderShop()
	for _, c in ipairs(shopList:GetChildren()) do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	shopTitle.Text = "🎭 Costume Shop  ·  🪙 " .. (profile and profile.coins or 0)
	local order = 0
	for _, role in ipairs({ "hulk", "abomination", "civilian" }) do
		order += 1
		label({ Size = UDim2.new(1, 0, 0, 26), Text = string.upper(Config.Names[role]), Font = Enum.Font.GothamBlack, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = if role == "hulk" then GREEN elseif role == "abomination" then RED else TEXT, LayoutOrder = order, ZIndex = 12, Parent = shopList })
		for _, id in ipairs(Config.CostumeOrder[role]) do
			order += 1
			local costume = Config.Costumes[id]
			local owned = profile and profile.owned[id]
			local equipped = profile and profile.equipped[role] == id
			local row = new("Frame", { Size = UDim2.new(1, -8, 0, 44), BackgroundColor3 = Color3.fromRGB(30, 30, 38), LayoutOrder = order, ZIndex = 12, Parent = shopList }, { corner(8) })
			new("Frame", { Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(28, 28), BackgroundColor3 = costume.skin or costume.shirt, ZIndex = 13, Parent = row }, { corner(14) })
			label({ Position = UDim2.fromOffset(44, 0), Size = UDim2.new(1, -190, 1, 0), Text = costume.name, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 13, Parent = row })
			local button = new("TextButton", {
				AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(130, 30),
				BackgroundColor3 = if equipped then Color3.fromRGB(60, 60, 70) elseif owned then Color3.fromRGB(70, 120, 200) else Color3.fromRGB(230, 180, 40),
				Text = if equipped then "Equipped" elseif owned then "Equip" else "🪙 " .. costume.price,
				TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBlack, TextSize = 14, ZIndex = 13, Parent = row,
			}, { corner(8) })
			button.MouseButton1Click:Connect(function()
				if equipped then
					return
				end
				local ok, message = ShopRF:InvokeServer(if owned then "equip" else "buy", id)
				showToast(message or "")
			end)
		end
	end
end

---------------------------------------------------------------------------
-- Spectating (after you're caught or killed)
---------------------------------------------------------------------------
local spectateBar = new("Frame", { Visible = false, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Size = UDim2.fromOffset(360, 40), BackgroundColor3 = BG, BackgroundTransparency = 0.2, Parent = gui }, { corner(10) })
local spectateName = label({ Position = UDim2.fromOffset(50, 0), Size = UDim2.new(1, -100, 1, 0), Text = "", Parent = spectateBar })
local prevButton = new("TextButton", { Position = UDim2.fromOffset(6, 5), Size = UDim2.fromOffset(36, 30), Text = "◀", BackgroundColor3 = Color3.fromRGB(50, 50, 60), TextColor3 = TEXT, Font = Enum.Font.GothamBold, TextSize = 16, Parent = spectateBar }, { corner(6) })
local nextButton = new("TextButton", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 5), Size = UDim2.fromOffset(36, 30), Text = "▶", BackgroundColor3 = Color3.fromRGB(50, 50, 60), TextColor3 = TEXT, Font = Enum.Font.GothamBold, TextSize = 16, Parent = spectateBar }, { corner(6) })
local spectateIndex = 1
local spectating = false

local function spectateTargets()
	local list = {}
	for _, model in ipairs(workspace:GetChildren()) do
		if model:IsA("Model") and model:GetAttribute("Role") and model:FindFirstChildOfClass("Humanoid") and not Players:GetPlayerFromCharacter(model) then
			table.insert(list, model) -- AI giants
		end
	end
	for _, other in ipairs(Players:GetPlayers()) do
		local role = other:GetAttribute("Role")
		if other ~= player and other.Character and (role == "civilian" or role == "hulk" or role == "abomination") then
			table.insert(list, other.Character)
		end
	end
	return list
end

local function cycle(step)
	local list = spectateTargets()
	if #list == 0 then
		spectateName.Text = "Nobody to watch"
		return
	end
	spectateIndex = (spectateIndex - 1 + step) % #list + 1
	local target = list[spectateIndex]
	local humanoid = target:FindFirstChildOfClass("Humanoid")
	workspace.CurrentCamera.CameraSubject = humanoid
	spectateName.Text = "👁 " .. target.Name
end
prevButton.MouseButton1Click:Connect(function()
	cycle(-1)
end)
nextButton.MouseButton1Click:Connect(function()
	cycle(1)
end)

---------------------------------------------------------------------------
-- Role-dependent layout
---------------------------------------------------------------------------
local function applyRole()
	local role = player:GetAttribute("Role")
	meters.Visible = role == "civilian"
	cooldownBox.Visible = role == "hulk" or role == "abomination"
	for _, c in ipairs(cooldownBox:GetChildren()) do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	table.clear(cooldowns)
	if role == "hulk" then
		cooldownChip("smash", "SMASH (Click/F)")
		cooldownChip("clap", "CLAP (Q)")
		cooldownChip("leap", "LEAP (R)")
	elseif role == "abomination" then
		cooldownChip("smash", "SMASH (Click/F)")
		cooldownChip("roar", "ROAR (Q)")
		cooldownChip("leap", "LEAP (R)")
	end
	local wasSpectating = spectating
	spectating = role == "spectator"
	spectateBar.Visible = spectating
	if spectating and not wasSpectating then
		task.delay(1, function()
			cycle(0)
		end)
	elseif not spectating and wasSpectating then
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			workspace.CurrentCamera.CameraSubject = humanoid
		end
	end
end
player:GetAttributeChangedSignal("Role"):Connect(applyRole)
applyRole()

-- Stamina comes from the Controls script through an attribute
player:GetAttributeChangedSignal("Stamina"):Connect(function()
	staminaFill.Size = UDim2.fromScale(math.clamp((player:GetAttribute("Stamina") or 0) / Config.Civilian.stamina, 0, 1), 1)
end)

---------------------------------------------------------------------------
-- Server events
---------------------------------------------------------------------------
local PHASE_TEXT = { lobby = "LOBBY", hide = "HIDE!", hunt = "THE HUNT", results = "RESULTS" }

ToClient.OnClientEvent:Connect(function(kind, a, b, c, d)
	if kind == "State" then
		local s = a
		local t = math.ceil(s.timeLeft)
		local clock = string.format("%d:%02d", t // 60, t % 60)
		if s.phase == "lobby" then
			phaseLabel.Text = "🏢 Next lockdown in " .. clock .. "   ·   🪙 " .. (profile and profile.coins or 0)
		else
			phaseLabel.Text = string.format("%s  %s   ·   👥 %d/%d left", PHASE_TEXT[s.phase] or "", clock, s.civiliansLeft, s.civiliansTotal)
		end
		chaosFill.Size = UDim2.fromScale(math.clamp(s.chaos / 100, 0, 1), 1)
		chaosBack.Visible = s.phase ~= "lobby"
		bars.hulk.frame.Visible = s.phase == "hide" or s.phase == "hunt"
		bars.abomination.frame.Visible = s.phase == "hide" or s.phase == "hunt"
	elseif kind == "GiantHP" then
		local bar = bars[a]
		if bar then
			bar.fill.Size = UDim2.fromScale(math.clamp(b / c, 0, 1), 1)
			local name = string.upper(Config.Names[a])
			bar.name.Text = if d == "dead" then name .. "  —  DEAD" elseif d == "ko" then name .. "  —  KNOCKED OUT" else name
		end
	elseif kind == "Chaos" then
		chaosFill.Size = UDim2.fromScale(math.clamp(a / 100, 0, 1), 1)
	elseif kind == "ChaosEvent" then
		showAnnouncement("⚠️ " .. b, "warn")
	elseif kind == "Announce" then
		showAnnouncement(a, b)
	elseif kind == "Toast" then
		showToast(a)
	elseif kind == "RoleReveal" then
		showRole(a)
	elseif kind == "Cooldown" then
		local cd = cooldowns[a]
		if cd then
			cd.readyAt = os.clock() + b
			cd.length = b
		end
	elseif kind == "Battery" then
		batteryFill.Size = UDim2.fromScale(math.clamp(a / Config.Civilian.flashlightBattery, 0, 1), 1)
	elseif kind == "Results" then
		local hulkWon = a == "hulk"
		resultsTitle.Text = if hulkWon then "🟢 " .. string.upper(Config.Names.hulk) .. " & SURVIVORS WIN" else "🔴 THE " .. string.upper(Config.Names.abomination) .. " WINS"
		resultsTitle.TextColor3 = if hulkWon then GREEN else RED
		resultsText.Text = b
		rewardText.Text = ""
		results.Visible = true
		task.delay(Config.Round.results, function()
			results.Visible = false
		end)
	elseif kind == "Reward" then
		rewardText.Text = (if b then "🏆 You won!  " else "") .. "+🪙 " .. a
	elseif kind == "Profile" then
		profile = a
		if shop.Visible then
			renderShop()
		end
	elseif kind == "OpenShop" then
		shop.Visible = true
		renderShop()
	elseif kind == "Exposed" then
		showAnnouncement("💥 YOUR HIDING SPOT WAS DESTROYED — RUN!", "bad")
	elseif kind == "Caught" then
		showAnnouncement("☠️ YOU WERE CAUGHT", "bad")
	end
end)

-- Cooldown chips fill back up
RunService.RenderStepped:Connect(function()
	local now = os.clock()
	for _, cd in pairs(cooldowns) do
		local left = math.max(0, cd.readyAt - now)
		cd.fill.Size = UDim2.fromScale(1 - left / math.max(cd.length, 0.01), 1)
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.Escape and shop.Visible then
		shop.Visible = false
	end
end)
