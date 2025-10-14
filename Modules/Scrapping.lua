---@class LibRTC
local LibRTC = LibStub('AceAddon-3.0'):GetAddon('Libs-RemixPowerLevel')
---@class LibRTC.Module.Scrapping : AceModule
local module = LibRTC:NewModule('Scrapping', 'AceEvent-3.0')
module.DisplayName = 'Auto Scrapper'
module.description = 'Automatically scrap items based on filters'

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
	autoScrap = false,
	maxQuality = Enum.ItemQuality.Rare,
	minLevelDiff = 0,
	affixBlacklist = {}
}

-- Tooltip scanner for detecting affixes
local scannerTooltip = CreateFrame('GameTooltip', 'LibsRemixPowerLevelScannerTooltip', nil, 'GameTooltipTemplate')
scannerTooltip:SetOwner(UIParent, 'ANCHOR_NONE')

function module:OnInitialize()
	-- Check if character name starts with "lib" for auto-scrap default
	local charName = UnitName('player'):lower()
	if charName:sub(1, 3) == 'lib' then
		DbDefaults.autoScrap = true
	end

	module.Database = LibRTC.dbobj:RegisterNamespace('Scrapping', {profile = DbDefaults})
	module.DB = module.Database.profile ---@type LibRTC.Module.Scrapping.DB

	-- Add module options to parent addon options table
	self:InitializeOptions()
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
			autoScrap = {
				type = 'toggle',
				name = 'Enable Auto Scrap',
				desc = 'Automatically fill the scrapping machine with items matching your filters',
				order = 10,
				width = 'full',
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
			}
		}
	}
end

function module:OnEnable()
	if not PlayerGetTimerunningSeasonID or PlayerGetTimerunningSeasonID() == nil then
		return
	end

	self:Init()
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
---@param itemLink string
---@return table<string, boolean>
function module:ScanItemAffixes(itemLink)
	local affixes = {}
	if not itemLink then
		return affixes
	end

	scannerTooltip:ClearLines()
	scannerTooltip:SetHyperlink(itemLink)

	-- Scan all tooltip lines
	for i = 1, scannerTooltip:NumLines() do
		local line = _G['LibsRemixPowerLevelScannerTooltipTextLeft' .. i]
		if line then
			local text = line:GetText()
			if text then
				affixes[text] = true
			end
		end
	end

	return affixes
end

