local Codec = {}

function Codec.encode(assignments)
	local parts = {}
	for petSlot, slimeSlot in pairs(assignments or {}) do
		if type(petSlot) == "number" and type(slimeSlot) == "number" then
			table.insert(parts, { Pet = math.floor(petSlot), Slime = math.floor(slimeSlot) })
		end
	end
	table.sort(parts, function(a, b)
		return a.Pet < b.Pet
	end)
	local encoded = {}
	for _, pair in ipairs(parts) do
		table.insert(encoded, string.format("%d:%d", pair.Pet, pair.Slime))
	end
	return table.concat(encoded, ",")
end

function Codec.decode(value)
	local result = {}
	if type(value) ~= "string" or value == "" then
		return result
	end
	for token in string.gmatch(value, "[^,]+") do
		local petSlot, slimeSlot = string.match(token, "^(%d+):(%d+)$")
		petSlot, slimeSlot = tonumber(petSlot), tonumber(slimeSlot)
		if petSlot and slimeSlot and petSlot >= 1 and slimeSlot >= 1 then
			result[petSlot] = slimeSlot
		end
	end
	return result
end

return Codec
