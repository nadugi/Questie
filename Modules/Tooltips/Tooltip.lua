---@class QuestieTooltips
local QuestieTooltips = QuestieLoader:CreateModule("QuestieTooltips");
local _QuestieTooltips = QuestieTooltips.private
-------------------------
--Import modules.
-------------------------
---@type QuestieComms
local QuestieComms = QuestieLoader:ImportModule("QuestieComms");
---@type QuestieLib
local QuestieLib = QuestieLoader:ImportModule("QuestieLib");
---@type QuestiePlayer
local QuestiePlayer = QuestieLoader:ImportModule("QuestiePlayer");
---@type QuestieDB
local QuestieDB = QuestieLoader:ImportModule("QuestieDB");

local tinsert = table.insert
QuestieTooltips.lastGametooltip = ""
QuestieTooltips.lastGametooltipCount = -1;
QuestieTooltips.lastGametooltipType = "";
QuestieTooltips.lastFrameName = "";

QuestieTooltips.lookupByKey = {
    --["u_Grell"] = {questid, {"Line 1", "Line 2"}}
}
QuestieTooltips.lookupKeysByQuestId = {
    --["questId"] = {"u_Grell", ... }
}

local _InitObjectiveTexts

-- key format:
--  The key is the string name of the object the tooltip is relevant to,
--  started with a small flag that specifies the type:
--        units: u_
--        items: i_
--      objects: o_
---@param questId number
---@param key string
---@param objective table
function QuestieTooltips:RegisterObjectiveTooltip(questId, key, objective)
    if QuestieTooltips.lookupByKey[key] == nil then
        QuestieTooltips.lookupByKey[key] = {};
    end
    if QuestieTooltips.lookupKeysByQuestId[questId] == nil then
        QuestieTooltips.lookupKeysByQuestId[questId] = {}
    end
    local tooltip = {};
    tooltip.questId = questId;
    tooltip.objective = objective
    QuestieTooltips.lookupByKey[key][tostring(questId) .. " " .. objective.Index] = tooltip
    table.insert(QuestieTooltips.lookupKeysByQuestId[questId], key)

    --We want to cache gameobjects for future use within tooltips, ugly but improves performance a lot
    local typ, id = strsplit("_", key);
    if(typ and id and typ == "o") then
        _QuestieTooltips:cacheGameObject(tonumber(id))
    end
end

---@param questId number
---@param npc table
function QuestieTooltips:RegisterQuestStartTooltip(questId, npc)
    local key = "m_" .. npc.id
    if QuestieTooltips.lookupByKey[key] == nil then
        QuestieTooltips.lookupByKey[key] = {};
    end
    if QuestieTooltips.lookupKeysByQuestId[questId] == nil then
        QuestieTooltips.lookupKeysByQuestId[questId] = {}
    end
    local tooltip = {};
    tooltip.questId = questId
    tooltip.npc = npc
    QuestieTooltips.lookupByKey[key][tostring(questId) .. " " .. npc.name] = tooltip
    table.insert(QuestieTooltips.lookupKeysByQuestId[questId], key)
end

---@param questId number
function QuestieTooltips:RemoveQuest(questId)
    Questie:Debug(DEBUG_SPAM, "[QuestieTooltips:RemoveQuest]", questId)
    if (not QuestieTooltips.lookupKeysByQuestId[questId]) then
        return
    end

    for _, key in pairs(QuestieTooltips.lookupKeysByQuestId[questId]) do
        QuestieTooltips.lookupByKey[key] = nil
    end

    QuestieTooltips.lookupKeysByQuestId[questId] = {}
end

