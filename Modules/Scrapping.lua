---@class LibRTC
local LibRTC = LibStub('AceAddon-3.0'):GetAddon('Libs-RemixPowerLevel')
---@class LibRTC.Module.Scrapping : AceModule, AceEvent-3.0, AceTimer-3.0
local module = LibRTC:NewModule('Scrapping', 'AceEvent-3.0', 'AceTimer-3.0')
module.DisplayName = 'Auto Scrapper'
module.description = 'Automatically scrap items based on filters'

-- Debug flag - set to true to enable detailed logging
local detailedLogs = false

-- Constants
local SCRAPPING_MACHINE_MAX_SLOTS = 9

-- Known Legion Remix Affixes (alphabetically sorted)
local KNOWN_AFFIXES = {
	['Arcane Aegis'] = 1232720,
	['Arcane Ward'] = 1242202,
	['Brewing Storm'] = 1258587,
	['Highmountain Fortitude'] = 1234683,
	['I Am My Scars!'] = 1242022,
	["Light's Vengeance"] = 1251666,
	['Souls of the Caw'] = 1235159,
	['Storm Surger'] = 1241854,
	['Temporal Retaliation'] = 1232262,
	['Terror From Below'] = 1233595,
	['Touch of Malice'] = 1242992,
	['Volatile Magics'] = 1234774
}

-- Common stats to blacklist (separate dropdown)
local KNOWN_STATS = {
	'Avoidance',
	'Critical Strike',
	'Haste',
	'Leech',
	'Mastery',
	'Speed',
	'Versatility'
}

-- Map inventory types to equipment slots
local ITEM_TO_INV_SLOT = {
	[Enum.InventoryType.IndexHeadType] = 1,
	[Enum.InventoryType.IndexNeckType] = 2,
	[Enum.InventoryType.IndexShoulderType] = 3,
	[Enum.InventoryType.IndexBodyType] = 4,
	[Enum.InventoryType.IndexChestType] = 5,
	[Enum.InventoryType.IndexWaistType] = 6,
	[Enum.InventoryType.IndexLegsType] = 7,
	[Enum.InventoryType.IndexFeetType] = 8,
	[Enum.InventoryType.IndexWristType] = 9,
	[Enum.InventoryType.IndexHandType] = 10,
	[Enum.InventoryType.IndexFingerType] = {11, 12},
	[Enum.InventoryType.IndexTrinketType] = {13, 14},
	[Enum.InventoryType.IndexCloakType] = 15,
	[Enum.InventoryType.IndexRobeType] = 5,
	[Enum.InventoryType.IndexWeaponType] = 16,
	[Enum.InventoryType.IndexShieldType] = 17,
	[Enum.InventoryType.Index2HweaponType] = 16,
	[Enum.InventoryType.IndexWeaponmainhandType] = 16,
	[Enum.InventoryType.IndexWeaponoffhandType] = 17
}

---@class ScrappableItem
---@field bagID number
---@field slotID number
---@field level number
---@field invType Enum.InventoryType
---@field quality Enum.ItemQuality
---@field link string
---@field location ItemLocation

---@class LibRTC.Module.Scrapping.DB
local DbDefaults = {
	enabled = true,
	autoScrap = true,
	maxQuality = Enum.ItemQuality.Rare,
	minLevelDiff = 0,
	affixBlacklist = {},
	scrappingListManualHide = false,
	notInGearset = true,
	notWeapons = (PlayerGetTimerunningSeasonID and PlayerGetTimerunningSeasonID() == 2) or false,
	useAdvancedFiltering = false,
	advancedFilters = {
		armor = {
			maxQuality = Enum.ItemQuality.Epic,
			minLevelDiff = 0
		},
		accessories = {
			maxQuality = Enum.ItemQuality.Rare,
			minLevelDiff = 0,
			keepHighestDuplicates = true
		}
	}
}

-- Tooltip scanner for detecting affixes
local scannerTooltip = CreateFrame('GameTooltip', 'LibsRemixPowerLevelScannerTooltip', nil, 'GameTooltipTemplate')
scannerTooltip:SetOwner(UIParent, 'ANCHOR_NONE')

-- Cache tables
local tooltipAffixCache = {} -- Cache keyed by itemLink
local gearsetCache = {} -- Cache keyed by "bag-slot"

function module:OnInitialize()
	module.Database = LibRTC.dbobj:RegisterNamespace('Scrapping', {profile = DbDefaults})
	module.DB = module.Database.profile ---@type LibRTC.Module.Scrapping.DB

	-- Add module options to parent addon options table
	self:InitializeOptions()
end

---Clear all caches
function module:ClearCaches()
	if detailedLogs and LibRTC and LibRTC.logger then
		LibRTC.logger.debug('ClearCaches: Clearing tooltip and gearset caches')
	end
	tooltipAffixCache = {}
	gearsetCache = {}
end

---Clear only the gearset cache (items moved in bags)
function module:ClearGearsetCache()
	gearsetCache = {}
end

---Add scrapping options to parent addon options
function module:InitializeOptions()
	if not LibRTC.OptTable then
		return
	end

	LibRTC.OptTable.args.scrapping = {
		type = 'group',
		name = 'Auto Scrapper',
		order = 30,
		args = {
			description = {
				type = 'description',
				name = 'Automatically scrap items at the scrapping machine based on filters.',
				order = 1,
				fontSize = 'medium'
			},
			enabled = {
				type = 'toggle',
				name = 'Enable Module',
				desc = 'Enable or disable the Auto Scrapper module entirely. When disabled, the UI will not be created.',
				order = 5,
				width = 'full',
				get = function()
					return self.DB.enabled
				end,
				set = function(_, value)
					self.DB.enabled = value
					if value then
						LibRTC:EnableModule('Scrapping')
					else
						LibRTC:DisableModule('Scrapping')
					end
				end
			},
			autoScrap = {
				type = 'toggle',
				name = 'Enable Auto Scrap',
				desc = 'Automatically fill the scrapping machine with items matching your filters',
				order = 10,
				width = 'full',
				disabled = function()
					return not self.DB.enabled
				end,
				get = function()
					return self.DB.autoScrap
				end,
				set = function(_, value)
					self.DB.autoScrap = value
				end
			},
			maxQuality = {
				type = 'select',
				name = 'Max Quality to Scrap',
				desc = 'Only scrap items up to this quality level',
				order = 11,
				width = 'full',
				disabled = function()
					return not self.DB.enabled
				end,
				values = {
					[Enum.ItemQuality.Common] = '|cffFFFFFFCommon|r',
					[Enum.ItemQuality.Uncommon] = '|cff1EFF00Uncommon|r',
					[Enum.ItemQuality.Rare] = '|cff0070DDRare|r',
					[Enum.ItemQuality.Epic] = '|cffA335EEEpic|r'
				},
				get = function()
					return self.DB.maxQuality
				end,
				set = function(_, value)
					self.DB.maxQuality = value
				end
			},
			minLevelDiff = {
				type = 'range',
				name = 'Min Item Level Difference',
				desc = 'Only scrap items this many levels below your equipped gear',
				order = 12,
				width = 'full',
				min = 0,
				max = 50,
				step = 1,
				disabled = function()
					return not self.DB.enabled
				end,
				get = function()
					return self.DB.minLevelDiff
				end,
				set = function(_, value)
					self.DB.minLevelDiff = value
				end
			},
			affixInfo = {
				type = 'description',
				name = '\nAffix blacklist management is available in the scrapping machine UI.',
				order = 20
			},
			advancedHeader = {
				type = 'header',
				name = 'Advanced Filtering',
				order = 30
			},
			advancedDescription = {
				type = 'description',
				name = 'Enable advanced filtering to set separate rules for armor (has stats) and accessories (has affixes).',
				order = 31,
				fontSize = 'medium'
			},
			useAdvancedFiltering = {
				type = 'toggle',
				name = 'Enable Advanced Filtering',
				desc = 'When enabled, use separate quality and ilvl settings for armor vs accessories. When disabled, the main quality dropdown applies to both.',
				order = 32,
				width = 'full',
				disabled = function()
					return not self.DB.enabled
				end,
				get = function()
					return self.DB.useAdvancedFiltering
				end,
				set = function(_, value)
					self.DB.useAdvancedFiltering = value
				end
			},
			notInGearset = {
				type = 'toggle',
				name = "Don't Scrap Items in Equipment Sets",
				desc = 'Protect items that are part of any equipment set from being scrapped.',
				order = 33,
				width = 'full',
				disabled = function()
					return not self.DB.enabled
				end,
				get = function()
					return self.DB.notInGearset
				end,
				set = function(_, value)
					self.DB.notInGearset = value
				end
			},
			notWeapons = {
				type = 'toggle',
				name = "Don't Scrap Weapons",
				desc = 'Protect all weapons from being scrapped. Enabled by default for Legion Remix (Season 2).',
				order = 34,
				width = 'full',
				disabled = function()
					return not self.DB.enabled
				end,
				get = function()
					return self.DB.notWeapons
				end,
				set = function(_, value)
					self.DB.notWeapons = value
				end
			},
			armorGroup = {
				type = 'group',
				name = 'Armor Settings',
				desc = 'Armor items have stats (Critical Strike, Haste, Mastery, Versatility, etc.)',
				order = 40,
				inline = true,
				disabled = function()
					return not self.DB.enabled or not self.DB.useAdvancedFiltering
				end,
				args = {
					armorMaxQuality = {
						type = 'select',
						name = 'Max Quality to Scrap',
						desc = 'Only scrap armor up to this quality level',
						order = 1,
						values = {
							[Enum.ItemQuality.Common] = '|cffFFFFFFCommon|r',
							[Enum.ItemQuality.Uncommon] = '|cff1EFF00Uncommon|r',
							[Enum.ItemQuality.Rare] = '|cff0070DDRare|r',
							[Enum.ItemQuality.Epic] = '|cffA335EEEpic|r'
						},
						get = function()
							return self.DB.advancedFilters.armor.maxQuality
						end,
						set = function(_, value)
							self.DB.advancedFilters.armor.maxQuality = value
						end
					},
					armorMinLevelDiff = {
						type = 'range',
						name = 'Min Item Level Difference',
						desc = 'Only scrap armor this many levels below your equipped gear',
						order = 2,
						min = 0,
						max = 50,
						step = 1,
						get = function()
							return self.DB.advancedFilters.armor.minLevelDiff
						end,
						set = function(_, value)
							self.DB.advancedFilters.armor.minLevelDiff = value
						end
					}
				}
			},
			accessoriesGroup = {
				type = 'group',
				name = 'Accessories Settings',
				desc = 'Accessories have affixes (special effects). Use Affix Blacklist to protect specific affixes.',
				order = 50,
				inline = true,
				disabled = function()
					return not self.DB.enabled or not self.DB.useAdvancedFiltering
				end,
				args = {
					accessoriesMaxQuality = {
						type = 'select',
						name = 'Max Quality to Scrap',
						desc = 'Only scrap accessories up to this quality level',
						order = 1,
						values = {
							[Enum.ItemQuality.Common] = '|cffFFFFFFCommon|r',
							[Enum.ItemQuality.Uncommon] = '|cff1EFF00Uncommon|r',
							[Enum.ItemQuality.Rare] = '|cff0070DDRare|r',
							[Enum.ItemQuality.Epic] = '|cffA335EEEpic|r'
						},
						get = function()
							return self.DB.advancedFilters.accessories.maxQuality
						end,
						set = function(_, value)
							self.DB.advancedFilters.accessories.maxQuality = value
						end
					},
					accessoriesMinLevelDiff = {
						type = 'range',
						name = 'Min Item Level Difference',
						desc = 'Only scrap accessories this many levels below your equipped gear',
						order = 2,
						min = 0,
						max = 50,
						step = 1,
						get = function()
							return self.DB.advancedFilters.accessories.minLevelDiff
						end,
						set = function(_, value)
							self.DB.advancedFilters.accessories.minLevelDiff = value
						end
					},
					keepHighestDuplicates = {
						type = 'toggle',
						name = 'Keep Only Highest iLvl Duplicate',
						desc = 'When you have multiple of the same accessory, only scrap the lower item level versions and keep the highest.',
						order = 3,
						width = 'full',
						get = function()
							return self.DB.advancedFilters.accessories.keepHighestDuplicates
						end,
						set = function(_, value)
							self.DB.advancedFilters.accessories.keepHighestDuplicates = value
						end
					}
				}
			}
		}
	}
