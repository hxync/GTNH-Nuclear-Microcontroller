local component, computer = component, computer
local component_list, component_proxy, computer_uptime, modem, modem_broadcast = component.list, component.proxy, computer.uptime
do
    local temp = component_list("modem")()
    if temp then
        modem = component_proxy(temp)
        modem_broadcast = modem.broadcast
        modem.open(6978)
        modem.setWakeMessage("_NUCLEAR_SEARCH")
        pcall(modem.setStrength, 0)
    end
end
local transposer, redstone = component_proxy(component_list("transposer")()), component_proxy(component_list("redstone")())
local transposer_getAllStacks, transposer_transferItem, transposer_getStackInSlot, redstone_getInput, redstone_setOutput = transposer.getAllStacks, transposer.transferItem, transposer.getStackInSlot, redstone.getInput, redstone.setOutput

local fuelRodSlot, coolantCellSlot, possibleSideRedstone, fuelRod, coolantCell, isMEInterfaceMode, isActive, minCoolantCellDurability, sideOutput, sideReactorChamber, sideRedstone, damageRecords = {}, {}, {}
local isCoolant = {[3]=0.7,[6]=0.4,[9]=0.4,[10]=0.6,[15]=0.6,[22]=0.9,[26]=1,[29]=1,[33]=0.9,[40]=0.6,[45]=0.6,[46]=0.4,[49]=0.4,[52]=0.7}
local setActive, search, getItemSlot, check, sleep, initialize, main

