local table_util = {}

function table_util.deep_copy(value, seen)
	if type(value) ~= "table" then
		return value
	end
	seen = seen or {}
	if seen[value] then
		return seen[value]
	end
	local copy = {}
	seen[value] = copy
	for key, child in pairs(value) do
		copy[table_util.deep_copy(key, seen)] = table_util.deep_copy(child, seen)
	end
	return copy
end

function table_util.contains(array, value)
	for _, item in ipairs(array) do
		if item == value then
			return true
		end
	end
	return false
end

function table_util.count(dictionary)
	local count = 0
	for _ in pairs(dictionary) do
		count += 1
	end
	return count
end

function table_util.is_finite_number(value)
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

function table_util.clamp_integer(value, minimum, maximum, fallback)
	if not table_util.is_finite_number(value) then
		return fallback
	end
	value = math.floor(value)
	return math.clamp(value, minimum, maximum)
end

return table_util
