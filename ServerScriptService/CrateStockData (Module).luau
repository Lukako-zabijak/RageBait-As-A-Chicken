-- Made by LukakoZabijak (lukakozabijak) on discord, killerox3905 on Roblox.

local crate_stock_data = {
	PlayerStock = {},
}

crate_stock_data.player_stock = crate_stock_data.PlayerStock

function crate_stock_data.clear(user_id)
	crate_stock_data.PlayerStock[user_id] = nil
end

return crate_stock_data
