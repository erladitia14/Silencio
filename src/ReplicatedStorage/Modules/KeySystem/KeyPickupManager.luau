--[[
	KeyPickupManager.luau (KeySystem)
	---------------------------------
	Mengelola objek ber-tag "KeyPickup".
	Tiap kunci diberi ProximityPrompt "Ambil Kunci".
	Saat diambil: KeyId dicatat di KeyService (shared/tim), lalu objek kuncinya
	dibereskan. Bersifat server-authoritative.

	Apa yang terjadi pada objek kunci setelah diambil:

	| Jenis kunci | Config.KeyToolToBackpack | Hasil                                 |
	|-------------|--------------------------|---------------------------------------|
	| Tool        | true (default)           | masuk Backpack pemain (muncul hotbar) |
	| Tool        | false                    | dihapus dari dunia                    |
	| Part/Model  | (tidak berlaku)          | dihapus dari dunia                    |

	Attribute `KeepInWorld` = true pada objek kunci -> kunci TIDAK disentuh
	sama sekali (tidak dihapus, tidak dipindah), jadi pemain lain masih bisa
	mengambilnya. Berguna untuk kunci dekorasi / co-op longgar.

	Kunci berupa Tool + Attribute MonsterBait = true tetap dikenali
	EnemyController mode ITEM_HOLDER selama ada di Backpack/tangan pemain.

	CATATAN Tool di Workspace: engine Roblox otomatis memasukkan Tool ke
	Backpack begitu karakter menyentuhnya -- jalur itu MELEWATI prompt,
	sehingga KeyService tidak pernah tahu kuncinya sudah diambil dan pintu
	tetap terkunci walau pemain memegang kuncinya. Dua pengaman di bawah:
	  1. Handle.CanTouch = false  -> matikan auto-pickup, prompt jadi satu-satunya jalan
	  2. AncestryChanged watcher  -> kalau Tool tetap sampai ke pemain lewat jalur
	                                 lain, KeyId dicatat juga (tidak ada kunci "hantu")
--]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Config = require(script.Parent.Config)

local KeyPickupManager = {}
KeyPickupManager.__index = KeyPickupManager

function KeyPickupManager.new(keyService: any, onKeyGranted: ((keyId: string) -> ())?)
	local self = setmetatable({}, KeyPickupManager)
	self._keyService = keyService
	self._onKeyGranted = onKeyGranted
	self._registered = {} :: { [Instance]: boolean }
	return self
end

local function resolvePart(inst: Instance): BasePart?
	if inst:IsA("BasePart") then
		return inst
	elseif inst:IsA("Model") then
		return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart")
	end
	return nil
end

--- Cari Player pemilik sebuah instance (Tool di Backpack atau di Character).
local function ownerOf(inst: Instance): Player?
	local parent = inst.Parent
	if not parent then return nil end
	-- Tool di Backpack: Parent = Backpack, Parent.Parent = Player
	local player = Players:GetPlayerFromCharacter(parent)
	if player then return player end
	if parent:IsA("Backpack") then
		local p = parent.Parent
		if p and p:IsA("Player") then return p end
	end
	return nil
end

--- Pindahkan Tool ke Backpack pemain. Mengembalikan true kalau berhasil.
local function giveToolToPlayer(tool: Tool, player: Player): boolean
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return false
	end
	-- Buang prompt: kalau Tool di-equip, Handle-nya pindah ke Character (di
	-- Workspace), jadi prompt lama akan muncul lagi & bisa di-trigger ulang.
	for _, d in ipairs(tool:GetDescendants()) do
		if d:IsA("ProximityPrompt") then
			d:Destroy()
		end
	end
	tool.Parent = backpack
	return true
end

function KeyPickupManager:register(inst: Instance)
	if self._registered[inst] then return end

	local part = resolvePart(inst)
	if not part then
		warn("[KeySystem] KeyPickup '" .. inst.Name .. "' tidak punya BasePart. Skip.")
		return
	end

	local keyId = inst:GetAttribute("KeyId") or Config.DefaultKeyId
	local keepInWorld = inst:GetAttribute("KeepInWorld") == true
	local isToolPickup = inst:IsA("Tool") and Config.KeyToolToBackpack and not keepInWorld

	local prompt = part:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.HoldDuration = Config.PromptHoldDuration
		prompt.MaxActivationDistance = Config.PromptMaxDistance
		prompt.RequiresLineOfSight = false
		prompt.Parent = part
	end
	prompt.ActionText = Config.PromptKeyPickup

	-- Matikan auto-pickup engine (lihat CATATAN di header) supaya prompt jadi
	-- satu-satunya jalur masuk dan KeyService selalu tercatat.
	if inst:IsA("Tool") and Config.KeyToolBlockTouchPickup then
		part.CanTouch = false
	end

	self._registered[inst] = true

	-- Prompt bisa ter-trigger lebih dari sekali sebelum objeknya beres.
	local granted = false

	local function grant(keyIdToGrant: string)
		self._keyService:grantKey(keyIdToGrant)
		if self._onKeyGranted then
			self._onKeyGranted(keyIdToGrant)
		end
	end

	prompt.Triggered:Connect(function(player)
		if granted and not keepInWorld then return end

		grant(keyId)

		if keepInWorld then
			return -- kunci dibiarkan apa adanya, pemain lain masih bisa ambil
		end

		granted = true

		if isToolPickup then
			if player and player.Parent == Players and giveToolToPlayer(inst, player) then
				return
			end
			-- Backpack tidak ada (pemain keluar tepat saat mengambil): hapus,
			-- jangan tinggalkan kunci separuh jalan.
			warn("[KeySystem] Backpack pemain tidak ditemukan, kunci '" .. inst.Name .. "' dihapus.")
		end

		inst:Destroy()
	end)

	-- Pengaman: kalau Tool sampai ke pemain lewat jalur selain prompt, catat
	-- juga KeyId-nya. Tanpa ini pemain bisa memegang kunci sambil pintunya
	-- tetap bilang "Terkunci".
	if inst:IsA("Tool") and not keepInWorld then
		inst.AncestryChanged:Connect(function()
			if granted then return end
			if ownerOf(inst) then
				granted = true
				grant(keyId)
			end
		end)
	end
end

function KeyPickupManager:start()
	for _, inst in CollectionService:GetTagged(Config.KeyPickupTag) do
		self:register(inst)
	end
	CollectionService:GetInstanceAddedSignal(Config.KeyPickupTag):Connect(function(inst)
		self:register(inst)
	end)
end

return KeyPickupManager
