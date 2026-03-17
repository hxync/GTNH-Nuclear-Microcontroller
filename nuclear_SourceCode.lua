--初始化computer与component
local component, computer = component, computer--使用局部变量代替，以便后续通过重命名变量来压缩代码
local component_list, component_proxy, computer_uptime = component.list, component.proxy, computer.uptime
local transposer, redstone = component_proxy(component_list("transposer")()), component_proxy(component_list("redstone")())

--每个函数均创建局部变量以压缩调用代码
local transposer_getAllStacks, transposer_transferItem, transposer_getStackInSlot, redstone_getInput, redstone_getOutput, redstone_setOutput = transposer.getAllStacks, transposer.transferItem, transposer.getStackInSlot, redstone.getInput, redstone.getOutput, redstone.setOutput

local isCoolant = {[3]=0.7,[6]=0.4,[9]=0.4,[10]=0.6,[15]=0.6,[22]=0.9,[26]=1,[29]=1,[33]=0.9,[40]=0.6,[45]=0.6,[46]=0.4,[49]=0.4,[52]=0.7}--索引为冷却单元槽位，值为该槽位吸收的热量与第26槽吸收热量的比值

--[[集中声明以压缩代码
local fuelRod, coolantCell, minCoolantCellDurability--燃料棒id，冷却单元id，冷却单元最低耐久
local fuelRodSlot, coolantCellSlot = {}, {}--索引为方向，值为子表，子表索引为槽位，值为该槽物品数量。通过缓存物品信息以降低更换耗时
local isMEInterfaceMode, isActive--是否为ME模式，是否向反应堆输出红石信号
local sideOutput, sideReactorChamber, sideRedstone--物品输出方向，反应堆方向(转运器)，反应堆方向(红石卡)
local possibleSideRedstone = {}--输出红石信号的可能方向，由于红石卡的方向为前后左右，转运器的方向为东南西北，因此不能直接套用转运器的方向
]]
local fuelRodSlot, coolantCellSlot, possibleSideRedstone, fuelRod, coolantCell, minCoolantCellDurability, isMEInterfaceMode, isActive, sideOutput, sideReactorChamber, sideRedstone = {}, {}, {}

--集中声明函数以便前面的函数调用之后定义的函数
local setActive, search, getItemSlot, check, sleep, initialize, main

