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
	-- Еда и довольство (этап 2, шаг 2)
	foodPerResidentPerSecond: number,
	shopRadius: number,
	happinessRatePerSecond: number,
	fedHappiness: number,
	hungryHappiness: number,
	growMinHappiness: number,
	leaveBelowHappiness: number,
	leavePerSecond: number,
	leaveFloorShare: number,
}

-- Дом для расчёта еды: сколько живёт, сколько еды он «должен» съесть и сыт ли он.
export type Eater = {
	id: string,
	x: number,
	z: number,
	w: number,
	d: number,
	residents: number,
	debt: number, -- накопленная, но ещё не съеденная еда (дробная)
	fed: boolean, -- получил ли дом последнюю целую порцию
}

export type Shop = {
	id: string,
	x: number,
	z: number,
	w: number,
	d: number,
	stock: number, -- сколько продуктов в магазине
}

export type FeedResult = {
	taken: { [string]: number }, -- id магазина -> сколько продуктов забрали дома
	debt: { [string]: number }, -- id дома -> новый долг
	fed: { [string]: boolean }, -- id дома -> сыт ли
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

-- Жильцы через dt секунд с учётом довольства: довольные въезжают,
-- несчастные уезжают (но не все: доля leaveFloorShare остаётся, чтобы регион
-- мог подняться без рабочих), в середине никто не двигается.
function Population.migrate(
	residents: number,
	capacity: number,
	happiness: number,
	dt: number,
	config: Config
): number
	if happiness < config.leaveBelowHappiness then
		local floor = capacity * config.leaveFloorShare
		if residents <= floor then
			return residents
		end
		return math.max(floor, residents - config.leavePerSecond * dt)
	end
	if happiness >= config.growMinHappiness then
		return Population.grow(residents, capacity, dt, config)
	end
	return math.min(residents, capacity)
end

-- Довольство дома через dt секунд: плавно идёт к цели (сытый или голодный дом).
function Population.happiness(current: number, fed: boolean, dt: number, config: Config): number
	local target = if fed then config.fedHappiness else config.hungryHappiness
	local step = config.happinessRatePerSecond * dt
	if current < target then
		return math.min(target, current + step)
	end
	return math.max(target, current - step)
end

-- Накормить дома за dt секунд. Каждый дом копит «долг» по еде и, когда набирается
-- целая порция, забирает её из ближайших магазинов в радиусе shopRadius.
-- Сытость меняется только когда подошла порция: так маленький дом не голодает
-- между порциями. Дом без магазина рядом голоден сразу.
function Population.feed(eaters: { Eater }, shops: { Shop }, dt: number, config: Config): FeedResult
	local stock: { [string]: number } = {}
	for _, shop in shops do
		stock[shop.id] = shop.stock
	end
	local result: FeedResult = { taken = {}, debt = {}, fed = {} }
	for _, house in eaters do
		local near: { { shop: Shop, gap: number } } = {}
		for _, shop in shops do
			local gap = Population.gap(house, shop)
			if gap <= config.shopRadius then
				table.insert(near, { shop = shop, gap = gap })
			end
		end
		local debt = house.debt + math.floor(house.residents) * config.foodPerResidentPerSecond * dt
		local fed = house.fed
		if #near == 0 then
			fed = false
			debt = math.min(debt, 1) -- без магазина долг не копится бесконечно
		else
			local whole = math.floor(debt)
			if whole > 0 then
				table.sort(near, function(a, b)
					if a.gap ~= b.gap then
						return a.gap < b.gap
					end
					return a.shop.id < b.shop.id
				end)
				local got = 0
				for _, item in near do
					local id = item.shop.id
					local n = math.min(stock[id], whole - got)
					if n > 0 then
						stock[id] -= n
						result.taken[id] = (result.taken[id] or 0) + n
						got += n
					end
					if got >= whole then
						break
					end
				end
				fed = got >= whole
				-- Не съеденное не копится сверх одной порции: голод — это состояние, а не долг.
				debt = math.min(debt - got, 1)
			end
		end
		result.debt[house.id] = debt
		result.fed[house.id] = fed
	end
	return result
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
