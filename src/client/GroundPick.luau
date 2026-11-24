--!strict
-- Точка на земле под курсором или пальцем: пересечение луча камеры с плоскостью земли.
-- Не зависит от физики, поэтому работает даже там, где нет деталей.

local UserInputService = game:GetService("UserInputService")

local GroundPick = {}

local function intersect(ray: Ray, groundY: number): Vector3?
	if math.abs(ray.Direction.Y) < 1e-6 then
		return nil
	end
	local t = (groundY - ray.Origin.Y) / ray.Direction.Y
	if t <= 0 then
		return nil
	end
	return ray.Origin + ray.Direction * t
end

-- Под курсором мыши. GetMouseLocation учитывает верхнюю панель, поэтому ViewportPointToRay.
function GroundPick.fromMouse(groundY: number): Vector3?
	local mouse = UserInputService:GetMouseLocation()
	return intersect(workspace.CurrentCamera:ViewportPointToRay(mouse.X, mouse.Y), groundY)
end

-- Под точкой экрана из InputObject.Position (без верхней панели), поэтому ScreenPointToRay.
function GroundPick.fromScreen(position: Vector3 | Vector2, groundY: number): Vector3?
	return intersect(workspace.CurrentCamera:ScreenPointToRay(position.X, position.Y), groundY)
end

-- Используется ли сейчас мышь (а не палец).
function GroundPick.usingMouse(): boolean
	return UserInputService.MouseEnabled and UserInputService:GetLastInputType() ~= Enum.UserInputType.Touch
end

return GroundPick
