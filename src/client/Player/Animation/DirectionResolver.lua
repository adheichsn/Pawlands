local DirectionResolver = {}

local SECTOR_SIZE = math.pi / 4
local HALF_SECTOR = SECTOR_SIZE / 2
local FULL_TURN = math.pi * 2

local DIRECTIONS = {
	"Forward",
	"FrontRight",
	"Right",
	"BackRight",
	"Back",
	"BackLeft",
	"Left",
	"FrontLeft",
}

local DIRECTION_INDEX = {}
for index, direction in ipairs(DIRECTIONS) do
	DIRECTION_INDEX[direction] = index
end

local function circularDistance(a, b)
	local delta = math.abs(a - b) % FULL_TURN
	return math.min(delta, FULL_TURN - delta)
end

function DirectionResolver.Resolve(root, moveDirection, previousDirection, hysteresisDegrees)
	if not root or moveDirection.Magnitude <= 0.001 then
		return previousDirection or "Forward"
	end

	local localDirection = root.CFrame:VectorToObjectSpace(moveDirection.Unit)
	local angle = math.atan2(localDirection.X, -localDirection.Z) % FULL_TURN

	local previousIndex = DIRECTION_INDEX[previousDirection]
	if previousIndex then
		local hysteresis = math.rad(math.max(hysteresisDegrees or 0, 0))
		local previousCenter = ((previousIndex - 1) * SECTOR_SIZE) % FULL_TURN
		if circularDistance(angle, previousCenter) <= HALF_SECTOR + hysteresis then
			return previousDirection
		end
	end

	local normalized = (angle + HALF_SECTOR) % FULL_TURN
	local index = math.floor(normalized / SECTOR_SIZE) + 1
	return DIRECTIONS[index] or "Forward"
end

return DirectionResolver
