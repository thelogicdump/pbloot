PBLoot = {Locals = {}}

assert(DongleStub, string.format("PBloot requires DongleStub."))
DongleStub("Dongle-1.1"):New("PBLoot", PBLoot)
PBLoot.version = GetAddOnMetadata("PBLoot", "Version")
if PBLoot.version == "wowi:revision" then PBLoot.version = "SVN" end

local L = PBLoot.Locals

function PBLoot:Initialize()
    
	self.auctions = {}
	self.dkpList = {}
	self.itemList = {}
	
	self.initialBidFrameX = -400
	self.nextBidFrameX = self.initialBidFrameX
	self.frameWidth = 250
end

function PBLoot:Enable()
    L = PBLoot.Locals
        
    self.defaults = {
        profile = {
            auctions = {},
            dkpList = {},
            raids = {}
        }
    }
    
	self.acceptingBids = false
	self.handlingLoot = false
	
    self.db = self:InitializeDB("PBLootDB", self.defaults)
    self.profile = self.db.profile
    --self.auctions = self.profile.auctions
    --self.dkpList = self.profile.dkpList
    --self.raids = self.profile.raids
--    PBLoot:OptionsOnLoad()
--    PBLoot:EnableFrames()
    
    self:RegisterMessage("DONGLE_PROFILE_CHANGED")
    self:RegisterMessage("DONGLE_PROFILE_DELETED")
    self:RegisterMessage("DONGLE_PROFILE_RESET")

    self:RegisterEvent("CHAT_MSG_WHISPER","ParseWhisper")

    --self:RegisterMessage("PLAYER_REGEN_ENABLED")
    --self:RegisterMessage("PLAYER_REGEN_DISABLED")
    
    self.cmd = self:InitializeSlashCommand("PBLoot commands", "PBLOOT", "pbloot", "pb", "pbl")
	self.cmd:InjectDBCommands(self.db, "copy", "delete", "list","reset", "set")
	self.cmd:RegisterSlashHandler("printDkp - prints the DKP", "printDkp", "PrintDkp")
    self.cmd:RegisterSlashHandler("addPlayer - add player with DKP", "^addPlayer (.+) (.+)$", "AddPlayer")
    
	self.cmd:RegisterSlashHandler("open - open bidding on an item", "open (.+)$", "OpenAuction")
    self.cmd:RegisterSlashHandler("close - close bidding on an item", "close (.+)$", "CloseAuction")
    self.cmd:RegisterSlashHandler("closeall - cloase bidding on all items", "closeall", "CloseAllAuctions")
    self.cmd:RegisterSlashHandler("print - Print bids for an item", "print (.+)$", "PrintBids")
	self.cmd:RegisterSlashHandler("printall - Print bids for all items", "printall", "PrintAllBids")
	self.cmd:RegisterSlashHandler("clear - Remove bids for item", "remove (.+)$", "ClearAuction")
	self.cmd:RegisterSlashHandler("clearall - Clear all bids for all items", "clear", "ClearAllAuctions")
	self.cmd:RegisterSlashHandler("import - open the DKP import window", "import", "OpenImport")
end

StaticPopupDialogs["XML_IMPORT"] = {
	text = "Please paste the XML standings from www.raidbuilder.com",
	button1 = "Import",
	button2 = "Cancel",
	OnAccept = function() 
		xmlInput = getglobal(this:GetParent():GetName().."EditBox"):GetText()
		PBLoot:ParseDKP(xmlInput); end,
	timeout = 0,
	hasEditBox = 1,
	whileDead = 1,
	hideOnEscape = 1
};

function PBLoot:OpenImport()
	StaticPopup_Show("XML_IMPORT");
end

----------------------------------
--
-- Outgoing Whisper Block Hack
--
----------------------------------

OldHideOutgoingWhisper = ChatFrame_MessageEventHandler;
function HideOutgoingWhisper(self, event, ...)
	if (event == "CHAT_MSG_WHISPER_INFORM") then
		local found, _ = string.find(arg1, "^<PBLOOT>.*")
		if found then
			return
		end
	end
	
	OldHideOutgoingWhisper(self, event, ...);
end
ChatFrame_MessageEventHandler = HideOutgoingWhisper;

---------------------------
--
-- DKP Functions
--
---------------------------