---@param key string
function QuestieTooltips:GetTooltip(key)
    Questie:Debug(DEBUG_DEVELOP, "[QuestieTooltips:GetTooltip]", key)
    if key == nil then
        return nil
    end

    if GetNumGroupMembers() > 15 then
        return nil -- temporary disable tooltips in raids, we should make a proper fix
    end

    --Do not remove! This is the datastrucutre for tooltipData!
    --[[tooltipdata[questId] = {
        title = coloredTitle,
        objectivesText = {
            [objectiveIndex] = {
                [playerName] = {
                    [color] = color,
                    [text] = text
                }
            }
        }
    }]]--
    local tooltipData = {}
    local npcTooltip = {}

    if QuestieTooltips.lookupByKey[key] then
        local playerName = UnitName("player")
        for k, tooltip in pairs(QuestieTooltips.lookupByKey[key]) do
            if tooltip.npc then
                if Questie.db.char.showQuestsInNpcTooltip then
                    local questName, level = unpack(QuestieDB.QueryQuest(tooltip.questId, "name", "questLevel"))
                    local questString = QuestieLib:GetColoredQuestName(tooltip.questId, questName, level, Questie.db.global.enableTooltipsQuestLevel, true, true)
                    table.insert(npcTooltip, questString)
                end
            else
                local objective = tooltip.objective
                if (not objective.IsSourceItem) then
                    -- Tooltip was registered for a sourceItem and not a real "objective"
                    objective:Update()
                end

                local questId = tooltip.questId
                local objectiveIndex = objective.Index;
                if (not tooltipData[questId]) then
                    tooltipData[questId] = {}
                    tooltipData[questId].title = objective.QuestData:GetColoredQuestName();
                end

                if not QuestiePlayer.currentQuestlog[questId] then
                    QuestieTooltips.lookupByKey[key][k] = nil
                else
                    tooltipData[questId].objectivesText = _InitObjectiveTexts(tooltipData[questId].objectivesText, objectiveIndex, playerName)

                    local text;
                    local color = QuestieLib:GetRGBForObjective(objective)

                    if objective.Needed then
                        text = "   " .. color .. tostring(objective.Collected) .. "/" .. tostring(objective.Needed) .. " " .. tostring(objective.Description);
                        tooltipData[questId].objectivesText[objectiveIndex][playerName] = {["color"] = color, ["text"] = text};
                    else
                        text = "   " .. color .. tostring(objective.Description);
                        tooltipData[questId].objectivesText[objectiveIndex][playerName] = {["color"] = color, ["text"] = text};
                    end
                end
            end
        end
    end

    -- We are hovering over an NPC and don't want to show
    -- comms information
    if next(npcTooltip) then
        return npcTooltip
    end

    -- This code is related to QuestieComms, here we fetch all the tooltip data that exist in QuestieCommsData
    -- It uses a similar system like here with i_ID etc as keys.
    local anotherPlayer = false;
    if QuestieComms and QuestieComms.data:KeyExists(key) then
        ---@tooltipData @tooltipData[questId][playerName][objectiveIndex].text
        local tooltipDataExternal = QuestieComms.data:GetTooltip(key);
        for questId, playerList in pairs(tooltipDataExternal) do
            if (not tooltipData[questId]) then
                local questName, level = unpack(QuestieDB.QueryQuest(questId, "name", "questLevel"))
                local quest = QuestieDB:GetQuest(questId);
                if quest then
                    tooltipData[questId] = {}
                    tooltipData[questId].title = QuestieLib:GetColoredQuestName(questId, questName, level, Questie.db.global.enableTooltipsQuestLevel, true, true)
                end
            end
            for playerName, _ in pairs(playerList) do
                local playerInfo = QuestiePlayer:GetPartyMemberByName(playerName);
                if playerInfo or QuestieComms.remotePlayerEnabled[playerName] then
                    anotherPlayer = true
                    break
                end
            end
            if anotherPlayer then
                break
            end
        end
    end

    if QuestieComms and QuestieComms.data:KeyExists(key) and anotherPlayer then
        ---@tooltipData @tooltipData[questId][playerName][objectiveIndex].text
        local tooltipDataExternal = QuestieComms.data:GetTooltip(key);
        for questId, playerList in pairs(tooltipDataExternal) do
            if (not tooltipData[questId]) then
                local questName, level = unpack(QuestieDB.QueryQuest(questId, "name", "questLevel"))
                local quest = QuestieDB:GetQuest(questId);
                if quest then
                    tooltipData[questId] = {}
                    tooltipData[questId].title = QuestieLib:GetColoredQuestName(questId, questName, level, Questie.db.global.enableTooltipsQuestLevel, true, true)
                end
            end
            for playerName, objectives in pairs(playerList) do
                local playerInfo = QuestiePlayer:GetPartyMemberByName(playerName);
                if playerInfo or QuestieComms.remotePlayerEnabled[playerName] then
                    anotherPlayer = true;
                    for objectiveIndex, objective in pairs(objectives) do
                        if (not objective) then
                            objective = {}
                        end

                        tooltipData[questId].objectivesText =  _InitObjectiveTexts(tooltipData[questId].objectivesText, objectiveIndex, playerName)

                        local text;
                        local color = QuestieLib:GetRGBForObjective(objective)

                        if objective.required then
                            text = "   " .. color .. tostring(objective.fulfilled) .. "/" .. tostring(objective.required) .. " " .. objective.text;
                        else
                            text = "   " .. color .. objective.text;
                        end

                        tooltipData[questId].objectivesText[objectiveIndex][playerName] = { ["color"] = color, ["text"] = text};
                    end
                end
            end
        end
    end

    local tip
    local playerName = UnitName("player")

    for questId, questData in pairs(tooltipData) do
        --Initialize it here to return nil if tooltipData is empty.
        if (not tip) then
            tip = {}
        end
        local hasObjective = false
        local tempObjectives = {}
        for _, playerList in pairs(questData.objectivesText or {}) do
            for objectivePlayerName, objectiveInfo in pairs(playerList) do
                local playerInfo = QuestiePlayer:GetPartyMemberByName(objectivePlayerName)
                local playerColor
                local playerType = ""
                if playerInfo then
                    playerColor = "|c" .. playerInfo.colorHex
                elseif QuestieComms.remotePlayerEnabled[objectivePlayerName] and QuestieComms.remoteQuestLogs[questId] and QuestieComms.remoteQuestLogs[questId][objectivePlayerName] and (not Questie.db.global.onlyPartyShared or UnitInParty(objectivePlayerName)) then
                    playerColor = QuestieComms.remotePlayerClasses[playerName]
                    if playerColor then
                        playerColor = Questie:GetClassColor(playerColor)
                        playerType = " ("..QuestieLocale:GetUIString("Nearby")..")"
                    end
                end
                if objectivePlayerName == playerName and anotherPlayer then -- why did we have this case
                    local _, classFilename = UnitClass("player");
                    local _, _, _, argbHex = GetClassColor(classFilename)
                    objectiveInfo.text = objectiveInfo.text.." (|c"..argbHex.. objectivePlayerName .."|r"..objectiveInfo.color..")|r"
                elseif playerColor and objectivePlayerName ~= playerName then
                    objectiveInfo.text = objectiveInfo.text.." ("..playerColor.. objectivePlayerName .."|r"..objectiveInfo.color..")|r"..playerType
                end
                -- We want the player to be on top.
                if objectivePlayerName == playerName then
                    tinsert(tempObjectives, 1, objectiveInfo.text);
                    hasObjective = true
                elseif playerColor then
                    tinsert(tempObjectives, objectiveInfo.text);
                    hasObjective = true
                end
            end
        end
        if hasObjective then
            tinsert(tip, questData.title);
            for _, text in pairs(tempObjectives) do
                tinsert(tip, text);
            end
        end
    end
    return tip
