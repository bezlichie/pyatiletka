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
}

local DIRECTIONS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

function Roads.new(size: number): Roads
	return { size = size, cells = {}, count = 0 }
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
	return true
end

function Roads.remove(roads: Roads, x: number, z: number): boolean
	if not Roads.has(roads, x, z) then
		return false
	end
	roads.cells[key(roads, x, z)] = nil
	roads.count -= 1
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

-- Кратчайший путь по дорогам от любой клетки starts до любой клетки goals (поиск в ширину).
-- Возвращает список клеток от старта до цели включительно или nil, если пути нет.
function Roads.findPath(roads: Roads, starts: { Cell }, goals: { Cell }): { Cell }?
	local goalSet: { [number]: boolean } = {}
	for _, g in goals do
		if Roads.has(roads, g.x, g.z) then
			goalSet[key(roads, g.x, g.z)] = true
		end
	end

	local cameFrom: { [number]: number } = {}
	local queue: { number } = {}
	local head = 1
	for _, s in starts do
		if Roads.has(roads, s.x, s.z) then
			local k = key(roads, s.x, s.z)
			if cameFrom[k] == nil then
				cameFrom[k] = -1
				table.insert(queue, k)
			end
		end
	end

	while head <= #queue do
		local k = queue[head]
		head += 1
		if goalSet[k] then
			local path = {}
			local cur = k
			while cur ~= -1 do
				table.insert(path, 1, { x = cur % roads.size, z = cur // roads.size })
				cur = cameFrom[cur]
			end
			return path
		end
		local x, z = k % roads.size, k // roads.size
		for _, n in Roads.neighbors(roads, x, z) do
			local nk = key(roads, n.x, n.z)
			if cameFrom[nk] == nil then
				cameFrom[nk] = k
				table.insert(queue, nk)
			end
		end
	end
	return nil
end

return Roads