end

function module:OnEnable()
	if not PlayerGetTimerunningSeasonID or PlayerGetTimerunningSeasonID() == nil then
		return
	end

	-- Only initialize if the module is enabled
	if self.DB and not self.DB.enabled then
		return
	end

	self:Init()
end

function module:OnDisable()
	-- Hide UI elements when module is disabled
	if self.uiFrame then
		self.uiFrame:Hide()
	end
	if self.affixWindow then
		self.affixWindow:Hide()
	end

	-- Unregister events
	self:UnregisterEvent('BAG_UPDATE_DELAYED')
	self:UnregisterEvent('SCRAPPING_MACHINE_PENDING_ITEM_CHANGED')
end

----------------------------------------------------------------------------------------------------
-- Core Functions
----------------------------------------------------------------------------------------------------

---Get minimum item level for equipped gear in this slot
---@param invType Enum.InventoryType
---@return number|nil
function module:GetMinLevelForInvType(invType)
	local equipmentSlot = ITEM_TO_INV_SLOT[invType]
	if not equipmentSlot then
		return nil
	end

	if type(equipmentSlot) == 'number' then
		local equippedItemLoc = ItemLocation:CreateFromEquipmentSlot(equipmentSlot)
		if equippedItemLoc:IsValid() then
			return C_Item.GetCurrentItemLevel(equippedItemLoc)
		end
	elseif type(equipmentSlot) == 'table' then
		-- Handle multi-slot items (rings, trinkets)
		local minLevel = nil
		for _, slot in ipairs(equipmentSlot) do
			local equippedItemLoc = ItemLocation:CreateFromEquipmentSlot(slot)
			if equippedItemLoc:IsValid() then
				local itemLevel = C_Item.GetCurrentItemLevel(equippedItemLoc)
				if not minLevel or itemLevel < minLevel then
					minLevel = itemLevel
				end
			end
		end
		return minLevel
	end
	return nil
end

---Check if item is in an equipment set by scanning tooltip
---@param bag number
---@param slot number
---@return boolean
function module:IsInGearset(bag, slot)
	if not bag or not slot or bag < 0 or slot < 1 then
		return false
	end

	-- Check cache first
	local cacheKey = bag .. '-' .. slot
	if gearsetCache[cacheKey] ~= nil then
		return gearsetCache[cacheKey]
	end

	local success, result =
		pcall(
		function()
			scannerTooltip:SetOwner(UIParent, 'ANCHOR_NONE')
			scannerTooltip:SetBagItem(bag, slot)

			for i = 1, scannerTooltip:NumLines() do
				local line = _G['LibsRemixPowerLevelScannerTooltipTextLeft' .. i]
				if line and line:GetText() and line:GetText():find(EQUIPMENT_SETS:format('.*')) then
					scannerTooltip:Hide()
					return true
				end
			end
			scannerTooltip:Hide()
			return false
		end
	)

	if not success then
		gearsetCache[cacheKey] = false
		return false
	end

	-- Cache the result
	gearsetCache[cacheKey] = result
	return result
end

---Check if item is a weapon
---@param invType Enum.InventoryType
---@return boolean
function module:IsWeapon(invType)
	return invType == Enum.InventoryType.IndexWeaponType or invType == Enum.InventoryType.IndexShieldType or invType == Enum.InventoryType.Index2HweaponType or
		invType == Enum.InventoryType.IndexWeaponmainhandType or
		invType == Enum.InventoryType.IndexWeaponoffhandType or
		invType == Enum.InventoryType.IndexRangedType or
		invType == Enum.InventoryType.IndexRangedrightType or
		invType == Enum.InventoryType.IndexHoldableType
end

---Get item category for filtering
---@param invType Enum.InventoryType
---@return string category 'armor', 'accessory', or 'weapon'
function module:GetItemCategory(invType)
	-- Check weapons first
	if self:IsWeapon(invType) then
		return 'weapon'
	end

	-- Check accessories
	if invType == Enum.InventoryType.IndexNeckType or invType == Enum.InventoryType.IndexFingerType or invType == Enum.InventoryType.IndexTrinketType then
		return 'accessory'
	end

	-- Everything else is armor
	return 'armor'
end

---Get all scrappable items in bags
---@return ScrappableItem[]
function module:GetScrappableItems()
	local scrappableItems = {}
	for bagID = BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
		for slotID = 1, C_Container.GetContainerNumSlots(bagID) do
			local itemLoc = ItemLocation:CreateFromBagAndSlot(bagID, slotID)
			if itemLoc:IsValid() and C_Item.CanScrapItem(itemLoc) then
				table.insert(
					scrappableItems,
					{
						bagID = bagID,
						slotID = slotID,
						level = C_Item.GetCurrentItemLevel(itemLoc),
						invType = C_Item.GetItemInventoryType(itemLoc),
						quality = C_Item.GetItemQuality(itemLoc),
						link = C_Item.GetItemLink(itemLoc),
						location = itemLoc
					}
				)
			end
		end
	end
	return scrappableItems
