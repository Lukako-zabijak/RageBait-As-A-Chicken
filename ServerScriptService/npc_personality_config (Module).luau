-- Made by LukakoZabijak (lukakozabijak) on discord, killerox3905 on Roblox.

local config = {}

local personalities = {
	Classic = {
		Name = "Classic",
		Description = "Balanced pursuer",
		Color = Color3.fromRGB(255, 232, 122),
		BaseSpeed = 26,
		PredictionSeconds = 0,
		RepathInterval = 0.35,
	},
	Sprinter = {
		Name = "Sprinter",
		Description = "Very fast in open ground",
		Color = Color3.fromRGB(255, 91, 91),
		BaseSpeed = 32,
		PredictionSeconds = 0.08,
		RepathInterval = 0.42,
	},
	Tracker = {
		Name = "Tracker",
		Description = "Predicts your movement",
		Color = Color3.fromRGB(91, 193, 255),
		BaseSpeed = 25,
		PredictionSeconds = 0.55,
		RepathInterval = 0.22,
	},
	Berserker = {
		Name = "Berserker",
		Description = "Gets faster over time",
		Color = Color3.fromRGB(255, 65, 142),
		BaseSpeed = 23,
		PredictionSeconds = 0.15,
		RepathInterval = 0.3,
		SpeedGainPerSecond = 0.75,
		MaximumSpeed = 33,
	},
	Lazy = {
		Name = "Lazy",
		Description = "Slow start, strong finish",
		Color = Color3.fromRGB(170, 135, 255),
		BaseSpeed = 29,
		PredictionSeconds = 0.1,
		RepathInterval = 0.38,
		WakeDelay = 1.2,
	},
	Caller = {
		Name = "Caller",
		Description = "Calls a nearby NPC for help",
		Color = Color3.fromRGB(255, 171, 70),
		BaseSpeed = 24,
		PredictionSeconds = 0.2,
		RepathInterval = 0.3,
		CallDelay = 4,
		CallRadius = 60,
	},
	FakeOut = {
		Name = "Fake-Out",
		Description = "Stops, then bursts forward",
		Color = Color3.fromRGB(101, 255, 170),
		BaseSpeed = 27,
		PredictionSeconds = 0.25,
		RepathInterval = 0.28,
		FakeOutInterval = 5,
		PauseDuration = 0.55,
		BurstDuration = 1.25,
		BurstSpeed = 34,
	},
}

local order = {
	"Classic",
	"Sprinter",
	"Tracker",
	"Berserker",
	"Lazy",
	"Caller",
	"FakeOut",
}

local function copy_profile(profile)
	local result = {}
	for key, value in pairs(profile) do
		result[key] = value
	end
	return result
end

function config.get(name)
	local profile = personalities[name] or personalities.Classic
	return copy_profile(profile)
end

function config.for_npc(npc_name)
	local number = tonumber(string.match(tostring(npc_name), "%d+")) or 1
	local key = order[((number - 1) % #order) + 1]
	local profile = copy_profile(personalities[key])
	profile.Key = key
	return profile
end

function config.classic()
	local profile = copy_profile(personalities.Classic)
	profile.Key = "Classic"
	return profile
end

function config.names()
	local result = {}
	for _, name in ipairs(order) do
		table.insert(result, name)
	end
	return result
end

return config