---Check if item has any blacklisted affixes
---@param itemLink string
---@return boolean
function module:HasBlacklistedAffix(itemLink)
	if not self.DB.affixBlacklist then
		return false
	end

	local affixes = self:ScanItemAffixes(itemLink)
	for affixText in pairs(affixes) do
		for blacklistedAffix in pairs(self.DB.affixBlacklist) do
			if affixText:find(blacklistedAffix, 1, true) then
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
	local minLevelDiff = self.DB.minLevelDiff or 0
	local maxQuality = self.DB.maxQuality or Enum.ItemQuality.Rare

	local scrappableItems = self:GetScrappableItems()
	local filteredItems = {}

	for _, item in ipairs(scrappableItems) do
		local equippedItemLevel = self:GetMinLevelForInvType(item.invType)
		if equippedItemLevel and equippedItemLevel - item.level >= minLevelDiff and item.quality <= maxQuality then
			if not self:HasBlacklistedAffix(item.link) then
				table.insert(filteredItems, item)

				if capReturn and #filteredItems >= capReturn then
					break
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

	if #itemsToScrap < SCRAPPING_MACHINE_MAX_SLOTS then
		if self:GetNumActiveScrap() >= #itemsToScrap then
			return
		end
	end

	if C_ScrappingMachineUI.HasScrappableItems() then
		return
	end

	C_ScrappingMachineUI.RemoveAllScrapItems()
	for _, item in ipairs(itemsToScrap) do
		self:ScrapItemFromBag(item.bagID, item.slotID)
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

	C_Timer.After(
		0.1,
		function()
			self:AutoScrapBatch()
		end
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
	qualityLabel:SetPoint('TOPLEFT', frame, 'TOPLEFT', 15, -30)
	qualityLabel:SetText('Max Quality:')

	-- Quality dropdown
	local qualityTexts = {
		[Enum.ItemQuality.Common] = '|cffFFFFFFCommon|r',
		[Enum.ItemQuality.Uncommon] = '|cff1EFF00Uncommon|r',
		[Enum.ItemQuality.Rare] = '|cff0070DDRare|r',
		[Enum.ItemQuality.Epic] = '|cffA335EEEpic|r'
	}

	local qualityDropdown = CreateFrame('Frame', 'LibsRemixPowerLevelQualityDropdown', frame, 'UIDropDownMenuTemplate')
	qualityDropdown:SetPoint('TOPLEFT', qualityLabel, 'BOTTOMLEFT', -15, -5)
	UIDropDownMenu_SetWidth(qualityDropdown, 200)

	-- Initialize dropdown with function that gets called each time it opens
	UIDropDownMenu_Initialize(
		qualityDropdown,
		function(_, level)
			local qualities = {
				{text = '|cffFFFFFFCommon|r', value = Enum.ItemQuality.Common},
				{text = '|cff1EFF00Uncommon|r', value = Enum.ItemQuality.Uncommon},
				{text = '|cff0070DDRare|r', value = Enum.ItemQuality.Rare},
				{text = '|cffA335EEEpic|r', value = Enum.ItemQuality.Epic}
			}
			for _, quality in ipairs(qualities) do
				local info = UIDropDownMenu_CreateInfo()
				info.text = quality.text
				info.value = quality.value
				info.checked = module.DB.maxQuality == quality.value
				info.func = function()
					module.DB.maxQuality = quality.value
					UIDropDownMenu_SetText(qualityDropdown, quality.text)
					module:RefreshItemList()
				end
				UIDropDownMenu_AddButton(info, level)
			end
		end
	)

	-- Set initial text from saved value
	UIDropDownMenu_SetText(qualityDropdown, qualityTexts[module.DB.maxQuality])

	-- Min level label
	local minLevelLabel = frame:CreateFontString(nil, 'ARTWORK', 'GameFontNormalSmall')
	minLevelLabel:SetPoint('TOPLEFT', qualityDropdown, 'BOTTOMLEFT', 15, -5)
	minLevelLabel:SetText('Min Item Level Difference:')

	-- Min level editbox
	local minLevelBox = CreateFrame('EditBox', nil, frame, 'InputBoxTemplate')
	minLevelBox:SetPoint('TOPLEFT', minLevelLabel, 'BOTTOMLEFT', 5, -5)
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
					module:RefreshItemList()
				end
			end
		end
	)

	-- Affix blacklist button (moved to right of min level box)
	local affixButton = CreateFrame('Button', nil, frame, 'UIPanelButtonTemplate')
	affixButton:SetSize(120, 22)
	affixButton:SetPoint('LEFT', minLevelBox, 'RIGHT', 10, 0)
	affixButton:SetText('Affix Blacklist')
	affixButton:SetScript(
		'OnClick',
		function()
			self:ShowAffixBlacklistWindow()
		end
	)

	-- Auto scrap checkbox
	local autoScrapCheck = CreateFrame('CheckButton', nil, frame, 'UICheckButtonTemplate')
	autoScrapCheck:SetPoint('TOPLEFT', minLevelBox, 'BOTTOMLEFT', -5, -5)
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
	scrollFrame:SetPoint('TOPLEFT', autoScrapCheck, 'BOTTOMLEFT', 5, -5)
	scrollFrame:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -25, 10)

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
	self.scrollChild = scrollChild
	self.itemButtons = {}

	-- Hook events
	ScrappingMachineFrame:HookScript(
		'OnShow',
		function()
			frame:Show()
			self:RefreshItemList()
			self:AutoScrap()
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

	LibRTC:RegisterEvent(
		'BAG_UPDATE_DELAYED',
		function()
			if ScrappingMachineFrame:IsShown() then
				self:RefreshItemList()
			end
		end
	)

	LibRTC:RegisterEvent(
		'SCRAPPING_MACHINE_PENDING_ITEM_CHANGED',
		function()
			self:RefreshItemList()
			self:AutoScrap()
		end
	)
end

---Get map of pending items
---@return table<string, boolean>
function module:GetMappedPendingItems()
	local pendingMap = {}
	for i = 1, SCRAPPING_MACHINE_MAX_SLOTS do
		local itemLoc = C_ScrappingMachineUI.GetCurrentPendingScrapItemLocationByIndex(i - 1)
		if itemLoc and itemLoc:IsValid() then
			local bagID, slotID = itemLoc:GetBagAndSlot()
			pendingMap[bagID .. '-' .. slotID] = true
		end
	end
	return pendingMap
end

---Clear all pending scrap items (called when filters change)
function module:ClearFilteredPendingItems()
	-- When filters change, just clear all pending items like Blizzard does
	if LibRTC.logger then
		LibRTC.logger.info('ClearFilteredPendingItems called - clearing all pending items')
	end
	C_ScrappingMachineUI.RemoveAllScrapItems()
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
			window.TitleText:SetText('Affix Blacklist')
		elseif window.TitleContainer and window.TitleContainer.TitleText then
			window.TitleContainer.TitleText:SetText('Affix Blacklist')
		end

		-- Instructions
		local instructions = window:CreateFontString(nil, 'ARTWORK', 'GameFontNormal')
		instructions:SetPoint('TOPLEFT', 15, -30)
		instructions:SetPoint('TOPRIGHT', -15, -30)
		instructions:SetJustifyH('LEFT')
		instructions:SetText('Items with these stats/affixes will be excluded from auto-scrapping.\nSelect from dropdowns or enter custom text.')

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
							else
								module.DB.affixBlacklist[stat] = true
							end
							self:RefreshBlacklistDisplay()
							self:RefreshItemList()
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
							self:RefreshItemList()
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
						button:SetTooltip(function(tooltip)
							tooltip:SetSpellByID(spellID)
						end)
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

		local addButton = CreateFrame('Button', nil, window, 'UIPanelButtonTemplate')
		addButton:SetSize(80, 22)
		addButton:SetPoint('LEFT', addBox, 'RIGHT', 5, 0)
		addButton:SetText('Add')
		addButton:SetScript(
			'OnClick',
			function()
				local text = addBox:GetText():trim()
				if text ~= '' then
					module.DB.affixBlacklist[text] = true
					addBox:SetText('')
					self:ClearFilteredPendingItems()
					self:RefreshBlacklistDisplay()
					self:RefreshItemList()
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

			btn.deleteBtn = CreateFrame('Button', nil, btn, 'UIPanelButtonTemplate')
			btn.deleteBtn:SetSize(65, 20)
			btn.deleteBtn:SetPoint('RIGHT', -5, 0)
			btn.deleteBtn:SetText('Remove')

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
				self:ClearFilteredPendingItems()
				self:RefreshBlacklistDisplay()
				self:RefreshItemList()
			end
		)
		btn:Show()

		yOffset = yOffset + 24
	end

	-- Update scroll height
	window.scrollChild:SetHeight(math.max(yOffset, 1))
end
