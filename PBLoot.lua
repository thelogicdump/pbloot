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
    
    self:RegisterMessage("DONGLE_PROFILE_CHANGED")
    self:RegisterMessage("DONGLE_PROFILE_DELETED")
    self:RegisterMessage("DONGLE_PROFILE_RESET")

    self:RegisterEvent("CHAT_MSG_WHISPER","ParseWhisper")
    
    self.cmd = self:InitializeSlashCommand("PBLoot commands", "PBLOOT", "pbloot", "pb", "pbl")
	self.cmd:InjectDBCommands(self.db, "copy", "delete", "list","reset", "set")
	self.cmd:RegisterSlashHandler("printDkp - prints the DKP", "printDkp", "PrintDkp")
    self.cmd:RegisterSlashHandler("addPlayer - add player with DKP", "^addPlayer (.+) (.+)$", "AddPlayer")
    
	self.cmd:RegisterSlashHandler("open - open bidding on an item", "open (.+)$", "OpenAuction")
    self.cmd:RegisterSlashHandler("close - close bidding on an item", "close (.+)$", "CloseAuction")
    self.cmd:RegisterSlashHandler("closeall - cloase bidding on all items", "closeall", "CloseAllAuctions")
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
		t = t .. player.name .. " (" .. Round(player.dkp,3) .. ")|n"

		lineCount = lineCount + 1
    end

	for i, bid in ipairs(auction.offBids) do
		if (i == 1) then
			t = t .. "|nOffspec:|n"
			lineCount = lineCount + 2
        end

		player = self:FindPlayerByID(bid.ID)
		t = t .. player.name .. " (" .. Round(player.dkp,3) .. ")|n"

		lineCount = lineCount + 1
    end

	for i, bid in ipairs(auction.sideBids) do
		if (i == 1) then
			t = t .. "|nSidegrade:|n"
			lineCount = lineCount + 2
		end

		player = self:FindPlayerByID(bid.ID)
		t = t .. player.name .. " (" .. Round(player.dkp,3) .. ")|n"

		lineCount = lineCount + 1
    end
	
	local lineHeight = 14
	auction.bidBox:SetHeight(auction.bidBox.baseHeight + lineCount * lineHeight)
	auction.bidBox.bidderList:SetHeight(lineCount * lineHeight)
	auction.bidBox.bidderList:SetText(t)
	
	return t	
end

function PBLoot:CreateBidBox(itemLink)
	
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
	
	
	costString = dkp_string(itemLevel, itemEquipLoc)
    if (costString == nil) then
        costString = ""
    end

	itemTitle:SetText(itemLink .. "|n" .. costString)
	
	f.baseHeight = 90
	f:SetHeight(f.baseHeight)
	
	bidderList = f:CreateFontString(nil,"ARTWORK","ChatFontNormal")
	f.bidderList = bidderList
	bidderList:SetParent(f)
	bidderList:SetWidth(self.frameWidth)
	bidderList:SetHeight(24)
	bidderList:SetPoint("TOPLEFT",0,-70)
	
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

function PBLoot:RepositionFrames()
	self.nextBidFrameX = self.initialBidFrameX
	for i, auction in ipairs(self.auctions) do
		if auction.bidBox:IsVisible() then
		    auction.bidBox:SetPoint("CENTER",self.nextBidFrameX,0)
			self.nextBidFrameX = self.nextBidFrameX + self.frameWidth
		end
    end
end

-----------------------
---- DKP AUTO CALC STUFF
-----------------------

function Round(num, idp)
    return tonumber(string.format("%." .. (idp or 0) .. "f", num))
end

function CalculateDKPValue(ilvl, slot_mod)
	return Round(0.483 * (2^(ilvl/26)) * slot_mod, 0)
end

function BuildDKPString(slot_name, ilvl, slot_mod)
    return string.format("%s: %s dkp|n", slot_name, CalculateDKPValue(ilvl, slot_mod))
end

