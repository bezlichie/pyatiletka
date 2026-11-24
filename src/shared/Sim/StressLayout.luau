--!strict
-- Раскладка стресс-региона для замера тика: ряды одинаковых цепочек,
-- связанных в одну дорожную сеть. Чистый модуль: только координаты клеток.
--
-- Один блок — 16 × 4 клетки. Сверху вниз по z:
--   z0 .. z0+2   лесозаготовка 3×3, лесопилка 4×3, дом 2×2, автопарк 3×2;
--   z0+3         дорога вдоль блока.
-- Справа от каждого столбца блоков — вертикальная дорога, над первым рядом — общая.

local StressLayout = {}

export type Placement = { typeId: string, x: number, z: number, rotation: number }
export type Line = { x1: number, z1: number, x2: number, z2: number }
export type Layout = { buildings: { Placement }, roads: { Line }, chains: number }

local BLOCK_W, BLOCK_H = 16, 4

-- Отрезок дороги, разбитый на куски не длиннее maxCells (как у команды игрока).
local function addLine(roads: { Line }, x1: number, z1: number, x2: number, z2: number, maxCells: number)
	if z1 == z2 then
		local step = if x2 >= x1 then 1 else -1
		local x = x1
		while true do
			local xEnd = if step > 0 then math.min(x + maxCells - 1, x2) else math.max(x - maxCells + 1, x2)
			table.insert(roads, { x1 = x, z1 = z1, x2 = xEnd, z2 = z1 })
			if xEnd == x2 then
				return
			end
			x = xEnd + step
		end
	else
		local step = if z2 >= z1 then 1 else -1
		local z = z1
		while true do
			local zEnd = if step > 0 then math.min(z + maxCells - 1, z2) else math.max(z - maxCells + 1, z2)
			table.insert(roads, { x1 = x1, z1 = z, x2 = x1, z2 = zEnd })
			if zEnd == z2 then
				return
			end
			z = zEnd + step
		end
	end
end

-- chains цепочек в квадрате региона size × size, начиная с клетки (startX, startZ).
-- Цепочек может получиться меньше, если не хватает места.
function StressLayout.build(
	chains: number,
	size: number,
	startX: number,
	startZ: number,
	maxCells: number
): Layout
	local cols = math.max(1, math.min(chains, math.floor((size - startX) / BLOCK_W)))
	local maxRows = math.floor((size - startZ - 1) / BLOCK_H)
	local rows = math.min(math.ceil(chains / cols), maxRows)
	local total = math.min(chains, cols * rows)
	local layout: Layout = { buildings = {}, roads = {}, chains = total }
	if total <= 0 then
		layout.chains = 0
		return layout
	end
	-- Общая дорога над первым рядом связывает столбцы.
	local top = startZ
	addLine(layout.roads, startX, top, startX + cols * BLOCK_W - 1, top, maxCells)
	local placed = 0
	for col = 0, cols - 1 do
		local bx = startX + col * BLOCK_W
		local lastZ = top
		for row = 0, rows - 1 do
			if placed >= total then
				break
			end
			local bz = top + 1 + row * BLOCK_H
			table.insert(layout.buildings, { typeId = "forestry", x = bx, z = bz, rotation = 0 })
			table.insert(layout.buildings, { typeId = "sawmill", x = bx + 4, z = bz, rotation = 0 })
			table.insert(layout.buildings, { typeId = "house", x = bx + 9, z = bz + 1, rotation = 0 })
			table.insert(layout.buildings, { typeId = "depot", x = bx + 12, z = bz + 1, rotation = 0 })
			addLine(layout.roads, bx, bz + 3, bx + BLOCK_W - 2, bz + 3, maxCells)
			lastZ = bz + 3
			placed += 1
		end
		-- Вертикальная дорога справа от столбца: от общей дороги до последнего ряда.
		addLine(layout.roads, bx + BLOCK_W - 1, top + 1, bx + BLOCK_W - 1, lastZ, maxCells)
	end
	return layout
end

return StressLayout
