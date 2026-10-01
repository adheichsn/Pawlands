local Formation = {}

-- Stable 2-column formation; an incomplete row is centered.
function Formation.slot(index, count, spacing, depth, firstRow)
	local columns = math.min(2, count)
	local row = math.floor((index - 1) / columns)
	local column = (index - 1) % columns
	local inRow = math.min(columns, count - row * columns)
	return (column - (inRow - 1) / 2) * spacing, firstRow + row * depth
end

-- Dialogue idle keeps local Pets out of the center camera line while the
-- player is focused on an NPC. Combat goals still override this formation.
function Formation.dialogueSlot(index, spacing, depth, firstRow)
	local pairIndex = math.floor((index - 1) / 2)
	local side = ((index - 1) % 2 == 0) and -1 or 1
	local widthScale = 0.85 + pairIndex * 0.25
	return side * spacing * widthScale, firstRow + pairIndex * depth
end

return Formation
