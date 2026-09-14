--[[
	BreathBar.luau
	--------------
	UI Horror Safe Zone "Breath Meter" — Silencio Carnival Horror.
	Tema: The Growing Carnival Balloon (Balon Karnaval Membesar) V3.

	Fitur:
	  1. Balon membesar seiring tekanan napas naik:
	     - Ukuran balon tumbuh dari kecil (44x54 px) saat napas penuh,
	       menjadi besar (104x126 px) saat hampir habis.
	     - Aura merah berdenyut makin intens seiring balon mengembang.
	  2. Pop-out dramatis: Saat napas habis, balon mengembang sekejap
	     lalu MELETUS (shreds terpental + shockwave + flash).
	  3. Tidak ada gauge bar di bawah — visual murni balon + teks.
	  4. Vignette horror full screen tetap aktif.
	  5. Responsive: UISizeConstraint untuk semua ukuran layar.
--]]

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService   = game:GetService("RunService")

local BreathBar = {}
BreathBar.__index = BreathBar

local GUI_NAME = "SafeZoneBreath"

local COLOR_BALLOON_LIGHT = Color3.fromRGB(235, 45, 60)
local COLOR_BALLOON_DARK  = Color3.fromRGB(70, 6, 12)
local COLOR_TEXT_BONE     = Color3.fromRGB(235, 225, 220)
local COLOR_TEXT_WARN     = Color3.fromRGB(225, 110, 40)
local COLOR_TEXT_PANIC    = Color3.fromRGB(255, 45, 60)

local TEXT = {
	OCCUPIED = "HOLDING BREATH",
	BREACHED = "POP!",
	COOLDOWN = "STALL IS COMPROMISED",
	READY    = "HIDDEN IN SHADOWS",
	FULL     = "STALL IS OCCUPIED",
}

local STRAIN = {
	warn  = "LUNGS BURNING...",
	panic = "CAN'T HOLD ON!",
}

local function new(class: string, props: { [string]: any }): any
	local inst = Instance.new(class)
	local parent = props.Parent
	props.Parent = nil
	for key, value in props do
		(inst :: any)[key] = value
	end
	inst.Parent = parent
	return inst
end