function PBLoot:ParseDKP(xmlInput)
	self.dkpList = {}
    repeat
		found, _, CharacterInfo, xmlInput = string.find(xmlInput, "^.-%<character%s(.-)%/.-%>(.*)")
        if (found) then
            _, _, Name, DKP = string.find(CharacterInfo, '^name%=%"(.-)%".*dkp%=%"(.*)%"')
            self:AddPlayer(Name, tonumber(DKP))
        end
    until (found == nil)
end

---------------------------
--
-- DKP List Manipulation Functions
--
---------------------------

function PBLoot:AddPlayer(name, dkp)
	playerID = table.getn(self.dkpList) + 1
    table.insert(self.dkpList, {ID = playerID, name = name, dkp = dkp})
	return playerID
end

function PBLoot:RemovePlayer(playerID)
    for i, player in ipairs(self.dkpList) do
        if (player.ID == playerID) then
            table.remove(self.dkpList, i)
        end
    end
end

function PBLoot:FindPlayerByID(playerID)
    for i, player in ipairs(self.dkpList) do
        if (player.ID == playerID) then
			return player
        end
    end
end

function PBLoot:AdjustDkp(playerID, amount)
    for i, player in ipairs(self.dkpList) do
        if (player.ID == playerID) then
            player.dkp = player.dkp + amount
        end
    end
end

function PBLoot:SortDkpList()
    for i=2, (table.getn(self.dkpList)) do
        value = self.dkpList[i]
		j = i - 1
        while ((j >= 1) and (self.dkpList[j].dkp < value.dkp)) do
			self.dkpList[j + 1] = self.dkpList[j]
            j = j -1
        end
        self.dkpList[j + 1] = value
    end
end

function PBLoot:PrintDkp()
    self:SortDkpList(self.dkpList)
    dkpString = ""
    for i, player in ipairs(self.dkpList) do
        dkpString = player.name .. " " .. player.dkp --.. "\n"
		self:Print(player.name .. " " .. player.dkp)
    end
end

---------------------------
--
-- Whisper Parsing Functions
--
---------------------------

function PBLoot:ParseWhisper()
	local found, _ = string.find(arg1, "^%s*|c.*")
	if (found and self.acceptingBids) then
		local found, _, itemID, itemName, bidType = string.find(arg1, "^%s*|c%x+|Hitem%:(.-)%:.+|h%[(.*)%]%s*(.+)")
		typeOfBid = self:ParseBidType(bidType)
		self:RegisterBid(arg2, itemID, typeOfBid)
		SendChatMessage("<PBLOOT> Recieved your bid on " .. itemName .. " for your " .. typeOfBid, "WHISPER", "Common", arg2)
	else
		if ((self.handlingLoot == true) and (arg2 ~= UnitName("player"))) then
			if (self.acceptingBids == true) then
				SendChatMessage("<PBLOOT> If you were trying to place a bid, please use the correct format. Itemlink then main/off", "WHISPER", "Common", arg2)
			else
				SendChatMessage("<PBLOOT> Bids have closed for all current items, if you're bidding late you will need to make sure you get my attention", "WHISPER", "Common", arg2)
			end
		end
	end
end

function PBLoot:ParseBidType(typeOfBid)
	typeOfBid = string.lower(typeOfBid)
    if (string.find(typeOfBid, "main") ~= nil) then
        typeOfBid = "Mainspec"
    elseif (string.find(typeOfBid, "off") ~= nil) then
        typeOfBid = "Offspec"
	elseif (string.find(typeOfBid, "side") ~= nil) then
        typeOfBid = "Sidegrade"
	else
		typeOfBid = "Mainspec"
    end
	
	return typeOfBid
end

---------------------------
--
-- Loot Handling Functions
--
---------------------------

function PBLoot:AwardItem(itemID, playerID, dkpValue)
	self:AdjustDkp(playerID, -dkpValue)
	self:AddItemToList(itemID, playerID, dkpValue)
end

function PBLoot:AddItemToList(itemID, playerID, dkpValue)
	table.insert(self.itemList, {itemID = itemID, playerID = playerID, dkpValue = dkpValue})
end

---------------------------
--
-- Auction Control Functions
--
---------------------------

function PBLoot:FindAuction(itemID)
	for i, auction in ipairs(self.auctions) do
        if (auction.itemID == itemID) then
            return auction
        end
    end
end

