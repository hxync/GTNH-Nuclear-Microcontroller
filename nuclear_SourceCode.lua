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

-- 对组件API进行协程封装的工具函数
local function wrapFunc(func)
    return function(...)
        local result = func(...) -- 只使用一个返回值
        coroutine_yield()
        return result
    end
end


local redstoneMap = {1,[0]=0} -- 将转运器使用的绝对方向(东南西北)映射为红石卡使用的相对方向(前后左右)
local redstone_getOutput = {0,0,0,0,0,[0]=0} -- 已设置的红石输出值
local function initializeRedstoneMap(side) -- 首次开机时调用一次，用于完成redstoneMap的初始化
    if redstoneMap[6] then
        repeat
            coroutine_yield()
        until redstoneMap[side]
        return redstoneMap[side]
    end
    redstoneMap[6] = 1 -- 标记正在初始化，防止其它协程二次调用
    local tag = transposer_getStackInSlot(side, 1).tag
    local index = {0,2,0,3,1}
    for i = 2,5 do
        raw_redstone_setOutput(i, 1)
        local wakeTime = computer_uptime() + 1
        while computer_uptime() < wakeTime do
            coroutine_yield()
        end
        if transposer_getStackInSlot(side, 1).tag ~= tag then
            for j = 2,5 do
                redstoneMap[j] = ({3,5,2,4})[(index[j] + index[i] - index[side]) % 4 + 1]
            end
            break
        end
        raw_redstone_setOutput(i, 0)
    end
    return redstoneMap[side]
end
local function redstone_setOutput(side, value)
    if redstone_getOutput[side] ~= value then -- 减少组件API的调用，降低阻塞
        redstone_getOutput[side] = value
        return raw_redstone_setOutput(redstoneMap[side] or initializeRedstoneMap(side), value)
    end
end

-- 更新燃料棒与冷却单元来源容器的快照
local function update()
    for side,_ in pairs(fuelRodSlot) do
        fuelRodSlot[side], coolantCellSlot[side], mixedFuelRodSlot[side] = {}, {}, {}
        local slot = 0
        for stack in transposer_getAllStacks(side) do
            slot = slot + 1
            if stack.name == fuelRod then
                fuelRodSlot[side][slot] = stack.size
            elseif stack.name == coolantCell and stack.damage < 70 then
                coolantCellSlot[side][slot] = 1
            elseif mixedFuelRod and stack.name == mixedFuelRod then
                mixedFuelRodSlot[side][slot] = stack.size
            end
        end
    end
end


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
    update() -- 仅当快照中不存在所需物品时才调用组件API进行更新
    return retry and er() or getItem(slot, 1)
end


local Reactor = {}
Reactor.__index = Reactor

