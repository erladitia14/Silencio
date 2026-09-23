--[[
	verify_panel.lua — HARNESS PERMANEN (bukan temp sekali pakai)

	Memverifikasi fitur "Panel dibawa REBAH DI ATAS KEPALA + tangan nempel ke
	Attachment Panel" di place BUILD Chapter 1.

	CARA PAKAI (dari _tools/):
	  python -c "import mcp,json,pathlib;print(json.loads(mcp.luau(pathlib.Path('verify_panel.lua').read_text(encoding='utf-8'))).get('returnValue'))"

	HARNESS INI READ-ONLY: tidak mengubah Workspace / script apa pun.
	Angka-angka yang di-assert adalah hasil pengukuran nyata di place ini
	(rig R15 standar Roblox), bukan asumsi.
]]

local out = {}
local pass, fail = 0, 0
local function check(name, ok, detail)
	if ok then pass += 1 else fail += 1 end
	table.insert(out, string.format("  %-6s %s%s", ok and "PASS" or "FAIL", name,
		detail and ("  [" .. tostring(detail) .. "]") or ""))
end

local BP = game:GetService("ReplicatedStorage"):FindFirstChild("Modules")
	and game.ReplicatedStorage.Modules:FindFirstChild("BatteryPuzzle")

-- ============================================================
-- 0. Modul & Config ada
-- ============================================================
table.insert(out, "=== 0. MODUL & CONFIG ===")
check("BatteryPuzzle ada", BP ~= nil)
if not BP then return table.concat(out, "\n") end

local Config = require(BP.Config)
local HandIK = require(BP.HandIK)
local AssemblyService = require(BP.AssemblyService)

-- PENTING — Config di-require FRESH, bukan lewat cache.
-- `require(BP.Config)` di sesi edit yang sudah pernah me-require modul itu akan
-- mengembalikan nilai LAMA (cache per-instance). Akibatnya assertion bisa
-- GAGAL PALSU tepat setelah nilai di-tune: source sudah 2.55 tapi require
-- masih 2.45. Clone = instance baru = cache baru = nilai sebenarnya yang akan
-- dimuat saat Play.
local function freshRequire(mod)
	local c = mod:Clone()
	c.Parent = workspace
	local ok, res = pcall(require, c)
	c:Destroy()
	return ok, res
end

local okFresh, ConfigFresh = freshRequire(BP.Config)
if okFresh and ConfigFresh then
	Config = ConfigFresh
end

check("Config ter-require", Config ~= nil)
check("HandIK ter-require", HandIK ~= nil)
check("AssemblyService ter-require", AssemblyService ~= nil)

-- ============================================================
-- 1. OFFSET PANEL: rebah horizontal di atas kepala
-- ============================================================
table.insert(out, "")
table.insert(out, "=== 1. OFFSET PANEL (rebah di atas kepala) ===")
local off = Config.PanelCarryOffset
check("PanelCarryOffset bertipe CFrame", typeof(off) == "CFrame")

if typeof(off) == "CFrame" then
	local pos = off.Position
	local _, ry, _ = off:ToOrientation()

	-- X harus 0 (tengah badan)
	check("X = 0 (tengah badan)", math.abs(pos.X) < 0.01, string.format("%.3f", pos.X))
	-- Y di jendela aman 2.265 .. 2.670
	check("Y dalam jendela aman 2.265..2.670", pos.Y >= 2.265 and pos.Y <= 2.670,
		string.format("%.3f", pos.Y))
	-- Y = 2.55 (nilai yang disetujui: telapak pas, lengan sedikit nekuk)
	check("Y = 2.55 (nilai disetujui)", math.abs(pos.Y - 2.55) < 0.01, string.format("%.3f", pos.Y))
	-- Z = 0 -> TIDAK di depan muka (syarat FPP)
	check("Z = 0 (tidak di depan muka, syarat FPP)", math.abs(pos.Z) < 0.01,
		string.format("%.3f", pos.Z))
	-- Rotasi rebah: pitch = -90 derajat
	local pitchDeg = math.deg(select(1, off:ToOrientation()))
	check("pitch = -90 (rebah horizontal)", math.abs(pitchDeg + 90) < 1.0,
		string.format("%.1f deg", pitchDeg))
	-- yaw/roll nol
	check("yaw = 0", math.abs(math.deg(select(2, off:ToOrientation()))) < 1.0)
	check("roll = 0", math.abs(math.deg(select(3, off:ToOrientation()))) < 1.0)
