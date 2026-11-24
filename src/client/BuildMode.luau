--!strict
-- Режим стройки: панель зданий и дорог, призрак на сетке, поворот, установка и снос.
-- Клиент только показывает и просит: место окончательно проверяет сервер.
-- ПК: цифры или кнопки — выбрать здание или дорогу, R — повернуть, ЛКМ — поставить, X — снос.
-- Дорога: ЛКМ — начало, ЛКМ — конец участка буквой «Г»; следующий участок начинается с конца.
-- Телефон: кнопка, касание — показать место, второе касание туда же — подтвердить.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BuildingsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Buildings"))
local Text = require(Shared:WaitForChild("Config"):WaitForChild("Text"))
local RoadsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Roads"))
local Grid = require(Shared:WaitForChild("Sim"):WaitForChild("Grid"))
local Roads = require(Shared:WaitForChild("Sim"):WaitForChild("Roads"))
local GroundPick = require(script.Parent:WaitForChild("GroundPick"))

local BuildMode = {}

local GHOST_OK = Color3.fromRGB(80, 200, 120)
local GHOST_BAD = Color3.fromRGB(220, 70, 60)
local MESSAGE_SECONDS = 2.5
local NUMBER_KEYS = {
	Enum.KeyCode.One,
	Enum.KeyCode.Two,
	Enum.KeyCode.Three,
	Enum.KeyCode.Four,
	Enum.KeyCode.Five,
	Enum.KeyCode.Six,
	Enum.KeyCode.Seven,
	Enum.KeyCode.Eight,
	Enum.KeyCode.Nine,
}

type Mode = "none" | "place" | "road" | "demolish"

local function errorText(code: string?): string
	local t = if code then Text.buildErrors[code] else nil
	return if t then t.ru else Text.buildErrors.bad_args.ru
end

-- Список зданий для панели в порядке order.
local function buildingList(): { string }
	local ids = {}
	for id, def in BuildingsConfig do
		if def.era <= 0 then
			table.insert(ids, id)
		end
	end
	table.sort(ids, function(a, b)
		return BuildingsConfig[a].order < BuildingsConfig[b].order
	end)
	return ids
end

local function makeButton(text: string, parent: Instance): TextButton
	local button = Instance.new("TextButton")
	button.AutomaticSize = Enum.AutomaticSize.X
	button.Size = UDim2.fromOffset(0, 44)
	button.BackgroundColor3 = Color3.fromRGB(35, 38, 42)
	button.BackgroundTransparency = 0.15
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Font = Enum.Font.GothamMedium
	button.TextSize = 16
	button.Text = text
	button.AutoButtonColor = true
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.Parent = button
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button
	button.Parent = parent
	return button
end

