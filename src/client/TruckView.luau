--!strict
-- Плавное движение грузовиков. Сервер переставляет модели несколько раз в секунду,
-- клиент прячет их и рисует свои копии.
-- Копия показывает положение «из недавнего прошлого» (RENDER_DELAY) и плавно
-- интерполирует между двумя полученными от сервера положениями, поэтому едет ровно.

local RunService = game:GetService("RunService")

local TruckView = {}

-- Задержка показа: чуть больше шага сервера (0,2 с), чтобы всегда было между чем интерполировать.
local RENDER_DELAY = 0.3
local MAX_SNAPSHOTS = 8
local SNAP_DISTANCE = 12 -- скачок дальше этого (телепорт) не интерполируем

type Snapshot = { time: number, cframe: CFrame }
type Visual = {
	source: Model,
	sourceRoot: BasePart,
	model: Model,
	root: BasePart,
	cargo: BasePart?,
	snapshots: { Snapshot },
}

-- Прячем серверную модель только у себя: сервер не меняет прозрачность после создания.
local function hidePart(d: Instance)
	if d:IsA("BasePart") then
		d.Transparency = 1
	end
end

local function record(visual: Visual)
	local snapshots = visual.snapshots
	table.insert(snapshots, { time = os.clock(), cframe = visual.sourceRoot.CFrame })
	if #snapshots > MAX_SNAPSHOTS then
		table.remove(snapshots, 1)
	end
end

-- Положение копии на момент renderTime по снимкам сервера.
local function sample(snapshots: { Snapshot }, renderTime: number): CFrame
	local last = snapshots[#snapshots]
	if renderTime >= last.time then
		return last.cframe
	end
	for i = #snapshots - 1, 1, -1 do
		local a = snapshots[i]
		if a.time <= renderTime then
			local b = snapshots[i + 1]
			if (b.cframe.Position - a.cframe.Position).Magnitude > SNAP_DISTANCE then
				return b.cframe
			end
			local t = (renderTime - a.time) / math.max(b.time - a.time, 1e-3)
			return a.cframe:Lerp(b.cframe, t)
		end
	end
	return snapshots[1].cframe
end

function TruckView.start()
	local trucksFolder = workspace:WaitForChild("Region"):WaitForChild("Trucks")
	local visualsFolder = Instance.new("Folder")
	visualsFolder.Name = "TruckVisuals"
	visualsFolder.Parent = workspace

	local visuals: { [Model]: Visual } = {}

	local function track(child: Instance)
		if not child:IsA("Model") or visuals[child] then
			return
		end
		local sourceRoot = child:WaitForChild("Root", 5) :: BasePart?
		if sourceRoot == nil or child.Parent ~= trucksFolder then
			return
		end
		local copy = child:Clone()
		local root = copy:FindFirstChild("Root") :: BasePart
		for _, d in copy:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
			end
		end
		copy.Parent = visualsFolder
		for _, d in child:GetDescendants() do
			hidePart(d)
		end
		child.DescendantAdded:Connect(hidePart)

		local visual: Visual = {
			source = child,
			sourceRoot = sourceRoot,
			model = copy,
			root = root,
			cargo = copy:FindFirstChild("Cargo") :: BasePart?,
			snapshots = {},
		}
		record(visual)
		sourceRoot:GetPropertyChangedSignal("CFrame"):Connect(function()
			record(visual)
		end)
		visuals[child] = visual
	end

	for _, child in trucksFolder:GetChildren() do
		task.spawn(track, child)
	end
	trucksFolder.ChildAdded:Connect(track)
	trucksFolder.ChildRemoved:Connect(function(child)
		local visual = visuals[child :: Model]
		if visual then
			visual.model:Destroy()
			visuals[child :: Model] = nil
		end
	end)

	RunService.RenderStepped:Connect(function()
		local renderTime = os.clock() - RENDER_DELAY
		for _, visual in visuals do
			local cf = sample(visual.snapshots, renderTime)
			visual.root.CFrame = cf
			-- Детали без сварки: ставим каждую по смещению от корпуса (атрибут Offset).
			for _, child in visual.model:GetChildren() do
				local offset = child:GetAttribute("Offset")
				if child:IsA("BasePart") and typeof(offset) == "CFrame" then
					child.CFrame = cf * offset
				end
			end
			local cargo = visual.cargo
			if cargo then
				local amount = visual.source:GetAttribute("Cargo")
				cargo.Transparency = if type(amount) == "number" and amount > 0 then 0 else 1
			end
		end
	end)
end

return TruckView
