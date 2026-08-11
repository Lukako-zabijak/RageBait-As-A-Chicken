-- Made by LukakoZabijak (lukakozabijak) on discord, killerox3905 on Roblox.

local session_data = {
	PlayerSessions = {},
}

session_data.player_sessions = session_data.PlayerSessions

function session_data.reset(user_id)
	session_data.PlayerSessions[user_id] = {
		SessionStart = os.time(),
		AllUnlocked = false,
	}
	return session_data.PlayerSessions[user_id]
end

function session_data.clear(user_id)
	session_data.PlayerSessions[user_id] = nil
end

return session_data
