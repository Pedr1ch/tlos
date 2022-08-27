-- BELIEVE IT OR NOT I ACTUALLY COMMITED 1.0.1 IN GITHUB WITH THIS BLANK CRAP LOL
-- BY THE WAY PART OF THIS SCRIPT WAS MADE BY BOATBOMBER, GO FOLLOW HIM!
-- by pedrich
-- globalstorage module by boatbomber

-- /PedrichWasTaken, /boatbomber

local deviceIdSvc


--[[
-- GLOBAL STORAGE MODULE IS MADE BY BOATBOMBER
-- you can use this if you want your data to be global at all games that are made from 
-- your team / group;
	GlobalStorage
	by boatbomber (c) 2021
	This is a module for handling data that can be read from/written to
	from multiple servers at a time. It is made only for commutative updates.
	This is so that your operations can be applied locally and globally at different
	times and still end up at the same value eventually. Uses MemoryStore for atomic locking.
	Make sure your transform function is deterministic and has no side effects,
	as it will be run twice- once locally and once globally. If it absolutely must,
	then it can take in a second arguement, a boolean "isGlobal" that is true when being
	run globally and false during the local run.
	Examples:
		local PlayerStore = GlobalStorage:GetStore("User_1234")
		local DEFAULT_COINS = 100
		-- Can be used to safely +/- number stores
		local coins = PlayerStore:Get("Coins", DEFAULT_COINS)
		PlayerStore:Update("Coins", function(oldValue)
			return (oldValue or DEFAULT_COINS) + 5
		end)
		coins = PlayerStore:Get("Coins", DEFAULT_COINS)
		-- Can be used to safely add/remove unique dict keys
		local notifications = PlayerStore:Get("Notifications", {})
		PlayerStore:Update("Notifications", function(oldValue)
			return (oldValue or {})[GUID] = newNotif
		end)
		notifications = PlayerStore:Get("notifications", {})
--]] local replicatedstorage = game:GetService('ReplicatedStorage') local RunSvc = game:GetService('RunService')
-- GLOBAL DATA SAVE, by Boatbomber
local DataStoreService = game:GetService("DataStoreService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local MessagingService = game:GetService("MessagingService")
local Network = require(replicatedstorage.modules.modules.network)
local GlobalStorage = {
	_cache = {},
}

function GlobalStorage.new(name: string)
	-- Get existing store object if possible
	if GlobalStorage._cache[name] then
		return GlobalStorage._cache[name]
	end

	-- Create new store object
	local Store = {
		_dsStore = DataStoreService:GetDataStore(name),
		_msMap = MemoryStoreService:GetSortedMap(name),
		_cache = {},
		_msgId = "BS_" .. name,
		_updateQueue = {},
		_events = {},
		_destroyed = false,
	}

	function Store:_flushUpdateQueue()
		for key, transformers in pairs(self._updateQueue) do
			if #transformers < 1 then
				continue
			end

			task.spawn(function()
				-- DataStore UpdateAsync can conflict with other servers if called at the exact same time
				-- and race so whichever finishes last will overwrite the previous.
				-- MemoryStore UpdateAsync solves this by retrying if two are called at once, so we use
				-- that as a locking mechanism to avoid two DataStore updates overwriting. If two try to grab
				-- while unlocked, MemoryStore will force one of them to retry later.

				local unlocked, lockWaitTime = false, 0
				while unlocked == false do
					local success, message = pcall(function()
						self._msMap:UpdateAsync(key, function(lockOwner)
							if lockOwner ~= nil then
								return nil -- Someone else has this key rn, we must wait
							end

							unlocked = true

							-- Since other servers trying to take it will be returning
							-- different JobId, memorystore will know its a conflict
							-- and force the others to retry
							return game.JobId
						end, 30)
					end)
					if not success then
						warn(message)
					end

					if unlocked == false then
						lockWaitTime += task.wait()
						if lockWaitTime > 60 then
							warn(
								"Update flush for "
									.. key
									.. " expired after 60 seconds while waiting for lock to be available."
							)
							return
						end
					end
				end

				self._dsStore:UpdateAsync(key, function(storedValue)
					local value = storedValue

					for i, transformer in ipairs(transformers) do
						local success, newValue = pcall(transformer, value, true)
						if not success then
							warn(newValue)
							continue -- skip this one, transform errored
						end

						if newValue == nil then
							continue -- skip this one, transform exited
						end

						value = newValue
					end
					table.clear(transformers)

					self._cache[key] = value

					-- Inform other servers they need to refresh
					task.defer(function()
						local publishSuccess, publishResult = pcall(function()
							MessagingService:PublishAsync(self._msgId, {
								JobId = game.JobId,
								Key = key,
							})
						end)
						if not publishSuccess then
							warn(publishResult)
						end
					end)

					return value
				end)

				-- Unlock this key for the next server to take

				pcall(self._msMap.RemoveAsync, self._msMap, key)
			end)
		end
	end

	function Store:GetKeyChangedSignal(key: string)
		local event = self._events[key]
		if not event then
			event = Instance.new("BindableEvent")
			self._events[key] = event
		end
		return event.Event
	end

	function Store:Get(key: string, default: any?, skipCache: boolean?)
		if not skipCache and self._cache[key] ~= nil then
			return self._cache[key] or default
		end

		local value = self._dsStore:GetAsync(key)

		if value == nil then
			value = default
		end

		self._cache[key] = value
		return value
	end

	function Store:Update(key: string, transformer: (any?, boolean?) -> any?)
		-- Queue it up for updating on the latest real value & replication
		if self._updateQueue[key] == nil then
			self._updateQueue[key] = { transformer }
		else
			table.insert(self._updateQueue[key], transformer)
		end

		-- First, perform it locally
		local success, newValue = pcall(transformer, self._cache[key], false)
		if not success then
			warn(newValue)
			return -- cancel, transform errored
		end

		if newValue == nil then
			return -- cancel, transform exited
		end

		self._cache[key] = newValue
		local event = self._events[key]
		if event then
			event:Fire(newValue)
		end
	end

	function Store:Destroy()
		GlobalStorage._cache[name] = nil

		self._destroyed = true
		self:_flushUpdateQueue()

		for _, event in pairs(self._events) do
			event:Destroy()
		end
		if self._msgConnection ~= nil then
			self._msgConnection:Disconnect()
		end

		table.clear(self)
	end

	task.spawn(function()
		-- Subscribe to store's msg for cross-server updates
		local subscribeSuccess, subscribeConnection = pcall(function()
			return MessagingService:SubscribeAsync(Store._msgId, function(message)
				if game.JobId == message.Data.JobId then
					return
				end

				local key = message.Data.Key
				--print(name, "/", key, "was updated by another server")

				local newValue = Store:Get(key, Store._cache[key], true)
				local event = Store._events[key]
				if event then
					event:Fire(newValue)
				end
			end)
		end)
		if subscribeSuccess then
			Store._msgConnection = subscribeConnection
		else
			warn(subscribeConnection)
		end

		-- Start update queue flush thread
		while not Store._destroyed do
			local jitter = math.random(0, 100) / 100 -- Reduce server conflicts?
			task.wait(6 + jitter)

			Store:_flushUpdateQueue()
		end
	end)

	-- Cache the store object for future GetStore sharing
	GlobalStorage._cache[name] = Store
	return Store
end

game:BindToClose(function()
	for _, Store in pairs(GlobalStorage._cache) do
		Store:_flushUpdateQueue()
	end
end
)

local function NewGlobalStorageJob(name: string)
	-- Get existing store object if possible
	if GlobalStorage._cache[name] then
		return GlobalStorage._cache[name]
	end

	-- Create new store object
	local Store = {
		_dsStore = DataStoreService:GetDataStore(name),
		_msMap = MemoryStoreService:GetSortedMap(name),
		_cache = {},
		_msgId = "BS_" .. name,
		_updateQueue = {},
		_events = {},
		_destroyed = false,
	}

	function Store:_flushUpdateQueue()
		for key, transformers in pairs(self._updateQueue) do
			if #transformers < 1 then
				continue
			end

			task.spawn(function()
				-- DataStore UpdateAsync can conflict with other servers if called at the exact same time
				-- and race so whichever finishes last will overwrite the previous.
				-- MemoryStore UpdateAsync solves this by retrying if two are called at once, so we use
				-- that as a locking mechanism to avoid two DataStore updates overwriting. If two try to grab
				-- while unlocked, MemoryStore will force one of them to retry later.

				local unlocked, lockWaitTime = false, 0
				while unlocked == false do
					local success, message = pcall(function()
						self._msMap:UpdateAsync(key, function(lockOwner)
							if lockOwner ~= nil then
								return nil -- Someone else has this key rn, we must wait
							end

							unlocked = true

							-- Since other servers trying to take it will be returning
							-- different JobId, memorystore will know its a conflict
							-- and force the others to retry
							return game.JobId
						end, 30)
					end)
					if not success then
						warn(message)
					end

					if unlocked == false then
						lockWaitTime += task.wait()
						if lockWaitTime > 60 then
							warn(
								"Update flush for "
									.. key
									.. " expired after 60 seconds while waiting for lock to be available."
							)
							return
						end
					end

					for i, transformer in ipairs(transformers) do
						local success, newValue = pcall(transformer, value, true)
						if not success then
							warn(newValue)
							continue -- skip this one, transform errored
						end

						if newValue == nil then
							continue -- skip this one, transform exited
						end

						value = newValue
					end
					table.clear(transformers)

					self._cache[key] = value

					-- Inform other servers they need to refresh
					task.defer(function()
						local publishSuccess, publishResult = pcall(function()
							MessagingService:PublishAsync(self._msgId, {
								JobId = game.JobId,
								Key = key,
							})
						end)
						if not publishSuccess then
							warn(publishResult)
						end
					end)

					return value
				end

				-- Unlock this key for the next server to take

				pcall(self._msMap.RemoveAsync, self._msMap, key)
			end)
		end
	end

	function Store:GetKeyChangedSignal(key: string)
		local event = self._events[key]
		if not event then
			event = Instance.new("BindableEvent")
			self._events[key] = event
		end
		return event.Event
	end

	function Store:Get(key: string, default: any?, skipCache: boolean?)
		if not skipCache and self._cache[key] ~= nil then
			return self._cache[key] or default
		end

		local value = self._dsStore:GetAsync(key)

		if value == nil then
			value = default
		end

		self._cache[key] = value
		return value
	end

	function Store:Update(key: string, transformer: (any?, boolean?) -> any?)
		-- Queue it up for updating on the latest real value & replication
		if self._updateQueue[key] == nil then
			self._updateQueue[key] = { transformer }
		else
			table.insert(self._updateQueue[key], transformer)
		end

		-- First, perform it locally
		local success, newValue = pcall(transformer, self._cache[key], false)
		if not success then
			warn(newValue)
			return -- cancel, transform errored
		end

		if newValue == nil then
			return -- cancel, transform exited
		end

		self._cache[key] = newValue
		local event = self._events[key]
		if event then
			event:Fire(newValue)
		end
	end

	function Store:Destroy()
		GlobalStorage._cache[name] = nil

		self._destroyed = true
		self:_flushUpdateQueue()

		for _, event in pairs(self._events) do
			event:Destroy()
		end
		if self._msgConnection ~= nil then
			self._msgConnection:Disconnect()
		end

		table.clear(self)
	end

	task.spawn(function()
		-- Subscribe to store's msg for cross-server updates
		local subscribeSuccess, subscribeConnection = pcall(function()
			return MessagingService:SubscribeAsync(Store._msgId, function(message)
				if game.JobId == message.Data.JobId then
					return
				end

				local key = message.Data.Key
				--print(name, "/", key, "was updated by another server")

				local newValue = Store:Get(key, Store._cache[key], true)
				local event = Store._events[key]
				if event then
					event:Fire(newValue)
				end
			end)
		end)
		if subscribeSuccess then
			Store._msgConnection = subscribeConnection
		else
			warn("error while making globalstore, failure in subscribe connection. (ln455): "..subscribeConnection)
		end

		-- Start update queue flush thread
		while not Store._destroyed do
			local jitter = math.random(0, 100) / 100 -- Reduce server conflicts?
			task.wait(6 + jitter)

			Store:_flushUpdateQueue()
		end
	end)

	-- Cache the store object for future GetStore sharing
	GlobalStorage._cache[name] = Store
	return Store
end






modes = {
	debugModeEnabled=false,
	debugPrint=false,
	testing=false,
	normalPlayingPov=true,
	Playing=true,
	scripting=false,
	programming=false,
	dataStructureModeling=true,
	setDataAsNormalStructureTest=true,
}
local NewJob = NewGlobalStorageJob('globalstore')
-- SERVER JOBS by Pedro
local dss = game:GetService('DataStoreService')
print('PedroServer BEGAN: Processing Script Data SERVER JOBS AT LINE 255 ')
local store = dss:GetDataStore('store')
local dataStructure = {
	['Number']={
		['Hp']={50,"HP"},
		['Level']={1,"Level"},
		['XP']={0,"XP"},
		['Gold']={50,"Gold"},
		['Stats']={
			['DEX']={0,'DEX'},
			['CRIT']={0,'CRIT'},
			['MGP']={0,'MGP'},
			['ATK']={0,'ATK'},
			['VIT']={0,'VIT'},
			['GRD']={0,'GRD'},
			['LUCK']={1.0,'LUCK'},
			['DEF']={0,'DEF'}
		},
	},
	['BuildExpecifications']={
		['AvaibleSkillPoints']=99999,
		['SkillsAchieved']={

		},
		['RightHand']={},
		['LeftHand']={},
		['Boots']={},
		['Armor']={
			['Name'] = "Null Armor",
			['Defense'] = 0
		},
		['Weapon'] = {
			['Name'] = "Wood Stick",
			['Attack'] = 9,
		},
		['Hat']={},
		['Pet']={},
		['Amulet']={},
	},
	['GONER_INFORMATION']={
		['VesselName']='nil',
		['VesselCharacter']={}
	},
	['Character']={
		['Hair']="Adventurer's Hair",
		['HairColor']="Brown",
		['Face']="Man's Face",
		['SkinColor']='Normal White',
	},
	['Quests']={
		['Stats']={
			['Nasty Blobs #1']={
				['KilledBlobs']=10
			}
		},
		['Finished']={},
		['Active']={
			"Nasty Blobs #1"
		},
		['Unknown']={
			"Dave's Hunter Quest #1",
			"Dave's Hunter Quest #2",
			"Queen's Dinner",
			"The Lost Crown",
			"Butterfly Catcher",
			"Nasty Blobs #2",
			"Bloopies!?",
			"Annoying Bloops",
			"Oh my GOD! Groot real?",
			"I'm going to chop down those groots",
			"Fisher's Stats!",
			"I want to be more Lucky #1",
			"I want to be more Lucky #2",
			"A Gross Job",
			"The Forgotten Fish",
		},
	},
	['Inventory']={
		['Equipment']={
			['Wood Stick']={
				['Enchantments']={},
				['Equipped']=true,
				['Hand']='LeftHand',
				['BonusDamage']=5,
				['NormalDamage']=10,
				['StrongDamage']=15,
				['CritDamage']=25
			}
		},
		['Comsumables']={
			"Pedro's Dev Gift"
		},
		['Materials']={}
	},
	['Actions']={

	},

}
profileDataPOG = true
local function saveClient(Client: Player)
	local s,ren = pcall(function()
		local newSync = store:GetAsync(Client.UserId)
		if newSync == nil then
			newSync = dataStructure
			return 
		end
		if newSync[4] == nil then
			local Armor = Client:WaitForChild('Armor').Value
			print("SaveClientFFlag: LOADED ARMOR")
			newSync.BuildExpecifications.Armor.Name = Armor
			print("SaveClientFFlag: SETTED ARMORNAME ("..Armor..")")
			newSync.BuildExpecifications.Armor.Defense = require(game.ReplicatedStorage.modules.itemData[Armor]).points
			print("SaveClientFFlag: LOADED DEFENSE POINTS ("..require(game.ReplicatedStorage.modules.itemData[Armor]).points..")")
			local newTable = newSync
			local tats = Client:WaitForChild('Stats')
			for _,x in pairs(tats:GetChildren()) do
				if x.Name == 'Stats' or x.Name == "Value" then
					-- yield
				else
					newTable.Number.Stats[x.Name][1] = x.Value
				end
			end
			for _,v in pairs(Client.NumberPrincipals:GetChildren()) do
				if v:IsA('NumberValue') then
					if newTable.Number[v.Name] == nil then
					else
						newTable.Number[v.Name][1]=v.Value
					end

				else
					warn("saving:origin value is not a value at dataStructure?")
				end
			end
			for _,v in pairs(Client.Stats:GetChildren()) do
				if v:IsA('NumberValue') then
					newTable.Number.Stats[v.Name][1]=v.Value
				else
					if modes.debugPrint and modes.debugModeEnabled == true then
						warn("saving:origin value is not a value at dataStructure?")
					else	
					end
				end
			end
			store:SetAsync(tostring(Client.UserId),newTable)
		else
			local newTable = newSync
			local STATS = Client:WaitForChild('Stats') or nil
			if STATS == nil then
				STATS = Instance.new("Folder")
				STATS.Name = 'Stats'
				STATS.Parent = Client
			end
			for _,v in pairs(STATS:GetChildren()) do
				if newTable.Number.Stats == nil then
					return print('stats nil')
				end
				newTable.Number.Stats[v.Name][1] = v.Value
			end
			for _,v in pairs(Client.NumberPrincipals:GetChildren()) do
				if v:IsA('NumberValue') then
					newTable.Number[v.Name][1]=v.Value
				else
					warn("saving:origin value is not a value at dataStructure?")
				end
			end
			for _,v in pairs(Client.Stats:GetChildren()) do
				if v:IsA('NumberValue') then
					newTable.Number.Stats[v.Name][1]=v.Value
				else
					warn("saving:origin value is not a value at dataStructure?")
				end
			end
			store:SetAsync(tostring(Client.UserId),newTable,{Client.UserId})
		end

	end)
	if s then
		-- not as debug.
	else
		warn('FATAL FLAW: '..ren)
	end
end
game.Players.PlayerRemoving:Connect(function(Player)
	saveClient(Player)
	print("Saved;")
end)
game.Players.PlayerAdded:Connect(function(player)
	local Player = player
	local CommunicationHelperEvents = Instance.new("Folder")
	local CancelAnnouncementsThreads = Instance.new("BindableEvent")
	CommunicationHelperEvents.Name = "CommunicationHelperEvents"
	CancelAnnouncementsThreads.Name = "CancelAnnouncementThread"
	CommunicationHelperEvents:Clone().Parent = Player
	CancelAnnouncementsThreads:Clone().Parent = Player.CommunicationHelperEvents
	local YieldG = Instance.new("BindableEvent")
	YieldG.Name = "YieldG"
	YieldG:Clone().Parent = CommunicationHelperEvents
	CancelAnnouncementsThreads.Event:Connect(function()
		print("STOPPED")
	end)
	YieldG.Event:Connect(function()
		if Player.PlayerGui.main.Enabled == false then
			Player.PlayerGui.main.Enabled = true
		else
			Player.PlayerGui.main.Enabled = false
		end
	end)
	if modes.setDataAsNormalStructureTest == true then
		store:SetAsync(player.UserId,dataStructure)
	end

	local e = Instance.new('Folder')
	e.Name = 'Stats'
	e.Parent = player
	local success,errorm = pcall(function()
		return store:GetAsync(player.UserId) or dataStructure 
	end)
	local dataValue = Instance.new('StringValue')
	dataValue.Name = "Data"
	dataValue.Value = require(replicatedstorage.modules.repr)(errorm)
	dataValue:Clone().Parent = player
	if errorm.Number.Stats.ATK == nil then
		warn('CHANGED THE STATS OF DATA (CANCELLED), POSSIBLY CORRUPTED! IF YOURE A PLAYER SEEING THIS, YOU SHOULD TAKE CARE OF YOUR DATA OR MAKE A BACKUP USING THE BACKUP SYSTEM')
		-- set data as datastructure
		store:SetAsync(player.UserId,dataStructure)
		wait()
	end
	local numPrincipals = Instance.new("Folder")
	numPrincipals.Name = "NumberPrincipals"
	numPrincipals.Parent = player

	for _k,m in pairs(errorm.Number) do
		if m=='Stats' then
		else
			local ea2=Instance.new('NumberValue')
			if errorm.Number[_k].ATK == true or errorm.Number[_k]=='Stats' then
				-- ignore statname
				warn('ignored')
			else
				--TODO>	Fix Bugs. Possibly Glitched I KNEW IT. ( TODO:FINISHED )
				local s,e = pcall(function()
					if not errorm.Number[_k][6]==nil then
					else
						if typeof(errorm.Number[_k][1]) == "string" then
							ea2.Name = errorm.Number[_k][1] or 'IGNORED'
						else
							ea2.Name = errorm.Number[_k][2] or 'IGNORED'
						end
					end
				end)
				if ea2.Name == 'IGNORED' then
					ea2:Destroy()
				else
					ea2.Parent = numPrincipals
					ea2.Value = errorm.Number[_k][1]
				end
				if s then
					print('Success At ID@SetNumData::Global! TOKEN TIME :D -- '.._k)
				else
					print('FATAL_FLAW At ID@SetNumData::Global! TOKEN TIME AND ERROR D: -- '.._k..', '..e)
				end

			end

		end
	end
	for _,stat in pairs(errorm.Number.Stats) do
		local statInstance = Instance.new('NumberValue')
		statInstance.Name = stat[2]
		statInstance.Value = stat[1]
		statInstance:Clone().Parent = e
		warn('created stat '..stat[2])
	end
	local armorInstance = Instance.new("StringValue")
	armorInstance.Name = "Armor"
	armorInstance.Value = errorm.BuildExpecifications.Armor.Name or "Null Armor"
	armorInstance.Parent = player
	local armorInstance = Instance.new("StringValue")
	armorInstance.Name = "Weapon"
	armorInstance.Value = errorm.BuildExpecifications.Weapon.Name or "Null Weapon"
	armorInstance.Parent = player
	--[[local function LOAD_EQUIPMENT()
		local inventory = errorm.Inventory
		local equipment = inventory.Equipment
		local Weapons = replicatedstorage.Weapons
		for _,weapon in pairs(Weapons:GetChildren()) do
			if equipment[weapon.Name] == true then
				weapon:Clone().Parent = player.Backpack
			else
	            warn('dont exist')
			end
		end
	end
	LOAD_EQUIPMENT()]]
	if success == true then
		print("success")
	else
		warn(errorm)
	end
	store:SetAsync(tostring(player.UserId),errorm,{player.UserId})
end) --> load client


local function onGameCloseBind()
	if RunSvc:IsStudio() then
		wait(4)
	end
	for _,v in pairs(game.Players:GetChildren()) do
		saveClient(v)
	end
end
game:BindToClose(onGameCloseBind)
--[[function zpcall(func)
	local success, errorm = pcall(func)
	if success then
		return print('success')
	else
		return print('error '..errorm)
	end
end
--> ZPCALL: BETA
-- Server Location Module
local PedriChservices = game.ReplicatedStorage.PedrichServices
local ServerLocateService = require(PedriChservices.ServerLocateService)
ServerLocateService.Locate()]]

print('[STARTING] Now Section REMOTES!')
--> remote handler, imagine
-- we did that didnt we
--> DONT NEED ZPCALL :flushed_toilet:

local INCREMENT
local HttpService = game:GetService("HttpService")

local HeatUp = require(script.HeatUp)
local Store = HeatUp.new("store")

print("[STARTING] Now Section SAVING IT TO THE SERVER ")
-- pain.
-- hotkey updater: DATA
-- why cooldown, but NOT HEAT UP? 👿

-- ratio.
-- by pedrich :)

