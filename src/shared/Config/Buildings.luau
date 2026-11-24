--!strict
-- Здания, которые можно поставить: размер на сетке, вид и название.
-- Производство зданий описано в Recipes.luau под тем же id (если здание что-то производит).

export type Building = {
	name: { ru: string, en: string },
	sizeX: number, -- ширина в клетках (до поворота)
	sizeZ: number, -- глубина в клетках (до поворота)
	height: number, -- высота корпуса в студах
	color: { number }, -- RGB 0–255 (не Color3, чтобы конфиг читался в Lune)
	roofColor: { number },
	era: number, -- с какой эпохи доступно
	order: number, -- порядок кнопок на панели стройки
}

local Buildings: { [string]: Building } = {
	forestry = {
		name = { ru = "Лесозаготовка", en = "Forestry" },
		sizeX = 3,
		sizeZ = 3,
		height = 5,
		color = { 122, 92, 62 },
		roofColor = { 70, 110, 60 },
		era = 0,
		order = 1,
	},
	sawmill = {
		name = { ru = "Лесопилка", en = "Sawmill" },
		sizeX = 4,
		sizeZ = 3,
		height = 7,
		color = { 176, 140, 96 },
		roofColor = { 110, 70, 50 },
		era = 0,
		order = 2,
	},
	house = {
		name = { ru = "Жилой дом", en = "House" },
		sizeX = 2,
		sizeZ = 2,
		height = 6,
		color = { 214, 200, 170 },
		roofColor = { 150, 60, 50 },
		era = 0,
		order = 3,
	},
}

return Buildings