function PBLoot:OpenAuction(itemLink)
	self:ClearAuction(itemLink)
    -- Two methods. 1 GUI 2 /openBid {item}
    local found, _, itemID, itemName    = string.find(itemLink, "^%s*|c%x+|Hitem%:(.-)%:.+|h%[(.*)%]")
	-- SendChatMessage("Opening Bids for " .. itemLink, "RAID_WARNING", "Common")
	local bidBox = self:CreateBidBox(itemLink)
	table.insert(self.auctions, {itemID = itemID, itemName = itemName, open = true, mainBids = {}, sideBids = {}, offBids = {}, bidBox = bidBox})
	self.acceptingBids = true
	self.handlingLoot = true
	
	self.nextBidFrameX = self.initialBidFrameX
end

function PBLoot:CloseAuction(itemLink)
	local found, _, itemID, itemName    = string.find(itemLink, "^%s*|c%x+|Hitem%:(.-)%:.+|h%[(.*)%]")
	self:Print("Close Auction for " .. itemLink)
	-- SendChatMessage("Closing Bids for " .. itemLink, "RAID_WARNING", "Common");
    
	self.acceptingBids = false --Assume that no bids are being accepted & re-enable if open auction found

	for i, auction in ipairs(self.auctions) do
        if (auction.itemID == itemID) then
            auction.open = false
			auction.bidBox:SetHeight(auction.bidBox:GetHeight() + 20)
        else
			if (auction.open == true) then
				self.acceptingBids = true
			end
		end
    end
end

function PBLoot:CloseAllAuctions()
	-- SendChatMessage("Closing All Bids", "RAID", "Common")
    
	for i, auction in ipairs(self.auctions) do
        auction.open = false
		auction.bidBox:SetHeight(auction.bidBox:GetHeight() + 20)
    end
	self.acceptingBids = false
end

function PBLoot:ClearAuction(itemLink)
	local found, _, itemID, itemName    = string.find(itemLink, "^%s*|c%x+|Hitem%:(.-)%:.+|h%[(.*)%]")
	self:Print("Clear Auction for " .. itemLink)
	
	self.handlingLoot = false --Assume that no loot is being handled & re-enable if open auction found

	for i, auction in ipairs(self.auctions) do
        if (auction.itemID == itemID) then
			auction.bidBox:Hide()
            auction.bidBox = nil
			table.remove(self.auctions, i)
		else
		    self.handlingLoot = true
        end
    end
end

function PBLoot:ClearAllAuctions()
	-- SendChatMessage("Clearing all bids", "CHANNEL", "Common", GetChannelName("pbloot"));

	for i, auction in ipairs(self.auctions) do
		if (auction.bidBox ~= nil) then
            auction.bidBox = nil
		end
    end
	self.handlingLoot = false
	self.auctions = {}
end

function PBLoot:RegisterBid(name, itemID, typeOfBid)

	playerFound = false
	for k, player in ipairs(self.dkpList) do
		if (player.name == name) then
			playerID = k
			playerFound = true
		end
	end

	if (playerFound == false) then
		playerID = self:AddPlayer(name, 0)
	end

    for i, auction in ipairs(self.auctions) do
        if (auction.itemID == itemID) then
            if (typeOfBid == "Mainspec") then
				table.insert(auction.mainBids, {ID = playerID})
            elseif (typeOfBid == "Sidegrade") then
				table.insert(auction.sideBids, {ID = playerID})
			else
				table.insert(auction.offBids, {ID = playerID})
            end
			self:UpdateBidList(auction)
        end
    end
end

---------------------------
--
-- Print Auctions Functions
--
---------------------------

function PBLoot:SortBids(list)
	numBids = table.getn(list)
	for i=1, (numBids - 1) do
		for j=1, (numBids - i) do
			if (self.dkpList[list[j].ID].dkp < self.dkpList[list[j + 1].ID].dkp) then
				temp = list[j]
				list[j] = list[j + 1]
				list[j + 1] = temp
			end
		end
	end
end

