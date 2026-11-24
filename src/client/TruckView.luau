--!strict
-- Плавное движение грузовиков. Сервер переставляет модели несколько раз в секунду,
-- клиент прячет их и рисует свои копии, которые мягко догоняют серверное положение.

local RunService = game:GetService("RunService")

local TruckView = {}

local SMOOTHING = 12 -- чем больше, тем быстрее копия догоняет сервер
local SNAP_DISTANCE = 12 -- если отстали сильнее (телепорт), прыгаем сразу

type Visual = { source: Model, sourceRoot: BasePart, model: Model, root: BasePart, cargo: BasePart? }

local function hide(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = 1
		end
	end
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
				d.LocalTransparencyModifier = 0
			end
		end
		copy.Parent = visualsFolder
		hide(child)
		child.DescendantAdded:Connect(function(d)
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = 1
			end
		end)
		visuals[child] = {
			source = child,
			sourceRoot = sourceRoot,
			model = copy,
			root = root,
			cargo = copy:FindFirstChild("Cargo") :: BasePart?,
		}
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

	RunService.RenderStepped:Connect(function(dt)
		local alpha = 1 - math.exp(-SMOOTHING * dt)
		for _, visual in visuals do
			local target = visual.sourceRoot.CFrame
			local current = visual.root.CFrame
			if (target.Position - current.Position).Magnitude > SNAP_DISTANCE then
				visual.root.CFrame = target
			else
				visual.root.CFrame = current:Lerp(target, alpha)
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