--初始化
function initialize()
    local prefix, typeInventory = "gregtech:gt.", {}--物品id前缀（用于压缩代码），微控制器附近的容器类型列表
    local fuelRodList = { [prefix.."rodThorium4"]=4, [prefix.."rodUranium4"]=13, [prefix.."rodHighDensityUranium4"]=13,
                          [prefix.."rodMOX4"]=13, [prefix.."rodHighDensityPlutonium4"]=13, [prefix.."rodNaquadria4"]=13,
                          [prefix.."rodNaquadah32"]=1050, [prefix.."rodTiberium4"]=13, [prefix.."rodExcitedUranium4"]=200,
                          [prefix.."rodExcitedPlutonium4"]=200 }--索引为燃料棒id，值为第26槽冷却单元每秒吸收热量的百分之一（向上取整）
    local coolantCellList = { [prefix.."60k_Helium_Coolantcell"]=6, [prefix.."180k_Helium_Coolantcell"]=18, [prefix.."360k_Helium_Coolantcell"]=36,
                              [prefix.."60k_NaK_Coolantcell"]=6, [prefix.."180k_NaK_Coolantcell"]=18, [prefix.."360k_NaK_Coolantcell"]=36,
                              [prefix.."180k_Space_Coolantcell"]=18, [prefix.."360k_Space_Coolantcell"]=36, [prefix.."540k_Space_Coolantcell"]=54,
                              [prefix.."1080k_Space_Coolantcell"]=108, [prefix.."neutroniumHeatCapacitor"]=1e5 }--索引为冷却单元id，值为其热容的万分之一
    for i=5,0,-1 do--检查各个方向的容器，倒序以确保优先将上下方向记录为反应堆方向(转运器)
        local function checkContainer()--将容器方向信息添加到fuelRodSlot,coolantCellSlot
            local info, emptySlotCount = transposer_getAllStacks(i), 0
            for j=1,info.count() do
                local stack = info()
                local name = stack.name--用于压缩代码
                if fuelRodList[name] then
                    if fuelRod and fuelRod ~= name then
                        error("不支持多类型燃料棒")
                    end
                    fuelRod, fuelRodSlot[i] = name, {}
                elseif coolantCellList[name] and stack.damage < 70 then
                    if coolantCell and coolantCell ~= name then
                        error("不支持多类型冷却单元")
                    end
                    coolantCell, coolantCellSlot[i] = name, {}
                else
                    emptySlotCount = emptySlotCount + 1
                end
            end
            return emptySlotCount == info.count()--是否可以作为输出容器
        end
        local name = transposer.getInventoryName(i)
        typeInventory[i] = name
        if name == "blockReactorChamber" then
            if transposer.getInventorySize(i) < 54 then
                error("需要六个核反应仓")
            end
            sideReactorChamber, typeInventory[i] = i, 1
        elseif name == "tile.appliedenergistics2.BlockInterface" or name == "tile.fluid_interface" then
            if isMEInterfaceMode then
                error("转运器附近存在多个ME接口")
            end
            isMEInterfaceMode, fuelRodSlot[i], coolantCellSlot[i], fuelRod, coolantCell = true, {}, {}--重置其它容器的信息
            checkContainer()
            sideOutput = i
        elseif name and not isMEInterfaceMode and checkContainer() then
            sideOutput = i
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
    minCoolantCellDurability = math.ceil( 2 * fuelRodList[fuelRod] / coolantCellList[coolantCell])--两秒消耗的耐久值(向上取整)
    if minCoolantCellDurability > 20 then
        error("冷却单元热容过小")
    end
    search(1)
    search()
    check()
    if sideReactorChamber < 2 then--如果为反应堆方向(转运器)为上下，直接记录为红石输出方向，否则将可能的输出方向添加到possibleSideRedstone中以待后续检测
        sideRedstone = sideReactorChamber
    else
        for i=2,5 do
            if redstone.getComparatorInput(i) < 1 then--反应堆无法被红石比较器读取
                possibleSideRedstone[#possibleSideRedstone+1] = i--添加到列表，待收到开机信号后再逐个验证
            end
        end
    end
    computer.pushSignal("redstone_changed")--手动触发红石更新
    sleep(0.1)
    computer.beep(500,1)
end

--设置红石输出信号
function setActive(active)
    if sideRedstone then
        redstone_setOutput(sideRedstone, active and 1 or 0)
    elseif active then--首次开机时验证所有可能的方向
        local tag = transposer_getStackInSlot(sideReactorChamber, 1).tag
        for i=#possibleSideRedstone,1,-1 do
            redstone_setOutput(possibleSideRedstone[i], 1)
            for i=1,20 do--阻塞一秒，不使用sleep以避免清除消息
                transposer_getStackInSlot(sideReactorChamber, 1)
            end
            if transposer_getStackInSlot(sideReactorChamber, 1).tag ~= tag then
                sideRedstone, possibleSideRedstone = possibleSideRedstone[i]
                break
            end
            redstone_setOutput(possibleSideRedstone[i], 0)
        end
    end
end

--更新fuelRodSlot/coolantCellSlot
function search(isCoolant)
    local t, name, notFound = isCoolant and coolantCellSlot or fuelRodSlot, isCoolant and coolantCell or fuelRod, 1
    for side,_ in pairs(t) do
        local info = transposer_getAllStacks(side)
        if info then
            for i=1,info.count() do
                local stack = info()
                if stack.name == name and (not isCoolant or stack.damage < 70) then
                    t[side][i], notFound = stack.size
                else
                    t[side][i] = 0
                end
            end
        end
    end
    if notFound then
        error("缺少"..(isCoolant and "冷却单元" or "燃料棒"))
    end
end

--获取可用燃料棒/冷却单元的方向与槽位
function getItemSlot(isCoolant)
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

--检查核反应堆内容物
function check(active)
    local info, notShutdown, slotReplaced = transposer_getAllStacks(sideReactorChamber).getAll(), 1, {}
    for i=1,54 do
        if isCoolant[i] and (info[i-1].name ~= coolantCell or info[i-1].damage > 98 - isCoolant[i] * minCoolantCellDurability) or not isCoolant[i] and info[i-1].name ~= fuelRod then
            if isCoolant[i] and notShutdown then
                setActive()
                sleep(1)
                notShutdown=nil
            end
            slotReplaced[#slotReplaced+1] = i--添加到待处理列表，确保先停机再处理
        end
    end
    for i=1,#slotReplaced do
        local side, slot = getItemSlot(isCoolant[slotReplaced[i]])
        if info[slotReplaced[i]-1].name then
            transposer_transferItem(sideReactorChamber, sideOutput, 1, slotReplaced[i])
        end
        if transposer_transferItem(side, sideReactorChamber, 1, slot, slotReplaced[i]) == 0 then
            search(isCoolant[slotReplaced[i]])
            side, slot = getItemSlot(isCoolant[slotReplaced[i]])
            if transposer_transferItem(side, sideReactorChamber, 1, slot, slotReplaced[i]) == 0 then
                error((isCoolant[slotReplaced[i]] and "冷却单元" or "燃料棒").."更换失败")
            end
        end
    end
    setActive(active)
end

--sleep函数
function sleep(duration)
    local timeStart = computer_uptime()
    while computer_uptime() - timeStart < (duration or 0.7) do
        local name = computer.pullSignal(0.1)
        if name == "redstone_changed" then
            local maxInput, redstoneInput = 0, redstone_getInput()
            for i=0,5 do
                if redstoneInput[i] > maxInput then
                    maxInput = redstoneInput[i]
                end
            end
            isActive = maxInput > 1
            if not isActive then
                setActive()
            end
        end
    end
end

--主循环
function main()
    initialize()
    while 1 do
        check(isActive)
        sleep()
    end
end

local _, err = pcall(main)
setActive()
error(err:sub(9))