end

---Scan item tooltip to detect affixes
---@param bagID number
---@param slotID number
---@param itemLink string
---@return table<string, boolean>
function module:ScanItemAffixes(bagID, slotID, itemLink)
	local affixes = {}
	if not itemLink or not bagID or not slotID then
		return affixes
	end

	-- Check cache first
	if tooltipAffixCache[itemLink] then
		if detailedLogs and LibRTC and LibRTC.logger then
			LibRTC.logger.debug(string.format('ScanItemAffixes: Using cached data for %s', itemLink))
		end
		return tooltipAffixCache[itemLink]
	end

	-- Use SetBagItem instead of SetHyperlink - this actually loads tooltip data
	scannerTooltip:ClearLines()
	scannerTooltip:SetOwner(UIParent, 'ANCHOR_NONE')
	scannerTooltip:SetBagItem(bagID, slotID)

	-- Scan all tooltip lines
	local itemName = C_Item.GetItemNameByID(itemLink) or 'Unknown'
	local numLines = scannerTooltip:NumLines()

	if detailedLogs and LibRTC and LibRTC.logger then
		LibRTC.logger.debug(string.format('ScanItemAffixes: Scanning tooltip for %s bag=%d slot=%d (%d lines)', itemName, bagID, slotID, numLines))
	end

	for i = 1, numLines do
		local line = _G['LibsRemixPowerLevelScannerTooltipTextLeft' .. i]
		if line then
			local text = line:GetText()
			if text then
				affixes[text] = true
				if detailedLogs and LibRTC and LibRTC.logger then
					LibRTC.logger.debug(string.format('  Line %d: "%s"', i, text))
				end
			end
		end
	end

	scannerTooltip:Hide()

	-- Only cache if we got data (tooltip loaded successfully)
	-- Don't cache empty tooltips - they haven't loaded from server yet
	if numLines > 0 then
		tooltipAffixCache[itemLink] = affixes
		if detailedLogs and LibRTC and LibRTC.logger then
			LibRTC.logger.debug(string.format('ScanItemAffixes: Cached %d lines for %s', numLines, itemName))
		end
	else
		if detailedLogs and LibRTC and LibRTC.logger then
			LibRTC.logger.debug(string.format('ScanItemAffixes: NOT caching empty tooltip for %s - data not loaded yet', itemName))
		end
	end

	return affixes
end

