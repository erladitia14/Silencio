--!strict
--[[
	HandIK — menempelkan TANGAN pemain ke Attachment di Engine memakai IKControl.

	Masalah yang diselesaikan:
	  Animasi R15 menyimpan SUDUT sendi ("tekuk siku 45 derajat"). Kalau pemain
	  punya panjang lengan / ukuran badan berbeda, hasilnya meleset dari Attachment.
	  IKControl sebaliknya: kita suruh "taruh telapak tangan TEPAT di titik ini",
	  Roblox menghitung sendiri sudut bahu & sikunya.

	Kenapa TIDAK bertabrakan dengan animasi:
	  Roblox mengevaluasi Animasi lebih dulu, lalu IKControl di frame yang SAMA.
	  IKControl menang untuk lengan yang di-chain; kaki tetap dikendalikan animasi
	  jalan. Jadi pemain tetap bisa jalan normal sambil tangannya nempel di Engine.

	Kontrak Attachment di Engine (dibuat Aer):
	  "<Sisi>(<Tangan>)"  ->  "Left(LeftArm)", "Left(RightArm)",
	                          "Right(LeftArm)", "Right(RightArm)"
	  Sisi  = sisi carrier (pemain mana yang memegang)
	  Tangan = nama tulang R15 yang di-IK (LeftArm / RightArm)

	Modul ini MURNI visual & berdiri sendiri; tidak menyentuh sistem lain.
]]

local Config = require(script.Parent.Config)

local HandIK = {}

type Rig = {
	hum: Humanoid,
	ikControls: { IKControl },
}

local active: { [Player]: Rig } = {}

-- ----------------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------------

local function getHumanoid(player: Player): Humanoid?
	local char = player.Character
	if not char then return nil end
	return char:FindFirstChildOfClass("Humanoid")
end

-- Ambil instance tulang R15 berdasarkan nama ("LeftArm" -> LeftUpperArm/LeftHand).
local function findBone(char: Model, name: string): BasePart?
	return char:FindFirstChild(name) :: BasePart?
end

-- ----------------------------------------------------------------------
-- API
-- ----------------------------------------------------------------------

-- Pasang IK kedua tangan ke Attachment sisi tertentu.
-- side: "Left" | "Right" (sisi carrier)
-- attachments: daftar Attachment milik Engine (nama "<Sisi>(<Tangan>)")
function HandIK.attach(player: Player, side: "Left" | "Right", attachments: { [string]: Attachment })
	if not Config.UseHandIK then return end
	if active[player] then
		HandIK.detach(player)
	end

	local char = player.Character
	if not char then return end
	local hum = getHumanoid(player)
	if not hum then return end
	-- IKControl hanya bekerja pada rig R15.
	if hum.RigType ~= Enum.HumanoidRigType.R15 then return end

	local ikControls: { IKControl } = {}

	-- Map nama "tangan" di attachment -> nama tulang R15 sesungguhnya.
	-- Attachment memakai "LeftArm"/"RightArm" (lengan mana yang meraih),
	-- sedangkan tulang R15 bernama "LeftHand"/"RightHand" (end effector) dan
	-- "LeftUpperArm"/"RightUpperArm" (pangkal rantai IK).
	local ARM_MAP = {
		LeftArm = { hand = "LeftHand", upper = "LeftUpperArm" },
		RightArm = { hand = "RightHand", upper = "RightUpperArm" },
		-- Alias kalau attachment langsung diberi nama bone.
		LeftHand = { hand = "LeftHand", upper = "LeftUpperArm" },
		RightHand = { hand = "RightHand", upper = "RightUpperArm" },
	}

	-- Untuk setiap Attachment yang cocok dengan sisi carrier ini,
	-- buat satu IKControl yang mengarah ke tulang tangan yang sesuai.
	for attName, att in pairs(attachments) do
		-- pola: "<Sisi>(<Tangan>)"
		local s, armName = string.match(attName, "^(%w+)%((%w+)%)$")
		local map = armName and ARM_MAP[armName]
		if s == side and map then
			local endEffector = findBone(char, map.hand)
			local chainRoot = findBone(char, map.upper)
			if endEffector and chainRoot then
				local ik = Instance.new("IKControl")
				ik.Name = "CarryIK_" .. map.hand
				-- Type = Position: tangan HANYA ditarik ke TITIK attachment; rotasi
				-- pergelangan dibiarkan natural. (Transform akan memaksa telapak ikut
				-- ORIENTASI attachment -> kalau attachment 0,0,0 pergelangan nekuk aneh.)
				ik.Type = Config.IKType or Enum.IKControlType.Position
				ik.ChainRoot = chainRoot
				ik.EndEffector = endEffector
				ik.Target = att
				ik.Weight = Config.IKWeight
				ik.Parent = hum
				table.insert(ikControls, ik)
			end
		end
	end

	if #ikControls > 0 then
		active[player] = { hum = hum, ikControls = ikControls }
	end
