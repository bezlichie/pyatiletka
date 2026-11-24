--!strict
-- Плавное движение грузовиков. Сервер несколько раз в секунду пишет положение грузовика
-- в атрибут CFrame его (пустой) модели, а клиент рисует свою модель (Shared/Visual/TruckModel).
-- Копия показывает положение «из недавнего прошлого» (RENDER_DELAY) и плавно
-- интерполирует между двумя полученными от сервера положениями, поэтому едет ровно.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local TruckModel =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Visual"):WaitForChild("TruckModel"))

local TruckView = {}

-- Задержка показа: чуть больше шага сервера (0,2 с), чтобы всегда было между чем интерполировать.
local RENDER_DELAY = 0.3
local MAX_SNAPSHOTS = 8
local SNAP_DISTANCE = 12 -- скачок дальше этого (телепорт) не интерполируем

type Snapshot = { time: number, cframe: CFrame }
type Visual = {
	source: Model,
	model: Model,
	root: BasePart,
	cargo: BasePart?,
	snapshots: { Snapshot },
}

local function record(visual: Visual)
	local cf = visual.source:GetAttribute("CFrame")
	if typeof(cf) ~= "CFrame" then
		return
	end
	local snapshots = visual.snapshots
	table.insert(snapshots, { time = os.clock(), cframe = cf })
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
		local model, root, cargo = TruckModel.build(child.Name)
		local visual: Visual = {
			source = child,
			model = model,
			root = root,
			cargo = cargo,
			snapshots = {},
		}
		record(visual)
		child:GetAttributeChangedSignal("CFrame"):Connect(function()
			record(visual)
		end)
		visuals[child] = visual
	end

	for _, child in trucksFolder:GetChildren() do
		track(child)
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
			if #visual.snapshots == 0 then
				continue -- положение ещё не пришло: модель не показываем
			end
			if visual.model.Parent ~= visualsFolder then
				visual.model.Parent = visualsFolder
			end
			TruckModel.place(visual.model, visual.root, sample(visual.snapshots, renderTime))
			local cargo = visual.cargo
			if cargo then
				local amount = visual.source:GetAttribute("Cargo")
				cargo.Transparency = if type(amount) == "number" and amount > 0 then 0 else 1
			end
		end
	end)
end

return TruckView