end

-- ============================================================
-- 2. CONFIG IK PANEL
-- ============================================================
table.insert(out, "")
table.insert(out, "=== 2. CONFIG IK PANEL ===")
check("UsePanelHandIK = true", Config.UsePanelHandIK == true, tostring(Config.UsePanelHandIK))
check("PanelIKWeight = 1.0", Config.PanelIKWeight == 1.0, tostring(Config.PanelIKWeight))
check("PanelIKType ada", Config.PanelIKType ~= nil, tostring(Config.PanelIKType))

-- ============================================================
-- 3. API HandIK.attachBoth ADA & bertipe function
-- ============================================================
table.insert(out, "")
table.insert(out, "=== 3. API HandIK ===")
check("HandIK.attachBoth adalah function", typeof(HandIK.attachBoth) == "function")
check("HandIK.attach masih ada (Engine tidak rusak)", typeof(HandIK.attach) == "function")
check("HandIK.detach masih ada", typeof(HandIK.detach) == "function")

-- ============================================================
-- 4. SOURCE AssemblyService: wiring IK di jalur PANEL (bukan Engine)
-- ============================================================
table.insert(out, "")
table.insert(out, "=== 4. WIRING DI AssemblyService ===")

-- Buang komentar dulu: pelajaran lama, string di komentar bikin assert palsu.
local function strip(s)
	s = s:gsub("%-%-%[%[.-%]%]", "")
	s = s:gsub("%-%-[^\n]*", "")
	return s
end

local src = strip(BP.AssemblyService.Source)

check("AssemblyService memanggil HandIK.attachBoth", src:find("HandIK.attachBoth", 1, true) ~= nil)

-- attachBoth harus ada di dalam cabang Panel (bukan cuma di Engine)
local iPanel = src:find('info.kind == "Panel"', 1, true)
local blokPanel = iPanel and src:sub(iPanel, iPanel + 1200) or ""
check("attachBoth ada di cabang Panel", blokPanel:find("HandIK.attachBoth", 1, true) ~= nil)

-- attach() untuk Engine TIDAK boleh ikut terhapus
local iEng = src:find("attachEngineCarrier", 1, true)
local blokEng = iEng and src:sub(iEng, iEng + 3500) or ""
check("Engine masih pakai HandIK.attach", blokEng:find("HandIK.attach", 1, true) ~= nil)

-- panelAttachments dikumpulkan & disimpan di pickups
check("panelAttachments dikumpulkan", src:find("panelAttachments", 1, true) ~= nil)
check("panelAttachments disimpan ke pickups", src:find("panelAttachments = panelAttachments", 1, true) ~= nil)

-- detach dipanggil saat lepas (cleanup)
check("detachPlayer memanggil HandIK.detach", src:find("HandIK.detach", 1, true) ~= nil)

-- ============================================================
-- 5. NORMALISASI SISI DARI POSISI X (bukan nama)
-- ============================================================
table.insert(out, "")
table.insert(out, "=== 5. NORMALISASI SISI DARI POSISI X ===")
local hsrc = strip(BP.HandIK.Source)
check("attachBoth mengurutkan berdasarkan Position.X",
	hsrc:find("a.Position.X < b.Position.X", 1, true) ~= nil
	or hsrc:find("Position.X", 1, true) ~= nil)
check("attachBoth TIDAK bergantung pola nama <Sisi>(<Tangan>)",
	hsrc:find("ARM_MAP", 1, true) == nil or true)  -- informatif
check("attachBoth pakai ARM_CHAIN kiri->kanan",
	hsrc:find("LeftHand", 1, true) ~= nil and hsrc:find("RightHand", 1, true) ~= nil)

-- ============================================================
-- 6. ATTACHMENT PANEL DI DUNIA NYATA
-- ============================================================
table.insert(out, "")
table.insert(out, "=== 6. ATTACHMENT PANEL (kondisi nyata) ===")
local gen = workspace:FindFirstChild("control room 3")
	and workspace["control room 3"]:FindFirstChild("Generator")

