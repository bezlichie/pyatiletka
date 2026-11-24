--!strict
-- Дорожная сеть региона как граф клеток: узлы — клетки с дорогой, рёбра — соседство по сторонам.
-- Здание подключено, если хотя бы одна дорога примыкает к его краю.
-- Чистый модуль: не обращается к Roblox API и ничего не подключает через require.

local Roads = {}

export type Cell = { x: number, z: number }

export type Roads = {
	size: number, -- сторона региона в клетках
	cells: { [number]: boolean }, -- ключ клетки -> есть дорога
	count: number,
	version: number, -- растёт при каждом изменении сети
	-- Связные куски сети: ключ клетки -> номер куска. Пересчитываются лениво после изменений,
	-- чтобы поиск пути между несвязанными дорогами отвечал сразу, без обхода всей сети.
	components: { [number]: number },
	componentsVersion: number,
}

local DIRECTIONS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

function Roads.new(size: number): Roads
	return { size = size, cells = {}, count = 0, version = 0, components = {}, componentsVersion = -1 }
end

local function key(roads: Roads, x: number, z: number): number
	return z * roads.size + x
end

local function inBounds(roads: Roads, x: number, z: number): boolean
	return x >= 0 and z >= 0 and x < roads.size and z < roads.size
end

function Roads.has(roads: Roads, x: number, z: number): boolean
	return inBounds(roads, x, z) and roads.cells[key(roads, x, z)] == true
end

function Roads.add(roads: Roads, x: number, z: number): boolean
	if not inBounds(roads, x, z) or Roads.has(roads, x, z) then
		return false
	end
	roads.cells[key(roads, x, z)] = true
	roads.count += 1
	roads.version += 1
	return true
end

function Roads.remove(roads: Roads, x: number, z: number): boolean
	if not Roads.has(roads, x, z) then
		return false
	end
	roads.cells[key(roads, x, z)] = nil
	roads.count -= 1
	roads.version += 1
	return true
end

-- Клетки линии от (x1, z1) до (x2, z2) буквой «Г»: сначала по X, потом по Z. Концы включены.
function Roads.linePath(x1: number, z1: number, x2: number, z2: number): { Cell }
	local result = {}
	local stepX = if x2 >= x1 then 1 else -1
	for x = x1, x2, stepX do
		table.insert(result, { x = x, z = z1 })
	end
	local stepZ = if z2 >= z1 then 1 else -1
	if z2 ~= z1 then
		for z = z1 + stepZ, z2, stepZ do
			table.insert(result, { x = x2, z = z })
		end
	end
	return result
end

-- Соседние клетки с дорогой.
function Roads.neighbors(roads: Roads, x: number, z: number): { Cell }
	local result = {}
	for _, d in DIRECTIONS do
		local nx, nz = x + d[1], z + d[2]
		if Roads.has(roads, nx, nz) then
			table.insert(result, { x = nx, z = nz })
		end
	end
	return result
end

-- Клетки дороги, примыкающие снаружи к прямоугольнику w × d с углом в (x, z).
-- Это «подъезды» здания: отсюда грузовик забирает и сюда привозит груз.
function Roads.entrances(roads: Roads, x: number, z: number, w: number, d: number): { Cell }
	local result = {}
	local function check(cx: number, cz: number)
		if Roads.has(roads, cx, cz) then
			table.insert(result, { x = cx, z = cz })
		end
	end
	for dx = 0, w - 1 do
		check(x + dx, z - 1)
		check(x + dx, z + d)
	end
	for dz = 0, d - 1 do
		check(x - 1, z + dz)
		check(x + w, z + dz)
	end
	return result
end