print('started other section --> line 810, data.')

local MyDateTime = DateTime.now()
-- sync post
game.ReplicatedStorage.modules.modules.network.signals.getPlayerData_Signal.OnServerInvoke = function(p, player)
	if player ~= nil then
		return store:GetAsync(player.UserId) or dataStructure
	else
		return store:GetAsync(p.UserId) or dataStructure
	end

end
--> quests

local HttpService = game:GetService("HttpService")

local HeatUp = require(script.HeatUp)
local Store = HeatUp.new("store")

--> both gs and heat are not working right now, data is at beta number 1
--> now the good stuff...

print("SetArmorDataConnect")
local modules = game.ReplicatedStorage.modules
local signals = modules.modules.network.signals


signals.playerSettedArmorData_Signal.OnServerEvent:Connect(function(player, newArmor: string)
	local playerData = store:GetAsync(player.UserId)
	playerData.BuildExpecifications.Armor["Name"] = newArmor
	playerData.BuildExpecifications.Armor["Defense"] = require(game.ReplicatedStorage.modules.itemData)[newArmor].points
	print("SETTED ARMOR DATA:"..newArmor)
end)
signals.playerSettedArmorValue_Signal.OnServerEvent:Connect(function(player, newArmor: string)
	player.Armor.Value = newArmor
end)
signals.playerSettedArmorValue_Signal.OnServerEvent:Connect(function(player, value)
	player.Weapon.Value = value
end)
signals.playerSettedWeaponData_Signal.OnServerEvent:Connect(function(player, newWeapon: string)
	local playerData = store:GetAsync(player.UserId)
	playerData.BuildExpecifications.Weapon["Name"] = newWeapon
	playerData.BuildExpecifications.Weapon["Defense"] = require(game.ReplicatedStorage.modules.itemData)[newArmor].points
	print("SETTED WEAPON DATA:".. newWeapon)
end)
signals.playerEquippedItem_Signal.OnServerEvent:Connect(function(player, item: string)
	local itemData = require(game.ReplicatedStorage.modules.itemData[item])
	if itemData.manifestType:lower() == "armor" then
		local playerCharacter = workspace[player.Name]
		for index, value in pairs(playerCharacter:GetChildren()) do
			if value:IsA("Model") and value:FindFirstChildWhichIsA("Weld") then
				return "Already Equipped equipment of the same type. Unequip the current equipment with the requested type and equip the equipment you want."
			else

				break
			end
		end
		local itemManifest = itemData.manifest:Clone()
		itemManifest.Name = itemData.manifestName
		itemManifest.AccessoryWeld.Part1 = playerCharacter.ArmorHitBox.Torso
		itemManifest.Parent = player
	end
end)
signals.playerDropItem_Signal.OnServerEvent:Connect(function(player, item: string)
	local itemModule = require(game.ReplicatedStorage.modules.itemData[item])
	local itemManifest = itemModule.manifest:Clone()
	local itemType = itemModule.manifestType
	if itemType:lower() == "armor" then
		if item then
			if item == player.Armor.Value then
				player.Character[item]:Destroy()
			end
			itemManifest.Name = "debris_"..math.random(1,1201921201120)
			itemManifest.PrimaryPart.CFrame = player.Character.HumanoidRootPart.CFrame * player.Character.HumanoidRootPart.CFrame + 6
			itemManifest.Parent = workspace.Debris

		end
	end
end)
print("PaddedConnect2FFlag")
game.Players.PlayerAdded:Connect(function(player)
	workspace:WaitForChild(player.Name).Parent = workspace.Entities.Players
	local playerData = store:GetAsync(player.UserId) or dataStructure
	print("PaddedConnect2FFlag:: LOADED DATA")
	if rawequal(playerData, dataStructure) == true then
		return print("Its true 😳;")
	end
	local armor = playerData.BuildExpecifications.Armor["Name"]
	if armor == "Null Armor" then
		print("PaddedConnect2FFlag:: ARMOR IS SET AS NIL;")
	else
		local armorInst = modules.itemData[armor].manifest:Clone()
		print("PaddedConnect2FFlag:: CLONED MANIFEST;")
		armorInst.Name = armor
		armorInst.Parent = player.Character
		for i,v in pairs(armorInst:GetChildren()) do
			if v:IsA("Weld") then
				print("PaddedConnect2FFlag:: SETTED WELD;")
				v.Part1 = player.Character:WaitForChild('ArmorHitBox').PrimaryPart
			else
				print("PaddedConnect2FFlag:: ZERO'ED TRANSPARENCY;")
				v.Transparency = 0
			end
		end

	end
	local weapon = playerData.BuildExpecifications.Weapon["Name"]
	if weapon == "Null Weapon" then
		print("PaddedConnect2FFlag:: WEAPON IS SET AS NIL;")
	else
		local weaponInst = game.ReplicatedStorage.modules.itemData[weapon].manifest:Clone()
		print("PaddedConnect2FFlag:: CLONED MANIFEST FOR WEAPON;")
		weaponInst.Name = weapon
		weaponInst.Handle.AccessoryWeld.Part1 = player.Character.RightHand
		weaponInst.Parent = player.Character
	end
	local __hair, __faces = game.ReplicatedStorage.characterHair, game.ReplicatedStorage.characterFaces
	local face, hair = playerData.Character.Face, playerData.Character.Hair
	local SkinColor = playerData.Character.SkinColor
	print("Skin Color Data: ")
	local BodyColors = player.Character["Body Colors"]
	local colors = require(game.ReplicatedStorage.modules.colorsLookup)
	local SkinColors = colors.SkinColors
	BodyColors.RightArmColor3 = SkinColors[SkinColor]
	BodyColors.LeftArmColor3 = SkinColors[SkinColor]
	BodyColors.HeadColor3 = SkinColors[SkinColor]
	if player.Name == "Phroaguz" or "Jibanyan1220" or "cafcover" or "Kuncheon1"  or "freezegirl1114" then
		face = "Shrek Harvey"
	end
	if hair == "Bald" then
	else
		local hairModel = __hair[hair]:Clone()
		hairModel.Color.Value = playerData.Character.HairColor
		--hairModel.Handle.HairAttachment.Attachment1 = player.Character.Head.HairAttachment @@@@@NO LOL
		hairModel.Handle.AccessoryWeld.Part1 = player.Character.Head
		hairModel.Parent = player.Character
	end
	player.Character.Head.face.Texture = __faces[face].Texture
end)
--pedrich#1561
print("Loaded "..script.Name)
