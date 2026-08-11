local rate_limiter = {}
rate_limiter.__index = rate_limiter

function rate_limiter.new()
	return setmetatable({
		calls = {},
	}, rate_limiter)
end

function rate_limiter:allow(key, interval)
	local now = os.clock()
	local last = self.calls[key]
	if last and now - last < interval then
		return false
	end
	self.calls[key] = now
	return true
end

function rate_limiter:clear(key)
	self.calls[key] = nil
end

function rate_limiter:clear_prefix(prefix)
	for key in pairs(self.calls) do
		if type(key) == "string" and string.sub(key, 1, #prefix) == prefix then
			self.calls[key] = nil
		end
	end
end

function rate_limiter:clear_all()
	table.clear(self.calls)
end

return rate_limiter