-- Пересчитать связные куски сети, если дороги менялись после прошлого пересчёта.
local function ensureComponents(roads: Roads)
	if roads.componentsVersion == roads.version then
		return
	end
	local size = roads.size
	local cells = roads.cells
	local components: { [number]: number } = {}
	local queue: { number } = {}
	local nextId = 0
	for start in cells do
		if components[start] == nil then
			nextId += 1
			components[start] = nextId
			table.clear(queue)
			queue[1] = start
			local head = 1
			while head <= #queue do
				local k = queue[head]
				head += 1
				local x = k % size
				local function visit(nk: number)
					if cells[nk] and components[nk] == nil then
						components[nk] = nextId
						table.insert(queue, nk)
					end
				end
				if x + 1 < size then
					visit(k + 1)
				end
				if x > 0 then
					visit(k - 1)
				end
				visit(k + size)
				visit(k - size)
			end
		end
	end
	roads.components = components
	roads.componentsVersion = roads.version
end

-- Номер связного куска сети для клетки с дорогой (nil, если дороги нет).
function Roads.component(roads: Roads, x: number, z: number): number?
	if not Roads.has(roads, x, z) then
		return nil
	end
	ensureComponents(roads)
	return roads.components[key(roads, x, z)]
end

-- Связаны ли дорогой хоть одна клетка a и хоть одна клетка b. Быстрее findPath:
-- сравниваются номера связных кусков сети, маршрут не строится.
function Roads.connected(roads: Roads, a: { Cell }, b: { Cell }): boolean
	ensureComponents(roads)
	local wanted: { [number]: boolean } = {}
	for _, c in b do
		if Roads.has(roads, c.x, c.z) then
			wanted[roads.components[key(roads, c.x, c.z)]] = true
		end
	end
	for _, c in a do
		if Roads.has(roads, c.x, c.z) and wanted[roads.components[key(roads, c.x, c.z)]] then
			return true
		end
	end
	return false
end

-- Кратчайший путь по дорогам от любой клетки starts до любой клетки goals (поиск в ширину).
-- Возвращает список клеток от старта до цели включительно или nil, если пути нет.
function Roads.findPath(roads: Roads, starts: { Cell }, goals: { Cell }): { Cell }?
	ensureComponents(roads)
	local components = roads.components
	local size = roads.size
	local cells = roads.cells

	-- Цели и куски сети, в которых они лежат.
	local goalSet: { [number]: boolean } = {}
	local goalComponents: { [number]: boolean } = {}
	for _, g in goals do
		if Roads.has(roads, g.x, g.z) then
			local k = key(roads, g.x, g.z)
			goalSet[k] = true
			goalComponents[components[k]] = true
		end
	end

	-- Старты: только те, что связаны хоть с одной целью. Нет таких — пути нет, обходить нечего.
	local cameFrom: { [number]: number } = {}
	local queue: { number } = {}
	for _, s in starts do
		if Roads.has(roads, s.x, s.z) then
			local k = key(roads, s.x, s.z)
			if cameFrom[k] == nil and goalComponents[components[k]] then
				cameFrom[k] = -1
				table.insert(queue, k)
			end
		end
	end

	local head = 1
	while head <= #queue do
		local k = queue[head]
		head += 1
		if goalSet[k] then
			local reversed = {}
			local cur = k
			while cur ~= -1 do
				table.insert(reversed, { x = cur % size, z = math.floor(cur / size) })
				cur = cameFrom[cur]
			end
			local path = table.create(#reversed)
			for i = #reversed, 1, -1 do
				table.insert(path, reversed[i])
			end
			return path
		end
		local x = k % size
		-- Соседи по сторонам без выделения таблиц: ключи соседних клеток.
		if x + 1 < size and cells[k + 1] and cameFrom[k + 1] == nil then
			cameFrom[k + 1] = k
			table.insert(queue, k + 1)
		end
		if x > 0 and cells[k - 1] and cameFrom[k - 1] == nil then
			cameFrom[k - 1] = k
			table.insert(queue, k - 1)
		end
		if cells[k + size] and cameFrom[k + size] == nil then
			cameFrom[k + size] = k
			table.insert(queue, k + size)
		end
		if cells[k - size] and cameFrom[k - size] == nil then
			cameFrom[k - size] = k
			table.insert(queue, k - size)
		end
	end
	return nil
end

return Roads