function BreathBar.new()
	local self = setmetatable({}, BreathBar)
	local player = Players.LocalPlayer
	local playerGui = player and (player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 5))
	if not playerGui then
		playerGui = Instance.new("Folder")
	end

	local screen = playerGui:FindFirstChild(GUI_NAME) or new("ScreenGui", {
		Name = GUI_NAME,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 15,
		Parent = playerGui,
	})
	pcall(function()
		screen.ScreenInsets = Enum.ScreenInsets.None
		screen.ClipToDeviceSafeArea = false
	end)
	screen:ClearAllChildren()

	-- 1. Horror Vignette Full Screen (Edge-to-Edge)
	local vignetteContainer = new("Frame", {
		Name = "HorrorVignette",
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Active = false,
		Parent = screen,
	})

	local topVig = new("Frame", {
		Size = UDim2.new(1, 0, 0.35, 0),
		Position = UDim2.new(0, 0, 0, 0),
		BackgroundColor3 = Color3.fromRGB(25, 0, 4),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = vignetteContainer,
	})
	new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.15),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = topVig,
	})

	local bottomVig = new("Frame", {
		Size = UDim2.new(1, 0, 0.45, 0),
		Position = UDim2.new(0, 0, 0.55, 0),
		BackgroundColor3 = Color3.fromRGB(30, 0, 5),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = vignetteContainer,
	})
	new("UIGradient", {
		Rotation = -90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = bottomVig,
	})

	local leftVig = new("Frame", {
		Size = UDim2.new(0.35, 0, 1, 0),
		Position = UDim2.new(0, 0, 0, 0),
		BackgroundColor3 = Color3.fromRGB(20, 0, 3),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = vignetteContainer,
	})
	new("UIGradient", {
		Rotation = 0,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = leftVig,
	})

	local rightVig = new("Frame", {
		Size = UDim2.new(0.35, 0, 1, 0),
		Position = UDim2.new(0.65, 0, 0, 0),
		BackgroundColor3 = Color3.fromRGB(20, 0, 3),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = vignetteContainer,
	})
	new("UIGradient", {
		Rotation = 180,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = rightVig,
	})

	-- 2. HUD Container (Lebih besar untuk balon yang membesar)
	local holder = new("Frame", {
		Name = "Holder",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -50),
		Size = UDim2.new(0.4, 0, 0, 190),
		BackgroundTransparency = 1,
		Active = false,
		Visible = false,
		Parent = screen,
	})

	new("UISizeConstraint", {
		MinSize = Vector2.new(280, 170),
		MaxSize = Vector2.new(520, 210),
		Parent = holder,
	})

	-- 3. Wadah Balon Karnaval
	local balloonWrap = new("Frame", {
		Name = "BalloonWrap",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.new(0, 140, 0, 145),
		BackgroundTransparency = 1,
		Active = false,
		Parent = holder,
	})

	-- Aura Cahaya Merah di Belakang Balon
	local balloonAura = new("Frame", {
		Name = "Aura",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.42, 0),
		Size = UDim2.new(0, 90, 0, 108),
		BackgroundColor3 = Color3.fromRGB(180, 20, 35),
		BackgroundTransparency = 0.78,
		BorderSizePixel = 0,
		Active = false,
		Parent = balloonWrap,
	})
	new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = balloonAura })

	-- Badan Balon (Oval Karnaval)
	local balloonBody = new("Frame", {
		Name = "Body",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.42, 0),
		Size = UDim2.new(0, 44, 0, 54),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Active = false,
		Parent = balloonWrap,
	})
	new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = balloonBody })

	local balloonGrad = new("UIGradient", {
		Color = ColorSequence.new(COLOR_BALLOON_LIGHT, COLOR_BALLOON_DARK),
		Rotation = 72,
		Parent = balloonBody,
	})

	new("UIStroke", {
		Color = Color3.fromRGB(110, 12, 22),
		Thickness = 1.5,
		Transparency = 0.25,
		Parent = balloonBody,
	})

	-- Kilau Pantulan Cahaya (Specular Gloss Highlight)
	local shine = new("Frame", {
		Name = "Shine",
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.new(0.18, 0, 0.15, 0),
		Size = UDim2.new(0, 16, 0, 10),
		BackgroundColor3 = Color3.fromRGB(255, 235, 240),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Rotation = -28,
		Parent = balloonBody,
	})
	new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = shine })

	-- Simpul Bawah Balon
	local knot = new("Frame", {
		Name = "Knot",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, -3),
		Size = UDim2.new(0, 11, 0, 9),
		BackgroundColor3 = COLOR_BALLOON_DARK,
		BorderSizePixel = 0,
		Rotation = 45,
		Parent = balloonBody,
	})
	new("UICorner", { CornerRadius = UDim.new(0, 2), Parent = knot })

	-- Tali Benang Balon
	local stringLine = new("Frame", {
		Name = "String",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 5),
		Size = UDim2.new(0, 1.5, 0, 22),
		BackgroundColor3 = Color3.fromRGB(140, 115, 110),
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Parent = balloonBody,
	})

	-- 8 Serpihan Karet untuk Efek Meletus (POP!)
	local shreds = {}
	local shredContainer = new("Frame", {
		Name = "ShredContainer",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.42, 0),
		Size = UDim2.new(0, 100, 0, 100),
		BackgroundTransparency = 1,
		Active = false,
		Parent = balloonWrap,
	})

	for i = 1, 8 do
		local shred = new("Frame", {
			Name = "Shred" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			Size = UDim2.new(0, 14, 0, 8),
			BackgroundColor3 = COLOR_BALLOON_LIGHT,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Rotation = i * 45,
			Parent = shredContainer,
		})
		new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = shred })
		table.insert(shreds, shred)
	end

	-- Shockwave Ring Merah saat Meletus
	local popRing = new("Frame", {
		Name = "PopRing",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.42, 0),
		Size = UDim2.new(0, 12, 0, 12),
		BackgroundTransparency = 1,
		Parent = balloonWrap,
	})
	new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = popRing })
	local popStroke = new("UIStroke", {
		Color = COLOR_BALLOON_LIGHT,
		Thickness = 2.5,
		Transparency = 1,
		Parent = popRing,
	})

	-- 4. Label Status Utama (Di bawah balon)
	local label = new("TextLabel", {
		Name = "StatusLabel",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -4),
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		Font = Enum.Font.SpecialElite,
		TextSize = 17,
		TextColor3 = COLOR_TEXT_BONE,
		TextStrokeColor3 = Color3.new(0, 0, 0),
		TextStrokeTransparency = 0,
		Text = "HOLDING BREATH",
		Active = false,
		Parent = holder,
	})

	self.screen = screen
	self.vignetteContainer = vignetteContainer
	self.vigFrames = { topVig, bottomVig, leftVig, rightVig }
	self.holder = holder
	self.balloonWrap = balloonWrap
	self.balloonAura = balloonAura
	self.balloonBody = balloonBody
	self.balloonGrad = balloonGrad
	self.knot = knot
	self.stringLine = stringLine
	self.shreds = shreds
	self.popRing = popRing
	self.popStroke = popStroke
	self.label = label
	self.autoHideToken = 0
	self.pulseTween = nil
	self.jitterConn = nil
	self.popped = false

	return self