function PBLoot:PrintBids(itemLink)
    local found, _, itemID, itemName    = string.find(itemLink, "^%s*|c%x+|Hitem%:(.-)%:.+|h%[(.*)%]")

    SendChatMessage("Bids for " .. itemName .. " " .. itemID, "CHANNEL", "Common", GetChannelName("pbloot"));
    for i, auction in ipairs(self.auctions) do
        if (auction.itemID == itemID) then
            self:SortBids(auction.mainBids)
            self:SortBids(auction.sideBids)
            self:SortBids(auction.offBids)

			SendChatMessage("Main Spec Bids", "CHANNEL", "Common", GetChannelName("pbloot"));
            for j, bid in ipairs(auction.mainBids) do
				player = self:FindPlayerByID(bid.ID)
				SendChatMessage("    " .. player.name .. " " .. player.dkp, "CHANNEL", "Common", GetChannelName("pbloot"));
            end

			SendChatMessage("Sidegrade Bids", "CHANNEL", "Common", GetChannelName("pbloot"));
            for j, bid in ipairs(auction.sideBids) do
				player = self:FindPlayerByID(bid.ID)
				SendChatMessage("    " .. player.name .. " " .. player.dkp, "CHANNEL", "Common", GetChannelName("pbloot"));
            end

			SendChatMessage("Off Spec Bids", "CHANNEL", "Common", GetChannelName("pbloot"));
            for j, bid in ipairs(auction.offBids) do
				player = self:FindPlayerByID(bid.ID)	
				SendChatMessage("    " .. player.name .. " " .. player.dkp, "CHANNEL", "Common", GetChannelName("pbloot"));
            end
        end
    end
end

function PBLoot:PrintAllBids()
    -- Two methods. 1 GUI 2 /printBids
    for i, auction in ipairs(self.auctions) do
		SendChatMessage("Bids for " .. auction.itemName .. " " .. auction.itemID, "CHANNEL", "Common", GetChannelName("pbloot"));
		self:SortBids(auction.mainBids)
		self:SortBids(auction.sideBids)
		self:SortBids(auction.offBids)
		
		SendChatMessage("Main Spec Bids", "CHANNEL", "Common", GetChannelName("pbloot"));
		for j, bid in ipairs(auction.mainBids) do
			player = self:FindPlayerByID(bid.ID)
			SendChatMessage("    " .. player.name .. " " .. player.dkp, "CHANNEL", "Common", GetChannelName("pbloot"));
		end

		SendChatMessage("Sidegrade Bids", "CHANNEL", "Common", GetChannelName("pbloot"));
		for j, bid in ipairs(auction.sideBids) do
			player = self:FindPlayerByID(bid.ID)
			SendChatMessage("    " .. player.name .. " " .. player.dkp, "CHANNEL", "Common", GetChannelName("pbloot"));
		end

		SendChatMessage("Off Spec Bids", "CHANNEL", "Common", GetChannelName("pbloot"));
		for j, bid in ipairs(auction.offBids) do
			player = self:FindPlayerByID(bid.ID)
			SendChatMessage("    " .. player.name .. " " .. player.dkp, "CHANNEL", "Common", GetChannelName("pbloot"));
		end
	end
end

function PBLoot:UpdateBidList(auction)
    local t, lineCount
    t = ""
	lineCount = 1
	

	self:SortBids(auction.mainBids)
	self:SortBids(auction.sideBids)
	self:SortBids(auction.offBids)
	
    for i, bid in ipairs(auction.mainBids) do
		if (i == 1) then
			t = t .. "Mainspec:|n"
			lineCount = lineCount + 1
		end

		player = self:FindPlayerByID(bid.ID)
		t = t .. player.name .. " (" .. PBLoot:Round(player.dkp,3) .. ")|n"

		lineCount = lineCount + 1
    end

	for i, bid in ipairs(auction.offBids) do
		if (i == 1) then
			t = t .. "|nOffspec:|n"
			lineCount = lineCount + 2
        end

		player = self:FindPlayerByID(bid.ID)
		t = t .. player.name .. " (" .. PBLoot:Round(player.dkp,3) .. ")|n"

		lineCount = lineCount + 1
    end

	for i, bid in ipairs(auction.sideBids) do
		if (i == 1) then
			t = t .. "|nSidegrade:|n"
			lineCount = lineCount + 2
		end

		player = self:FindPlayerByID(bid.ID)
		t = t .. player.name .. " (" .. PBLoot:Round(player.dkp,3) .. ")|n"

		lineCount = lineCount + 1
    end
	
	local lineHeight = 14
	auction.bidBox:SetHeight(auction.bidBox.baseHeight + lineCount * lineHeight)
	auction.bidBox.bidderList:SetHeight(lineCount * lineHeight)
	auction.bidBox.bidderList:SetText(t)
	
	return t	
