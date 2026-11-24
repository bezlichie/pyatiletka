--!strict
-- Проверка команды «поставить здание», пришедшей от клиента.
-- Клиенту нельзя доверять: аргументы могут быть любого типа и любого значения.
-- Чистый модуль: конфиг зданий и сетка передаются аргументами.

local BuildCommand = {}

export type BuildingSize = { sizeX: number, sizeZ: number, era: number }

export type Command = { typeId: string, x: number, z: number, rotation: number }

export type CommandError = "bad_args" | "unknown_building" | "locked"

local function isInteger(v: any): boolean
	return type(v) == "number" and v == v and v % 1 == 0 and math.abs(v) < 1e6
end

-- Возвращает разобранную команду или nil и причину отказа.
-- currentEra — эпоха игрока: здания более поздних эпох ставить нельзя.
function BuildCommand.parse(
	buildings: { [string]: BuildingSize },
	currentEra: number,
	typeId: any,
	x: any,
	z: any,
	rotation: any
): (Command?, CommandError?)
	if type(typeId) ~= "string" or not isInteger(x) or not isInteger(z) or not isInteger(rotation) then
		return nil, "bad_args"
	end
	if rotation < 0 or rotation > 3 then
		return nil, "bad_args"
	end
	local building = buildings[typeId]
	if building == nil then
		return nil, "unknown_building"
	end
	if building.era > currentEra then
		return nil, "locked"
	end
	return { typeId = typeId, x = x, z = z, rotation = rotation }, nil
end

return BuildCommand
