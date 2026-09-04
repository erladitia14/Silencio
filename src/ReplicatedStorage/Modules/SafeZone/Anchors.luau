--[[
	Anchors.luau
	------------
	Menghitung TIGA titik penting sebuah bilik, dari geometri Part-nya:

	  hide  — di mana karakter berdiri saat sembunyi (di dalam bilik)
	  peek  — di mana kamera "mengintip" (di balik pintu, melihat keluar)
	  exit  — ke mana pemain dikeluarkan saat napas habis / keluar sendiri

	KONVENSI ARAH PINTU: muka depan Part (`LookVector`, sumbu −Z lokal).
	Jadi tim cukup memutar Part-nya supaya muka depannya = pintu toilet.
	Tidak ada Attribute yang perlu diisi.

	KALAU BUTUH PRESISI: taruh child bernama `HidePoint` / `PeekPoint` /
	`ExitPoint` di dalam Part (BasePart atau Attachment). Kalau ada, CFrame
	child itu dipakai apa adanya dan perhitungan otomatis dilewati — berguna
	untuk mesh toilet yang pintunya tidak di tengah muka Part.

	Modul ini murni matematika: tidak menyimpan state, tidak menyentuh
	Instance apa pun. Aman dipakai server maupun client.
--]]

local Config = require(script.Parent.Config)

local Anchors = {}

---------------------------------------------------------------------
-- HELPER
---------------------------------------------------------------------

--- Ambil CFrame sebuah child penanda, kalau tim menyediakannya.
local function markerCFrame(zonePart: BasePart, name: string?): CFrame?
	if not name or typeof(name) ~= "string" or name == "" then
		return nil
	end
	local child = zonePart:FindFirstChild(name)
	if not child then
		return nil
	end
	if child:IsA("BasePart") then
		return child.CFrame
	end
	if child:IsA("Attachment") then
		return child.WorldCFrame
	end
	return nil
end

--- Ketinggian lantai bilik (dunia).
local function floorY(zonePart: BasePart): number
	return zonePart.Position.Y - zonePart.Size.Y / 2
end

--- Setengah kedalaman bilik pada arah pintu (sumbu Z lokal).
local function halfDepth(zonePart: BasePart): number
	return zonePart.Size.Z / 2
end

--- Arah keluar bilik (menghadap pintu), sudah didatarkan ke bidang XZ.
--- Didatarkan supaya karakter/kamera tidak pernah menghadap ke langit
--- kalau tim memiringkan Part-nya sedikit.
local function outward(zonePart: BasePart): Vector3
	local look = zonePart.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-4 then
		-- Part menghadap tegak lurus ke atas/bawah: tidak ada arah pintu
		-- yang masuk akal. Pakai sumbu Z dunia sebagai jalan terakhir.
		return Vector3.new(0, 0, -1)
	end
	return flat.Unit
end

--- CFrame di posisi `pos` yang menghadap arah `dir` (datar).
local function facing(pos: Vector3, dir: Vector3): CFrame
	return CFrame.lookAt(pos, pos + dir, Vector3.yAxis)
end

---------------------------------------------------------------------
-- TITIK
---------------------------------------------------------------------

--- Di mana karakter berdiri saat sembunyi. Menghadap pintu (keluar),
--- supaya kalau nanti ada animasi "mengintip", arahnya sudah benar.
function Anchors.hide(zonePart: BasePart): CFrame
	local markerName = Config.HidePointName or "HidePoint"
	local override = markerCFrame(zonePart, markerName)
	if override then
		return override
	end

	local dir = outward(zonePart)
	local feetOffset = Config.HideFeetOffset or 3.0
	local pos = Vector3.new(
		zonePart.Position.X,
		floorY(zonePart) + feetOffset,
		zonePart.Position.Z
	)
	return facing(pos, dir)
end

--- Di mana kamera mengintip: setinggi mata, digeser ke muka pintu.
--- `PeekOutward` diperlakukan sebagai FRAKSI setengah kedalaman bilik,
--- bukan studs — supaya bilik sempit dan lemari besar sama-sama benar
--- tanpa tuning per objek.
function Anchors.peek(zonePart: BasePart): CFrame
	local markerName = Config.PeekPointName or "PeekPoint"
	local override = markerCFrame(zonePart, markerName)
	if override then
		return override
	end

	local dir = outward(zonePart)
	local hide = Anchors.hide(zonePart)
	local eyeHeight = Config.PeekEyeHeight or 1.4
	local peekOutward = Config.PeekOutward or 0.4
	local pos = hide.Position
		+ Vector3.new(0, eyeHeight, 0)
		+ dir * (halfDepth(zonePart) * peekOutward)

	return facing(pos, dir)
end

--- Ke mana pemain dilempar saat keluar / diusir. Di LUAR bilik, supaya
--- ia tidak langsung memicu prompt lagi (atau, pada bilik TouchToEnter,
--- tidak langsung terdaftar ulang sebagai penghuni).
function Anchors.exit(zonePart: BasePart): CFrame
	local markerName = Config.ExitPointName or "ExitPoint"
	local override = markerCFrame(zonePart, markerName)
	if override then
		return override
	end

	local dir = outward(zonePart)
	local feetOffset = Config.HideFeetOffset or 3.0
	local exitPush = Config.ExitPush or 4.0
	local pos = Vector3.new(
		zonePart.Position.X,
		floorY(zonePart) + feetOffset,
		zonePart.Position.Z
	) + dir * (halfDepth(zonePart) + exitPush)

	-- Menghadap BALIK ke bilik: pemain yang baru diusir melihat tempat
	-- persembunyiannya (dan monster yang menunggu di depannya).
	return facing(pos, -dir)
end

--- Ketiga titik sekaligus (menghindari hitung ulang di pemanggil).
function Anchors.all(zonePart: BasePart): { hide: CFrame, peek: CFrame, exit: CFrame }
	return {
		hide = Anchors.hide(zonePart),
		peek = Anchors.peek(zonePart),
		exit = Anchors.exit(zonePart),
	}
end

--- Arah pintu bilik (unit, datar). Dipakai client untuk membatasi
--- sudut mengintip.
function Anchors.doorDirection(zonePart: BasePart): Vector3
	return outward(zonePart)
end

return Anchors