end

function PBLoot:CreateBidBox(itemLink)
	--local test = CreateFrame("Frame", "AuctionFrame",UIParent,"PBLoot_AuctionFrame")
	
	--test:SetFrameStrata("BACKGROUND")
	--test:SetPoint("CENTER",0,0)
	--AuctionFrame.itemLink = itemLink
	
    local f = CreateFrame("Frame",nil,UIParent)
	f:SetFrameStrata("BACKGROUND")
	f:SetWidth(self.frameWidth)

	f:SetPoint("CENTER",self.nextBidFrameX,0)
	self.nextBidFrameX = self.nextBidFrameX + self.frameWidth
	f.baseHeight = 54

	local t = f:CreateTexture(nil,"BACKGROUND")
	t:SetAllPoints(f)
	t:SetTexture(0,0,0)
	t:SetAlpha(0.9)
	f.texture = t

	
	f:EnableMouse(true)	
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:CreateTitleRegion()
	f:GetTitleRegion():SetAllPoints(true)
	
	itemTitle = f:CreateFontString(nil,"ARTWORK","ChatFontNormal")
	f.itemTitle = itemTitle
	itemTitle:SetParent(f)
	itemTitle:SetWidth(self.frameWidth)
	itemTitle:SetHeight(84)
	itemTitle:SetFontObject(GameFontNormal)
	itemTitle:SetPoint("TOPLEFT",0,-2)
	
	itemTitle:SetNonSpaceWrap(false)
	itemTitle:SetJustifyV("TOP")
	
	
	name,_,itemRarity,itemLevel,_,itemType,itemSubType,_,itemEquipLoc = GetItemInfo(itemLink)
	
	local locationText = " "
	
	baseCost = 0
	if itemLevel == 213 then
		baseCost = 141
	end
	
	if itemLevel == 226 then
		baseCost = 200
	end
	
	if itemLevel == 232 then
		baseCost = 234
	end
	
	if itemLevel == 239 then
		baseCost = 283
	end

	costGroup = {}
	costModifier = {}
	
	i = 0
	
	if itemEquipLoc == "INVTYPE_HEAD" then
		locationText = "Head"
		costGroup[i] = "All"
		costModifier[i] = 1
		i = i + 1
	end
	
	if itemEquipLoc == "INVTYPE_NECK" then
		locationText = "Neck"
		costGroup[i] = "All"
		costModifier[i] = 0.5
		i = i + 1
	end
	
	if itemEquipLoc == "INVTYPE_SHOULDER" then
		locationText = "Shoulder"
		costGroup[i] = "All"
		costModifier[i] = 0.75
		i = i + 1
	end
	
	if itemEquipLoc == "INVTYPE_CHEST" then
		locationText = "Chest"
		costGroup[i] = "All"
		costModifier[i] = 1
		i = i + 1
	end
	
	if itemEquipLoc == "INVTYPE_ROBE" then
		locationText = "Chest"
		costGroup[i] = "All"
		costModifier[i] = 1
		i = i + 1
	end
	
	if itemEquipLoc == "INVTYPE_WAIST" then
		locationText = "Waist"
		costGroup[i] = "All"
		costModifier[i] = 0.75
		i = i + 1
	end
	
	if itemEquipLoc == "INVTYPE_LEGS" then
		locationText = "Legs"
		costGroup[i] = "All"
		costModifier[i] = 1
		i = i + 1
	end
	
	if itemEquipLoc == "INVTYPE_FEET" then
		locationText = "Feet"
		costGroup[i] = "All"
		costModifier[i] = 0.75
		i = i + 1
	end
	
	if itemEquipLoc == "INVTYPE_WRIST" then
		locationText = "Wrist"
		costGroup[i] = "All"
		costModifier[i] = 0.5
		i = i + 1
	end
	
	if itemEquipLoc == "INVTYPE_HAND" then
		locationText = "Hands"
		costGroup[i] = "All"
		costModifier[i] = 0.75
		i = i + 1
	end
	
	if itemEquipLoc == "INVTYPE_FINGER" then
		locationText = "Finger"
		costGroup[i] = "All"
		costModifier[i] = 0.5
		i = i + 1
	end
	
	if itemEquipLoc == "INVTYPE_TRINKET" then
		locationText = "Trinket"
		costGroup[i] = "All"
		costModifier[i] = 0.75
		i = i + 1
	end
	
	if itemEquipLoc == "INVTYPE_CLOAK" then
		locationText = "Cloak"
		costGroup[0] = "All"
		costModifier[0] = 0.5
		i = i + 1
	end
	
	if itemEquipLoc == "INVTYPE_WEAPON" then
		locationText = "1H Weapon"
		costGroup[i] = "Standard"
		costModifier[i] = 1.5
		i = i + 1
		costGroup[i] = "DW Melee"
		costModifier[i] = 1
		i = i + 1
		costGroup[i] = "Hunter/Tank"
		costModifier[i] = 0.5
		i = i + 1
	end
	
	if itemEquipLoc == "INVTYPE_SHIELD" then
		locationText = "Shield"
		costGroup[i] = "Tank"
		costModifier[i] = 1.5
		i = i + 1
		costOptions[i]["Healer"] = "All"
		costModifier[i] = 0.5 
		i = i + 1
	end
	
	if itemEquipLoc == "INVTYPE_2HWEAPON" then
		locationText = "2H Weapon"
		costGroup[i] = "Standard"
		costModifier[i] = 2
		i = i + 1
		costGroup[i] = "TG Warrior"
		costModifier[i] = 1.5
		i = i + 1
		costGroup[i] = "Hunter"
		costModifier[i] = 1
		i = i + 1
	end
	
	if itemEquipLoc == "INVTYPE_WEAPONMAINHAND" then
		locationText = "MH Weapon"
		costGroup[i] = "Standard"
		costModifier[i] = 1.5
		i = i + 1
		costGroup[i] = "DW Melee"
		costModifier[i] = 1
		i = i + 1
		costGroup[i] = "Hunter/Tank"
		costModifier[i] = 0.5
		i = i + 1
	end
	
	if itemEquipLoc == "INVTYPE_WEAPONOFFHAND" then
		locationText = "OH Weapon"
		costGroup[i] = "Standard"
		costModifier[i] = 1.5
		i = i + 1
		costGroup[i] = "DW Melee"
		costModifier[i] = 1
		i = i + 1
		costGroup[i] = "Hunter/Tank"
		costModifier[i] = 0.5		
		i = i + 1
	end
	
	if itemEquipLoc == "INVTYPE_HOLDABLE" then
		locationText = "Held in off-hand"
		costGroup[i] = "All"
		costModifier[i] = 0.5
		i = i + 1
	end
	
	if itemEquipLoc == "INVTYPE_RANGED" then
		locationText = "Bow"
		costGroup[i] = "Hunter"
		costModifier[i] = 1.5
		i = i + 1
		costGroup[i] = "Other"
		costModifier[i] = 0.5
		i = i + 1
	end
	
	if itemEquipLoc == "INVTYPE_THROWN" then
		locationText = "Thrown"
		costGroup[i] = "All"
		costModifier[i] = 0.5
		i = i + 1
	end
	
	if itemEquipLoc == "INVTYPE_RANGEDRIGHT" then
		locationText = "Ranged"
		costGroup[i] = "Hunter"
		costModifier[i] = 1.5
		i = i + 1
		costGroup[i] = "Other"
		costModifier[i] = 0.5
		i = i + 1
	end
	
	if itemEquipLoc == "INVTYPE_RELIC" then
		locationText = "Relic"
		costGroup[i] = "All"
		costModifier[i] = 0.5
		i = i + 1
	end
	
	if locationText == " " then
		locationText = itemEquipLoc
	end
	
	local costString = " "
		
	for j = 0, i-1 do
		if j==0 then
			costString = costGroup[j] .. ": " .. ceil(costModifier[j] * baseCost) .. " DKP"
		else
			costString = costString .. "|n" .. costGroup[j] .. ": " .. ceil(costModifier[j] * baseCost) .. " DKP"
		end
	end
	
	itemTitle:SetText(itemLink .. "|n" .. locationText .. " (ilvl " .. itemLevel .. ")" .. "|n" .. costString)
	
	f.baseHeight = (i+2) * 14 + 20
	f:SetHeight(f.baseHeight)
	
	bidderList = f:CreateFontString(nil,"ARTWORK","ChatFontNormal")
	f.bidderList = bidderList
	bidderList:SetParent(f)
	bidderList:SetWidth(self.frameWidth)
	bidderList:SetHeight(24)
	bidderList:SetPoint("TOPLEFT",0,-((i+2) * 14))
	
	bidderList:SetNonSpaceWrap(false)
	bidderList:SetJustifyV("TOP")
	bidderList:SetText("")
	
	closeButton = CreateFrame("Button", "closeButton", f, "OptionsButtonTemplate")
	closeButton:Show()
	closeButton:SetText("Close Auction")
	closeButton:SetPoint("BOTTOM",0,0)
	closeButton:SetHeight(20)
	closeButton:SetWidth(96)	
	closeButton:SetScript("OnClick", function() PBLoot:CloseAuction(itemLink); this:GetParent().closeButton:Hide(); this:GetParent().clearButton:Show()end)
	f.closeButton = closeButton
	