function dkp_string(ilvl, slot)
	if slot == "INVTYPE_HEAD" then
		return BuildDKPString("Head", ilvl, 1)
	end
	if slot == "INVTYPE_NECK" then
		return BuildDKPString("Neck", ilvl, 0.5)
	end
	if slot == "INVTYPE_SHOULDER" then
		return BuildDKPString("Shoulder", ilvl, 0.75)
	end
	if slot == "INVTYPE_CHEST" then
		return BuildDKPString("Chest", ilvl, 1)
	end
	if slot == "INVTYPE_ROBE" then
		return BuildDKPString("Chest", ilvl, 1)
	end
	if slot == "INVTYPE_WAIST" then
		return BuildDKPString("Waist", ilvl, 0.75)
	end
	if slot == "INVTYPE_LEGS" then
		return BuildDKPString("Legs", ilvl, 1)
	end
	if slot == "INVTYPE_FEET" then
		return BuildDKPString("Feet", ilvl, 0.75)
	end
	if slot == "INVTYPE_WRIST" then
		return BuildDKPString("Wrist", ilvl, 0.5)
	end
	if slot == "INVTYPE_HAND" then
		return BuildDKPString("Hands", ilvl, 0.75)
	end
	if slot == "INVTYPE_CLOAK" then
		return BuildDKPString("Cloak", ilvl, 0.5)
	end
	if slot == "INVTYPE_FINGER" then
		return BuildDKPString("Finger", ilvl, 0.5)
	end
	if slot == "INVTYPE_TRINKET" then
		return BuildDKPString("Trinket", ilvl, 0.75)
	end
	if slot == "INVTYPE_WEAPON" then
		cost_string = BuildDKPString("OneH", ilvl, 1.5)
		cost_string = cost_string .. BuildDKPString("OneH Dual", ilvl, 1)
		cost_string = cost_string .. BuildDKPString("OneH Hunter/Tank", ilvl, 0.5)
		return cost_string
	end
	if slot == "INVTYPE_SHIELD" then
		cost_string = BuildDKPString("Tank Shield", ilvl, 1.5)
		cost_string = cost_string .. BuildDKPString("Healer Shield", ilvl, 0.5)
		return cost_string
	end
	if slot == "INVTYPE_2HWEAPON" then
		cost_string = BuildDKPString("2H", ilvl, 2)
		cost_string = cost_string .. BuildDKPString("2H TG", ilvl, 1.5)
		cost_string = cost_string .. BuildDKPString("2H Hunter", ilvl, 1)
		return cost_string
	end
	if slot == "INVTYPE_WEAPONMAINHAND" then
		cost_string = BuildDKPString("MH", ilvl, 1.5)
		cost_string = cost_string .. BuildDKPString("MH Dual", ilvl, 1)
		cost_string = cost_string .. BuildDKPString("MH Hunter/Tank", ilvl, 0.5)
		return cost_string
	end
	if slot == "INVTYPE_WEAPONOFFHAND" then
		cost_string = BuildDKPString("OH", ilvl, 1.5)
		cost_string = cost_string .. BuildDKPString("OH Dual", ilvl, 1)
		cost_string = cost_string .. BuildDKPString("OH Hunter/Tank", ilvl, 0.5)
		return cost_string
	end
	if slot == "INVTYPE_HOLDABLE" then
		return BuildDKPString("OH Frill", ilvl, 0.5)
	end
	if slot == "INVTYPE_RANGED" then
		cost_string = BuildDKPString("Ranged Hunter", ilvl, 1.5)
		cost_string = cost_string .. BuildDKPString("Ranged Other", ilvl, 0.5)
		return cost_string
	end
	if slot == "INVTYPE_THROWN" then
		cost_string = BuildDKPString("Ranged Hunter", ilvl, 1.5)
		cost_string = cost_string .. BuildDKPString("Ranged Other", ilvl, 0.5)
		return cost_string
	end
	if slot == "INVTYPE_RANGEDRIGHT" then
		cost_string = BuildDKPString("Ranged Hunter", ilvl, 1.5)
		cost_string = cost_string .. BuildDKPString("Ranged Other", ilvl, 0.5)
		return cost_string
	end
	if slot == "INVTYPE_RELIC" then
		return BuildDKPString("Relic", ilvl, 0.5)
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
	
		self:PrintF(L.PROFILE_RESET, profileKey)
	end
end


function PBLoot:DONGLE_PROFILE_DELETED(event, db, parent, svname, profileKey)
	if db == self.db then
		self:PrintF(L.PROFILE_DELETED, profileKey)
	end
end