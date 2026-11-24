--!strict
-- Рецепты зданий: что здание потребляет и что выпускает за один цикл.
-- Все числа здесь черновые: баланс правится в этом файле, а не в коде симуляции.
-- Модуль ничего не подключает через require, чтобы его можно было тестировать в Lune.

export type Recipe = {
	inputs: { [string]: number }, -- ресурс -> сколько тратится за цикл
	outputs: { [string]: number }, -- ресурс -> сколько выпускается за цикл
	cycleSeconds: number, -- длительность цикла при полной укомплектованности
	workers: number, -- сколько рабочих нужно для 100% скорости
	storage: number, -- ёмкость склада на каждый ресурс (и на входе, и на выходе)
	era: number, -- с какой эпохи доступно (0 = старт)
}

local Recipes: { [string]: Recipe } = {
	-- Стройматериалы
	forestry = { inputs = {}, outputs = { logs = 1 }, cycleSeconds = 4, workers = 4, storage = 20, era = 0 },
	sawmill = {
		inputs = { logs = 2 },
		outputs = { boards = 1 },
		cycleSeconds = 5,
		workers = 6,
		storage = 20,
		era = 0,
	},
	quarry = { inputs = {}, outputs = { gravel = 1 }, cycleSeconds = 4, workers = 5, storage = 20, era = 1 },
	concrete_plant = {
		inputs = { gravel = 2 },
		outputs = { concrete = 1 },
		cycleSeconds = 6,
		workers = 8,
		storage = 20,
		era = 1,
	},

	-- Еда
	farm = { inputs = {}, outputs = { grain = 2 }, cycleSeconds = 8, workers = 5, storage = 30, era = 0 },
	food_plant = {
		inputs = { grain = 2 },
		outputs = { food = 2 },
		cycleSeconds = 6,
		workers = 6,
		storage = 30,
		era = 0,
	},

	-- Металл
	ore_mine = { inputs = {}, outputs = { ore = 1 }, cycleSeconds = 5, workers = 8, storage = 20, era = 2 },
	coal_mine = { inputs = {}, outputs = { coal = 1 }, cycleSeconds = 5, workers = 8, storage = 20, era = 2 },
	steelworks = {
		inputs = { ore = 2, coal = 1 },
		outputs = { steel = 1 },
		cycleSeconds = 8,
		workers = 12,
		storage = 20,
		era = 2,
	},
	machine_plant = {
		inputs = { steel = 3 },
		outputs = { vehicles = 1 },
		cycleSeconds = 20,
		workers = 15,
		storage = 10,
		era = 3,
	},

	-- ТЭЦ и электросеть появятся отдельным модулем: электричество не хранится на складах.
}

return Recipes