--	bidderList = CreateFrame("Frame", "bidderList", f, "UIDropDownMenuTemplate"); 
--	bidderList:SetPoint("BOTTOM",0,20);
--	UIDropDownMenu_SetWidth(bidderList, 80)
--	UIDropDownMenu_Initialize(bidderList, bidderList_Initialise); 
--	f.bidderList = bidderList
--	f.bidderList:Hide()
	
	clearButton = CreateFrame("Button", "clearButton", f, "OptionsButtonTemplate")
	clearButton:Show()
	clearButton:SetText("Clear Auction")
	clearButton:SetPoint("BOTTOM",0,0)
	clearButton:SetHeight(20)
	clearButton:SetWidth(96)
	clearButton:SetScript("OnClick", function() PBLoot:ClearAuction(itemLink);end)
	f.clearButton = clearButton
	f.clearButton:Hide()
	
	f:Show()
	
	return f
end

function PBLoot:CloseAuctionFrame(frame)
	frame:Hide()
end

function bidderList_Initialise()
	local info = UIDropDownMenu_CreateInfo();

	info.text = "First Menu Item"; --the text of the menu item
	info.value = 0; -- the value of the menu item. This can be a string also.
	info.func = function() print(this.owner) end; --sets the function to execute when this item is clicked
	info.owner = this:GetParent(); --binds the drop down menu as the parent of the menu item. This is very important for dynamic drop down menues.
	info.checked = nil; --initially set the menu item to being unchecked with a yellow tick
	info.icon = nil; --we can use this to set an icon for the drop down menu item to accompany the text
	UIDropDownMenu_AddButton(info); --Adds the new button to the drop down menu specified in the UIDropDownMenu_Initialise function. In this case, it's MyDropDownMenu

	info.text = "Second Menu Item";
	info.value = 1;
	info.func = function() MyDropDownMenuItem_OnClick() end;
	info.owner = this:GetParent();
	info.checked = nil;
	info.icon = nil;
	UIDropDownMenu_AddButton(info);

