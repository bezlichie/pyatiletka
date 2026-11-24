--!strict
-- Стройплощадка: здание ждёт материалы, грузовики их привозят, потом идёт стройка.
-- Чистый модуль: не обращается к Roblox API и ничего не подключает через require.

local Construction = {}

export type State = {
	cost: { [string]: number }, -- сколько каждого материала нужно всего
	delivered: { [string]: number }, -- сколько уже привезли
	buildSeconds: number,
	progress: number, -- секунд стройки пройдено (идёт, когда все материалы на месте)
	done: boolean,
}

function Construction.new(cost: { [string]: number }, buildSeconds: number): State
	return {
		cost = table.clone(cost),
		delivered = {},
		buildSeconds = buildSeconds,
		progress = 0,
		done = false,
	}
end

-- Сколько ещё нужно привезти материала.
function Construction.remaining(state: State, resource: string): number
	local need = state.cost[resource]
	if need == nil then
		return 0
	end
	return math.max(0, need - (state.delivered[resource] or 0))
end

function Construction.hasAllMaterials(state: State): boolean
	for resource in state.cost do
		if Construction.remaining(state, resource) > 0 then
			return false
		end
	end
	return true
end

-- Грузовик привозит материал. Возвращает, сколько принято (лишнее не берём).
function Construction.deliver(state: State, resource: string, amount: number): number
	if state.done or amount <= 0 then
		return 0
	end
	local accepted = math.min(amount, Construction.remaining(state, resource))
	if accepted > 0 then
		state.delivered[resource] = (state.delivered[resource] or 0) + accepted
	end
	return accepted
end

-- Продвигает стройку. Возвращает true в момент завершения и после него.
function Construction.tick(state: State, dt: number): boolean
	if state.done then
		return true
	end
	if not Construction.hasAllMaterials(state) then
		return false
	end
	state.progress = math.min(state.buildSeconds, state.progress + dt)
	if state.progress >= state.buildSeconds then
		state.done = true
	end
	return state.done
end

return Construction
