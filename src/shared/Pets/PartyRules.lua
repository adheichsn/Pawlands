local PartyRules = {}

function PartyRules.resolve(value, catalog)
	if type(value) ~= "string" or #value > 48 then
		return nil
	end
	local trimmed = string.match(value, "^%s*(.-)%s*$")
	return catalog.Aliases[string.lower(trimmed)]
end

-- Pure validation: reject the entire change on failure; never partially equip.
function PartyRules.validate(requested, catalog, maxSize)
	if type(requested) ~= "table" then
		return nil, "Party must be an array of pet names."
	end
	local count = 0
	for key in pairs(requested) do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
			return nil, "Party must be a consecutive array."
		end
		count += 1
		if count > maxSize or key > maxSize then
			return nil, "A party can contain at most " .. maxSize .. " pets."
		end
	end
	local result, seenSpecies = {}, {}
	for index = 1, count do
		local id = PartyRules.resolve(requested[index], catalog)
		local definition = id and catalog.Pets[id]
		if not definition then
			return nil, "Unknown pet or missing party slot at position " .. index .. "."
		end
		local speciesId = definition.SpeciesId
		if seenSpecies[speciesId] then
			return nil, "Only one " .. speciesId .. " is allowed in a party."
		end
		seenSpecies[speciesId] = true
		result[index] = id
	end
	return result, nil
end

return PartyRules