end

function PBLoot:Round(number,decimalPlaces)
	return floor(number * (10^decimalPlaces))/(10^decimalPlaces)
end

function PBLoot:RepositionFrames()
	self.nextBidFrameX = self.initialBidFrameX
	for i, auction in ipairs(self.auctions) do
		if auction.bidBox:IsVisible() then
		    auction.bidBox:SetPoint("CENTER",self.nextBidFrameX,0)
			self.nextBidFrameX = self.nextBidFrameX + self.frameWidth
		end
    end
end





--------------------------------------
--
-- DONGLE Stuff
--
--------------------------------------

function PBLoot:DONGLE_PROFILE_CHANGED(event, db, parent, svname, profileKey)
	if db == self.db then
		self:PrintF(L.PROFILE_CHANGED, profileKey)

		self.profile = self.db.profile
		self.profileKey = profileKey
	end
end

function PBLoot:DONGLE_PROFILE_RESET(event, db, parent, svname, profileKey)
	if db == self.db then

		self.profile = self.db.profile
		self.profileKey = profileKey
	
		self:Print(L.PROFILE_RESET, profileKey)
	end
end


function PBLoot:DONGLE_PROFILE_DELETED(event, db, parent, svname, profileKey)
	if db == self.db then
		self:PrintF(L.PROFILE_DELETED, profileKey)
	end
end