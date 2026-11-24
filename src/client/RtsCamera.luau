--!strict
-- RTS-камера сверху: двигается над регионом, вращается вокруг точки фокуса, приближается.
-- ПК: WASD или стрелки — сдвиг, Q/E — поворот, правая кнопка мыши — вращение, колесо — масштаб.
-- Телефон и планшет: один палец — сдвиг, два пальца — масштаб и поворот.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local RtsCamera = {}

export type Config = {
	startZoom: number,
	minZoom: number,
	maxZoom: number,
	zoomStep: number,
	startPitch: number,
	minPitch: number,
	maxPitch: number,
	startYaw: number,
	panSpeed: number,
	keyRotateSpeed: number,
	mouseRotateSpeed: number,
	touchPanFactor: number,
	smoothing: number,
}

-- Границы, за которые не уходит точка фокуса (мировые X и Z).
export type Bounds = { minX: number, maxX: number, minZ: number, maxZ: number, groundY: number }

local PAN_KEYS = {
	forward = { Enum.KeyCode.W, Enum.KeyCode.Up },
	back = { Enum.KeyCode.S, Enum.KeyCode.Down },
	left = { Enum.KeyCode.A, Enum.KeyCode.Left },
	right = { Enum.KeyCode.D, Enum.KeyCode.Right },
	rotateLeft = { Enum.KeyCode.Q },
	rotateRight = { Enum.KeyCode.E },
}

local function anyDown(keys: { Enum.KeyCode }): boolean
	for _, k in keys do
		if UserInputService:IsKeyDown(k) then
			return true
		end
	end
	return false
end

-- Направления «вперёд» и «вправо» по земле при данном повороте камеры.
local function groundAxes(yawDeg: number): (Vector3, Vector3)
	local yaw = math.rad(yawDeg)
	local forward = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
	local right = forward:Cross(Vector3.yAxis)
	return forward, right
end

function RtsCamera.start(config: Config, bounds: Bounds)
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable

	-- Целевые значения меняет ввод, текущие плавно их догоняют.
	local target = {
		focus = Vector3.new((bounds.minX + bounds.maxX) / 2, bounds.groundY, (bounds.minZ + bounds.maxZ) / 2),
		yaw = config.startYaw,
		pitch = config.startPitch,
		zoom = config.startZoom,
	}
	local current = table.clone(target)

	local function clampTarget()
		target.focus = Vector3.new(
			math.clamp(target.focus.X, bounds.minX, bounds.maxX),
			bounds.groundY,
			math.clamp(target.focus.Z, bounds.minZ, bounds.maxZ)
		)
		target.pitch = math.clamp(target.pitch, config.minPitch, config.maxPitch)
		target.zoom = math.clamp(target.zoom, config.minZoom, config.maxZoom)
	end

	-- Сдвиг фокуса в пикселях экрана (для пальца): переводим в студы по текущему масштабу.
	local function panByPixels(dx: number, dy: number)
		local forward, right = groundAxes(target.yaw)
		local studsPerPixel = target.zoom * 0.002 * config.touchPanFactor
		target.focus += (-right * dx + forward * dy) * studsPerPixel
		clampTarget()
	end

	local rotating = false

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			rotating = true
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			rotating = false
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
	end)

	UserInputService.InputChanged:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.MouseMovement and rotating then
			target.yaw -= input.Delta.X * config.mouseRotateSpeed
			target.pitch += input.Delta.Y * config.mouseRotateSpeed
			clampTarget()
		elseif input.UserInputType == Enum.UserInputType.MouseWheel and not processed then
			local steps = input.Position.Z
			target.zoom *= (1 - config.zoomStep) ^ steps
			clampTarget()
		end
	end)

	-- Сенсорный ввод: Roblox сам распознаёт жесты.
	local lastPan = Vector2.zero
	UserInputService.TouchPan:Connect(function(touches, total, _velocity, state, processed)
		if processed or #touches ~= 1 then
			lastPan = total
			return
		end
		if state == Enum.UserInputState.Begin then
			lastPan = Vector2.zero
		end
		local delta = total - lastPan
		lastPan = total
		panByPixels(delta.X, delta.Y)
	end)

	local pinchStartZoom = target.zoom
	UserInputService.TouchPinch:Connect(function(_touches, scale, _velocity, state, processed)
		if processed then
			return
		end
		if state == Enum.UserInputState.Begin then
			pinchStartZoom = target.zoom
		end
		if scale > 0 then
			target.zoom = pinchStartZoom / scale
			clampTarget()
		end
	end)

	local rotateStartYaw = target.yaw
	UserInputService.TouchRotate:Connect(function(_touches, rotation, _velocity, state, processed)
		if processed then
			return
		end
		if state == Enum.UserInputState.Begin then
			rotateStartYaw = target.yaw
		end
		target.yaw = rotateStartYaw - rotation
	end)

	RunService:BindToRenderStep("RtsCamera", Enum.RenderPriority.Camera.Value, function(dt)
		camera.CameraType = Enum.CameraType.Scriptable

		-- Клавиши не работают, пока игрок печатает в поле ввода (например, в чате).
		if UserInputService:GetFocusedTextBox() == nil then
			local forward, right = groundAxes(target.yaw)
			local move = Vector3.zero
			if anyDown(PAN_KEYS.forward) then
				move += forward
			end
			if anyDown(PAN_KEYS.back) then
				move -= forward
			end
			if anyDown(PAN_KEYS.right) then
				move += right
			end
			if anyDown(PAN_KEYS.left) then
				move -= right
			end
			if move.Magnitude > 0 then
				target.focus += move.Unit * config.panSpeed * target.zoom * dt
			end
			if anyDown(PAN_KEYS.rotateLeft) then
				target.yaw += config.keyRotateSpeed * dt
			end
			if anyDown(PAN_KEYS.rotateRight) then
				target.yaw -= config.keyRotateSpeed * dt
			end
			clampTarget()
		end

		local alpha = 1 - math.exp(-config.smoothing * dt)
		current.focus = current.focus:Lerp(target.focus, alpha)
		current.yaw += (target.yaw - current.yaw) * alpha
		current.pitch += (target.pitch - current.pitch) * alpha
		current.zoom += (target.zoom - current.zoom) * alpha

		local yaw, pitch = math.rad(current.yaw), math.rad(current.pitch)
		local offset = Vector3.new(
			math.sin(yaw) * math.cos(pitch),
			math.sin(pitch),
			math.cos(yaw) * math.cos(pitch)
		) * current.zoom
		camera.CFrame = CFrame.lookAt(current.focus + offset, current.focus)
	end)
end

return RtsCamera