initialize = function()
    local prefix, typeInventory = "gregtech:gt.", {}
    local fuelRodList = { [prefix.."rodUranium4"]=13, [prefix.."rodHighDensityUranium4"]=13, [prefix.."rodMOX4"]=13,
                          [prefix.."rodHighDensityPlutonium4"]=13, [prefix.."rodNaquadria4"]=13, [prefix.."rodNaquadah32"]=1050,
                          [prefix.."rodTiberium4"]=13, [prefix.."rodExcitedUranium4"]=200, [prefix.."rodExcitedPlutonium4"]=200 }
    local coolantCellList = { [prefix.."60k_Helium_Coolantcell"]=6, [prefix.."180k_Helium_Coolantcell"]=18, [prefix.."360k_Helium_Coolantcell"]=36,
                              [prefix.."60k_NaK_Coolantcell"]=6, [prefix.."180k_NaK_Coolantcell"]=18, [prefix.."360k_NaK_Coolantcell"]=36,
                              [prefix.."180k_Space_Coolantcell"]=18, [prefix.."360k_Space_Coolantcell"]=36, [prefix.."540k_Space_Coolantcell"]=54,
                              [prefix.."1080k_Space_Coolantcell"]=108, [prefix.."neutroniumHeatCapacitor"]=1e5 }
    for i=5,0,-1 do
        local function searchInitializing()
            local info, emptySlotCount = transposer_getAllStacks(i), 0
            for j=1,info.count() do
                local stack = info()
                local name = stack.name
                if fuelRodList[name] then
                    if fuelRod and fuelRod ~= name then error("出现了多种类型的燃料棒") end
                    fuelRod, fuelRodSlot[i] = name, {}
                elseif coolantCellList[name] and stack.damage < 70 then
                    if coolantCell and coolantCell ~= name then error("出现了多种类型的冷却单元") end
                    coolantCell, coolantCellSlot[i] = name, {}
                else
                    emptySlotCount = emptySlotCount + 1
                end
            end
            return emptySlotCount == info.count()
        end
        local name = transposer.getInventoryName(i)
        typeInventory[i] = name
        if name == "blockReactorChamber" then
            if transposer.getInventorySize(i) < 54 then error("核反应堆过小") end
            sideReactorChamber, typeInventory[i] = i, 1
        elseif name == "tile.appliedenergistics2.BlockInterface" or name == "tile.fluid_interface" then
            if isMEInterfaceMode then error("转运器附近存在多个ME接口") end
            isMEInterfaceMode, fuelRodSlot[i], coolantCellSlot[i] = true, {}, {}
            fuelRod, coolantCell = nil
            searchInitializing()
            sideOutput = i
        elseif name then
            if not isMEInterfaceMode and searchInitializing() then
                sideOutput = i
            end
        end
    end
    if not fuelRod then
        error("未识别到燃料棒")
    elseif not coolantCell then
        error("未识别到冷却单元")
    elseif not sideOutput then
        error("未识别到输出容器")
    elseif not sideReactorChamber then
        error("未识别到核反应堆")
    end
    minCoolantCellDurability = math.ceil( 2 * fuelRodList[fuelRod] / coolantCellList[coolantCell])
    if minCoolantCellDurability > 20 then
        error("冷却单元热容过小")
    end
    search(1)
    search()
    check()
    if sideReactorChamber < 2 then
        sideRedstone = sideReactorChamber
    else
        for i=2,5 do
            if redstone.getComparatorInput(i) < 1 then
                possibleSideRedstone[#possibleSideRedstone+1] = i
            end
        end
        damageRecords = {}
    end
    computer.pushSignal("redstone_changed")
    sleep(0.1)
    computer.beep(500,1)
end

setActive = function(active)
    if sideRedstone then
        redstone_setOutput(sideRedstone, active and 1 or 0)
    else
        for i=1,#possibleSideRedstone do
            redstone_setOutput(possibleSideRedstone[i], active and 1 or 0)
        end
        if active then
            local damageNow = transposer_getStackInSlot(sideReactorChamber, 26).damage
            if #damageRecords == 0 or damageNow ~= damageRecords[#damageRecords][1] then
                damageRecords[#damageRecords+1] = { damageNow, computer_uptime() }
            end
            if #damageRecords > 2 and not damageRecords[0] and 2 * damageRecords[#damageRecords][2] - damageRecords[#damageRecords-1][2] - computer_uptime() < 2 then
                redstone_setOutput(possibleSideRedstone[#possibleSideRedstone], 0)
                damageRecords[0], damageRecords[-1], possibleSideRedstone[#possibleSideRedstone] = #damageRecords, possibleSideRedstone[#possibleSideRedstone]
            end
            if damageRecords[0] and computer_uptime() + damageRecords[#damageRecords-1][2] - 2 * damageRecords[#damageRecords][2] > 2 then
                if #damageRecords == damageRecords[0] then
                    sideRedstone, possibleSideRedstone, damageRecords = #possibleSideRedstone + 2
                else
                    damageRecords[0] = nil
                end
            end
        else
            damageRecords = {}
        end
    end
end

search = function(isCoolant)
    local t, name, notFound = isCoolant and coolantCellSlot or fuelRodSlot, isCoolant and coolantCell or fuelRod, 1
    for k,_ in pairs(t) do
        local info = transposer_getAllStacks(k)
        for i=1,info.count() do
            local stack = info()
            if stack.name == name and (not isCoolant or stack.damage < 70) then
                notFound = nil
                t[k][i] = stack.size
            else
                t[k][i] = 0
            end
        end
    end
    if notFound then
        error("未找到"..(isCoolant and "冷却剂" or "燃料棒"))
    end
end

getItemSlot = function(isCoolant)
    local t = isCoolant and coolantCellSlot or fuelRodSlot
    for k,v in pairs(t) do
        for i=1,#v do
            if v[i] > 0 then
                if not isMEInterfaceMode then
                    (isCoolant and coolantCellSlot or fuelRodSlot)[k][i] = v[i] - 1
                end
                return k, i
            end
        end
    end
    search(isCoolant)
    return getItemSlot(isCoolant)
end

check = function(active)
    local info, notShutdown = transposer_getAllStacks(sideReactorChamber).getAll(), 1
    for i=1,54 do
        if isCoolant[i] and (info[i-1].name ~= coolantCell or info[i-1].damage > 98 - isCoolant[i] * minCoolantCellDurability) or not isCoolant[i] and info[i-1].name ~= fuelRod then
            local side, slot = getItemSlot(isCoolant[i])
            if isCoolant[i] and notShutdown then
                setActive()
                sleep(1)
                notShutdown=nil
            end
            transposer_transferItem(sideReactorChamber, sideOutput, 1, i)
            if transposer_transferItem(side, sideReactorChamber, 1, slot, i) == 0 then
                search(isCoolant[i])
                side, slot = getItemSlot(isCoolant[i])
                if transposer_transferItem(side, sideReactorChamber, 1, slot, i) == 0 then
                    error((isCoolant[i] and "冷却单元" or "燃料棒").."更换失败")
                end
            end
        end
    end
    setActive(active)
end

sleep = function(duration)
    local timeStart = computer_uptime()
    if modem then modem_broadcast(6978, "_NUCLEAR_HEARTBEAT", fuelRod, coolantCell, isActive) end
    while computer_uptime() - timeStart < (duration or 0.7) do
        local name, _1, _2, _3, _4, _5 = computer.pullSignal(0.1)
        if name == "modem_message" then
            if _5 == "_NUCLEAR_BOOT" then
                isActive = true
            elseif _5 == "_NUCLEAR_SHUTDOWN" then
                isActive = false
                setActive()
            end
        elseif name == "redstone_changed" then
            local maxInput, input = 0
            for i=0,5 do
                input = redstone_getInput(i)
                if input > maxInput then
                    maxInput = input
                end
            end
            isActive = maxInput > 1
            if not isActive then setActive() end
        end
    end
end
main = function()
    while 1 do
        check(isActive)
        sleep()
    end
end

initialize()
local _, err = pcall(main)
setActive()
if modem then
    modem_broadcast(6978, "_NUCLEAR_BREAKDOWN", err)
end
error(err)