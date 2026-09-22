--[[
	KnockHud.luau
	-------------
	UI presentasi kondisi TUMBANG (knocked): BillboardGui di atas kepala
	pemain tumbang yang menunjukkan SISA WAKTU sebelum ia mati.

	Kenapa billboard (bukan UI layar): teman yang mau menolong perlu tahu
	SIAPA yang tumbang dan berapa lama lagi — dan itu harus terbaca walau
	ia berdiri beberapa studs jauhnya. Korban sendiri juga ikut melihatnya.

	KONTRAK MODUL UI (pola sama SafeZone/BreathBar, supaya tim bisa menukar
	tanpa menyentuh script):
	  hud = KnockHud.new()
	  hud:update(payload)   -- payload di bawah; nil = sembunyikan
	  hud:destroy()

	payload = {
	  name           = "Player1",  -- nama pemain tumbang
	  bleedOut       = 12.3,       -- sisa detik sebelum mati
	  total          = 30,         -- durasi bleed-out penuh
	  fraction       = 0.41,       -- bleedOut / total (0..1)
	  reviveProgress = 0.0,        -- 0..1, progres teman menolong
	}

	PENTING: modul ini murni TAMPILAN — ia tidak tahu soal monster, revive,
	atau server. Semua angka datang dari Attribute karakter (lihat KnockUI.client).
	Teks yang dilihat pemain = BAHASA INGGRIS (aturan project).
--]]

local TweenService = game:GetService("TweenService")

local KnockHud = {}
KnockHud.__index = KnockHud

local COLOR_BONE   = Color3.fromRGB(235, 225, 220)
local COLOR_WARN   = Color3.fromRGB(225, 110, 40)
local COLOR_PANIC  = Color3.fromRGB(255, 45, 60)
local COLOR_REVIVE = Color3.fromRGB(150, 230, 170)
local COLOR_BLOOD  = Color3.fromRGB(120, 12, 20)
local COLOR_BLOOD_BRIGHT = Color3.fromRGB(215, 35, 45)

-- Ambang "mau mati": di bawah ini teks berubah & mulai berdenyut.
local PANIC_SECONDS = 10

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

--- Membuat billboard untuk SATU karakter tumbang.
function KnockHud.new(adornee: BasePart)
	local self = setmetatable({}, KnockHud)

	local billboard = new("BillboardGui", {
		Name = "KnockHud",
		Adornee = adornee,
		Size = UDim2.new(0, 190, 0, 74),
		StudsOffsetWorldSpace = Vector3.new(0, 3.0, 0),
		AlwaysOnTop = false,
		MaxDistance = 90,
		LightInfluence = 0,
		ResetOnSpawn = false,
		Parent = adornee,
	})

	-- Bingkai utama (gelap, tepi darah)
	local frame = new("Frame", {
		Name = "Frame",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(12, 2, 4),
		BackgroundTransparency = 0.18,
		BorderSizePixel = 0,
		Parent = billboard,
	})
	new("UICorner", { CornerRadius = UDim.new(0, 5), Parent = frame })
	local stroke = new("UIStroke", {
		Color = COLOR_BLOOD,
		Thickness = 1.5,
		Transparency = 0.15,
		Parent = frame,
	})

	-- Nama + status
	local title = new("TextLabel", {
		Name = "Title",
		Position = UDim2.new(0, 8, 0, 4),
		Size = UDim2.new(1, -16, 0, 18),
		BackgroundTransparency = 1,
		Font = Enum.Font.SpecialElite,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = COLOR_BONE,
		TextStrokeColor3 = Color3.new(0, 0, 0),
		TextStrokeTransparency = 0.2,
		Text = "DOWN",
		Parent = frame,
	})

	-- Countdown besar (kanan atas)
	local timer = new("TextLabel", {
		Name = "Timer",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 2),
		Size = UDim2.new(0, 70, 0, 22),
		BackgroundTransparency = 1,
		Font = Enum.Font.SpecialElite,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = COLOR_PANIC,
		TextStrokeColor3 = Color3.new(0, 0, 0),
		TextStrokeTransparency = 0,
		Text = "30s",
		Parent = frame,
	})

	-- Bar bleed-out (merah, mengecil)
	local bleedTrack = new("Frame", {
		Name = "BleedTrack",
		Position = UDim2.new(0, 8, 0, 30),
		Size = UDim2.new(1, -16, 0, 9),
		BackgroundColor3 = Color3.fromRGB(45, 6, 10),
		BorderSizePixel = 0,
		Parent = frame,
	})
	new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = bleedTrack })
	local bleedFill = new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = COLOR_BLOOD_BRIGHT,
		BorderSizePixel = 0,
		Parent = bleedTrack,
	})
	new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = bleedFill })

	-- Bar revive (hijau, hanya muncul saat ada yang menolong)
	local reviveLabel = new("TextLabel", {
		Name = "ReviveLabel",
		Position = UDim2.new(0, 8, 0, 42),
		Size = UDim2.new(1, -16, 0, 14),
		BackgroundTransparency = 1,
		Font = Enum.Font.SpecialElite,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = COLOR_REVIVE,
		TextStrokeColor3 = Color3.new(0, 0, 0),
		TextStrokeTransparency = 0.2,
		Text = "",
		Visible = false,
		Parent = frame,
	})
	local reviveTrack = new("Frame", {
		Name = "ReviveTrack",
		Position = UDim2.new(0, 8, 0, 58),
		Size = UDim2.new(1, -16, 0, 7),
		BackgroundColor3 = Color3.fromRGB(20, 40, 26),
		BorderSizePixel = 0,
		Visible = false,
		Parent = frame,
	})
	new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = reviveTrack })
	local reviveFill = new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = COLOR_REVIVE,
		BorderSizePixel = 0,
		Parent = reviveTrack,
	})
	new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = reviveFill })

	self.billboard  = billboard
	self.frame      = frame
	self.stroke     = stroke
	self.title      = title
	self.timer      = timer
	self.bleedTrack = bleedTrack
	self.bleedFill  = bleedFill
	self.reviveLabel = reviveLabel
	self.reviveTrack = reviveTrack
	self.reviveFill  = reviveFill

	self.panic = false
	self.lastText = nil

	return self
