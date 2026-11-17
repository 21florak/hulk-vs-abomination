-- Coins and costumes, saved between sessions.
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Data = {}

local store
pcall(function()
	store = DataStoreService:GetDataStore("MonsterLockdown_v1")
end)

local profiles = {}
local winsBoard
pcall(function()
	winsBoard = DataStoreService:GetOrderedDataStore("MonsterLockdown_Wins_v1")
end)
Data.winsBoard = winsBoard
Data.onLevelUp = nil -- set by Main: function(player, level)

local function default()
	return {
		coins = 0,
		owned = { hulk_classic = true, abom_classic = true, civ_office = true },
		equipped = { hulk = "hulk_classic", abomination = "abom_classic", civilian = "civ_office" },
		wins = 0,
		catches = 0,
		xp = 0,
		lastLoginDay = 0,
		streak = 0,
	}
end

function Data.load(player)
	local data
	if store then
		local ok, result = pcall(store.GetAsync, store, "p_" .. player.UserId)
		if ok and type(result) == "table" then
			data = result
		end
	end
	local profile = default()
	if data then
		for k, v in pairs(data) do
			profile[k] = v
		end
	end
	profiles[player] = profile
	return profile
end

function Data.get(player)
	return profiles[player]
end

function Data.save(player)
	local profile = profiles[player]
	if store and profile then
		pcall(store.SetAsync, store, "p_" .. player.UserId, profile)
	end
	if winsBoard and profile and profile.wins > 0 then
		pcall(winsBoard.SetAsync, winsBoard, "p_" .. player.UserId, profile.wins)
	end
end

---------------------------------------------------------------------------
-- Levels
---------------------------------------------------------------------------
function Data.levelFor(xp)
	local level, need = 1, Config.XP.levelBase
	while xp >= need do
		xp -= need
		level += 1
		need += Config.XP.levelStep
	end
	return level, xp, need -- level, progress into it, XP needed for the next one
end

function Data.updateStats(player)
	local profile = profiles[player]
	local stats = player:FindFirstChild("leaderstats")
	if not (profile and stats) then
		return
	end
	for name, value in pairs({ Level = (Data.levelFor(profile.xp)), Wins = profile.wins, Coins = profile.coins }) do
		local v = stats:FindFirstChild(name)
		if v then
			v.Value = value
		end
	end
end

function Data.addXP(player, amount)
	local profile = profiles[player]
	if not profile or amount <= 0 then
		return
	end
	local before = Data.levelFor(profile.xp)
	profile.xp += amount
	local after = Data.levelFor(profile.xp)
	if after > before then
		Data.addCoins(player, Config.XP.coinsPerLevel * after)
		if Data.onLevelUp then
			Data.onLevelUp(player, after)
		end
	end
	Data.updateStats(player)
end

---------------------------------------------------------------------------
-- Daily login rewards: returns the reward given today (or nil if already claimed)
---------------------------------------------------------------------------
function Data.claimDaily(player)
	local profile = profiles[player]
	if not profile then
		return nil
	end
	local today = math.floor(os.time() / 86400)
	if profile.lastLoginDay >= today then
		return nil
	end
	profile.streak = if profile.lastLoginDay == today - 1 then profile.streak + 1 else 1
	profile.lastLoginDay = today
	local day = (profile.streak - 1) % #Config.DailyRewards + 1
	local reward = Config.DailyRewards[day]
	local coins = reward.coins or 0
	local costume = reward.costume
	if costume and profile.owned[costume] then
		costume = nil
		coins += 100 -- already have it: extra coins instead
	end
	if costume then
		profile.owned[costume] = true
	end
	Data.addCoins(player, coins)
	return { day = day, streak = profile.streak, coins = coins, costume = costume and Config.Costumes[costume].name or nil }
end

function Data.release(player)
	Data.save(player)
	profiles[player] = nil
end

function Data.addCoins(player, amount)
	local profile = profiles[player]
	if profile and amount > 0 then
		profile.coins += amount
		local stats = player:FindFirstChild("leaderstats")
		if stats then
			stats.Coins.Value = profile.coins
		end
	end
end

function Data.costumeFor(player, role)
	local profile = profiles[player]
	local id = profile and profile.equipped[role]
	return Config.Costumes[id] or Config.Costumes[Config.CostumeOrder[role][1]]
end

-- Shop actions: { action = "buy" | "equip", id }
function Data.shop(player, action, id)
	local profile = profiles[player]
	local costume = Config.Costumes[id]
	if not (profile and costume) then
		return false, "Unknown costume."
	end
	if action == "buy" then
		if profile.owned[id] then
			return false, "You already own it."
		end
		if not costume.price then
			return false, "This one is a daily login reward."
		end
		if profile.coins < costume.price then
			return false, "Not enough coins."
		end
		profile.coins -= costume.price
		profile.owned[id] = true
		profile.equipped[costume.role] = id
		Data.addCoins(player, 0)
		local stats = player:FindFirstChild("leaderstats")
		if stats then
			stats.Coins.Value = profile.coins
		end
		return true, "Unlocked " .. costume.name .. "!"
	elseif action == "equip" then
		if not profile.owned[id] then
			return false, "Buy it first."
		end
		profile.equipped[costume.role] = id
		return true, "Equipped " .. costume.name .. "."
	end
	return false, "Unknown action."
end

function Data.all()
	return profiles
end

return Data
