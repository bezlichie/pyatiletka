--!strict
-- Внешний вид грузовика. Модель строит только клиент (client/TruckView):
-- сервер хранит положение грузовика в атрибуте, а не двигает детали (шаг 7: так дешевле).

local TruckModel = {}

TruckModel.size = Vector3.new(1.8, 1.6, 3.2) -- корпус; по его высоте сервер ставит грузовик на дорогу

local function makePart(name: string, size: Vector3, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false -- не мешает кликам по зданиям и дорогам
	part.CanTouch = false
	return part
end

-- Модель: корпус Root и детали на нём. Детали без сварки: каждую ставит
-- TruckModel.place по смещению от корпуса (атрибут Offset).
function TruckModel.build(name: string): (Model, BasePart, BasePart)
	local model = Instance.new("Model")
	model.Name = name
	local root = makePart("Root", TruckModel.size, Color3.fromRGB(70, 110, 160))
	root.Parent = model
	local cab = makePart("Cab", Vector3.new(1.7, 0.9, 1.1), Color3.fromRGB(220, 220, 210))
	cab:SetAttribute("Offset", CFrame.new(0, 1.2, -1))
	cab.Parent = model
	local cargo = makePart("Cargo", Vector3.new(1.6, 0.8, 1.8), Color3.fromRGB(150, 105, 60))
	cargo:SetAttribute("Offset", CFrame.new(0, 1.2, 0.6))
	cargo.Parent = model
	model.PrimaryPart = root
	return model, root, cargo
end

-- Поставить модель: корпус в cf, детали по смещениям.
function TruckModel.place(model: Model, root: BasePart, cf: CFrame)
	root.CFrame = cf
	for _, child in model:GetChildren() do
		local offset = child:GetAttribute("Offset")
		if child ~= root and child:IsA("BasePart") and typeof(offset) == "CFrame" then
			child.CFrame = cf * offset
		end
	end
end

return TruckModel