end

function BreathBar:_setVignetteAlpha(targetTransparency: number, duration: number)
	for _, f in self.vigFrames do
		TweenService:Create(f, TweenInfo.new(duration or 0.4), {
			BackgroundTransparency = targetTransparency
		}):Play()
	end
end

function BreathBar:_startVignettePulse(speed: number, maxAlpha: number)
	if self.pulseTween then
		self.pulseTween:Cancel()
		self.pulseTween = nil
	end

	for _, f in self.vigFrames do
		self.pulseTween = TweenService:Create(
			f,
			TweenInfo.new(speed, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ BackgroundTransparency = maxAlpha }
		)
		self.pulseTween:Play()
	end
end

function BreathBar:_stopVignette()
	if self.pulseTween then
		self.pulseTween:Cancel()
		self.pulseTween = nil
	end
	self:_setVignetteAlpha(1, 0.35)
end

function BreathBar:_setJitter(enabled: boolean)
	if enabled and not self.jitterConn then
		self.jitterConn = RunService.RenderStepped:Connect(function()
			if self.balloonBody and self.balloonBody.Parent then
				local ox = (math.random() - 0.5) * 6
				local oy = (math.random() - 0.5) * 5
				self.balloonBody.Position = UDim2.new(0.5, ox, 0.42, oy)
			end
			if self.balloonAura and self.balloonAura.Parent then
				local ox = (math.random() - 0.5) * 7
				local oy = (math.random() - 0.5) * 6
				self.balloonAura.Position = UDim2.new(0.5, ox, 0.42, oy)
			end
			if self.label and self.label.Parent then
				local ox = (math.random() - 0.5) * 3
				self.label.Position = UDim2.new(0.5, ox, 1, -4)
			end
		end)
	elseif not enabled and self.jitterConn then
		self.jitterConn:Disconnect()
		self.jitterConn = nil
		if self.balloonBody then
			self.balloonBody.Position = UDim2.new(0.5, 0, 0.42, 0)
		end
		if self.balloonAura then
			self.balloonAura.Position = UDim2.new(0.5, 0, 0.42, 0)
		end
		if self.label then
			self.label.Position = UDim2.new(0.5, 0, 1, -4)
		end
	end
end

--- Efek Meletus (POP!) saat napas habis / pemain diusir paksa
function BreathBar:popBalloon()
	if self.popped then
		return
	end
	self.popped = true
	self:_setJitter(false)

	-- 1. Balon mengembang sekejap (pop-out) lalu hilang
	if self.balloonBody then
		-- Quick pop-out scale up (1.15x) then hide
		local currentW = self.balloonBody.Size.X.Offset
		local currentH = self.balloonBody.Size.Y.Offset
		TweenService:Create(self.balloonBody, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.new(0, math.floor(currentW * 1.15), 0, math.floor(currentH * 1.15))
		}):Play()
		task.delay(0.08, function()
			if self.balloonBody then
				self.balloonBody.Visible = false
			end
		end)
	end
	if self.balloonAura then
		self.balloonAura.Visible = false
	end

	if self.label then
		self.label.Text = "POP!"
		self.label.TextSize = 24
		self.label.TextColor3 = COLOR_TEXT_PANIC
	end

	-- 2. 8 Serpihan Karet Terpental Keluar Melingkar
	local angles = { 0, 45, 90, 135, 180, 225, 270, 315 }
	for idx, shred in ipairs(self.shreds) do
		local rad = math.rad(angles[idx] or (idx * 45))
		local dist = math.random(40, 60)
		local tx = math.cos(rad) * dist
		local ty = math.sin(rad) * dist

		shred.Position = UDim2.new(0.5, 0, 0.5, 0)
		shred.BackgroundTransparency = 0
		shred.Visible = true

		TweenService:Create(shred, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, tx, 0.5, ty),
			BackgroundTransparency = 1,
			Rotation = shred.Rotation + math.random(120, 240)
		}):Play()
	end

	-- 3. Shockwave Ring Merah 110px
	if self.popRing and self.popStroke then
		self.popRing.Size = UDim2.new(0, 12, 0, 12)
		self.popStroke.Transparency = 0
		TweenService:Create(self.popRing, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.new(0, 110, 0, 110)
		}):Play()
		TweenService:Create(self.popStroke, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 1
		}):Play()
	end

	-- Flash Vignette Darah
	self:_setVignetteAlpha(0.1, 0.08)
	task.delay(0.1, function()
		self:_setVignetteAlpha(1, 0.4)
	end)