end

_InitObjectiveTexts = function (objectivesText, objectiveIndex, playerName)
    if (not objectivesText) then
        objectivesText = {}
    end
    if (not objectivesText[objectiveIndex]) then
        objectivesText[objectiveIndex] = {}
    end
    if (not objectivesText[objectiveIndex][playerName]) then
        objectivesText[objectiveIndex][playerName] = {}
    end
    return objectivesText
end

function QuestieTooltips:Initialize()
    -- For the clicked item frame.
    ItemRefTooltip:HookScript("OnTooltipSetItem", _QuestieTooltips.AddItemDataToTooltip)
    ItemRefTooltip:HookScript("OnHide", function(self)
        if (not self.IsForbidden) or (not self:IsForbidden()) then -- do we need this here also
            QuestieTooltips.lastGametooltip = ""
            QuestieTooltips.lastItemRefTooltip = ""
            QuestieTooltips.lastGametooltipItem = nil
            QuestieTooltips.lastGametooltipUnit = nil
            QuestieTooltips.lastGametooltipCount = 0
            QuestieTooltips.lastFrameName = "";
        end
    end)

    -- For the hover frame.
    GameTooltip:HookScript("OnTooltipSetUnit", _QuestieTooltips.AddUnitDataToTooltip)
    GameTooltip:HookScript("OnTooltipSetItem", _QuestieTooltips.AddItemDataToTooltip)
    GameTooltip:HookScript("OnShow", function(self)
        if (not self.IsForbidden) or (not self:IsForbidden()) then -- do we need this here also
            QuestieTooltips.lastGametooltipItem = nil
            QuestieTooltips.lastGametooltipUnit = nil
            QuestieTooltips.lastGametooltipCount = 0
            QuestieTooltips.lastFrameName = "";
        end
    end)
    GameTooltip:HookScript("OnHide", function(self)
        if (not self.IsForbidden) or (not self:IsForbidden()) then -- do we need this here also
            QuestieTooltips.lastGametooltip = ""
            QuestieTooltips.lastItemRefTooltip = ""
            QuestieTooltips.lastGametooltipItem = nil
            QuestieTooltips.lastGametooltipUnit = nil
            QuestieTooltips.lastGametooltipCount = 0
        end
    end)

    --GameTooltip:HookScript("OnUpdate", function(self)
    --    if (not self.IsForbidden) or (not self:IsForbidden()) then
    --        --Because this is an OnUpdate we need to check that it is actually not a Unit or Item to think its a
    --        local uName, unit = self:GetUnit()
    --        local iName, link = self:GetItem()
    --        if (uName == nil and unit == nil and iName == nil and link == nil) then
    --            if  (QuestieTooltips.lastGametooltip ~= GameTooltipTextLeft1:GetText() or
    --                (not QuestieTooltips.lastGametooltipCount) or
    --                QuestieTooltips.lastGametooltipType ~= "object" or
    --                _QuestieTooltips:CountTooltip() < QuestieTooltips.lastGametooltipCount
    --            ) then
    --                _QuestieTooltips:AddObjectDataToTooltip(GameTooltipTextLeft1:GetText())
    --                QuestieTooltips.lastGametooltipCount = _QuestieTooltips:CountTooltip()
    --            end
    --        end
    --        QuestieTooltips.lastGametooltip = GameTooltipTextLeft1:GetText()
    --    end
    --end)

    GameTooltip:HookScript("OnTooltipSetDefaultAnchor", function (self)
        Questie:Debug(DEBUG_DEVELOP, "[Tooltip] - OnTooltipSetDefaultAnchor")
        --When this is called we know its a new frame, so we reset everything!
        if (not self.IsForbidden) or (not self:IsForbidden()) then -- do we need this here also
            QuestieTooltips.lastGametooltip = ""
            QuestieTooltips.lastItemRefTooltip = ""
            QuestieTooltips.lastGametooltipItem = nil
            QuestieTooltips.lastGametooltipUnit = nil
            QuestieTooltips.lastGametooltipCount = 0
            QuestieTooltips.lastFrameName = "";
        end
        -- A timer is needed here because GetUnit and GetItem only gets populated after this event,
        -- we use a 0ms timer to execute the code on the next frame.
        C_Timer.After(0, function ()
            if (not self.IsForbidden) or (not self:IsForbidden()) then
                -- We cache the "title" of the tooltip because we don't want to run the code multiple times
                local tooltipTitle = GameTooltipTextLeft1:GetText()

                local uName, unit = GameTooltip:GetUnit()
                local iName, link = GameTooltip:GetItem()
                -- Only execute code if its no a Unit or Item
                if (uName == nil and unit == nil and iName == nil and link == nil) then
                    -- We only want to run CountTooltip once, so we save the value
                    local tooltipCount = _QuestieTooltips:CountTooltip()

                    if  (QuestieTooltips.lastGametooltip ~= tooltipTitle or
                        (not QuestieTooltips.lastGametooltipCount) or
                        QuestieTooltips.lastGametooltipType ~= "object" or
                        tooltipCount < QuestieTooltips.lastGametooltipCount
                    ) then
                        _QuestieTooltips:AddObjectDataToTooltip(tooltipTitle)
                        QuestieTooltips.lastGametooltipCount = tooltipCount
                    end
                end
                QuestieTooltips.lastGametooltip = tooltipTitle
            end
        end)
    end)
end

