-- AI for bot giants. They walk straight at their goal and, when a wall is in the way,
-- smash through it — so bots tear the building apart as they hunt and fight.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Giants = require(script.Parent.Giants)
local Hiding = require(script.Parent.Hiding)

local Bots = {}

-- Intel the Abomination bot has heard about: { position, expires }
local clues = {}
local searched = {} -- spot -> time it was last searched

function Bots.reset()
	table.clear(clues)
	table.clear(searched)
end

function Bots.hear(position, seconds)
	table.insert(clues, { position = position, expires = os.clock() + (seconds or 8) })
end

local function flatDistance(a, b)
	return ((a - b) * Vector3.new(1, 0, 1)).Magnitude
end

local function face(actor, position)
	local root = actor.root
	local target = Vector3.new(position.X, root.Position.Y, position.Z)
	if (target - root.Position).Magnitude > 0.5 then
		root.CFrame = CFrame.lookAt(root.Position, target)
	end
end

-- Move toward a point; if we haven't made progress, smash whatever is in front of us
local function travel(actor, position)
	actor.humanoid:MoveTo(position)
	local now = os.clock()
	actor.progress = actor.progress or { at = now, from = actor.root.Position }
	if now - actor.progress.at > 1.1 then
		local moved = flatDistance(actor.root.Position, actor.progress.from)
		if moved < 3 and flatDistance(actor.root.Position, position) > 8 then
			face(actor, position)
			Giants.smash(actor)
			if math.random() < 0.15 then
				Giants.leap(actor)
			end
		end
		actor.progress = { at = now, from = actor.root.Position }
	end
end

local function intactSpots()
	local root = Workspace:FindFirstChild("Facility")
	local folder = root and root:FindFirstChild("HidingSpots")
	local list = {}
	for _, spot in ipairs(folder and folder:GetChildren() or {}) do
		if spot.PrimaryPart and not spot:GetAttribute("Destroyed") then
			table.insert(list, spot)
		end
	end
	return list
end

local function abominationThink(actor, civilians)
	local root = actor.root
	local now = os.clock()
	if actor.searching then
		return
	end
	-- Fight back if the Hulk is on top of us
	local hulk = Giants.byRole.hulk
	-- (always when it just hit us, otherwise some of the time — it would rather hunt)
	if Giants.alive(hulk) and flatDistance(hulk.root.Position, root.Position) < Config.Abomination.smashRange + 4
		and (now - (actor.lastHitAt or -99) < 5 or math.random() < 0.3) then
		face(actor, hulk.root.Position)
		Giants.smash(actor)
		return
	end
	-- Chase anyone out in the open
	local best, bestDistance
	for _, player in ipairs(civilians) do
		local character = player.Character
		local target = character and character:FindFirstChild("HumanoidRootPart")
		if target and not Hiding.isHidden(player) then
			local d = flatDistance(target.Position, root.Position)
			if d < 150 and (not bestDistance or d < bestDistance) then
				best, bestDistance = target, d
			end
		end
	end
	if best then
		if bestDistance < Config.Abomination.smashRange then
			face(actor, best.Position)
			Giants.smash(actor)
		end
		travel(actor, best.Position)
		return
	end
	if math.random() < 0.02 then
		Giants.roar(actor)
	end
	-- Follow the freshest clue (noise or a roar reveal), then search spots near it
	for i = #clues, 1, -1 do
		if clues[i].expires < now then
			table.remove(clues, i)
		end
	end
	local goal = actor.goal
	local clue = clues[#clues]
	if clue then
		goal = clue.position
	end
	-- Pick the nearest unsearched spot to the goal (or to us)
	local spots = intactSpots()
	local focus = goal or root.Position
	local spot, spotScore
	for _, s in ipairs(spots) do
		if now - (searched[s] or -999) > 40 then
			local score = flatDistance(s.PrimaryPart.Position, focus) + math.random() * 25
			if not spotScore or score < spotScore then
				spot, spotScore = s, score
			end
		end
	end
	if not spot then
		actor.goal = nil
		return
	end
	actor.goal = spot.PrimaryPart.Position
	if flatDistance(spot.PrimaryPart.Position, root.Position) < Config.Abomination.searchRange - 4 then
		-- Stop, rip it open
		searched[spot] = now
		actor.searching = true
		actor.humanoid:MoveTo(root.Position)
		face(actor, spot.PrimaryPart.Position)
		task.delay(Config.Abomination.searchTime, function()
			actor.searching = false
			if Giants.active(actor) then
				local found = Hiding.search(actor, spot)
				if not found and math.random() < 0.35 then
					-- frustrated: smash it to pieces
					Giants.smash(actor)
				end
			end
		end)
		if clue and flatDistance(clue.position, spot.PrimaryPart.Position) < 30 then
			table.remove(clues, #clues)
		end
		return
	end
	travel(actor, spot.PrimaryPart.Position)
end

local function hulkThink(actor, civilians)
	local root = actor.root
	local foe = Giants.byRole.abomination
	if Giants.alive(foe) and os.clock() >= foe.koUntil then
		local d = flatDistance(foe.root.Position, root.Position)
		if d < Config.Hulk.clapRadius * 0.7 and math.random() < 0.15 then
			Giants.clap(actor)
		end
		if d < Config.Hulk.smashRange + 2 then
			face(actor, foe.root.Position)
			Giants.smash(actor)
		elseif d > 70 and math.random() < 0.05 then
			face(actor, foe.root.Position)
			Giants.leap(actor)
		end
		travel(actor, foe.root.Position)
		return
	end
	-- Foe is down: guard whoever is closest to it
	local guardPoint = if Giants.alive(foe) then foe.root.Position else root.Position
	travel(actor, guardPoint + Vector3.new(math.random(-20, 20), 0, math.random(-20, 20)))
end

function Bots.step(civilians, hunting)
	for _, actor in pairs(Giants.actors) do
		if actor.bot and Giants.active(actor) and not actor.frozen and hunting then
			if actor.role == "abomination" then
				abominationThink(actor, civilians)
			else
				hulkThink(actor, civilians)
			end
		end
	end
end

return Bots