-- 检查核反应堆内容物
function Reactor:check()
    local nextCheckTime, needReplace, extra, hasItem = 5, {}, {}, {}
    local info = transposer.getAllStacks(self.side) -- 直接调用避免让出协程
    for i=1,54 do
        local stack = info()
        local name, damage = stack.name, stack.damage
        hasItem[i] = name
        if isCoolant[i] then
            if name ~= coolantCell or damage > 99 - 2 * isCoolant[i] then
                table.insert(needReplace, 1, i)
            else
                if damage > 98 - 4 * isCoolant[i] then
                    extra[#extra+1] = i
                end
                nextCheckTime = math.min(nextCheckTime, (99 - stack.damage) / isCoolant[i] - 3)
            end
        elseif mixedFuelRod and i % 2 == 0 then
            if stack.name ~= mixedFuelRod then
                needReplace[#needReplace+1] = i
            end
        elseif stack.name ~= fuelRod then
            needReplace[#needReplace+1] = i
        end
    end
    if needReplace[1] then -- 如果需要停机，将临近阈值的冷却单元一并更换
        for _, slot in ipairs(extra) do
            needReplace[#needReplace+1] = slot
        end
    end
    return needReplace, hasItem, math.max(nextCheckTime, 0.3) -- 返回值分别为：待更换的物品列表，核电此槽位是否存在物品，休眠多少秒再进行下一次check()
end

-- 更换燃料棒或冷却单元
function Reactor:replace(needReplace, hasItem, retry)
    if needReplace[1] and redstone_setOutput(self.side, 0) then
        self:sleep(1) -- 停机并等待一秒
    end
    for _, slot in ipairs(needReplace) do
        local _side, _slot = getItem(slot)
        if hasItem[slot] then -- hasItem参数的作用是在这里节省一次可能的组件API调用
            transposer_transferItem(self.side, sideOutput, 1, slot)
        end
        if transposer_transferItem(_side, self.side, 1, _slot, slot) == 0 then
            update() -- 如果失败了，更新快照并重试
            if transposer_transferItem(_side, self.side, 1, _slot, slot) == 0 then
                er() -- 再次失败直接报错退出
            end
        end
    end
    if needReplace[1] then -- 若发生了更换，进行二次检查再开机
        local _1, _2 = self:check()
        if isCoolant[_1[1]] then
            -- 最初检测到低耐久冷却单元到关闭红石输出之后，核电有低概率会进行两次结算，若此结算导致新的冷却单元进入低耐久状态，则会意外进入此分支，故而允许重试
            -- 此分支的目的是防止ME断电后，低耐久冷却单元从ME接口反复进出引起冷却单元熔毁（反复进出是因为，只要能从预期位置转运物品就不会调用API获取物品信息，以节约性能）
            return retry > 3 and er() or self:replace(_1, _2, retry + 1) -- 一开始是仅允许重试1次，但是一直有人莫名其妙报错停机，干脆改成了3次（所以到底是为什么呢？）
        end
    end
    redstone_setOutput(self.side, isActive and 1 or 0)
end

-- 协程休眠
function Reactor:sleep(duration)
    self.wakeTime = computer_uptime() + duration
    while computer_uptime() < self.wakeTime do
        coroutine_yield()
    end
end

local function main()
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
                            er()
                        end
                    end
                    fuelRod, fuelRodSlot[i] = mixedFuelRod and fuelRod or name, {}
                elseif coolantCellList[name] and stack.damage < 70 then -- 冷却单元分支
                    if coolantCell and coolantCell ~= name then
                        er()
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
                er()
            end
            reactors[i] = {side=i}
        elseif name == "tile.appliedenergistics2.BlockInterface" or name == "tile.fluid_interface" then -- ME接口分支
            if isMEInterfaceMode then
                er()
            end
            isMEInterfaceMode, fuelRodSlot, fuelRod, coolantCell = true, {} -- 重置其它容器的信息
            checkContainer()
            sideOutput = i
        elseif name and not isMEInterfaceMode and checkContainer() then -- 输出容器分支
            sideOutput = i
        end
    end
    if mixedFuelRod then -- 混合布局的第26槽发热量与“核心”一致，比率有所不同
        isCoolant = {[3]=0.2,[6]=0.5,[9]=0.1,[10]=0.7,[15]=0.2,[22]=0.9,[26]=1,[29]=0.2,[33]=0.2,[40]=0.7,[45]=0.2,[46]=0.5,[49]=0.1,[52]=0.8}
    end
    for slot, heat in pairs(isCoolant) do
        isCoolant[slot] = (fuelRodList[fuelRod] / coolantCellList[coolantCell]) * heat -- 覆写为每秒消耗的耐久值
    end
    if not (fuelRod and coolantCell and sideOutput and next(reactors)) or isCoolant[26] > 10 then
        er()
    end
    for side,_ in pairs(fuelRodSlot) do
        mixedFuelRodSlot[side] = {}
        coolantCellSlot[side] = {}
    end
    update()
    for _, reactor in pairs(reactors) do
        setmetatable(reactor, Reactor)
        reactor.task = c3.wrap(function()
            while 1 do
                local _1, _2, _3 = reactor:check()
                reactor:replace(_1, _2, 0)
                reactor:sleep(_3)
            end
        end)
    end
    transposer_getAllStacks = wrapFunc(transposer_getAllStacks)
    transposer_transferItem = wrapFunc(transposer_transferItem)
    transposer_getStackInSlot = wrapFunc(transposer_getStackInSlot)
    raw_redstone_setOutput = wrapFunc(raw_redstone_setOutput)
    computer_pushSignal(redstone_changed)

    -- 主循环
    while 1 do
        for _, reactor in pairs(reactors) do
            reactor.task()
        end
        local wakeTime = 0
        for _, reactor in pairs(reactors) do
            wakeTime = math.min(wakeTime, reactor.wakeTime or 0)
        end
        local signal = computer_pullSignal(math.max(0, wakeTime - computer_uptime()))
        if signal == redstone_changed then
            local maxInput, redstoneInput = 0, redstone.getInput()
            for i=0,5 do
                if redstoneInput[i] > maxInput then
                    maxInput = redstoneInput[i]
                end
            end
            isActive = maxInput > 1
            if not isActive then
                redstone_getOutput = {0,0,0,0,0,[0]=0}
                redstone.setOutput(redstone_getOutput)
            end
        end
    end
end

pcall(main)
redstone.setOutput({0,0,0,0,0,[0]=0}) -- 若关机则红石卡输出会自动置零，重启则不会
if computer_uptime() > 60 then
    c2.shutdown(1) -- 如果运行超过一分钟则允许重启
end
-- eeprom代码运行完毕自动抛出"computer halted"错误