end

function BreathBar:update(payload: { [string]: any }?)
	if not self.holder or not self.holder.Parent then
		return
	end

	-- State NONE / nil -> Hancurkan tampilan seketika (Anti-Nyangkut)
	if not payload or payload.state == nil or payload.state == "NONE" then
		self.autoHideToken += 1
		self:_stopVignette()
		self:_setJitter(false)
		TweenService:Create(self.holder, TweenInfo.new(0.2), { Position = UDim2.new(0.5, 0, 1, -30) }):Play()
		task.delay(0.2, function()
			if self.holder then
				self.holder.Visible = false
				self.holder.Position = UDim2.new(0.5, 0, 1, -50)
				self.popped = false
				if self.balloonBody then
					self.balloonBody.Visible = true
				end
				if self.balloonAura then
					self.balloonAura.Visible = true
				end
				if self.label then
					self.label.TextSize = 17
				end
			end
		end)
		return
	end

	local state = tostring(payload.state)
	local fraction = math.clamp(tonumber(payload.fraction) or 0, 0, 1)

	local labelText = TEXT[state] or state
	local labelColor = COLOR_TEXT_BONE

	if state == "OCCUPIED" then
		if fraction <= 0 then
			self:popBalloon()
			return
		elseif fraction <= 0.25 then
			labelText = STRAIN.panic
			labelColor = COLOR_TEXT_PANIC
			self:_startVignettePulse(0.35, 0.2)
			self:_setJitter(true)
		elseif fraction <= 0.55 then
			labelText = STRAIN.warn
			labelColor = COLOR_TEXT_WARN
			self:_startVignettePulse(0.8, 0.45)
			self:_setJitter(false)
		else
			labelText = TEXT.OCCUPIED
			labelColor = COLOR_TEXT_BONE
			self:_setVignetteAlpha(0.65, 0.5)
			self:_setJitter(false)
		end

		-- Reset popped state jika pemain baru masuk
		if self.popped and fraction > 0.1 then
			self.popped = false
			if self.balloonBody then
				self.balloonBody.Visible = true
			end
			if self.balloonAura then
				self.balloonAura.Visible = true
			end
			if self.label then
				self.label.TextSize = 17
			end
		end
	elseif state == "BREACHED" then
		self:popBalloon()
		labelColor = COLOR_TEXT_PANIC

		self.autoHideToken += 1
		local currentToken = self.autoHideToken
		task.delay(1.5, function()
			if self.autoHideToken == currentToken and self.holder then
				self:update(nil)
			end
		end)
		return
	else
		labelColor = COLOR_TEXT_PANIC
		self:_stopVignette()
		self:_setJitter(false)

		self.autoHideToken += 1
		local currentToken = self.autoHideToken
		task.delay(1.6, function()
			if self.autoHideToken == currentToken and self.holder then
				self:update(nil)
			end
		end)
	end

	self.label.Text = labelText
	self.label.TextColor3 = labelColor

	-- Ukuran Balon MEMBESAR seiring napas habis (tekanan naik):
	-- Dari 44x54 px (saat napas penuh, fraction=1.0)
	-- Menjadi 104x126 px (saat hampir habis, fraction≈0.0)
	if not self.popped and self.balloonBody then
		local tension = 1 - fraction -- 0.0 (full) -> 1.0 (empty)
		local curW = math.floor(44 + tension * 60)
		local curH = math.floor(54 + tension * 72)
		TweenService:Create(
			self.balloonBody,
			TweenInfo.new(0.12, Enum.EasingStyle.Linear),
			{ Size = UDim2.new(0, curW, 0, curH) }
		):Play()

		if self.balloonAura then
			local auraW = curW + 16
			local auraH = curH + 16
			TweenService:Create(
				self.balloonAura,
				TweenInfo.new(0.12, Enum.EasingStyle.Linear),
				{ Size = UDim2.new(0, auraW, 0, auraH) }
			):Play()
		end
	end

	self.holder.Visible = true
end

function BreathBar:destroy()
	self:_stopVignette()
	self:_setJitter(false)
	if self.screen then
		self.screen:Destroy()
	end
	self.screen = nil
	self.holder = nil
	self.balloonWrap = nil
	self.balloonAura = nil
	self.balloonBody = nil
	self.shreds = nil
	self.popRing = nil
	self.popStroke = nil
	self.label = nil
	self.vignetteContainer = nil
	self.vigFrames = nil
end

return BreathBar
