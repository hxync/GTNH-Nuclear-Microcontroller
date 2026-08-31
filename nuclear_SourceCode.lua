---@diagnostic disable: unbalanced-assignments, undefined-global
local c1, c2, c3, er, redstone_changed = component, computer, coroutine, error, "redstone_changed" -- 使用局部变量代替，以便后续通过重命名变量来压缩代码
local component_list, component_proxy, computer_uptime, computer_pullSignal, computer_pushSignal, coroutine_yield = c1.list, c1.proxy, c2.uptime, c2.pullSignal, c2.pushSignal, c3.yield
local transposer, redstone = component_proxy(component_list("transposer")()), component_proxy(component_list("redstone")())
local transposer_getAllStacks, transposer_transferItem, transposer_getStackInSlot, transposer_getInventorySize, raw_redstone_setOutput = transposer.getAllStacks, transposer.transferItem, transposer.getStackInSlot, transposer.getInventorySize, redstone.setOutput

local isCoolant = {[3]=0.8,[6]=0.5,[9]=0.5,[10]=0.7,[15]=0.7,[22]=0.9,[26]=1,[29]=1,[33]=0.9,[40]=0.7,[45]=0.7,[46]=0.5,[49]=0.5,[52]=0.8}

--[[
local reactors = {} -- 反应堆实例，索引为转运器方向
local isActive, isMEInterfaceMode, sideOutput -- 是否处于工作状态，是否使用ME接口进行物流，输出容器的方向
local fuelRod, mixedFuelRod, coolantCell -- 燃料棒ID，混合棒额外燃料棒的ID，冷却单元ID
local fuelRodSlot, mixedFuelRodSlot, coolantCellSlot = {}, {}, {} -- 燃料棒、冷却单元快照，索引为容器方向，子表索引为槽位，子表值为数量
]]
local fuelRodSlot, mixedFuelRodSlot, coolantCellSlot, reactors, fuelRod, mixedFuelRod, coolantCell, isActive, isMEInterfaceMode, sideOutput = {}, {}, {}, {}


local redstoneMap, initializingMap = {1,[0]=0} -- 将转运器使用的绝对方向(东南西北)映射为红石卡使用的相对方向(前后左右)
local redstone_getOutput = {0,0,0,0,0,[0]=0} -- 已设置的红石输出值
local function initializeRedstoneMap(side) -- 首次开机时调用一次，用于完成redstoneMap的初始化
    if initializingMap then
        initializingMap[side] = 1
        repeat
            coroutine_yield()
        until redstoneMap[side]
        return
    end
    initializingMap = {[side]=1} -- 标记正在初始化，阻断其它协程的二次调用
    ::WAIT::
    for i = 5,2,-1 do
        if reactors[i] and not initializingMap[i] then
            coroutine_yield()
            goto WAIT -- 等待其它反应堆完成检查
        end
    end
    local index, tags = {0,2,0,3,1}, {}
    for i = 2,5 do
        if reactors[i] then
            tags[i] = transposer_getStackInSlot(i, 1).tag
        end
    end
    for i = 5,2,-1 do -- 优先探测左侧与右侧
        raw_redstone_setOutput(i, 1)
        local wt = computer_uptime() + 1
        while computer_uptime() < wt do
            coroutine_yield()
        end
        raw_redstone_setOutput(i, 0)
        for j = 2,5 do
            if reactors[j] and transposer_getStackInSlot(j, 1).tag ~= tags[j] then
                for k = 2,5 do
                    redstoneMap[k] = ({3,5,2,4})[(index[k] + index[i] - index[j]) % 4 + 1]
                end
                return
            end
        end
    end
end
local function redstone_setOutput(side, value)
    if redstone_getOutput[side] ~= value then -- 减少组件API的调用，降低阻塞
        if redstoneMap[side] then
            redstone_getOutput[side] = value
            local result = raw_redstone_setOutput(redstoneMap[side], value)
            coroutine_yield()
            return result
        else
            initializeRedstoneMap(side)
            -- return redstone_setOutput(side, value) -- 有概率导致升温
            isActive = nil -- 引发一次红石更新以立即进行一次检查再开机
            computer_pushSignal(redstone_changed)
        end
    end
end


-- 更新燃料棒与冷却单元来源容器的快照
local function update()
    isMEInterfaceMode = isMEInterfaceMode and 0 or nil
    for side,_ in pairs(fuelRodSlot) do
        fuelRodSlot[side], coolantCellSlot[side], mixedFuelRodSlot[side] = {}, {}, {}
        local slot = 0
        for stack in transposer.getAllStacks(side) do -- 避免在此处让出协程引发竞态
            slot = slot + 1
            local name, size = stack.name, stack.size
            if name == fuelRod then
                fuelRodSlot[side][slot] = size
            elseif name == coolantCell and stack.damage < 70 then
                coolantCellSlot[side][slot] = 1
            elseif mixedFuelRod and name == mixedFuelRod then
                mixedFuelRodSlot[side][slot] = size
            end
            if isMEInterfaceMode and not name then
                isMEInterfaceMode = slot -- 记录ME接口的空槽位
            end
        end
    end
    if isMEInterfaceMode == 0 then
        er("ME接口已满")
    end
