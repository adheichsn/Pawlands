local PartyCodec = {}

function PartyCodec.encode(party)
	return table.concat(party, "|")
end

-- One attribute publishes the whole party atomically to all clients.
function PartyCodec.decode(value)
	if type(value) ~= "string" or #value > 256 or value == "" then
		return {}
	end
	return string.split(value, "|")
end

return PartyCodec
