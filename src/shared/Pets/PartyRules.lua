local PartyRules = {}

local function arrayCount(requested, maxSize, noun)
	if type(requested) ~= "table" then
		return nil, noun .. " must be an array."
	end
	local count = 0
	for key in pairs(requested) do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
			return nil, noun .. " must be a consecutive array."
		end
		count += 1
		if count > maxSize or key > maxSize then
			return nil, "A party can contain at most " .. maxSize .. " pets."
		end
	end
	return count, nil
end

function PartyRules.resolve(value, catalog)
	if type(value) ~= "string" or #value > 48 then
		return nil
	end
	local trimmed = string.match(value, "^%s*(.-)%s*$")
	return catalog.Aliases[string.lower(trimmed)]
end

-- Client/display validation for the replicated visual pet ids.
function PartyRules.validate(requested, catalog, maxSize)
	local count, countReason = arrayCount(requested, maxSize, "Party")
	if not count then
		return nil, countReason
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

-- Server ownership validation. The party stores unique pet instance ids while the client still receives visual pet ids.
function PartyRules.validateOwned(requested, getPet, catalog, maxSize)
	local count, countReason = arrayCount(requested, maxSize, "Party")
	if not count then
		return nil, countReason
	end
	if type(getPet) ~= "function" then
		return nil, "Pet ownership resolver is unavailable."
	end
	local result, seenUids, seenSpecies = {}, {}, {}
	for index = 1, count do
		local uid = requested[index]
		if type(uid) ~= "string" or uid == "" or #uid > 64 then
			return nil, "Invalid pet instance id at position " .. index .. "."
		end
		if seenUids[uid] then
			return nil, "The same pet instance cannot be equipped twice."
		end
		local pet = getPet(uid)
		if not pet then
			return nil, "Pet is not owned: " .. uid
		end
		local definition = catalog.Pets[pet.PetId]
		if not definition or definition.SpeciesId ~= pet.SpeciesId then
			return nil, "Owned pet data is invalid: " .. uid
		end
		if seenSpecies[pet.SpeciesId] then
			return nil, "Only one " .. pet.SpeciesId .. " is allowed in a party."
		end
		seenUids[uid] = true
		seenSpecies[pet.SpeciesId] = true
		result[index] = uid
	end
	return result, nil
end

return PartyRules
