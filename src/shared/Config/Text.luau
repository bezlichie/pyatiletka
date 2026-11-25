--!strict
-- Тексты интерфейса. Пока показываем русские, английские добавим вместе с выбором языка (этап 2).

export type Text = { ru: string, en: string }

return {
	resources = {
		logs = { ru = "брёвна", en = "logs" },
		boards = { ru = "доски", en = "boards" },
		gravel = { ru = "гравий", en = "gravel" },
		concrete = { ru = "бетон", en = "concrete" },
		grain = { ru = "зерно", en = "grain" },
		food = { ru = "продукты", en = "food" },
		ore = { ru = "руда", en = "ore" },
		coal = { ru = "уголь", en = "coal" },
		steel = { ru = "сталь", en = "steel" },
		vehicles = { ru = "техника", en = "vehicles" },
	} :: { [string]: Text },

	status = {
		working = { ru = "работает", en = "working" },
		no_input = { ru = "нет сырья", en = "no input" },
		output_full = { ru = "склад полон", en = "storage full" },
		no_workers = { ru = "нет рабочих", en = "no workers" },
		no_road = { ru = "нет дороги", en = "no road access" },
	} :: { [string]: Text },

	buildErrors = {
		bad_args = { ru = "Ошибка команды", en = "Bad command" },
		unknown_building = { ru = "Неизвестное здание", en = "Unknown building" },
		locked = { ru = "Ещё не открыто", en = "Not unlocked yet" },
		out_of_bounds = { ru = "За краем региона", en = "Outside the region" },
		occupied = { ru = "Место занято", en = "Space is taken" },
		bad_size = { ru = "Ошибка размера", en = "Bad size" },
		not_found = { ru = "Здание не найдено", en = "Building not found" },
		too_fast = { ru = "Слишком быстро", en = "Too fast" },
		too_long = { ru = "Слишком длинная дорога", en = "Road is too long" },
	} :: { [string]: Text },

	labels = {
		input = { ru = "сырьё", en = "input" },
		output = { ru = "склад", en = "stock" },
		trucks = { ru = "грузовиков", en = "trucks" },
		construction = { ru = "стройка", en = "construction" },
		waitingMaterials = { ru = "ждёт материалы", en = "waiting for materials" },
		building = { ru = "строится", en = "building" },
		built = { ru = "построен", en = "built" },
		trucksFree = { ru = "свободно", en = "free" },
		workers = { ru = "рабочие", en = "workers" },
		residents = { ru = "жильцов", en = "residents" },
		working = { ru = "работают", en = "working" },
		happiness = { ru = "довольство", en = "happiness" },
		fed = { ru = "еда есть", en = "fed" },
		hungry = { ru = "нет еды", en = "no food" },
		noShop = { ru = "нет магазина рядом", en = "no shop nearby" },
	} :: { [string]: Text },

	buildMode = {
		demolish = { ru = "Снос", en = "Demolish" },
		road = { ru = "Дорога", en = "Road" },
		cancel = { ru = "Отмена", en = "Cancel" },
		placeHint = {
			ru = "ЛКМ — поставить · R — повернуть · та же цифра или «Отмена» — выйти",
			en = "LMB — place · R — rotate · same number or Cancel — exit",
		},
		placeHintTouch = {
			ru = "Коснитесь места, затем коснитесь ещё раз, чтобы поставить",
			en = "Tap a spot, then tap again to place",
		},
		roadHintTouch = {
			ru = "Коснитесь начала, затем конца, затем конца ещё раз, чтобы проложить",
			en = "Tap the start, then the end, then the end again to build",
		},
		roadHint = {
			ru = "ЛКМ — начало, ЛКМ ещё раз — конец участка · та же цифра или «Отмена» — выйти",
			en = "LMB — start, LMB again — end of segment · same number or Cancel — exit",
		},
		demolishHint = {
			ru = "ЛКМ по зданию или дороге — снести · X или «Отмена» — выйти",
			en = "Click a building to demolish · X or Cancel — exit",
		},
	} :: { [string]: Text },
}
