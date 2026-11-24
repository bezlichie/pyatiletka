--!strict
-- Сетка региона: перевод мировых координат в клетки и занятость клеток.
-- Чистый модуль: не обращается к Roblox API и ничего не подключает через require.
-- Клетка (0, 0) — угол региона с наименьшими X и Z.

local Grid = {}

export type Cell = { x: number, z: number }

-- Почему клетку нельзя занять. Клиент показывает это при стройке.
export type PlaceError = "out_of_bounds" | "occupied" | "bad_size"

export type Grid = {
	cellSize: number,
	size: number, -- сторона региона в клетках
	originX: number, -- мировая координата X угла клетки (0, 0)
	originZ: number,
	cells: { [number]: string }, -- ключ клетки -> id объекта, который её занимает
	objects: { [string]: { number } }, -- id объекта -> ключи его клеток
}

export type Config = { cellSize: number, regionCells: number }

-- centerX, centerZ — мировые координаты центра региона.
function Grid.new(config: Config, centerX: number, centerZ: number): Grid
	local half = config.regionCells * config.cellSize / 2
	return {
		cellSize = config.cellSize,
		size = config.regionCells,
		originX = centerX - half,
		originZ = centerZ - half,
		cells = {},
		objects = {},
	}
end

local function key(grid: Grid, x: number, z: number): number
	return z * grid.size + x
end

function Grid.inBounds(grid: Grid, x: number, z: number): boolean
	return x >= 0 and z >= 0 and x < grid.size and z < grid.size
end

-- Клетка под мировой точкой или nil, если точка за пределами региона.
function Grid.toCell(grid: Grid, worldX: number, worldZ: number): Cell?
	local x = math.floor((worldX - grid.originX) / grid.cellSize)
	local z = math.floor((worldZ - grid.originZ) / grid.cellSize)
	if not Grid.inBounds(grid, x, z) then
		return nil
	end
	return { x = x, z = z }
end

-- Мировые координаты центра клетки.
function Grid.cellCenter(grid: Grid, x: number, z: number): (number, number)
	return grid.originX + (x + 0.5) * grid.cellSize, grid.originZ + (z + 0.5) * grid.cellSize
end

-- Мировые координаты центра прямоугольника sizeX × sizeZ клеток с углом в (x, z).
-- rotation — число поворотов на 90°; при нечётном стороны меняются местами.
function Grid.areaCenter(
	grid: Grid,
	x: number,
	z: number,
	sizeX: number,
	sizeZ: number,
	rotation: number
): (number, number)
	local w, d = Grid.rotatedSize(sizeX, sizeZ, rotation)
	return grid.originX + (x + w / 2) * grid.cellSize, grid.originZ + (z + d / 2) * grid.cellSize
end

function Grid.rotatedSize(sizeX: number, sizeZ: number, rotation: number): (number, number)
	if rotation % 2 == 1 then
		return sizeZ, sizeX
	end
	return sizeX, sizeZ
end

-- Клетки, которые займёт прямоугольник с углом в (x, z).
function Grid.footprint(x: number, z: number, sizeX: number, sizeZ: number, rotation: number): { Cell }
	local w, d = Grid.rotatedSize(sizeX, sizeZ, rotation)
	local result = {}
	for dz = 0, d - 1 do
		for dx = 0, w - 1 do
			table.insert(result, { x = x + dx, z = z + dz })
		end
	end
	return result
end

-- Можно ли поставить объект. Возвращает true или false и причину.
function Grid.canPlace(
	grid: Grid,
	x: number,
	z: number,
	sizeX: number,
	sizeZ: number,
	rotation: number
): (boolean, PlaceError?)
	if sizeX < 1 or sizeZ < 1 or sizeX % 1 ~= 0 or sizeZ % 1 ~= 0 then
		return false, "bad_size"
	end
	for _, cell in Grid.footprint(x, z, sizeX, sizeZ, rotation) do
		if not Grid.inBounds(grid, cell.x, cell.z) then
			return false, "out_of_bounds"
		end
		if grid.cells[key(grid, cell.x, cell.z)] ~= nil then
			return false, "occupied"
		end
	end
	return true, nil
end

-- Занимает клетки под объектом id. Возвращает false и причину, если места нет.
function Grid.place(
	grid: Grid,
	id: string,
	x: number,
	z: number,
	sizeX: number,
	sizeZ: number,
	rotation: number
): (boolean, PlaceError?)
	if grid.objects[id] ~= nil then
		return false, "occupied"
	end
	local ok, err = Grid.canPlace(grid, x, z, sizeX, sizeZ, rotation)
	if not ok then
		return false, err
	end
	local keys = {}
	for _, cell in Grid.footprint(x, z, sizeX, sizeZ, rotation) do
		local k = key(grid, cell.x, cell.z)
		grid.cells[k] = id
		table.insert(keys, k)
	end
	grid.objects[id] = keys
	return true, nil
end

-- Освобождает клетки объекта. Возвращает false, если такого объекта нет.
function Grid.remove(grid: Grid, id: string): boolean
	local keys = grid.objects[id]
	if keys == nil then
		return false
	end
	for _, k in keys do
		grid.cells[k] = nil
	end
	grid.objects[id] = nil
	return true
end

-- id объекта в клетке или nil.
function Grid.objectAt(grid: Grid, x: number, z: number): string?
	if not Grid.inBounds(grid, x, z) then
		return nil
	end
	return grid.cells[key(grid, x, z)]
end

return Grid