end

-- Lepas IK (saat drop / install / mati).
function HandIK.detach(player: Player)
	local rig = active[player]
	if not rig then return end
	for _, ik in ipairs(rig.ikControls) do
		ik:Destroy()
	end
	active[player] = nil
end

-- ----------------------------------------------------------------------
-- attachBoth — IK dua tangan ke DUA Attachment eksplisit.
-- ----------------------------------------------------------------------
-- Dipakai PANEL: Aer menaruh 2 Attachment di setiap Panel sebagai titik pegang,
-- tapi namanya polos "Left"/"Right" (bukan pola "<Sisi>(<Tangan>)" seperti
-- Engine), karena Panel dibawa 1 orang sehingga tidak ada sisi carrier.
-- attach() yang berbasis pola akan melewatinya DIAM-DIAM, jadi dipakai
-- fungsi ini yang menerima Attachment langsung.
--
-- PENTING — SISI DITENTUKAN DARI POSISI, BUKAN NAMA:
--   Attachment dengan X lebih kecil (paling kiri di ruang lokal part) dipasang
--   ke LeftArm. Ini menormalkan Panel yang attachment-nya tertukar (nyata:
--   Panel_02 Left X=+1.736 / Right X=-1.764 -> terbalik dibanding Panel_01).
--   Kalau memakai nama apa adanya, tangan akan menyilang.
--
-- @param player  pemain yang membawa
-- @param atts    daftar Attachment (>=1) di part yang dibawa
-- @return number jumlah IKControl yang berhasil dibuat
function HandIK.attachBoth(player: Player, atts: { Attachment }): number
	if not Config.UsePanelHandIK then return 0 end
	if #atts == 0 then return 0 end

	HandIK.detach(player)

	local char = player.Character
	if not char then return 0 end
	local hum = getHumanoid(player)
	if not hum then return 0 end
	-- IKControl hanya bekerja pada rig R15.
	if hum.RigType ~= Enum.HumanoidRigType.R15 then return 0 end

	-- Urutkan attachment berdasarkan X di ruang LOKAL part pembawa
	-- (ruang lokal part itu sumbu yang sama untuk kedua attachment).
	local sorted = table.clone(atts)
	table.sort(sorted, function(a, b)
		return a.Position.X < b.Position.X
	end)

	-- Kiri dulu (X terkecil), lalu kanan.
	local ARM_CHAIN = {
		{ hand = "LeftHand", upper = "LeftUpperArm" },
		{ hand = "RightHand", upper = "RightUpperArm" },
	}

	local ikControls: { IKControl } = {}
	for i, att in ipairs(sorted) do
		local chain = ARM_CHAIN[i]
		if not chain then break end
		local endEffector = findBone(char, chain.hand)
		local chainRoot = findBone(char, chain.upper)
		if endEffector and chainRoot then
			local ik = Instance.new("IKControl")
			ik.Name = "PanelCarryIK_" .. chain.hand
			ik.Type = Config.PanelIKType or Enum.IKControlType.Position
			ik.ChainRoot = chainRoot
			ik.EndEffector = endEffector
			ik.Target = att
			ik.Weight = Config.PanelIKWeight
			ik.Parent = hum
			table.insert(ikControls, ik)
		end
	end

	if #ikControls > 0 then
		active[player] = { hum = hum, ikControls = ikControls }
	end
	return #ikControls
end

function HandIK.cleanup(player: Player)
	HandIK.detach(player)
end

return HandIK