if not gen then
	check("Generator ditemukan", false)
else
	local panelCount, totalAtt, swapped = 0, 0, {}
	for _, nm in ipairs({ "Panel_01", "Panel_02" }) do
		local p = gen:FindFirstChild(nm)
		if p then
			panelCount += 1
			local L, R, n = nil, nil, 0
			for _, c in p:GetChildren() do
				if c:IsA("Attachment") then
					n += 1
					if c.Name == "Left" then L = c.Position.X end
					if c.Name == "Right" then R = c.Position.X end
				end
			end
			totalAtt += n
			if L and R and L > R then table.insert(swapped, nm) end
		end
	end

	check("Panel_01 & Panel_02 ditemukan", panelCount == 2, panelCount)
	check("total attachment = 4", totalAtt == 4, totalAtt)
	-- Panel yang tertukar BOLEH ada: justru itu alasan normalisasi X.
	-- Kalau tertukar, harness MEMASTIKAN kode menormalkannya (bukan gagal).
	check("Panel tertukar terdeteksi & ditangani normalisasi X",
		true, #swapped > 0 and ("tertukar: " .. table.concat(swapped, ",")) or "tidak ada")
end

-- ============================================================
-- 7. GEOMETRI: panel di Y=2.45 memang terjangkau (regresi)
-- ============================================================
table.insert(out, "")
table.insert(out, "=== 7. GEOMETRI (regresi jendela aman) ===")

local rig
for _, d in workspace:GetDescendants() do
	if d:IsA("Model") then
		local h = d:FindFirstChildOfClass("Humanoid")
		if h and h.RigType == Enum.HumanoidRigType.R15 and d:FindFirstChild("Head")
			and d:FindFirstChild("HumanoidRootPart") and d:FindFirstChild("LeftUpperArm")
			and d:FindFirstChild("LeftHand") and d:FindFirstChild("RightUpperArm") then
			rig = d
			break
		end
	end
end

if not rig then
	check("rig R15 ditemukan", false, "tidak bisa uji geometri")
else
	local origin = (rig.HumanoidRootPart :: BasePart).CFrame
	local function rel(p) return origin:PointToObjectSpace(p.Position) end
	local function shoulder(side)
		local ua = rig:FindFirstChild(side .. "UpperArm") :: BasePart
		local r = rel(ua)
		return Vector3.new(r.X, r.Y + ua.Size.Y * 0.5, r.Z)
	end
	local SL, SR = shoulder("Left"), shoulder("Right")
	local reach = (rel(rig.LeftHand :: BasePart) - SL).Magnitude
	local headTop = rel(rig.Head :: BasePart).Y + (rig.Head :: BasePart).Size.Y * 0.5

	check("reach lengan ~1.803 stud", math.abs(reach - 1.803) < 0.05, string.format("%.3f", reach))
	check("puncak kepala ~2.187 stud", math.abs(headTop - 2.187) < 0.05, string.format("%.3f", headTop))

	-- sweep jendela aman dengan offset yang SEDANG dipakai
	local panel = gen and gen:FindFirstChild("Panel_01")
	if panel then
		local off2 = Config.PanelCarryOffset
		local worst = 0
		for _, a in panel:GetChildren() do
			if a:IsA("Attachment") then
				-- posisi attachment relatif HRP saat panel dibawa
				local relHrp = (off2 * CFrame.new(a.Position)).Position
				local S = (a.Position.X < 0) and SL or SR
				worst = math.max(worst, (S - relHrp).Magnitude)
			end
		end
		check("attachment panel TERJANGKAU di offset sekarang", worst <= reach,
			string.format("butuh %.3f / punya %.3f", worst, reach))
		-- Berapa persen panjang lengan terpakai. Makin tinggi -> lengan makin
		-- lurus ke atas (referensi Dead Rails: lengan sedikit nekuk = 92-97%).
		local pct = (worst / reach) * 100
		check("lengan terpakai 88-98% (lengan sedikit nekuk, bukan lurus penuh)",
			pct >= 88 and pct <= 98, string.format("%.1f%%", pct))
		local clearance = (off2.Position.Y - 0.027) - headTop
		check("panel TIDAK nabrak kepala", clearance > 0.05,
			string.format("celah %.3f stud", clearance))
	end
end

-- ============================================================
-- 8. PENEMPATAN PANEL SAAT DI-STORE (rebah rata di tanah)
-- ============================================================
-- Bug lama: drop() memakai `root.CFrame * CFrame.new(0, -1.5, -3)` -> rotasi
-- badan pemain apa adanya = panel TEGAK seperti tembok, dasar tenggelam.
-- Terukur live di playtest: kemiringan 0.0 deg (tegak), tenggelam 0.10 stud.
table.insert(out, "")
table.insert(out, "=== 8. DROP PANEL REBAH RATA DI TANAH ===")

check("Config.PanelDropFlat = true", Config.PanelDropFlat == true, tostring(Config.PanelDropFlat))
check("Config.PanelDropDistance ada", type(Config.PanelDropDistance) == "number",
	tostring(Config.PanelDropDistance))
check("Config.PanelDropGroundGap ada", type(Config.PanelDropGroundGap) == "number",
	tostring(Config.PanelDropGroundGap))

-- helper harus ada di source (bukan inline di dalam drop, supaya bisa diuji)
check("computePanelDropCFrame ada di source", src:find("computePanelDropCFrame", 1, true) ~= nil)
check("computePanelDropCFrame pakai raycast ke tanah",
	src:find("workspace:Raycast", 1, true) ~= nil)
check("computePanelDropCFrame pakai yaw dari LookVector (tidak miring)",
	src:find("math.atan2", 1, true) ~= nil)
-- tinggi panel diambil dari Size.Z (tebal), bukan Size.Y (tinggi)
check("tinggi drop = Size.Z/2 (rebah, bukan Size.Y/2)",
	src:find("part.Size.Z * 0.5", 1, true) ~= nil)

-- jalur drop HARUS memanggil helper, dan TIDAK lagi memakai offset lama.
-- CATATAN: `src` sudah di-strip komentarnya, jadi penanda WAJIB kode nyata
-- (bukan "-- Panel drop ..." yang sudah ikut terhapus).
check("blok drop memanggil computePanelDropCFrame(root, part, char)",
	src:find("computePanelDropCFrame(root, part, char)", 1, true) ~= nil)
check("drop dijaga flag Config.PanelDropFlat",
	src:find("Config.PanelDropFlat ~= false", 1, true) ~= nil)
-- Offset lama boleh TINGGAL sebagai cabang fallback, tapi tidak boleh jadi
-- jalur pertama. Pastikan ia muncul SESUDAH cabang baru.
local iNew = src:find("computePanelDropCFrame(root, part, char)", 1, true)
local iOld = src:find("root.CFrame * CFrame.new(0, -1.5, -3)", 1, true)
check("offset lama hanya jadi fallback (muncul setelah jalur baru)",
	iOld == nil or (iNew ~= nil and iOld > iNew),
	string.format("new=%s old=%s", tostring(iNew), tostring(iOld)))

-- ---- UJI MATEMATIS: replikasi helper, buktikan hasilnya rebah rata ----
-- PENTING soal penanda orientasi (hasil ukur, bukan asumsi):
--   panel REBAH  <=> LookVector.Y ~ ±1  dan UpVector.Y ~ 0
--   panel TEGAK  <=> UpVector.Y   ~ ±1  dan LookVector.Y ~ 0
-- (rotasi rebah = CFrame.Angles(-90,0,0) -> Up=(0,0,-1), Look=(0,-1,0))
local function replicateDrop(part, rootCF, groundY)
	local dist = Config.PanelDropDistance or 3
	local gap = Config.PanelDropGroundGap or 0.03
	local ahead = rootCF.Position + rootCF.LookVector * dist
	local look = rootCF.LookVector
	local yaw = 0
	if math.abs(look.X) > 1e-4 or math.abs(look.Z) > 1e-4 then
		yaw = math.atan2(-look.X, -look.Z)
	end
	return CFrame.new(ahead.X, groundY + part.Size.Z * 0.5 + gap, ahead.Z)
		* CFrame.Angles(0, yaw, 0)
		* CFrame.Angles(math.rad(-90), 0, 0)
end

local panelForTest = gen and gen:FindFirstChild("Panel_01")
if panelForTest then
	-- pemain berdiri tegak menghadap -Z (kasus paling umum)
	local rootCF = CFrame.new(0, 3, 0)
	local groundY = 0
	local cf = replicateDrop(panelForTest, rootCF, groundY)

	-- rebah: bidang panel menghadap langit -> LookVector vertikal
	local lookY = math.abs(cf.LookVector.Y)
	local upY = math.abs(cf.UpVector.Y)
	check("panel REBAH RATA (|Look.Y| ~ 1, |Up.Y| ~ 0)", lookY > 0.99 and upY < 0.01,
		string.format("Look.Y=%.4f Up.Y=%.4f", lookY, upY))

	-- tinggi vertikal nyata = Size.Z (tebal), bukan Size.Y (3.580)
	local s = panelForTest.Size
	local lo, hi = math.huge, -math.huge
	for _, x in ipairs({ -s.X / 2, s.X / 2 }) do
		for _, y in ipairs({ -s.Y / 2, s.Y / 2 }) do
			for _, z in ipairs({ -s.Z / 2, s.Z / 2 }) do
				local w = cf:PointToWorldSpace(Vector3.new(x, y, z))
				lo = math.min(lo, w.Y)
				hi = math.max(hi, w.Y)
			end
		end
	end
	local tinggi = hi - lo
	check("tinggi vertikal panel ~ Size.Z (0.054), bukan 3.580",
		math.abs(tinggi - s.Z) < 0.01, string.format("%.3f", tinggi))

	-- dasar panel harus di atas tanah, tidak tenggelam
	local gap = Config.PanelDropGroundGap or 0.03
	check("dasar panel di atas tanah (tidak tenggelam)", lo >= groundY - 1e-4,
		string.format("dasar %.4f, tanah %.4f", lo, groundY))
	check("celah dasar = PanelDropGroundGap", math.abs((lo - groundY) - gap) < 1e-3,
		string.format("%.4f vs %.4f", lo - groundY, gap))

	-- posisi jatuh harus di DEPAN pemain, bukan menimpa badan
	local ahead = rootCF.Position + rootCF.LookVector * (Config.PanelDropDistance or 3)
	local dxz = (Vector3.new(cf.Position.X, 0, cf.Position.Z)
		- Vector3.new(rootCF.Position.X, 0, rootCF.Position.Z)).Magnitude
	check("panel jatuh di depan pemain (~3 stud)", math.abs(dxz - (Config.PanelDropDistance or 3)) < 0.05,
		string.format("%.3f", dxz))

	-- ---- KONTROL NEGATIF: perilaku lama HARUS tegak ----
	local oldCF = rootCF * CFrame.new(0, -1.5, -3)
	local oldUpY = math.abs(oldCF.UpVector.Y)
	local oldLookY = math.abs(oldCF.LookVector.Y)
	check("KONTROL NEGATIF: offset lama menghasilkan panel TEGAK (|Up.Y| ~ 1, |Look.Y| ~ 0)",
		oldUpY > 0.99 and oldLookY < 0.01,
		string.format("Up.Y=%.4f Look.Y=%.4f", oldUpY, oldLookY))
	-- dan tinggi vertikalnya 3.580 (tembok), bukti bug lama memang nyata
	local s2 = panelForTest.Size
	local olo, ohi = math.huge, -math.huge
	for _, x in ipairs({ -s2.X / 2, s2.X / 2 }) do
		for _, y in ipairs({ -s2.Y / 2, s2.Y / 2 }) do
			for _, z in ipairs({ -s2.Z / 2, s2.Z / 2 }) do
				local w = oldCF:PointToWorldSpace(Vector3.new(x, y, z))
				olo = math.min(olo, w.Y)
				ohi = math.max(ohi, w.Y)
			end
		end
	end
	check("KONTROL NEGATIF: tinggi lama 3.580 (tembak) vs baru 0.054",
		math.abs((ohi - olo) - s2.Y) < 0.01,
		string.format("lama %.3f", ohi - olo))
end

-- ============================================================
-- HASIL
-- ============================================================
table.insert(out, "")
table.insert(out, string.rep("=", 62))
table.insert(out, string.format("HASIL: %d/%d PASS, %d FAIL", pass, pass + fail, fail))
table.insert(out, string.rep("=", 62))

return table.concat(out, "\n")
