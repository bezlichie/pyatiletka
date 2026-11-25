--!strict
-- Население: жильцы в домах и рабочие на заводах (этап 2, шаг 1).
-- Жителей считаем по домам, а не поштучно. Чистый модуль: здания и конфиг передаются
-- аргументами, поэтому логика тестируется в Lune без Studio.

local Population = {}

-- Прямоугольник здания в клетках: угол (x, z), размер w × d (уже с учётом поворота).
export type Rect = { x: number, z: number, w: number, d: number }

export type House = {
	id: string,
	x: number,
	z: number,
	w: number,
	d: number,
	capacity: number, -- сколько жильцов вмещает
	residents: number, -- сколько живёт сейчас (может быть дробным, показываем целую часть)
}

export type Workplace = {
	id: string,
	x: number,
	z: number,
	w: number,
	d: number,
	need: number, -- сколько рабочих нужно для полной скорости
}

export type Config = {
	workerShare: number,
	walkRadius: number,
	moveInPerSecond: number,
}

export type Allocation = {
	workers: { [string]: number }, -- id здания -> сколько рабочих досталось
	employed: { [string]: number }, -- id дома -> сколько его жильцов работает
}

-- Расстояние между краями двух прямоугольников в клетках (по сторонам, без диагоналей).
-- Соседние здания — 0.
function Population.gap(a: Rect, b: Rect): number
	local dx = math.max(0, a.x - (b.x + b.w), b.x - (a.x + a.w))
	local dz = math.max(0, a.z - (b.z + b.d), b.z - (a.z + a.d))
	return dx + dz
end

-- Жильцы через dt секунд: свободные места заполняются с постоянной скоростью.
function Population.grow(residents: number, capacity: number, dt: number, config: Config): number
	if residents >= capacity then
		return capacity
	end
	return math.min(capacity, residents + config.moveInPerSecond * dt)
end

-- Сколько работников даёт дом.
function Population.workersOf(residents: number, config: Config): number
	return math.floor(math.floor(residents) * config.workerShare)
end

-- Распределить рабочих по зданиям. Здания обходятся в порядке списка
-- (вызывающий задаёт порядок), каждое берёт людей из ближайших домов в радиусе.
function Population.allocate(houses: { House }, workplaces: { Workplace }, config: Config): Allocation
	local free: { [string]: number } = {}
	local employed: { [string]: number } = {}
	for _, house in houses do
		free[house.id] = Population.workersOf(house.residents, config)
		employed[house.id] = 0
	end
	local workers: { [string]: number } = {}
	for _, place in workplaces do
		local near: { { house: House, gap: number } } = {}
		for _, house in houses do
			if free[house.id] > 0 then
				local gap = Population.gap(place, house)
				if gap <= config.walkRadius then
					table.insert(near, { house = house, gap = gap })
				end
			end
		end
		table.sort(near, function(a, b)
			if a.gap ~= b.gap then
				return a.gap < b.gap
			end
			return a.house.id < b.house.id
		end)
		local got = 0
		for _, item in near do
			if got >= place.need then
				break
			end
			local id = item.house.id
			local n = math.min(free[id], place.need - got)
			free[id] -= n
			employed[id] += n
			got += n
		end
		workers[place.id] = got
	end
	return { workers = workers, employed = employed }
end

return Population
