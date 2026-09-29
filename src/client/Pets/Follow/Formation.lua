local Formation = {}

-- Stable 2-column formation; an incomplete row is centered.
function Formation.slot(index, count, spacing, depth, firstRow)
	local columns = math.min(2, count)
	local row = math.floor((index - 1) / columns)
	local column = (index - 1) % columns
	local inRow = math.min(columns, count - row * columns)
	return (column - (inRow - 1) / 2) * spacing, firstRow + row * depth
end

return Formation