end

--- Perbarui tampilan. `payload` = tabel (lihat header) atau nil untuk sembunyi.
function KnockHud:update(payload)
	if not self.billboard or not self.billboard.Parent then
		return
	end

	if not payload then
		self.billboard.Enabled = false
		return
	end

	self.billboard.Enabled = true

	local fraction = math.clamp(tonumber(payload.fraction) or 0, 0, 1)
	local bleedOut = math.max(0, tonumber(payload.bleedOut) or 0)
	local revive   = math.clamp(tonumber(payload.reviveProgress) or 0, 0, 1)

	-- Nama + status
	local name = payload.name or "?"
	self.title.Text = "DOWN  " .. name

	-- Countdown (bulat ke atas; minimal tampil 0)
	local secs = math.ceil(bleedOut)
	self.timer.Text = tostring(secs) .. "s"

	-- Bar bleed-out
	self.bleedFill.Size = UDim2.fromScale(fraction, 1)

	-- Warna mengikuti sisa waktu
	local panic = bleedOut <= PANIC_SECONDS
	if panic ~= self.panic then
		self.panic = panic
		-- Timer selalu merah; yang berubah: judul & tepi bingkai menegang.
		self.title.TextColor3 = panic and COLOR_WARN or COLOR_BONE
		self.stroke.Color = panic and COLOR_PANIC or COLOR_BLOOD
		if not panic then
			-- Pulihkan tampilan normal saat tidak panik.
			self.stroke.Transparency = 0.15
			self.timer.TextTransparency = 0
		end
	end

	-- Progres revive (hanya saat ada yang menolong)
	if revive > 0 then
		self.reviveLabel.Visible = true
		self.reviveTrack.Visible = true
		self.reviveLabel.Text = string.format("REVIVING  %d%%", math.floor(revive * 100 + 0.5))
		self.reviveFill.Size = UDim2.fromScale(revive, 1)
	else
		self.reviveLabel.Visible = false
		self.reviveTrack.Visible = false
		self.reviveFill.Size = UDim2.fromScale(0, 1)
	end
end

--- Denyut saat hampir mati (dipanggil dari loop RenderStepped oleh KnockUI).
function KnockHud:tick(now: number)
	if not self.panic or not self.stroke or not self.stroke.Parent then
		return
	end
	-- 0..1 denyut cepat
	local pulse = (math.sin(now * 9) + 1) * 0.5
	self.stroke.Transparency = 0.55 - pulse * 0.5
	self.timer.TextTransparency = 0.35 - pulse * 0.35
end

function KnockHud:destroy()
	if self.billboard then
		self.billboard:Destroy()
	end
	self.billboard = nil
	self.frame = nil
	self.stroke = nil
	self.title = nil
	self.timer = nil
	self.bleedTrack = nil
	self.bleedFill = nil
	self.reviveLabel = nil
	self.reviveTrack = nil
	self.reviveFill = nil
end

return KnockHud
