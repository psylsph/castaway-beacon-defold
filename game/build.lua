-- build.lua — blueprints, slots, day caps (port of buildings.ts)
local M = {}

M.BLUEPRINTS = {
	["raft-platform"] = { wood = 5, per_day_limit = 1 },
	["water-collector"] = { wood = 8, per_day_limit = 1 },
	["hut"] = { wood = 10, per_day_limit = 1 },
}

-- Build slots: rafts on the shore ring, huts on the inner sand (>=80px apart)
M.RAFT_SLOTS = { { x = 240, y = 408 }, { x = 338, y = 382 }, { x = 142, y = 382 }, { x = 240, y = 304 } }
M.HUT_SLOTS = { { x = 210, y = 372 }, { x = 292, y = 356 }, { x = 240, y = 330 } }

function M.day_build_count(state, kind)
	local n = 0
	for _, s in ipairs(state.structures) do
		if s.kind == kind and s.built_day == state.day then n = n + 1 end
	end
	return n
end

-- returns ok, reason
function M.can_build(state, kind)
	local bp = M.BLUEPRINTS[kind]
	if not bp then return false, "unknown blueprint" end
	if state.resources.wood < bp.wood then
		return false, string.format("Need %d wood", bp.wood)
	end
	if M.day_build_count(state, kind) >= bp.per_day_limit then
		return false, "reached today's build limit"
	end
	return true
end

function M.next_slot(state, kind)
	local slots = kind == "hut" and M.HUT_SLOTS or M.RAFT_SLOTS
	local built = {}
	for _, s in ipairs(state.structures) do
		if s.kind == kind then built[s.slot_index] = true end
	end
	for i, slot in ipairs(slots) do
		if not built[i] then return i, slot end
	end
	return nil
end

-- throws on violation (mirrors placeStructure); caller announces the error
function M.place_structure(state, kind, slot_index, x, y)
	local ok, reason = M.can_build(state, kind)
	if not ok then error(reason) end
	local id = string.format("%s:%d:%d", kind, state.day, slot_index)
	for _, s in ipairs(state.structures) do
		if s.id == id then error("already occupied") end
	end
	table.insert(state.structures, {
		id = id, kind = kind, slot_index = slot_index, x = x, y = y, built_day = state.day,
	})
	state.resources.wood = state.resources.wood - M.BLUEPRINTS[kind].wood
	return state
end

function M.hut_count(state)
	local n = 0
	for _, s in ipairs(state.structures) do
		if s.kind == "hut" then n = n + 1 end
	end
	return n
end

return M