end

local FUELROD, COOLANTCELL, LACK = "燃料棒", "冷却单元", "缺少"

-- 获取一个可用燃料棒与冷却单元的方向和槽位
local function getItem(slot, retry)
    local list = fuelRodSlot
    if isCoolant[slot] then
        list = coolantCellSlot
    elseif mixedFuelRod and slot % 2 == 0 then
        list = mixedFuelRodSlot
    end
    for k,v in pairs(list) do
        for i,j in pairs(v) do
            if j > 0 then
                if not isMEInterfaceMode then
                    v[i] = j - 1
                end
                return k, i
            end
        end
    end
    update() -- 仅当快照中不存在所需物品时才调用组件 API 进行更新
    if retry then
        -- er(LACK..(isCoolant[slot] and COOLANTCELL or FUELROD))
        raw_redstone_setOutput({0,0,0,0,0,[0]=0})
        c2.shutdown(1) -- 重启
    end
    return getItem(slot, 1)
end


-- 协程循环
local function cycle(side)
    -- 检查反应堆内容物
    local needReplace, extra, hasItem, sleepTime = {}, {}, {}, 5
    local info = transposer_getAllStacks(side)
    for i=1,54 do
        local stack = info()
        local name, damage = stack.name, stack.damage
        hasItem[i] = name
        if isCoolant[i] then
            if name ~= coolantCell or damage > 99 - 2 * isCoolant[i] then
                needReplace[#needReplace+1] = i
            else
                if damage > 98 - 4 * isCoolant[i] then
                    extra[#extra+1] = i
                end
                sleepTime = math.min(sleepTime, (98 - damage) / isCoolant[i] - 3)
            end
        elseif mixedFuelRod and i % 2 == 0 then
            if name ~= mixedFuelRod then
                needReplace[#needReplace+1] = i
            end
        elseif name ~= fuelRod then
            needReplace[#needReplace+1] = i
        end
    end
    -- 更换
    if needReplace[1] then
        -- 将临近阈值的冷却单元一并更换
        for _, slot in ipairs(extra) do
            needReplace[#needReplace+1] = slot
        end
        -- 停机并等待1秒
        if redstone_setOutput(side, 0) then
            local wakeTime = computer_uptime() + 1 -- computer.uptime 的计算基于游戏tick，不必担忧tps引发的同步问题
            while computer_uptime() < wakeTime do
                coroutine_yield()
            end
        else
            update() -- 更换过但是检查不通过，需要重新检查
        end
        -- 更换燃料棒与冷却单元
        for _, slot in ipairs(needReplace) do
            ::RETRY::
            local _side, _slot = getItem(slot)
            if hasItem[slot] then -- hasItem 的作用是在这里节省一次可能的组件API调用
                if transposer_transferItem(table.unpack({side, sideOutput, 1, slot, isMEInterfaceMode})) < 1 then -- 第五个参数显式传入 nil 会引发报错
                    update()
                    goto RETRY
                end
                hasItem[slot] = nil
            end
            if transposer_transferItem(_side, side, 1, _slot, slot) < 1 then
                update()
                goto RETRY -- goto 相比 break 而言，组件 API 调用次数更少
            end
        end
    else -- 若发生了更换，等待下次循环进行二次检查后再开机
        local wakeTime = computer_uptime() + math.max(sleepTime, 0.3)
        redstone_setOutput(side, isActive and 1 or 0)
        while computer_uptime() < wakeTime do
            if coroutine_yield() then
                break
            end
        end
    end
end


-- 初始化
local prefix, suffix = "gregtech:gt.", "_Coolantcell" -- 物品id前后缀（用于压缩代码）
local fuelRodList = { [prefix.."rodThorium4"]=4, [prefix.."rodUranium4"]=13, [prefix.."rodHighDensityUranium4"]=13,
                        [prefix.."rodMOX4"]=13, [prefix.."rodHighDensityPlutonium4"]=13, [prefix.."rodNaquadria4"]=13,
                        [prefix.."rodNaquadah32"]=1050, [prefix.."rodTiberium4"]=13, [prefix.."rodExcitedUranium4"]=200,
                        [prefix.."rodExcitedPlutonium4"]=200 }--索引为燃料棒id，值为第26槽冷却单元每秒吸收热量的百分之一（向上取整）
local coolantCellList = { [prefix.."60k_Helium"..suffix]=6, [prefix.."180k_Helium"..suffix]=18, [prefix.."360k_Helium"..suffix]=36,
                            [prefix.."60k_NaK"..suffix]=6, [prefix.."180k_NaK"..suffix]=18, [prefix.."360k_NaK"..suffix]=36,
                            [prefix.."180k_Space"..suffix]=18, [prefix.."360k_Space"..suffix]=36, [prefix.."540k_Space"..suffix]=54,
                            [prefix.."1080k_Space"..suffix]=108, [prefix.."neutroniumHeatCapacitor"]=1e5 }--索引为冷却单元id，值为其热容的万分之一
for i=0,5 do
    local function checkContainer() -- 将容器方向信息添加到fuelRodSlot
        local info, emptySlotCount = transposer_getAllStacks(i), 0
        for j=1,info.count() do
            local stack = info()
            local name = stack.name
            if fuelRodList[name] then -- 燃料棒分支
                if fuelRod and fuelRod ~= name then
                    if fuelRodList[fuelRod] + fuelRodList[name] == 1250 then -- 额外引入对“核心”-激发钚/激发铀混合布局的支持
                        mixedFuelRod = name
                        if fuelRodList[fuelRod] < fuelRodList[mixedFuelRod] then
                            fuelRod, mixedFuelRod = mixedFuelRod, fuelRod -- 确保fuelRod是“核心”的物品id
                        end
                    else
                        er("不支持的混合"..FUELROD)
                    end
                end
                fuelRod, fuelRodSlot[i] = mixedFuelRod and fuelRod or name, {}
            elseif coolantCellList[name] and stack.damage < 70 then -- 冷却单元分支
                if coolantCell and coolantCell ~= name then
                    er("必须为一种"..COOLANTCELL)
                end
                coolantCell, fuelRodSlot[i] = name, {}
            else
                emptySlotCount = emptySlotCount + 1
            end
        end
        return emptySlotCount == info.count() -- 是否可以作为输出容器
    end
    local name = transposer_getInventorySize(i) ~= 0 and transposer.getInventoryName(i) -- 物品栏大小一定要大于0这一块，点名AE2和GT
    if name == "blockReactorChamber" then -- 核反应仓分支
        if transposer_getInventorySize(i) < 54 then
            er("必须为六仓反应堆")
        end
        reactors[i] = {side=i}
    elseif name == "tile.appliedenergistics2.BlockInterface" or name == "tile.fluid_interface" then -- ME接口分支
        if isMEInterfaceMode then
            er("存在多个ME接口")
        end
        isMEInterfaceMode, fuelRodSlot, fuelRod, coolantCell = 0, {} -- 重置其它容器的信息
        checkContainer()
        sideOutput = i
    elseif name and not isMEInterfaceMode and checkContainer() then -- 输出容器分支
        sideOutput = i
    end
end
if not fuelRod then
    er(LACK..FUELROD)
end
if not coolantCell then
    er(LACK..COOLANTCELL)
end
if not sideOutput then
    er(LACK.."输出容器")
end
if not next(reactors) then
    er(LACK.."反应堆")
end
if mixedFuelRod then -- 混合布局的第26槽发热量与“核心”一致，比率有所不同
    isCoolant = {[3]=0.2,[6]=0.5,[9]=0.1,[10]=0.7,[15]=0.2,[22]=0.9,[26]=1,[29]=0.2,[33]=0.2,[40]=0.7,[45]=0.2,[46]=0.5,[49]=0.1,[52]=0.8}
end
for slot, heat in pairs(isCoolant) do -- 覆写为每秒消耗的耐久值
    isCoolant[slot] = (fuelRodList[fuelRod] / coolantCellList[coolantCell]) * heat
end
if isCoolant[26] > 10 then
    er(COOLANTCELL.."热容过小")
end
for side,_ in pairs(fuelRodSlot) do
    mixedFuelRodSlot[side] = {}
    coolantCellSlot[side] = {}
end
update()
for side, _ in pairs(reactors) do
    reactors[side] = c3.wrap(function()
        while 1 do
            cycle(side)
        end
    end)
end
-- 对组件API进行协程封装的工具函数
local function wrapFunc(func)
    return function(...)
        local result = func(...) -- 只使用一个返回值
        coroutine_yield()
        return result
    end
end
transposer_getAllStacks = wrapFunc(transposer_getAllStacks)
transposer_transferItem = wrapFunc(transposer_transferItem)
transposer_getStackInSlot = wrapFunc(transposer_getStackInSlot)
computer_pushSignal(redstone_changed)

-- 主循环
while 1 do
    local wake
    local signal = computer_pullSignal(0.05)
    if signal == redstone_changed then
        local redstoneInput = redstone.getInput()
        for i=0,5 do
            --if not reactors[i] and redstoneInput[redstoneMap[i] or i] > 0 then
            -- getInput(side:number):number采用相对方向，但是其重载getInput():table采用绝对方向
            if not reactors[i] and redstoneInput[i] > 0 then
                wake = not isActive
                isActive = 1
                goto BREAK
            end
        end
        wake = isActive
        isActive = nil
        if wake then
            redstone_getOutput = {0,0,0,0,0,[0]=0}
            raw_redstone_setOutput(redstone_getOutput)
        end
        ::BREAK::
    end
    for _, reactor in pairs(reactors) do
        reactor(wake)
    end
end
