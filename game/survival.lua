-- survival.lua — fishing, digging, day clock, story beats (ports of survival.ts, day-cycle.ts, story.ts)
local world = require "game.world"
local M = {}

M.DAY_LENGTH_SECONDS = 120
M.MOVEMENT_SPEED = 60 -- px/s
M.FISH_YIELD = 2
M.DIGS_PER_EXPANSION = 4
M.FISH_WORK_SECONDS = 2.5
M.DIG_WORK_SECONDS = 3
M.MAX_ACTIVE_NODES = 3
M.NODES_PER_DAY = 6

M.STORM_DAY = 2
M.ARRIVALS = {
	{ day = 4, name = "Mira", hut = 2 },
	{ day = 6, name = "Tomas", hut = 3 },
}

function M.create_initial_state()
	return {
		day = 1,
		phase = "day",
		clock_seconds = 0,
		population = 1,
		resources = { wood = 0, food = 0 },
		actor = { x = 248, y = 380, mode = "idle", target_x = nil, target_y = nil },
		-- node queue: index of the next shoreline slot to spawn
		node_cursor = 0,
		nodes = {}, -- active nodes: { id, index, x, y, collected }
		collected_count = 0,
		structures = {},
		completed_objectives = {},
		dig_progress = 0,
		land_level = 0,
		stories_seen = {},
		arrivals_done = {},
		work_activity = "none",
		work_timer = 0,
	}
end

-- spawn driftwood nodes up to MAX_ACTIVE_NODES from the ring, deterministic order
function M.replenish_nodes(state)
	while #state.nodes < M.MAX_ACTIVE_NODES and state.node_cursor < M.NODES_PER_DAY do
		state.node_cursor = state.node_cursor + 1
		local point = world.DRIFTWOOD_RING[((state.node_cursor - 1) % #world.DRIFTWOOD_RING) + 1]
		table.insert(state.nodes, {
			id = string.format("driftwood:d%d:%d", state.day, state.node_cursor),
			x = point.x, y = point.y, collected = false,
		})
	end
end

function M.can_collect(state, node_id)
	M.replenish_nodes(state)
	for _, n in ipairs(state.nodes) do
		if n.id == node_id then
			if n.collected then return false, "already collected" end
			return true
		end
	end
	return false, "no such node"
end

function M.collect_node(state, node_id)
	for i, n in ipairs(state.nodes) do
		if n.id == node_id and not n.collected then
			n.collected = true
			state.collected_count = state.collected_count + 1
			state.resources.wood = state.resources.wood + 1
			table.remove(state.nodes, i)
			M.replenish_nodes(state)
			return state
		end
	end
	error("no such node")
end

function M.begin_move(state, x, y, land_level)
	local cx, cy = world.clamp_to_sand(x, y, land_level)
	state.actor.target_x, state.actor.target_y = cx, cy
	state.actor.mode = "moving"
	return state
end

function M.continue_movement(state, dt)
	local a = state.actor
	if a.mode ~= "moving" or not a.target_x then return state end
	local dist = math.sqrt((a.target_x - a.x) ^ 2 + (a.target_y - a.y) ^ 2)
	if dist <= M.MOVEMENT_SPEED * dt then
		a.x, a.y = a.target_x, a.target_y
		a.mode = "working"
		return state
	end
	local step = M.MOVEMENT_SPEED * dt
	a.x = a.x + (a.target_x - a.x) / dist * step
	a.y = a.y + (a.target_y - a.y) / dist * step
	return state
end

M.FISH_SPOT = { x = 346, y = 356 }
M.DIG_SPOT = { x = 140, y = 360 }

function M.begin_work(state, activity)
	local spot = activity == "fishing" and M.FISH_SPOT or M.DIG_SPOT
	state.work_activity = activity
	state.work_timer = activity == "fishing" and M.FISH_WORK_SECONDS or M.DIG_WORK_SECONDS
	return M.begin_move(state, spot.x, spot.y, state.land_level)
end

-- call each frame while actor is working at the spot; returns event or nil
function M.tick_work(state, dt)
	if state.actor.mode ~= "working" or state.work_activity == "none" then return nil end
	state.work_timer = state.work_timer - dt
	if state.work_timer > 0 then return nil end

	if state.work_activity == "fishing" then
		state.work_activity = "none"
		state.actor.mode = "idle"
		state.resources.food = state.resources.food + M.FISH_YIELD
		if not state.completed_objectives.first_catch then
			state.completed_objectives.first_catch = true
			return "first-catch"
		end
		return "fished"
	end

	-- digging
	state.work_activity = "none"
	state.actor.mode = "idle"
	state.dig_progress = state.dig_progress + 1
	if state.dig_progress >= M.DIGS_PER_EXPANSION then
		state.dig_progress = 0
		state.land_level = state.land_level + 1
		return "land-grow"
	end
	return string.format("digging:%d", state.dig_progress)
end

-- advance the day clock; returns "new-day" | "night-fell" | nil
function M.tick_day(state, dt)
	local prev_day, prev_phase = state.day, state.phase
	state.clock_seconds = state.clock_seconds + dt
	if state.clock_seconds >= M.DAY_LENGTH_SECONDS then
		state.clock_seconds = state.clock_seconds - M.DAY_LENGTH_SECONDS
		state.day = state.day + 1
		state.phase = "day"
		state.node_cursor = 0
		M.replenish_nodes(state)
		if prev_phase ~= "day" then return "new-day" end
		return "new-day"
	end
	local half = M.DAY_LENGTH_SECONDS / 2
	local phase = state.clock_seconds < half and "day" or "night"
	if phase ~= prev_phase then
		state.phase = phase
		return phase == "night" and "night-fell" or nil
	end
	return nil
end

-- story beats, deduped; returns beat table or nil (port of story.ts)
function M.next_story_beat(state)
	local function seen(id) return state.stories_seen[id] end
	local function mark(id) state.stories_seen[id] = true end

	if state.day >= M.STORM_DAY and state.phase == "night" and not seen("storm") then
		mark("storm")
		return { id = "storm", title = "The storm", body = "Thunder cracks. Waves hurl themselves at the sandbar. You hold on till dawn." }
	end
	if state.day > M.STORM_DAY and state.collected_count >= 5 and not seen("wreck") then
		mark("wreck")
		return { id = "wreck", title = "Wreckage on the tide", body = "Dawn reveals a broken hull on the rocks — and someone clinging to it." }
	end
	if state.land_level >= 1 and not seen("land-grow") then
		mark("land-grow")
		return { id = "land-grow", title = "New ground", body = "Your digging has pushed the sandbar outward. There is room to breathe." }
	end
	if state.structures and #state.structures >= 1 and not seen("first-hut") then
		for _, s in ipairs(state.structures) do
			if s.kind == "hut" then
				mark("first-hut")
				return { id = "first-hut", title = "A roof of your own", body = "The hut stands. For the first time, you sleep out of the wind." }
			end
		end
	end
	return nil
end

-- arrivals on new day; returns name or nil
function M.process_arrivals(state)
	for i, a in ipairs(M.ARRIVALS) do
		if state.day >= a.day and not state.arrivals_done[i] then
			local huts = 0
			for _, s in ipairs(state.structures) do
				if s.kind == "hut" then huts = huts + 1 end
			end
			if huts >= a.hut then
				state.arrivals_done[i] = true
				state.population = state.population + 1
				return a.name
			end
		end
	end
	return nil
end

return M
