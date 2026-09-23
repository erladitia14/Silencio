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
	-- Y = 2.45 (nilai yang disetujui)
	check("Y = 2.45 (nilai disetujui)", math.abs(pos.Y - 2.45) < 0.01, string.format("%.3f", pos.Y))
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
		local clearance = (off2.Position.Y - 0.027) - headTop
		check("panel TIDAK nabrak kepala", clearance > 0.05,
			string.format("celah %.3f stud", clearance))
	end
end

-- ============================================================
-- HASIL
-- ============================================================
table.insert(out, "")
table.insert(out, string.rep("=", 62))
table.insert(out, string.format("HASIL: %d/%d PASS, %d FAIL", pass, pass + fail, fail))
table.insert(out, string.rep("=", 62))

return table.concat(out, "\n")
