--!strict
-- Логика производства одного здания.
-- Чистый модуль: не обращается к Roblox API и ничего не подключает через require.
-- Рецепт передаётся аргументом, поэтому модуль тестируется в Lune без Studio.

local Production = {}

export type Recipe = {
	inputs: { [string]: number },
	outputs: { [string]: number },
	cycleSeconds: number,
	workers: number,
	storage: number,
}

-- Причина, по которой здание работает или стоит. Показывается игроку над зданием.
export type Status = "working" | "no_input" | "output_full" | "no_workers"

export type State = {
	running: boolean, -- идёт ли цикл (входные ресурсы уже списаны)
	progress: number, -- сколько секунд цикла пройдено
	input: { [string]: number }, -- входной склад
	output: { [string]: number }, -- выходной склад
	status: Status,
}

function Production.new(): State
	return {
		running = false,
		progress = 0,
		input = {},
		output = {},
		status = "no_input",
	}
end

local function hasInputs(recipe: Recipe, state: State): boolean
	for resource, amount in recipe.inputs do
		if (state.input[resource] or 0) < amount then
			return false
		end
	end
	return true
end

local function outputsFit(recipe: Recipe, state: State): boolean
	for resource, amount in recipe.outputs do
		if (state.output[resource] or 0) + amount > recipe.storage then
			return false
		end
	end
	return true
end

-- Продвигает производство на dt секунд. workers — сколько рабочих сейчас на месте.
-- Возвращает итоговый статус (он же записывается в state.status).
function Production.tick(recipe: Recipe, state: State, dt: number, workers: number): Status
	local noWorkers = recipe.workers > 0 and workers <= 0
	if not state.running then
		-- Не начинаем цикл, если продукцию некуда будет сложить: иначе сырьё пропадёт зря.
		-- Склад и сырьё проверяются раньше рабочих: игроку важнее настоящая причина простоя.
		if not outputsFit(recipe, state) then
			state.status = "output_full"
			return state.status
		end
		if not hasInputs(recipe, state) then
			state.status = "no_input"
			return state.status
		end
		if noWorkers then
			state.status = "no_workers"
			return state.status
		end
		for resource, amount in recipe.inputs do
			state.input[resource] -= amount
		end
		state.running = true
		state.progress = 0
	end

	if noWorkers then
		state.status = "no_workers"
		return state.status
	end

	local efficiency = if recipe.workers > 0 then math.min(1, workers / recipe.workers) else 1
	state.progress = math.min(recipe.cycleSeconds, state.progress + dt * efficiency)

	if state.progress >= recipe.cycleSeconds then
		if not outputsFit(recipe, state) then
			state.status = "output_full"
			return state.status
		end
		for resource, amount in recipe.outputs do
			state.output[resource] = (state.output[resource] or 0) + amount
		end
		state.running = false
		state.progress = 0
	end

	state.status = "working"
	return state.status
end

-- Может ли здание сейчас работать, если дать ему рабочих: цикл уже идёт
-- или есть сырьё и место для продукции. Простаивающим рабочих дают в последнюю очередь.
function Production.canWork(recipe: Recipe, state: State): boolean
	return state.running or (outputsFit(recipe, state) and hasInputs(recipe, state))
end

-- Грузовик привозит ресурс на входной склад. Возвращает, сколько здание приняло.
function Production.deliver(recipe: Recipe, state: State, resource: string, amount: number): number
	if recipe.inputs[resource] == nil or amount <= 0 then
		return 0
	end
	local current = state.input[resource] or 0
	local accepted = math.min(amount, recipe.storage - current)
	if accepted <= 0 then
		return 0
	end
	state.input[resource] = current + accepted
	return accepted
end

-- Грузовик забирает продукцию с выходного склада. Возвращает, сколько забрал.
function Production.take(state: State, resource: string, amount: number): number
	local current = state.output[resource] or 0
	local taken = math.min(amount, current)
	if taken <= 0 then
		return 0
	end
	state.output[resource] = current - taken
	return taken
end

return Production
