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
	`ExitPoint` (BasePart atau Attachment). Kalau ada, CFrame marker itu
	dipakai apa adanya dan perhitungan otomatis dilewati — berguna untuk
	mesh toilet yang pintunya tidak di tengah muka Part.

	Marker dicari di TIGA tempat, urut prioritas:
	  1. Child langsung Part ber-tag SafeZone (body bilik)
	  2. Descendant mana pun di dalam Model induk Part itu (misal di pintu)
	  3. Descendant mana pun di Workspace (fallback terakhir)

	Contoh kasus nyata: bilik Outhouse punya peephole oval di MESH PINTU
	(sibling dari body yang di-tag SafeZone). Tim menempel Attachment
	`PeekPoint` tepat di lubang pintu itu — modul ini menemukannya lewat
	jalur (2), tanpa perlu memindahkan tag SafeZone ke pintu.

	KONVENSI ARAH MARKER ATTACHMENT: arah hadap = PANAH KUNING attachment
	(sumbu +X). Itu yang tim atur pakai Rotate tool di Studio. Modul ini
	membaca +X sebagai "hadap", BUKAN LookVector — jadi yang terlihat di
	viewport (panah kuning) persis yang dipakai. Marker BasePart tetap
	pakai konvensi Roblox biasa (LookVector, muka depan Part).

	Modul ini murni matematika: tidak menyimpan state, tidak menyentuh
	Instance apa pun. Aman dipakai server maupun client.
--]]

local Config = require(script.Parent.Config)

local Anchors = {}

---------------------------------------------------------------------
-- HELPER
---------------------------------------------------------------------

--- Ambil CFrame sebuah child penanda, kalau tim menyediakannya.
--- Cari di: (1) child Part itu sendiri, (2) descendants Model induk,
--- (3) descendants Workspace. Ini memungkinkan PeekPoint ditempel
--- di pintu (sibling dari Part ber-tag), bukan hanya di body.
local function markerCFrame(zonePart: BasePart, name: string?): CFrame?
	if not name or typeof(name) ~= "string" or name == "" then
		return nil
	end

	-- (1) Child langsung dari Part ber-tag (paling umum).
	local child = zonePart:FindFirstChild(name)

	-- (2) Mana pun di dalam Model induk (misal pintu / dinding sibling).
	if not child then
		local parent = zonePart.Parent
		if parent and parent ~= workspace then
			child = parent:FindFirstChild(name, true)
		end
	end

	-- (3) Fallback: mana pun di Workspace (bilik kompleks multi-model).
	if not child then
		child = workspace:FindFirstChild(name, true)
	end

	if not child then
		return nil
	end
	if child:IsA("BasePart") then
		return child.CFrame
	end
	if child:IsA("Attachment") then
		-- Panah KUNING attachment di Studio = sumbu +X (RightVector). Itu yang
		-- tim putar untuk menentukan arah hadap. Jadikan LookVector hasil =
		-- panah kuning itu, supaya pemain/kamera menghadap persis seperti yang
		-- terlihat di viewport (bukan 90° nyamping seperti LookVector mentah).
		local wc = child.WorldCFrame
		local forward = wc.XVector
		return CFrame.lookAt(wc.Position, wc.Position + forward, Vector3.yAxis)
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
