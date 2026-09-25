--[[
	Number and time formatting for the UI.
]]

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

-- 1234 -> "1.23K", 5600000 -> "5.6M"
function Format.Short(n: number): string
	if n ~= n then
		return "0"
	end
	local negative = n < 0
	n = math.abs(n)
	local i = 1
	while n >= 1000 and i < #SUFFIXES do
		n /= 1000
		i += 1
	end
	local text
	if i == 1 then
		text = tostring(math.floor(n))
	elseif n >= 100 then
		text = string.format("%d%s", math.floor(n), SUFFIXES[i])
	else
		local digits = if n >= 10 then 1 else 2
		local factor = 10 ^ digits
		local num = string.format("%." .. digits .. "f", math.floor(n * factor) / factor)
		num = num:gsub("0+$", ""):gsub("%.$", "")
		text = num .. SUFFIXES[i]
	end
	return (if negative then "-" else "") .. text
end

-- 1234567 -> "1,234,567"
function Format.Commas(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return out
end

-- 3725 -> "1h 2m", 95 -> "1m 35s"
function Format.Duration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	local s = seconds % 60
	if h > 0 then
		return string.format("%dh %dm", h, m)
	elseif m > 0 then
		return string.format("%dm %ds", m, s)
	end
	return string.format("%ds", s)
end

function Format.Percent(p: number): string
	if p >= 1 then
		return string.format("%.1f%%", p)
	elseif p >= 0.01 then
		return string.format("%.2f%%", p)
	end
	return string.format("%.3f%%", p)
end

return Format