function BuildMode.start(grid: Grid.Grid, groundY: number)
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local placeRemote = remotes:WaitForChild("PlaceBuilding") :: RemoteFunction
	local roadRemote = remotes:WaitForChild("PlaceRoad") :: RemoteFunction
	local demolishRemote = remotes:WaitForChild("Demolish") :: RemoteFunction
	local region = workspace:WaitForChild("Region")
	local buildingsFolder = region:WaitForChild("Buildings")
	local roadsFolder = region:WaitForChild("Roads")

	-- Зеркало занятости клеток: чтобы призрак сразу краснел над занятым местом.
	local function track(child: Instance)
		local typeId, x, z, rotation =
			child:GetAttribute("TypeId"),
			child:GetAttribute("CellX"),
			child:GetAttribute("CellZ"),
			child:GetAttribute("Rotation")
		local def = if type(typeId) == "string" then BuildingsConfig[typeId] else nil
		if def and type(x) == "number" and type(z) == "number" and type(rotation) == "number" then
			Grid.place(grid, child.Name, x, z, def.sizeX, def.sizeZ, rotation)
		end
	end
	for _, child in buildingsFolder:GetChildren() do
		track(child)
	end
	buildingsFolder.ChildAdded:Connect(track)
	buildingsFolder.ChildRemoved:Connect(function(child)
		Grid.remove(grid, child.Name)
	end)

	-- Дороги тоже занимают клетки: по одной на участок.
	local function trackRoad(child: Instance)
		local x, z = child:GetAttribute("CellX"), child:GetAttribute("CellZ")
		if type(x) == "number" and type(z) == "number" then
			Grid.place(grid, child.Name, x, z, 1, 1, 0)
		end
	end
	for _, child in roadsFolder:GetChildren() do
		trackRoad(child)
	end
	roadsFolder.ChildAdded:Connect(trackRoad)
	roadsFolder.ChildRemoved:Connect(function(child)
		Grid.remove(grid, child.Name)
	end)

	-- Интерфейс
	local gui = Instance.new("ScreenGui")
	gui.Name = "BuildMenu"
	gui.ResetOnSpawn = false

	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -12)
	bar.Size = UDim2.fromOffset(0, 44)
	bar.AutomaticSize = Enum.AutomaticSize.X
	bar.BackgroundTransparency = 1
	bar.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = bar

	local hintFrame = Instance.new("Frame")
	hintFrame.AnchorPoint = Vector2.new(0.5, 0)
	hintFrame.Position = UDim2.new(0.5, 0, 0, 12)
	hintFrame.Size = UDim2.fromOffset(0, 36)
	hintFrame.AutomaticSize = Enum.AutomaticSize.X
	hintFrame.BackgroundTransparency = 1
	hintFrame.Visible = false
	hintFrame.Parent = gui
	local hintLayout = layout:Clone()
	hintLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	hintLayout.Parent = hintFrame
	local hint = Instance.new("TextLabel")
	hint.AutomaticSize = Enum.AutomaticSize.X
	hint.Size = UDim2.fromOffset(0, 36)
	hint.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	hint.BackgroundTransparency = 0.35
	hint.TextColor3 = Color3.new(1, 1, 1)
	hint.Font = Enum.Font.Gotham
	hint.TextSize = 15
	local hintPadding = Instance.new("UIPadding")
	hintPadding.PaddingLeft = UDim.new(0, 12)
	hintPadding.PaddingRight = UDim.new(0, 12)
	hintPadding.Parent = hint
	local hintCorner = Instance.new("UICorner")
	hintCorner.CornerRadius = UDim.new(0, 8)
	hintCorner.Parent = hint
	hint.Parent = hintFrame
	local cancelButton = makeButton(Text.buildMode.cancel.ru, hintFrame)
	cancelButton.Size = UDim2.fromOffset(0, 36)
	cancelButton.LayoutOrder = 2

	local message = Instance.new("TextLabel")
	message.AnchorPoint = Vector2.new(0.5, 1)
	message.Position = UDim2.new(0.5, 0, 1, -66)
	message.Size = UDim2.fromOffset(0, 30)
	message.AutomaticSize = Enum.AutomaticSize.X
	message.BackgroundColor3 = Color3.fromRGB(120, 30, 30)
	message.BackgroundTransparency = 0.2
	message.TextColor3 = Color3.new(1, 1, 1)
	message.Font = Enum.Font.GothamMedium
	message.TextSize = 15
	message.Visible = false
	local messagePadding = hintPadding:Clone()
	messagePadding.Parent = message
	local messageCorner = hintCorner:Clone()
	messageCorner.Parent = message
	message.Parent = gui

	gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")

	local messageToken = 0
	local function showMessage(text: string)
		messageToken += 1
		local token = messageToken
		message.Text = text
		message.Visible = true
		task.delay(MESSAGE_SECONDS, function()
			if token == messageToken then
				message.Visible = false
			end
		end)
	end

	-- Призрак здания
	local ghost = Instance.new("Part")
	ghost.Name = "BuildGhost"
	ghost.Anchored = true
	ghost.CanCollide = false
	ghost.CanQuery = false
	ghost.CanTouch = false
	ghost.CastShadow = false
	ghost.Material = Enum.Material.SmoothPlastic
	ghost.Transparency = 0.45

	local highlight = Instance.new("Highlight")
	highlight.FillColor = GHOST_BAD
	highlight.OutlineColor = GHOST_BAD
	highlight.FillTransparency = 0.5
	highlight.Parent = gui

	-- Предпросмотр дороги: по детали на клетку, детали переиспользуются.
	local roadGhosts: { Part } = {}
	local function roadGhost(i: number): Part
		local part = roadGhosts[i]
		if part == nil then
			part = ghost:Clone()
			roadGhosts[i] = part
		end
		return part
	end
	local function hideRoadGhosts(from: number)
		for i = from, #roadGhosts do
			roadGhosts[i].Parent = nil
		end
	end

	-- Состояние режима
	local mode: Mode = "none"
	local roadStart: Grid.Cell? = nil -- начало участка дороги
	local roadPendingEnd: Grid.Cell? = nil -- конец, выбранный касанием (ждёт подтверждения)
	local selected: string? = nil
	local rotation = 0
	local touchAnchor: Grid.Cell? = nil -- место, выбранное первым касанием
	local touchTarget: Instance? = nil -- здание или дорога, выбранные первым касанием в режиме сноса
	local buttons: { [string]: TextButton } = {}
	local demolishButton: TextButton
	local roadButton: TextButton

	local function refreshUi()
		for id, button in buttons do
			button.BackgroundColor3 = if mode == "place" and selected == id
				then Color3.fromRGB(60, 120, 80)
				else Color3.fromRGB(35, 38, 42)
		end
		roadButton.BackgroundColor3 = if mode == "road"
			then Color3.fromRGB(60, 120, 80)
			else Color3.fromRGB(35, 38, 42)
		demolishButton.BackgroundColor3 = if mode == "demolish"
			then Color3.fromRGB(140, 50, 45)
			else Color3.fromRGB(35, 38, 42)
		hintFrame.Visible = mode ~= "none"
		if mode == "place" then
			hint.Text = if GroundPick.usingMouse()
				then Text.buildMode.placeHint.ru
				else Text.buildMode.placeHintTouch.ru
		elseif mode == "road" then
			hint.Text = if GroundPick.usingMouse()
				then Text.buildMode.roadHint.ru
				else Text.buildMode.roadHintTouch.ru
		elseif mode == "demolish" then
			hint.Text = Text.buildMode.demolishHint.ru
		end
		ghost.Parent = if mode == "place" then workspace else nil
		if mode ~= "road" then
			hideRoadGhosts(1)
		end
		highlight.Adornee = nil
	end

	local function setMode(newMode: Mode, typeId: string?)
		mode = newMode
		selected = typeId
		touchAnchor = nil
		touchTarget = nil
		roadStart = nil
		roadPendingEnd = nil
		refreshUi()
	end

	local function toggleBuilding(typeId: string)
		if mode == "place" and selected == typeId then
			setMode("none")
		else
			setMode("place", typeId)
		end
	end

	local function toggleRoad()
		setMode(if mode == "road" then "none" else "road")
	end

	local function toggleDemolish()
		setMode(if mode == "demolish" then "none" else "demolish")
	end

	local list = buildingList()
	for index, id in list do
		local button = makeButton(`{index}  {BuildingsConfig[id].name.ru}`, bar)
		button.LayoutOrder = index
		button.Activated:Connect(function()
			toggleBuilding(id)
		end)
		buttons[id] = button
	end
	local roadKey = #list + 1
	roadButton = makeButton(`{roadKey}  {Text.buildMode.road.ru}`, bar)
	roadButton.LayoutOrder = roadKey
	roadButton.Activated:Connect(toggleRoad)
	demolishButton = makeButton(`X  {Text.buildMode.demolish.ru}`, bar)
	demolishButton.LayoutOrder = roadKey + 1
	demolishButton.Activated:Connect(toggleDemolish)
	cancelButton.Activated:Connect(function()
		setMode("none")
	end)
	refreshUi()

	-- Угол здания так, чтобы курсор был примерно в его центре.
	local function anchorFromPoint(point: Vector3?): Grid.Cell?
		if point == nil or selected == nil then
			return nil
		end
		local cell = Grid.toCell(grid, point.X, point.Z)
		if cell == nil then
			return nil
		end
		local def = BuildingsConfig[selected]
		local w, d = Grid.rotatedSize(def.sizeX, def.sizeZ, rotation)
		return { x = cell.x - math.floor((w - 1) / 2), z = cell.z - math.floor((d - 1) / 2) }
	end

	local function updateGhost(anchor: Grid.Cell?)
		if anchor == nil or selected == nil then
			ghost.Transparency = 1
			return
		end
		local def = BuildingsConfig[selected]
		local w, d = Grid.rotatedSize(def.sizeX, def.sizeZ, rotation)
		local cx, cz = Grid.areaCenter(grid, anchor.x, anchor.z, def.sizeX, def.sizeZ, rotation)
		ghost.Size = Vector3.new(w * grid.cellSize - 0.2, def.height, d * grid.cellSize - 0.2)
		ghost.Position = Vector3.new(cx, groundY + def.height / 2, cz)
		local ok = Grid.canPlace(grid, anchor.x, anchor.z, def.sizeX, def.sizeZ, rotation)
		ghost.Color = if ok then GHOST_OK else GHOST_BAD
		ghost.Transparency = 0.45
	end

	local function tryPlace(anchor: Grid.Cell?)
		local typeId = selected
		if anchor == nil or typeId == nil then
			return
		end
		local def = BuildingsConfig[typeId]
		local ok, err = Grid.canPlace(grid, anchor.x, anchor.z, def.sizeX, def.sizeZ, rotation)
		if not ok then
			showMessage(errorText(err))
			return
		end
		local rot = rotation
		task.spawn(function()
			local success, placed, result = pcall(function()
				return placeRemote:InvokeServer(typeId, anchor.x, anchor.z, rot)
			end)
			if not success then
				showMessage(errorText(nil))
			elseif not placed then
				showMessage(errorText(result))
			end
		end)
	end

	-- Здание или участок дороги под точкой экрана.
	local function objectAt(screenX: number, screenY: number, viewport: boolean): Instance?
		local camera = workspace.CurrentCamera
		local ray = if viewport
			then camera:ViewportPointToRay(screenX, screenY)
			else camera:ScreenPointToRay(screenX, screenY)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { buildingsFolder, roadsFolder }
		local hit = workspace:Raycast(ray.Origin, ray.Direction * 2000, params)
		if hit == nil then
			return nil
		end
		if hit.Instance.Parent == roadsFolder then
			return hit.Instance
		end
		local model = hit.Instance:FindFirstAncestorOfClass("Model")
		return if model and model.Parent == buildingsFolder then model else nil
	end

	local function tryRemove(target: Instance?)
		if target == nil then
			return
		end
		local id = target.Name
		task.spawn(function()
			local success, removed, result = pcall(function()
				return demolishRemote:InvokeServer(id)
			end)
			if not success then
				showMessage(errorText(nil))
			elseif not removed then
				showMessage(errorText(result))
			end
		end)
	end

	-- Клетка под точкой на земле или nil.
	local function cellAt(point: Vector3?): Grid.Cell?
		return if point then Grid.toCell(grid, point.X, point.Z) else nil
	end

	-- Можно ли проложить дорогу через клетку: свободна или там уже дорога.
	local function roadCellOk(cell: Grid.Cell): boolean
		local id = Grid.objectAt(grid, cell.x, cell.z)
		return Grid.inBounds(grid, cell.x, cell.z) and (id == nil or string.sub(id, 1, 5) == "road_")
	end

	-- Рисует предпросмотр участка от roadStart (или одной клетки) до cell.
	local function updateRoadPreview(cell: Grid.Cell?)
		if cell == nil then
			hideRoadGhosts(1)
			return
		end
		local start = roadStart or cell
		local path = Roads.linePath(start.x, start.z, cell.x, cell.z)
		local tooLong = #path > RoadsConfig.maxCellsPerCommand
		for i, c in path do
			local part = roadGhost(i)
			local cx, cz = Grid.cellCenter(grid, c.x, c.z)
			part.Size = Vector3.new(grid.cellSize - 0.2, 0.4, grid.cellSize - 0.2)
			part.Position = Vector3.new(cx, groundY + 0.2, cz)
			part.Color = if not tooLong and roadCellOk(c) then GHOST_OK else GHOST_BAD
			part.Transparency = 0.4
			part.Parent = workspace
		end
		hideRoadGhosts(#path + 1)
	end

	-- Клик или подтверждение в режиме дороги: первая точка — начало, вторая — конец участка.
	local function roadClick(cell: Grid.Cell?)
		if cell == nil then
			return
		end
		local start = roadStart
		if start == nil then
			roadStart = cell
			return
		end
		local path = Roads.linePath(start.x, start.z, cell.x, cell.z)
		if #path > RoadsConfig.maxCellsPerCommand then
			showMessage(errorText("too_long"))
			return
		end
		for _, c in path do
			if not roadCellOk(c) then
				showMessage(errorText(if Grid.inBounds(grid, c.x, c.z) then "occupied" else "out_of_bounds"))
				return
			end
		end
		-- Следующий участок продолжается от конца этого.
		roadStart = cell
		task.spawn(function()
			local success, placed, result = pcall(function()
				return roadRemote:InvokeServer(start.x, start.z, cell.x, cell.z)
			end)
			if not success then
				showMessage(errorText(nil))
			elseif not placed then
				showMessage(errorText(result))
			end
		end)
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.Keyboard then
			local index = table.find(NUMBER_KEYS, input.KeyCode)
			if index and list[index] then
				toggleBuilding(list[index])
			elseif index == roadKey then
				toggleRoad()
			elseif input.KeyCode == Enum.KeyCode.R and mode == "place" then
				rotation = (rotation + 1) % 4
				touchAnchor = nil
			elseif input.KeyCode == Enum.KeyCode.X then
				toggleDemolish()
			end
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
			if mode == "place" then
				tryPlace(anchorFromPoint(GroundPick.fromMouse(groundY)))
			elseif mode == "road" then
				roadClick(cellAt(GroundPick.fromMouse(groundY)))
			elseif mode == "demolish" then
				local mouse = UserInputService:GetMouseLocation()
				tryRemove(objectAt(mouse.X, mouse.Y, true))
			end
		end
	end)

	-- Касание без сдвига пальца: первое показывает место, второе туда же — подтверждает.
	UserInputService.TouchTap:Connect(function(positions, processed)
		if processed or #positions == 0 then
			return
		end
		local pos = positions[1]
		if mode == "place" then
			local anchor = anchorFromPoint(GroundPick.fromScreen(pos, groundY))
			if anchor and touchAnchor and anchor.x == touchAnchor.x and anchor.z == touchAnchor.z then
				tryPlace(anchor)
				touchAnchor = nil
			else
				touchAnchor = anchor
			end
		elseif mode == "road" then
			local cell = cellAt(GroundPick.fromScreen(pos, groundY))
			if roadStart == nil then
				roadStart = cell
			elseif cell and roadPendingEnd and cell.x == roadPendingEnd.x and cell.z == roadPendingEnd.z then
				roadClick(cell)
				roadPendingEnd = nil
			else
				roadPendingEnd = cell
			end
		elseif mode == "demolish" then
			local target = objectAt(pos.X, pos.Y, false)
			if target and target == touchTarget then
				tryRemove(target)
				touchTarget = nil
			else
				touchTarget = target
			end
		end
	end)

	RunService.RenderStepped:Connect(function()
		if mode == "place" then
			if GroundPick.usingMouse() then
				updateGhost(anchorFromPoint(GroundPick.fromMouse(groundY)))
			else
				updateGhost(touchAnchor)
			end
		elseif mode == "road" then
			if GroundPick.usingMouse() then
				updateRoadPreview(cellAt(GroundPick.fromMouse(groundY)))
			else
				updateRoadPreview(roadPendingEnd or roadStart)
			end
		elseif mode == "demolish" then
			local target: Instance? = touchTarget
			if GroundPick.usingMouse() then
				local mouse = UserInputService:GetMouseLocation()
				target = objectAt(mouse.X, mouse.Y, true)
			end
			highlight.Adornee = target
		end
	end)
end

return BuildMode
