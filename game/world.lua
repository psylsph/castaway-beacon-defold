-- world.lua — walkable sandbar model (port of world.ts)
local M = {}

M.SAND_CENTER = { x = 240, y = 356 }
M.SAND_RADIUS_X = 138
M.SAND_RADIUS_Y = 63
M.WALK_LIMIT = 0.82

-- Escalating land growth: +8px per level on rx, +3.6 on ry (matches LAND_STEP plan)
function M.sand_radii(land_level)
	return M.SAND_RADIUS_X + land_level * 8, M.SAND_RADIUS_Y + land_level * 3.6
end

function M.is_walkable(x, y, land_level)
	local rx, ry = M.sand_radii(land_level or 0)
	local dx = (x - M.SAND_CENTER.x) / rx
	local dy = (y - M.SAND_CENTER.y) / ry
	return dx * dx + dy * dy <= M.WALK_LIMIT * M.WALK_LIMIT
end

function M.clamp_to_sand(x, y, land_level)
	local rx, ry = M.sand_radii(land_level or 0)
	local dx = (x - M.SAND_CENTER.x) / rx
	local dy = (y - M.SAND_CENTER.y) / ry
	local d = math.sqrt(dx * dx + dy * dy)
	if d <= M.WALK_LIMIT or d == 0 then
		return x, y
	end
	local k = M.WALK_LIMIT / d
	return M.SAND_CENTER.x + dx * k * rx, M.SAND_CENTER.y + dy * k * ry
end

-- 8-point shoreline driftwood ring (port of driftwood.ts)
M.DRIFTWOOD_RING = {
	{ x = 346, y = 356 }, { x = 315, y = 390 }, { x = 240, y = 405 }, { x = 165, y = 390 },
	{ x = 134, y = 356 }, { x = 165, y = 322 }, { x = 240, y = 307 }, { x = 315, y = 322 },
}

return M