---Check if item has any blacklisted affixes
---@param bagID number
---@param slotID number
---@param itemLink string
---@return boolean
function module:HasBlacklistedAffix(bagID, slotID, itemLink)
	if not self.DB.affixBlacklist then
		if LibRTC and LibRTC.logger then
			LibRTC.logger.debug('HasBlacklistedAffix: No blacklist configured')
		end
		return false
	end

	local affixes = self:ScanItemAffixes(bagID, slotID, itemLink)

	-- Log what we found in the tooltip
	if detailedLogs and LibRTC and LibRTC.logger then
		local tooltipLines = {}
		for line in pairs(affixes) do
			table.insert(tooltipLines, '"' .. line .. '"')
		end
		local itemName = C_Item.GetItemNameByID(itemLink) or 'Unknown'
		LibRTC.logger.debug(string.format('HasBlacklistedAffix for %s: Found %d tooltip lines: [%s]', itemName, #tooltipLines, table.concat(tooltipLines, ', ')))
	end

	for affixText in pairs(affixes) do
		for blacklistedAffix in pairs(self.DB.affixBlacklist) do
			if affixText:find(blacklistedAffix, 1, true) then
				-- Always log when an item is excluded (important for debugging)
				if LibRTC and LibRTC.logger then
					LibRTC.logger.debug(string.format('Item excluded from scrapping: %s - Contains blacklisted text: "%s" (found in: "%s")', itemLink, blacklistedAffix, affixText))
				end
				return true
			end
		end
	end

	return false
end

---Get filtered scrappable items based on settings
---@param capReturn number|nil
---@return ScrappableItem[]
function module:GetFilteredScrappableItems(capReturn)
	local scrappableItems = self:GetScrappableItems()
	local filteredItems = {}
	local accessoryDuplicates = {} -- Track accessories for duplicate detection

	for _, item in ipairs(scrappableItems) do
		local shouldInclude = true

		-- Check if item is a weapon and weapons are disabled
		if shouldInclude and self.DB.notWeapons and self:IsWeapon(item.invType) then
			shouldInclude = false
		end

		-- Check if item is in a gearset
		if shouldInclude and self.DB.notInGearset and C_EquipmentSet.CanUseEquipmentSets() and self:IsInGearset(item.bagID, item.slotID) then
			shouldInclude = false
		end

		-- Check for blacklisted affixes
		if shouldInclude and self:HasBlacklistedAffix(item.bagID, item.slotID, item.link) then
			shouldInclude = false
		end

		-- Get equipped item level for this slot
		local equippedItemLevel = nil
		if shouldInclude then
			equippedItemLevel = self:GetMinLevelForInvType(item.invType)
			if not equippedItemLevel then
				shouldInclude = false
			end
		end

		-- Determine which filtering rules to apply
		local minLevelDiff, maxQuality
		local itemCategory = nil
		if shouldInclude then
			itemCategory = self:GetItemCategory(item.invType)

			if self.DB.useAdvancedFiltering then
				-- Use advanced filtering rules based on item category
				if itemCategory == 'armor' then
					minLevelDiff = self.DB.advancedFilters.armor.minLevelDiff
					maxQuality = self.DB.advancedFilters.armor.maxQuality
				elseif itemCategory == 'accessory' then
					minLevelDiff = self.DB.advancedFilters.accessories.minLevelDiff
					maxQuality = self.DB.advancedFilters.accessories.maxQuality
				else
					-- Skip weapons
					shouldInclude = false
				end
			else
				-- Use simple filtering (main UI quality dropdown sets both)
				minLevelDiff = self.DB.minLevelDiff or 0
				maxQuality = self.DB.maxQuality or Enum.ItemQuality.Rare
			end
		end

		-- Apply quality and item level checks
		if shouldInclude and equippedItemLevel then
			if equippedItemLevel - item.level >= minLevelDiff and item.quality <= maxQuality then
				-- Log items being added for scrapping (for debugging)
				if detailedLogs and LibRTC and LibRTC.logger then
					local itemName = C_Item.GetItemNameByID(item.link) or 'Unknown'
					LibRTC.logger.debug(string.format('Item added for scrapping: %s (iLvl: %d, Category: %s)', itemName, item.level, itemCategory or 'unknown'))
				end

				-- Track accessories for duplicate detection
				if itemCategory == 'accessory' and self.DB.useAdvancedFiltering and self.DB.advancedFilters.accessories.keepHighestDuplicates then
					local itemName = C_Item.GetItemNameByID(item.link)
					if itemName then
						if not accessoryDuplicates[itemName] then
							accessoryDuplicates[itemName] = {}
						end
						table.insert(accessoryDuplicates[itemName], item)
					end
				end

				table.insert(filteredItems, item)

				if capReturn and #filteredItems >= capReturn then
					break
				end
			end
		end
	end

	-- Handle duplicate accessories - keep only highest ilvl
	if self.DB.useAdvancedFiltering and self.DB.advancedFilters.accessories.keepHighestDuplicates then
		for itemName, duplicates in pairs(accessoryDuplicates) do
			if #duplicates > 1 then
				-- Sort by item level (descending)
				table.sort(
					duplicates,
					function(a, b)
						return a.level > b.level
					end
				)

				-- Keep the highest, remove the rest from filteredItems
				for i = 2, #duplicates do
					local itemToRemove = duplicates[i]
					for j = #filteredItems, 1, -1 do
						if filteredItems[j].bagID == itemToRemove.bagID and filteredItems[j].slotID == itemToRemove.slotID then
							table.remove(filteredItems, j)
							break
						end
					end
				end
			end
		end
	end

	return filteredItems
end

---Scrap an item from bag into scrapping machine
---@param bagID number
---@param slotID number
---@return boolean success
function module:ScrapItemFromBag(bagID, slotID)
	C_Container.PickupContainerItem(bagID, slotID)
	local slots = {ScrappingMachineFrame.ItemSlots:GetChildren()}
	for i = 1, SCRAPPING_MACHINE_MAX_SLOTS do
		if not C_ScrappingMachineUI.GetCurrentPendingScrapItemLocationByIndex(i - 1) then
			slots[i]:Click()
			return true
		end
	end
	ClearCursor()
	return false
end

---Get number of active scrap items
---@return number
function module:GetNumActiveScrap()
	local count = 0
	if C_ScrappingMachineUI.HasScrappableItems() then
		for i = 1, SCRAPPING_MACHINE_MAX_SLOTS do
			if C_ScrappingMachineUI.GetCurrentPendingScrapItemLocationByIndex(i - 1) then
				count = count + 1
			end
		end
	end
	return count
end

---Auto scrap a batch of items
function module:AutoScrapBatch()
	local itemsToScrap = self:GetFilteredScrappableItems(SCRAPPING_MACHINE_MAX_SLOTS)

	if detailedLogs and LibRTC and LibRTC.logger then
		LibRTC.logger.debug(string.format('AutoScrapBatch: Found %d items to scrap', #itemsToScrap))
	end

	if #itemsToScrap < SCRAPPING_MACHINE_MAX_SLOTS then
		local numActive = self:GetNumActiveScrap()
		if detailedLogs and LibRTC and LibRTC.logger then
			LibRTC.logger.debug(string.format('AutoScrapBatch: Have %d active scrap items, need %d items', numActive, #itemsToScrap))
		end
		if numActive >= #itemsToScrap then
			if detailedLogs and LibRTC and LibRTC.logger then
				LibRTC.logger.debug('AutoScrapBatch: Already have enough items in queue, skipping')
			end
			return
		end
	end

	if C_ScrappingMachineUI.HasScrappableItems() then
		if detailedLogs and LibRTC and LibRTC.logger then
			LibRTC.logger.debug('AutoScrapBatch: HasScrappableItems returned true, skipping')
		end
		return
	end

	if detailedLogs and LibRTC and LibRTC.logger then
		LibRTC.logger.debug('AutoScrapBatch: Clearing existing items and adding new batch')
	end

	C_ScrappingMachineUI.RemoveAllScrapItems()
	for _, item in ipairs(itemsToScrap) do
		local success = self:ScrapItemFromBag(item.bagID, item.slotID)
		if detailedLogs and LibRTC and LibRTC.logger then
			local itemName = C_Item.GetItemNameByID(item.link) or 'Unknown'
			LibRTC.logger.debug(string.format('AutoScrapBatch: Attempting to scrap %s - %s', itemName, success and 'SUCCESS' or 'FAILED'))
		end
	end
end

---Auto scrap if enabled
function module:AutoScrap()
	if not ScrappingMachineFrame or not ScrappingMachineFrame:IsShown() then
		return
	end
	if not self.DB.autoScrap then
		return
	end
	if C_ScrappingMachineUI.HasScrappableItems() then
		return
	end

	-- Cancel any pending auto-scrap timer
	if self.autoScrapTimer then
		self:CancelTimer(self.autoScrapTimer)
	end

	-- Schedule auto-scrap with a delay to allow bag updates from server
	self.autoScrapTimer =
		self:ScheduleTimer(
		function()
			self:AutoScrapBatch()
			self.autoScrapTimer = nil
		end,
		0.5
	)
end

---Initialize scrapping system
function module:Init()
	-- Wait for scrapping machine UI to load
	if not C_AddOns.IsAddOnLoaded('Blizzard_ScrappingMachineUI') then
		local frame = CreateFrame('Frame')
		frame:RegisterEvent('ADDON_LOADED')
		frame:SetScript(
			'OnEvent',
			function(_, event, addonName)
				if addonName == 'Blizzard_ScrappingMachineUI' then
					frame:UnregisterEvent('ADDON_LOADED')
					module:InitUI()
				end
			end
		)
	else
		self:InitUI()
	end
end

----------------------------------------------------------------------------------------------------
-- UI Initialization
----------------------------------------------------------------------------------------------------

function module:InitUI()
	if not ScrappingMachineFrame then
		return
	end

	-- Reset button
	local resetButton = CreateFrame('Button', nil, ScrappingMachineFrame)
	resetButton:SetSize(24, 24)
	resetButton:SetPoint('TOPRIGHT', ScrappingMachineFrame, 'TOPRIGHT', -10, -25)
	local resetTexture = resetButton:CreateTexture(nil, 'BACKGROUND')
	resetTexture:SetAllPoints()
	resetTexture:SetAtlas('GM-raidMarker-reset')
	resetButton:SetScript(
		'OnClick',
		function()
			C_ScrappingMachineUI.RemoveAllScrapItems()
		end
	)

	-- Side panel frame
	local frame = CreateFrame('Frame', 'LibsRemixPowerLevelScrappingUI', ScrappingMachineFrame, 'PortraitFrameTemplate')
	ButtonFrameTemplate_HidePortrait(frame)
	frame:SetSize(275, ScrappingMachineFrame:GetHeight())
	frame:SetPoint('TOPLEFT', ScrappingMachineFrame, 'TOPRIGHT', 5, 0)
	if frame.PortraitContainer then
		frame.PortraitContainer:Hide()
	end
	if frame.portrait then
		frame.portrait:Hide()
	end
	frame:SetTitle("|cffffffffLib's|r Auto Scrapper")
	self.uiFrame = frame

	-- Quality label
	local qualityLabel = frame:CreateFontString(nil, 'ARTWORK', 'GameFontNormalSmall')
	qualityLabel:SetPoint('TOPLEFT', frame, 'TOPLEFT', 18, -40)
	qualityLabel:SetText('Max Quality:')

	-- Quality dropdown using modern WowStyle1FilterDropdownTemplate
	local qualityTexts = {
		[Enum.ItemQuality.Common] = '|cffFFFFFFCommon|r',
		[Enum.ItemQuality.Uncommon] = '|cff1EFF00Uncommon|r',
		[Enum.ItemQuality.Rare] = '|cff0070DDRare|r',
		[Enum.ItemQuality.Epic] = '|cffA335EEEpic|r'
	}

	local qualityDropdown = CreateFrame('DropdownButton', nil, frame, 'WowStyle1FilterDropdownTemplate')
	qualityDropdown:SetPoint('LEFT', qualityLabel, 'RIGHT', 5, 0)
	qualityDropdown:SetSize(200, 22)
	qualityDropdown:SetText(qualityTexts[module.DB.maxQuality] or '|cff0070DDRare|r')

	-- Setup quality dropdown generator
	qualityDropdown:SetupMenu(
		function(_, rootDescription)
			local qualities = {
				{text = '|cffFFFFFFCommon|r', value = Enum.ItemQuality.Common},
				{text = '|cff1EFF00Uncommon|r', value = Enum.ItemQuality.Uncommon},
				{text = '|cff0070DDRare|r', value = Enum.ItemQuality.Rare},
				{text = '|cffA335EEEpic|r', value = Enum.ItemQuality.Epic}
			}
			for _, quality in ipairs(qualities) do
				local button =
					rootDescription:CreateButton(
					quality.text,
					function()
						module.DB.maxQuality = quality.value
						qualityDropdown:SetText(quality.text)
						module:UpdateAll()
					end
				)
				-- Mark current selection with checkmark
				if module.DB.maxQuality == quality.value then
					button:SetRadio(true)
				end
			end
		end
	)

	-- Min level label
	local minLevelLabel = frame:CreateFontString(nil, 'ARTWORK', 'GameFontNormalSmall')
	minLevelLabel:SetPoint('TOPLEFT', qualityLabel, 'BOTTOMLEFT', 0, -15)
	minLevelLabel:SetText('Min Item Level Difference:')

	-- Min level editbox
	local minLevelBox = CreateFrame('EditBox', nil, frame, 'InputBoxTemplate')
	minLevelBox:SetPoint('LEFT', minLevelLabel, 'RIGHT', 10, 0)
	minLevelBox:SetSize(50, 20)
	minLevelBox:SetAutoFocus(false)
	minLevelBox:SetMaxLetters(3)
	minLevelBox:SetNumeric(true)
	minLevelBox:SetText(tostring(module.DB.minLevelDiff))
	minLevelBox:SetScript(
		'OnTextChanged',
		function(editBox, userInput)
			if userInput then
				local num = tonumber(editBox:GetText())
				if num then
					module.DB.minLevelDiff = num
					module:UpdateAll()
				end
			end
		end
	)

	-- Affix blacklist button using error UI's black style
	local affixButton = CreateFrame('Button', nil, frame)
	affixButton:SetSize(180, 25)
	affixButton:SetPoint('TOPLEFT', minLevelLabel, 'BOTTOMLEFT', 0, -10)

	affixButton:SetNormalAtlas('auctionhouse-nav-button')
	affixButton:SetHighlightAtlas('auctionhouse-nav-button-highlight')
	affixButton:SetPushedAtlas('auctionhouse-nav-button-select')
	affixButton:SetDisabledAtlas('UI-CastingBar-TextBox')

	-- Texture coordinate manipulation for button effect
	local normalTexture = affixButton:GetNormalTexture()
	normalTexture:SetTexCoord(0, 1, 0, 0.7)

	affixButton.Text = affixButton:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
	affixButton.Text:SetPoint('CENTER')
	affixButton.Text:SetText('Affix & Stat Blacklist')
	affixButton.Text:SetTextColor(1, 1, 1, 1)

	affixButton:HookScript(
		'OnDisable',
		function(btn)
			btn.Text:SetTextColor(0.6, 0.6, 0.6, 0.6)
		end
	)

	affixButton:HookScript(
		'OnEnable',
		function(btn)
			btn.Text:SetTextColor(1, 1, 1, 1)
		end
	)

	affixButton:SetScript(
		'OnClick',
		function()
			self:ShowAffixBlacklistWindow()
		end
	)

	-- Advanced Settings button
	local advancedButton = CreateFrame('Button', nil, frame)
	advancedButton:SetSize(180, 25)
	advancedButton:SetPoint('TOPLEFT', affixButton, 'BOTTOMLEFT', 0, -5)

	advancedButton:SetNormalAtlas('auctionhouse-nav-button')
	advancedButton:SetHighlightAtlas('auctionhouse-nav-button-highlight')
	advancedButton:SetPushedAtlas('auctionhouse-nav-button-select')
	advancedButton:SetDisabledAtlas('UI-CastingBar-TextBox')

	-- Texture coordinate manipulation for button effect
	local advancedNormalTexture = advancedButton:GetNormalTexture()
	advancedNormalTexture:SetTexCoord(0, 1, 0, 0.7)

	advancedButton.Text = advancedButton:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
	advancedButton.Text:SetPoint('CENTER')
	advancedButton.Text:SetText('Advanced Settings')
	advancedButton.Text:SetTextColor(1, 1, 1, 1)

	advancedButton:HookScript(
		'OnDisable',
		function(btn)
			btn.Text:SetTextColor(0.6, 0.6, 0.6, 0.6)
		end
	)

	advancedButton:HookScript(
		'OnEnable',
		function(btn)
			btn.Text:SetTextColor(1, 1, 1, 1)
		end
	)

	advancedButton:SetScript(
		'OnClick',
		function()
			Settings.OpenToCategory("Lib's - Remix Power Level")
		end
	)

	-- Auto scrap checkbox
	local autoScrapCheck = CreateFrame('CheckButton', nil, frame, 'UICheckButtonTemplate')
	autoScrapCheck:SetPoint('TOPLEFT', advancedButton, 'BOTTOMLEFT', 0, -2)
	autoScrapCheck.text:SetText('Auto Scrap')
	autoScrapCheck:SetChecked(module.DB.autoScrap)
	autoScrapCheck:SetScript(
		'OnClick',
		function(checkbox)
			module.DB.autoScrap = checkbox:GetChecked()
			if checkbox:GetChecked() then
				module:AutoScrapBatch()
			end
		end
	)
	self.autoScrapCheck = autoScrapCheck

	-- Scroll frame for items with modern scrollbar and background
	local scrollFrame = CreateFrame('ScrollFrame', nil, frame)
	scrollFrame:SetPoint('TOPLEFT', autoScrapCheck, 'BOTTOMLEFT', 0, -8)
	scrollFrame:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -25, 10)

	-- Add background texture
	scrollFrame.bg = scrollFrame:CreateTexture(nil, 'BACKGROUND')
	scrollFrame.bg:SetPoint('TOPLEFT', scrollFrame, 'TOPLEFT', -8, 8)
	scrollFrame.bg:SetPoint('BOTTOMRIGHT', scrollFrame, 'BOTTOMRIGHT')
	scrollFrame.bg:SetAtlas('auctionhouse-background-index', true)

	-- Modern minimal scrollbar
	scrollFrame.ScrollBar = CreateFrame('EventFrame', nil, scrollFrame, 'MinimalScrollBar')
	scrollFrame.ScrollBar:SetPoint('TOPLEFT', scrollFrame.bg, 'TOPRIGHT', 6, 0)
	scrollFrame.ScrollBar:SetPoint('BOTTOMLEFT', scrollFrame.bg, 'BOTTOMRIGHT', 6, 0)
	ScrollUtil.InitScrollFrameWithScrollBar(scrollFrame, scrollFrame.ScrollBar)

	local scrollChild = CreateFrame('Frame', nil, scrollFrame)
	scrollFrame:SetScrollChild(scrollChild)
	scrollChild:SetSize(scrollFrame:GetWidth(), 1)
	self.scrollChild = scrollChild
	self.itemButtons = {}

	-- Hook events
	ScrappingMachineFrame:HookScript(
		'OnShow',
		function()
			-- Only show if module is enabled
			if self.DB and self.DB.enabled then
				frame:Show()
				module:UpdateAll()
			else
				frame:Hide()
			end
		end
	)

	ScrappingMachineFrame:HookScript(
		'OnHide',
		function()
			frame:Hide()
			-- Also hide affix blacklist window when scrapping UI closes
			if self.affixWindow then
				self.affixWindow:Hide()
			end
		end
	)

	self:RegisterEvent(
		'BAG_UPDATE_DELAYED',
		function()
			if self.DB and self.DB.enabled and ScrappingMachineFrame:IsShown() then
				-- Only clear gearset cache (items may have moved slots)
				-- Keep tooltip affix cache (itemLinks don't change)
				self:ClearGearsetCache()
				self:RefreshItemList()
			end
		end
	)

	-- Create scrapping list window and toggle button
	self:InitScrappingListUI()

	-- Register event for real-time updates of scrapping list
	self:RegisterEvent(
		'SCRAPPING_MACHINE_PENDING_ITEM_CHANGED',
		function()
			if self.DB and self.DB.enabled then
				self:RefreshScrappingList()
				self:UpdateScrappingListVisibility()

				self:ScheduleTimer(
					function()
						self:RefreshItemList()
						self:AutoScrap()
					end,
					0.1
				)
			end
		end
	)
end

----------------------------------------------------------------------------------------------------
-- Scrapping List UI
----------------------------------------------------------------------------------------------------

---Initialize the scrapping list window and toggle button
function module:InitScrappingListUI()
	if not ScrappingMachineFrame then
		return
	end

	-- Toggle button on scrapping machine frame
	local toggleButton = CreateFrame('Button', nil, ScrappingMachineFrame)
	toggleButton:SetSize(20, 20)
	toggleButton:SetPoint('BOTTOMRIGHT', ScrappingMachineFrame, 'BOTTOMRIGHT', -8, 8)

	-- Button textures using the arrow atlases
	local normalTexture = toggleButton:CreateTexture(nil, 'BACKGROUND')
	normalTexture:SetAllPoints()
	normalTexture:SetAtlas('128-RedButton-ArrowDown')
	toggleButton:SetNormalTexture(normalTexture)

	local pushedTexture = toggleButton:CreateTexture(nil, 'BACKGROUND')
	pushedTexture:SetAllPoints()
	pushedTexture:SetAtlas('128-RedButton-ArrowDown-Pressed')
	toggleButton:SetPushedTexture(pushedTexture)

	local highlightTexture = toggleButton:CreateTexture(nil, 'HIGHLIGHT')
	highlightTexture:SetAllPoints()
	highlightTexture:SetAtlas('128-RedButton-ArrowDown-Highlight')
	toggleButton:SetHighlightTexture(highlightTexture)

	self.scrappingListToggleButton = toggleButton

	-- Scrapping list window
	local window = CreateFrame('Frame', 'LibsRemixPowerLevelScrappingListWindow', ScrappingMachineFrame, 'PortraitFrameTemplate')
	ButtonFrameTemplate_HidePortrait(window)
	window:SetSize(ScrappingMachineFrame:GetWidth(), 215)
	window:SetPoint('TOP', ScrappingMachineFrame, 'BOTTOM', 0, -5)
	window:SetFrameStrata('MEDIUM')
	window:SetFrameLevel(ScrappingMachineFrame:GetFrameLevel() + 1)

	-- Set title
	if window.TitleText then
		window.TitleText:SetText('Scrapping')
	elseif window.TitleContainer and window.TitleContainer.TitleText then
		window.TitleContainer.TitleText:SetText('Scrapping')
	end

	-- Hide close button - we'll use the toggle button instead
	if window.CloseButton then
		window.CloseButton:SetScript(
			'OnClick',
			function()
				self.DB.scrappingListManualHide = true
				self:UpdateScrappingListVisibility()
			end
		)
	end

	-- Create scroll child for item list
	window.itemList = {}
	window.scrollChild = CreateFrame('Frame', nil, window.Inset or window)
	window.scrollChild:SetPoint('TOPLEFT', window.Inset or window, 'TOPLEFT', 5, -5)
	window.scrollChild:SetPoint('BOTTOMRIGHT', window.Inset or window, 'BOTTOMRIGHT', -5, 5)
	window.scrollChild:SetSize(window:GetWidth() - 10, 1)

	window.scrollChild.Background = window.scrollChild:CreateTexture(nil, 'BACKGROUND')
	window.scrollChild.Background:SetAtlas('auctionhouse-background-index', true)
	window.scrollChild.Background:SetPoint('TOPLEFT', window.scrollChild, 'TOPLEFT')
	window.scrollChild.Background:SetPoint('BOTTOMRIGHT', window.scrollChild, 'BOTTOMRIGHT')

	self.scrappingListWindow = window

	-- Toggle button click handler
	toggleButton:SetScript(
		'OnClick',
		function()
			self.DB.scrappingListManualHide = false
			self:UpdateScrappingListVisibility()
		end
	)

	-- Hook scrapping machine show/hide
	ScrappingMachineFrame:HookScript(
		'OnShow',
		function()
			if self.DB and self.DB.enabled then
				self:RefreshScrappingList()
				self:UpdateScrappingListVisibility()
			end
		end
	)

	ScrappingMachineFrame:HookScript(
		'OnHide',
		function()
			if self.scrappingListWindow then
				self.scrappingListWindow:Hide()
			end
			if self.scrappingListToggleButton then
				self.scrappingListToggleButton:Hide()
			end
		end
	)

	-- Initial state
	window:Hide()
	toggleButton:Hide()
end

---Get pending scrap items with their data
---@return table<number, {itemLoc: ItemLocation, link: string, level: number, quality: Enum.ItemQuality, name: string}>
function module:GetPendingScrapItems()
	local items = {}
	if not C_ScrappingMachineUI.HasScrappableItems() then
		return items
	end

	for i = 1, SCRAPPING_MACHINE_MAX_SLOTS do
		local itemLoc = C_ScrappingMachineUI.GetCurrentPendingScrapItemLocationByIndex(i - 1)
		if itemLoc then
			local isValid =
				pcall(
				function()
					return itemLoc:IsValid()
				end
			)
			if isValid and itemLoc:IsValid() then
				local link = C_Item.GetItemLink(itemLoc)
				if link then
					local level = C_Item.GetCurrentItemLevel(itemLoc)
					local quality = C_Item.GetItemQuality(itemLoc)
					local name = C_Item.GetItemName(itemLoc)
					table.insert(
						items,
						{
							itemLoc = itemLoc,
							link = link,
							level = level,
							quality = quality,
							name = name
						}
					)
				end
			end
		end
	end

	return items
end

---Refresh the scrapping list display
function module:RefreshScrappingList()
	if not self.scrappingListWindow or not self.scrappingListWindow.scrollChild then
		return
	end

	local window = self.scrappingListWindow
	local items = self:GetPendingScrapItems()

	-- Clear existing list
	for _, frame in ipairs(window.itemList) do
		frame:Hide()
	end

	-- Quality colors
	local qualityColors = {
		[Enum.ItemQuality.Poor] = '|cff9d9d9d',
		[Enum.ItemQuality.Common] = '|cffffffff',
		[Enum.ItemQuality.Uncommon] = '|cff1eff00',
		[Enum.ItemQuality.Rare] = '|cff0070dd',
		[Enum.ItemQuality.Epic] = '|cffa335ee',
		[Enum.ItemQuality.Legendary] = '|cffff8000'
	}

	-- Create/update item rows
	local yOffset = 20
	local rowHeight = 20
	for i, item in ipairs(items) do
		local row = window.itemList[i]
		if not row then
			row = CreateFrame('Frame', nil, window.scrollChild)
			row:SetSize(window.scrollChild:GetWidth(), rowHeight)

			-- Icon
			row.icon = row:CreateTexture(nil, 'ARTWORK')
			row.icon:SetSize(rowHeight - 4, rowHeight - 4)
			row.icon:SetPoint('LEFT', 5, 0)

			-- Item level text
			row.ilvl = row:CreateFontString(nil, 'ARTWORK', 'GameFontNormal')
			row.ilvl:SetPoint('LEFT', row.icon, 'RIGHT', 5, 0)
			row.ilvl:SetWidth(40)
			row.ilvl:SetJustifyH('LEFT')

			-- Item name text
			row.name = row:CreateFontString(nil, 'ARTWORK', 'GameFontNormal')
			row.name:SetPoint('LEFT', row.ilvl, 'RIGHT', 5, 0)
			row.name:SetPoint('RIGHT', -5, 0)
			row.name:SetJustifyH('LEFT')

			-- Make row clickable for tooltip
			row:EnableMouse(true)
			row:SetScript(
				'OnEnter',
				function()
					if row.itemLink then
						GameTooltip:SetOwner(row, 'ANCHOR_RIGHT')
						GameTooltip:SetHyperlink(row.itemLink)
						GameTooltip:Show()
					end
				end
			)
			row:SetScript(
				'OnLeave',
				function()
					GameTooltip:Hide()
				end
			)

			window.itemList[i] = row
		end

		-- Update row data
		row:SetPoint('TOPLEFT', window.scrollChild, 'TOPLEFT', 3, -yOffset)
		row.itemLink = item.link

		-- Set icon
		local icon = C_Item.GetItemIconByID(item.link)
		if icon then
			row.icon:SetTexture(icon)
		end

		-- Set ilvl with gear rating color (using game's GetItemQualityColor)
		local r, g, b = C_Item.GetItemQualityColor(item.quality)
		row.ilvl:SetText(tostring(item.level))
		row.ilvl:SetTextColor(r, g, b)

		-- Set name with quality color
		local qualityColor = qualityColors[item.quality] or '|cffffffff'
		row.name:SetText(qualityColor .. (item.name or 'Unknown') .. '|r')

		row:Show()
		yOffset = yOffset + rowHeight
	end

	-- Update scroll child height
	window.scrollChild:SetHeight(math.max(yOffset, 1))
end

---Update scrapping list window visibility based on item count and manual toggle
function module:UpdateScrappingListVisibility()
	if not self.scrappingListWindow or not self.scrappingListToggleButton then
		return
	end

	if not ScrappingMachineFrame or not ScrappingMachineFrame:IsShown() then
		self.scrappingListWindow:Hide()
		self.scrappingListToggleButton:Hide()
		return
	end

	local items = self:GetPendingScrapItems()
	local hasItems = #items > 0

	-- If manually hidden, show toggle button when there are items
	if self.DB.scrappingListManualHide then
		self.scrappingListWindow:Hide()
		if hasItems then
			self.scrappingListToggleButton:Show()
		else
			self.scrappingListToggleButton:Hide()
		end
	else
		-- Auto show/hide based on items
		if hasItems then
			self.scrappingListWindow:Show()
			self.scrappingListToggleButton:Hide()
		else
			self.scrappingListWindow:Hide()
			self.scrappingListToggleButton:Hide()
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Utility Functions
----------------------------------------------------------------------------------------------------

---Get map of pending items
---@return table<string, boolean>
function module:GetMappedPendingItems()
	local pendingMap = {}
	if not C_ScrappingMachineUI.HasScrappableItems() then
		return pendingMap
	end

	for i = 1, SCRAPPING_MACHINE_MAX_SLOTS do
		local itemLoc = C_ScrappingMachineUI.GetCurrentPendingScrapItemLocationByIndex(i - 1)
		if itemLoc then
			local isValid =
				pcall(
				function()
					return itemLoc:IsValid()
				end
			)
			if isValid and itemLoc:IsValid() then
				local bagID, slotID = itemLoc:GetBagAndSlot()
				pendingMap[bagID .. '-' .. slotID] = true
			end
		end
	end
	return pendingMap
end

---Clear all pending scrap items (called when filters change)
function module:ClearFilteredPendingItems()
	C_ScrappingMachineUI.RemoveAllScrapItems()
end

---Update everything when filters change
function module:UpdateAll()
	self:ClearCaches()
	self:ClearFilteredPendingItems()
	self:RefreshItemList()
	self:AutoScrap()
end

---Update auto scrap checkbox text with item count
function module:UpdateAutoScrapText()
	if not self.autoScrapCheck then
		return
	end

	local items = self:GetFilteredScrappableItems()
	local count = #items
	if count > 0 then
		self.autoScrapCheck.text:SetText(string.format('Auto Scrap - %d items', count))
	else
		self.autoScrapCheck.text:SetText('Auto Scrap')
	end
end

---Refresh the item list display
function module:RefreshItemList()
	if not self.scrollChild then
		return
	end

	local items = self:GetFilteredScrappableItems()
	local pendingMap = self:GetMappedPendingItems()

	-- Update the auto scrap checkbox text
	self:UpdateAutoScrapText()

	local itemsPerRow = 6
	local buttonSize = 35
	local padding = 2
	local minRows = 3
	local minSlots = itemsPerRow * minRows

	-- Calculate total slots to show (at least 3 rows)
	local totalSlots = math.max(#items, minSlots)

	-- Create/update buttons for all slots (items + empty)
	for i = 1, totalSlots do
		local btn = self.itemButtons[i]
		if not btn then
			btn = CreateFrame('Button', nil, self.scrollChild)
			btn:SetSize(buttonSize, buttonSize)

			btn.bg = btn:CreateTexture(nil, 'BACKGROUND')
			btn.bg:SetAllPoints()
			btn.bg:SetAtlas('bags-item-slot64')

			btn.icon = btn:CreateTexture(nil, 'ARTWORK')
			btn.icon:SetAllPoints()

			btn:SetScript(
				'OnClick',
				function(_, button)
					if btn.bagID and btn.slotID then
						if button == 'LeftButton' or button == 'RightButton' then
							self:ScrapItemFromBag(btn.bagID, btn.slotID)
						end
					end
				end
			)
			btn:RegisterForClicks('LeftButtonUp', 'RightButtonUp')

			btn:SetScript(
				'OnEnter',
				function()
					if btn.bagID and btn.slotID then
						GameTooltip:SetOwner(btn, 'ANCHOR_RIGHT')
						GameTooltip:SetBagItem(btn.bagID, btn.slotID)
						GameTooltip:Show()
					end
				end
			)

			btn:SetScript(
				'OnLeave',
				function()
					GameTooltip:Hide()
				end
			)

			self.itemButtons[i] = btn
		end

		-- Position in grid
		local row = math.floor((i - 1) / itemsPerRow)
		local col = (i - 1) % itemsPerRow
		local xOffset = col * (buttonSize + padding)
		local yOffset = -row * (buttonSize + padding)
		btn:ClearAllPoints()
		btn:SetPoint('TOPLEFT', self.scrollChild, 'TOPLEFT', xOffset, yOffset)

		-- Update button with item data if available
		local item = items[i]
		if item then
			btn.bagID = item.bagID
			btn.slotID = item.slotID
			btn.icon:SetTexture(C_Item.GetItemIconByID(item.link))
			btn.icon:Show()

			-- Desaturate if already pending
			local isPending = pendingMap[item.bagID .. '-' .. item.slotID]
			btn.icon:SetDesaturated(isPending)
		else
			-- Empty slot
			btn.bagID = nil
			btn.slotID = nil
			btn.icon:SetTexture(nil)
			btn.icon:Hide()
		end

		btn:Show()
	end

	-- Hide any extra buttons beyond what we need
	for i = totalSlots + 1, #self.itemButtons do
		self.itemButtons[i]:Hide()
	end

	-- Update scroll child height to fit all slots
	local totalRows = math.ceil(totalSlots / itemsPerRow)
	self.scrollChild:SetHeight(totalRows * (buttonSize + padding))
end

---Show the affix blacklist management window
function module:ShowAffixBlacklistWindow()
	-- Create window if it doesn't exist
	if not self.affixWindow then
		local window = CreateFrame('Frame', 'LibsRemixPowerLevelAffixWindow', UIParent, 'PortraitFrameTemplate')
		ButtonFrameTemplate_HidePortrait(window)
		window:SetSize(350, 400)

		-- Anchor to the right side of the scrapping UI panel
		if self.uiFrame then
			window:SetPoint('TOPLEFT', self.uiFrame, 'TOPRIGHT', 5, 0)
		else
			window:SetPoint('CENTER')
		end

		window:SetMovable(true)
		window:EnableMouse(true)
		window:RegisterForDrag('LeftButton')
		window:SetScript(
			'OnDragStart',
			function(frame)
				frame:StartMoving()
			end
		)
		window:SetScript(
			'OnDragStop',
			function(frame)
				frame:StopMovingOrSizing()
			end
		)

		if window.PortraitContainer then
			window.PortraitContainer:Hide()
		end
		if window.portrait then
			window.portrait:Hide()
		end
		if window.TitleText then
			window.TitleText:SetText('Affix & Stat Blacklist')
		elseif window.TitleContainer and window.TitleContainer.TitleText then
			window.TitleContainer.TitleText:SetText('Affix & Stat Blacklist')
		end

		-- Instructions
		local instructions = window:CreateFontString(nil, 'ARTWORK', 'GameFontNormal')
		instructions:SetPoint('TOPLEFT', 15, -30)
		instructions:SetPoint('TOPRIGHT', -15, -30)
		instructions:SetJustifyH('LEFT')
		instructions:SetText('Items with these stats or affixes will not be scrapped.\nSelect from dropdowns or enter custom text.')

		-- Stats dropdown
		local statsLabel = window:CreateFontString(nil, 'ARTWORK', 'GameFontNormalSmall')
		statsLabel:SetPoint('TOPLEFT', instructions, 'BOTTOMLEFT', 0, -15)
		statsLabel:SetText('Stats:')

		local statsDropdown = CreateFrame('DropdownButton', nil, window, 'WowStyle1FilterDropdownTemplate')
		statsDropdown:SetPoint('TOPLEFT', statsLabel, 'BOTTOMLEFT', 0, -5)
		statsDropdown:SetSize(200, 22)
		statsDropdown:SetText('Add Stat')

		-- Setup stats dropdown generator
		statsDropdown:SetupMenu(
			function(dropdown, rootDescription)
				for _, stat in ipairs(KNOWN_STATS) do
					local isBlacklisted = module.DB.affixBlacklist[stat] ~= nil
					local button =
						rootDescription:CreateButton(
						stat,
						function()
							if module.DB.affixBlacklist[stat] then
								module.DB.affixBlacklist[stat] = nil
								if detailedLogs and LibRTC and LibRTC.logger then
									LibRTC.logger.debug(string.format('Removed "%s" from blacklist, calling UpdateAll()', stat))
								end
							else
								module.DB.affixBlacklist[stat] = true
								if detailedLogs and LibRTC and LibRTC.logger then
									LibRTC.logger.debug(string.format('Added "%s" to blacklist, calling UpdateAll()', stat))
								end
							end
							self:RefreshBlacklistDisplay()
							self:UpdateAll()
						end
					)
					button:SetEnabled(not isBlacklisted)
				end
			end
		)

		-- Affixes dropdown
		local affixLabel = window:CreateFontString(nil, 'ARTWORK', 'GameFontNormalSmall')
		affixLabel:SetPoint('LEFT', statsLabel, 'RIGHT', 120, 0)
		affixLabel:SetText('Affixes:')

		local affixDropdown = CreateFrame('DropdownButton', nil, window, 'WowStyle1FilterDropdownTemplate')
		affixDropdown:SetPoint('TOPLEFT', affixLabel, 'BOTTOMLEFT', 0, -5)
		affixDropdown:SetSize(200, 22)
		affixDropdown:SetText('Add Affix')

		-- Setup affix dropdown generator
		affixDropdown:SetupMenu(
			function(dropdown, rootDescription)
				-- Get sorted list of affix names
				local affixNames = {}
				for affixName in pairs(KNOWN_AFFIXES) do
					table.insert(affixNames, affixName)
				end
				table.sort(affixNames)

				for _, affix in ipairs(affixNames) do
					local isBlacklisted = module.DB.affixBlacklist[affix] ~= nil
					local spellID = KNOWN_AFFIXES[affix]
					local icon = spellID and C_Spell.GetSpellTexture(spellID)

					local button =
						rootDescription:CreateButton(
						affix,
						function()
							if module.DB.affixBlacklist[affix] then
								module.DB.affixBlacklist[affix] = nil
							else
								module.DB.affixBlacklist[affix] = true
							end
							self:RefreshBlacklistDisplay()
							self:UpdateAll()
						end
					)
					if icon then
						button:AddInitializer(
							function(btn)
								local iconTexture = btn:AttachTexture()
								iconTexture:SetTexture(icon)
								iconTexture:SetSize(16, 16)
								iconTexture:SetPoint('LEFT', 4, 0)
								btn.fontString:SetPoint('LEFT', 24, 0)
							end
						)
					end
					-- Add tooltip to dropdown item
					if spellID then
						button:SetTooltip(
							function(tooltip)
								tooltip:SetSpellByID(spellID)
							end
						)
					end
					button:SetEnabled(not isBlacklisted)
				end
			end
		)

		-- Custom text entry
		local customLabel = window:CreateFontString(nil, 'ARTWORK', 'GameFontNormalSmall')
		customLabel:SetPoint('TOPLEFT', statsDropdown, 'BOTTOMLEFT', 0, -10)
		customLabel:SetText('Custom Text:')

		local addBox = CreateFrame('EditBox', nil, window, 'InputBoxTemplate')
		addBox:SetPoint('TOPLEFT', customLabel, 'BOTTOMLEFT', 5, -5)
		addBox:SetPoint('TOPRIGHT', window, 'TOPRIGHT', -100, -235)
		addBox:SetHeight(20)
		addBox:SetAutoFocus(false)
		addBox:SetMaxLetters(50)

		-- Add button using error UI's black style
		local addButton = CreateFrame('Button', nil, window)
		addButton:SetSize(80, 25)
		addButton:SetPoint('LEFT', addBox, 'RIGHT', 5, 0)

		addButton:SetNormalAtlas('auctionhouse-nav-button')
		addButton:SetHighlightAtlas('auctionhouse-nav-button-highlight')
		addButton:SetPushedAtlas('auctionhouse-nav-button-select')
		addButton:SetDisabledAtlas('UI-CastingBar-TextBox')

		local addNormalTexture = addButton:GetNormalTexture()
		addNormalTexture:SetTexCoord(0, 1, 0, 0.7)

		addButton.Text = addButton:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
		addButton.Text:SetPoint('CENTER')
		addButton.Text:SetText('Add')
		addButton.Text:SetTextColor(1, 1, 1, 1)

		addButton:HookScript(
			'OnDisable',
			function(btn)
				btn.Text:SetTextColor(0.6, 0.6, 0.6, 0.6)
			end
		)

		addButton:HookScript(
			'OnEnable',
			function(btn)
				btn.Text:SetTextColor(1, 1, 1, 1)
			end
		)

		addButton:SetScript(
			'OnClick',
			function()
				local text = addBox:GetText():trim()
				if text ~= '' then
					module.DB.affixBlacklist[text] = true
					addBox:SetText('')
					self:RefreshBlacklistDisplay()
					self:UpdateAll()
				end
			end
		)

		-- Scroll frame for blacklist display with modern scrollbar and background
		local scrollFrame = CreateFrame('ScrollFrame', nil, window)
		scrollFrame:SetPoint('TOPLEFT', addBox, 'BOTTOMLEFT', -5, -10)
		scrollFrame:SetPoint('BOTTOMRIGHT', window, 'BOTTOMRIGHT', -25, 10)

		-- Add background texture
		scrollFrame.bg = scrollFrame:CreateTexture(nil, 'BACKGROUND')
		scrollFrame.bg:SetAllPoints()
		scrollFrame.bg:SetAtlas('auctionhouse-background-index', true)

		-- Modern minimal scrollbar
		scrollFrame.ScrollBar = CreateFrame('EventFrame', nil, scrollFrame, 'MinimalScrollBar')
		scrollFrame.ScrollBar:SetPoint('TOPLEFT', scrollFrame, 'TOPRIGHT', 6, 0)
		scrollFrame.ScrollBar:SetPoint('BOTTOMLEFT', scrollFrame, 'BOTTOMRIGHT', 6, 0)
		ScrollUtil.InitScrollFrameWithScrollBar(scrollFrame, scrollFrame.ScrollBar)

		local scrollChild = CreateFrame('Frame', nil, scrollFrame)
		scrollFrame:SetScrollChild(scrollChild)
		scrollChild:SetSize(scrollFrame:GetWidth(), 1)

		window.scrollFrame = scrollFrame
		window.scrollChild = scrollChild
		window.blacklistButtons = {}

		-- Close button behavior
		window.CloseButton:SetScript(
			'OnClick',
			function()
				window:Hide()
			end
		)

		self.affixWindow = window
	end

	self:RefreshBlacklistDisplay()
	self.affixWindow:Show()
end

---Refresh the blacklist display (shows currently blacklisted items)
function module:RefreshBlacklistDisplay()
	if not self.affixWindow then
		return
	end

	local window = self.affixWindow
	local blacklisted = {}

	-- Build sorted list of blacklisted items
	for item in pairs(module.DB.affixBlacklist or {}) do
		table.insert(blacklisted, item)
	end
	table.sort(blacklisted)

	-- Hide existing buttons
	for _, btn in ipairs(window.blacklistButtons) do
		btn:Hide()
	end

	-- Create/update buttons for blacklisted items
	local yOffset = 0
	for i, item in ipairs(blacklisted) do
		local btn = window.blacklistButtons[i]
		if not btn then
			btn = CreateFrame('Frame', nil, window.scrollChild)
			btn:SetSize(window.scrollChild:GetWidth(), 24)

			-- Icon texture
			btn.icon = btn:CreateTexture(nil, 'ARTWORK')
			btn.icon:SetSize(20, 20)
			btn.icon:SetPoint('LEFT', 5, 0)

			-- Invisible button for tooltip hover
			btn.iconButton = CreateFrame('Button', nil, btn)
			btn.iconButton:SetSize(20, 20)
			btn.iconButton:SetPoint('LEFT', 5, 0)
			btn.iconButton:EnableMouse(true)

			-- Text button for tooltip hover
			btn.textButton = CreateFrame('Button', nil, btn)
			btn.textButton:SetPoint('LEFT', 30, 0)
			btn.textButton:SetPoint('RIGHT', -70, 0)
			btn.textButton:SetHeight(24)
			btn.textButton:EnableMouse(true)

			btn.text = btn.textButton:CreateFontString(nil, 'ARTWORK', 'GameFontNormal')
			btn.text:SetPoint('LEFT', 0, 0)
			btn.text:SetPoint('RIGHT', 0, 0)
			btn.text:SetJustifyH('LEFT')

			-- Remove button using error UI's black style
			btn.deleteBtn = CreateFrame('Button', nil, btn)
			btn.deleteBtn:SetSize(65, 22)
			btn.deleteBtn:SetPoint('RIGHT', -5, 0)

			btn.deleteBtn:SetNormalAtlas('auctionhouse-nav-button')
			btn.deleteBtn:SetHighlightAtlas('auctionhouse-nav-button-highlight')
			btn.deleteBtn:SetPushedAtlas('auctionhouse-nav-button-select')
			btn.deleteBtn:SetDisabledAtlas('UI-CastingBar-TextBox')

			local deleteNormalTexture = btn.deleteBtn:GetNormalTexture()
			deleteNormalTexture:SetTexCoord(0, 1, 0, 0.7)

			btn.deleteBtn.Text = btn.deleteBtn:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
			btn.deleteBtn.Text:SetPoint('CENTER')
			btn.deleteBtn.Text:SetText('Remove')
			btn.deleteBtn.Text:SetTextColor(1, 1, 1, 1)

			btn.deleteBtn:HookScript(
				'OnDisable',
				function(delBtn)
					delBtn.Text:SetTextColor(0.6, 0.6, 0.6, 0.6)
				end
			)

			btn.deleteBtn:HookScript(
				'OnEnable',
				function(delBtn)
					delBtn.Text:SetTextColor(1, 1, 1, 1)
				end
			)

			window.blacklistButtons[i] = btn
		end

		btn:SetPoint('TOPLEFT', 0, -yOffset)
		btn.text:SetText(item)

		-- Get spell ID and icon for this affix
		local spellID = KNOWN_AFFIXES[item]
		if spellID then
			local icon = C_Spell.GetSpellTexture(spellID)
			if icon then
				btn.icon:SetTexture(icon)
				btn.icon:Show()
				btn.iconButton:Show()

				-- Set up spell tooltip for icon
				btn.iconButton:SetScript(
					'OnEnter',
					function()
						GameTooltip:SetOwner(btn.iconButton, 'ANCHOR_RIGHT')
						GameTooltip:SetSpellByID(spellID)
						GameTooltip:Show()
					end
				)
				btn.iconButton:SetScript(
					'OnLeave',
					function()
						GameTooltip:Hide()
					end
				)

				-- Set up spell tooltip for text
				btn.textButton:SetScript(
					'OnEnter',
					function()
						GameTooltip:SetOwner(btn.textButton, 'ANCHOR_RIGHT')
						GameTooltip:SetSpellByID(spellID)
						GameTooltip:Show()
					end
				)
				btn.textButton:SetScript(
					'OnLeave',
					function()
						GameTooltip:Hide()
					end
				)
			else
				btn.icon:Hide()
				btn.iconButton:Hide()
			end
		else
			-- No icon for custom text or stats
			btn.icon:Hide()
			btn.iconButton:Hide()

			-- Clear text tooltip for non-affixes
			btn.textButton:SetScript('OnEnter', nil)
			btn.textButton:SetScript('OnLeave', nil)
		end

		btn.deleteBtn:SetScript(
			'OnClick',
			function()
				module.DB.affixBlacklist[item] = nil
				self:RefreshBlacklistDisplay()
				self:UpdateAll()
			end
		)
		btn:Show()

		yOffset = yOffset + 24
	end

	-- Update scroll height
	window.scrollChild:SetHeight(math.max(yOffset, 1))
end
