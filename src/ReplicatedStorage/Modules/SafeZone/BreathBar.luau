--[[
	BreathBar.luau
	--------------
	UI bar napas Safe Zone. MODUL TERPISAH dan bisa ditukar.

	Kenapa modul, bukan langsung di LocalScript: UI ini sementara (buatan
	kita). Kalau tim mengirim desain sendiri, yang perlu diganti cuma
	modul ini — LocalScript pemanggil dan seluruh sistem server tidak
	disentuh.

	KONTRAK (harus dipenuhi modul pengganti):
	  BreathBar.new()          -> objek bar
	  bar:update(payload)      -> payload dari RemoteEvent "SafeZoneState"
	  bar:destroy()            -> lepas semua koneksi & instance

	Bentuk payload dari server:
	  { state, breath, max, fraction, count, capacity, eternal }
	  state "NONE" = pemain sedang tidak berada di bilik mana pun.

	Murni presentasi — nol logika game. Server tetap satu-satunya pemilik
	kebenaran; bar ini hanya menggambar apa yang dikirim.
--]]

local BreathBar = {}
BreathBar.__index = BreathBar

-- Tampilan
local BAR_WIDTH   = 0.28   -- lebar bar, skala layar
local BAR_HEIGHT  = 14     -- tinggi bar, piksel
local BOTTOM_PAD  = 90     -- jarak dari bawah layar, piksel
local FADE_TIME   = 0.25   -- lama muncul/hilang, detik

-- Warna per keadaan napas
local COLOR_SAFE  = Color3.fromRGB(120, 220, 150)  -- napas banyak
local COLOR_WARN  = Color3.fromRGB(235, 200,  90)  -- mulai habis
local COLOR_PANIC = Color3.fromRGB(225,  75,  70)  -- kritis
local WARN_AT     = 0.5
local PANIC_AT    = 0.25

local LABEL = {
	OCCUPIED = "Menahan napas",
	BREACHED = "Napas habis!",
	COOLDOWN = "Bilik tidak bisa dipakai",
	READY    = "Bilik siap",
	FULL     = "Bilik sudah dipakai",
}

---------------------------------------------------------------------

local function make(class: string, props: { [string]: any }): any
	local inst = Instance.new(class)
	for key, value in props do
		if key ~= "Parent" then
			(inst :: any)[key] = value
		end
	end
	if props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

function BreathBar.new()
	local self = setmetatable({}, BreathBar)

	local player = game:GetService("Players").LocalPlayer

	-- ResetOnSpawn = false: bar ini harus selamat dari respawn, sama
	-- seperti HorrorVignette milik DamageEffect.
	local gui = player:WaitForChild("PlayerGui"):FindFirstChild("SafeZoneBreath")
	if not gui then
		gui = make("ScreenGui", {
			Name = "SafeZoneBreath",
			ResetOnSpawn = false,
			IgnoreGuiInset = true,
			DisplayOrder = 5,
			Parent = player:WaitForChild("PlayerGui"),
		})
	end
	gui:ClearAllChildren()

	local holder = make("Frame", {
		Name = "Holder",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -BOTTOM_PAD),
		Size = UDim2.new(BAR_WIDTH, 0, 0, BAR_HEIGHT + 22),
		BackgroundTransparency = 1,
		-- Active = false: bar tidak boleh memblokir klik/tap pemain.
		Active = false,
		Visible = false,
		Parent = gui,
	})

	local label = make("TextLabel", {
		Name = "Label",
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.new(0, 0, 0, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		TextColor3 = Color3.fromRGB(235, 235, 235),
		TextStrokeTransparency = 0.6,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "",
		Active = false,
		Parent = holder,
	})

	local track = make("Frame", {
		Name = "Track",
		Size = UDim2.new(1, 0, 0, BAR_HEIGHT),
		Position = UDim2.new(0, 0, 1, -BAR_HEIGHT),
		BackgroundColor3 = Color3.fromRGB(20, 20, 24),
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Active = false,
		Parent = holder,
	})
	make("UICorner", { CornerRadius = UDim.new(0, 4), Parent = track })

	local fill = make("Frame", {
		Name = "Fill",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = COLOR_SAFE,
		BorderSizePixel = 0,
		Active = false,
		Parent = track,
	})
	make("UICorner", { CornerRadius = UDim.new(0, 4), Parent = fill })

	self._gui = gui
	self._holder = holder
	self._label = label
	self._fill = fill
	self._tween = game:GetService("TweenService")
	self._visible = false

	return self
end

--- Warna bar mengikuti sisa napas — pemain tahu bahaya tanpa membaca teks.
local function colorFor(fraction: number): Color3
	if fraction <= PANIC_AT then
		return COLOR_PANIC
	elseif fraction <= WARN_AT then
		return COLOR_WARN
	end
	return COLOR_SAFE
end

function BreathBar:_setVisible(visible: boolean)
	if self._visible == visible then
		return
	end
	self._visible = visible

	if visible then
		self._holder.Visible = true
	else
		task.delay(FADE_TIME, function()
			if not self._visible and self._holder and self._holder.Parent then
				self._holder.Visible = false
			end
		end)
	end
end

--- Gambar keadaan terbaru.
--- @param payload  tabel dari RemoteEvent, atau nil = sembunyikan
function BreathBar:update(payload: { [string]: any }?)
	if not self._holder or not self._holder.Parent then
		return
	end

	if not payload or payload.state == "NONE" then
		self:_setVisible(false)
		return
	end

	local state = tostring(payload.state)

	-- Bilik abadi tidak punya timer -> tidak perlu bar.
	if payload.eternal == true then
		self._label.Text = "Aman"
		self._fill.Size = UDim2.new(1, 0, 1, 0)
		self._fill.BackgroundColor3 = COLOR_SAFE
		self:_setVisible(true)
		return
	end

	local fraction = tonumber(payload.fraction) or 0
	fraction = math.clamp(fraction, 0, 1)

	local text = LABEL[state] or state
	if state == "OCCUPIED" then
		local left = math.max(0, math.floor((tonumber(payload.breath) or 0) + 0.5))
		text = string.format("%s  %ds", text, left)
	end

	self._label.Text = text
	self._fill.BackgroundColor3 = colorFor(fraction)

	-- Tween pendek supaya bar tidak tersentak di antara detak server 0.1s.
	self._tween:Create(
		self._fill,
		TweenInfo.new(0.12, Enum.EasingStyle.Linear),
		{ Size = UDim2.new(fraction, 0, 1, 0) }
	):Play()

	self:_setVisible(true)
end

function BreathBar:destroy()
	if self._gui then
		self._gui:Destroy()
	end
	self._gui = nil
	self._holder = nil
	self._label = nil
	self._fill = nil
end

return BreathBar
