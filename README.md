# 强冷核电OC自动化

此方案硬编码了燃料棒、冷却单元、核电布局(六个反应仓)，识别燃料棒与冷却单元依赖于2.8.0以后的物品ID

**支持的燃料棒**：4联钍、4联铀、4联浓缩铀、4联MOX，4联浓缩钚、4联超能硅岩、“核心”、4联泰伯利亚、4联激发铀、4联激发钚

**支持的冷却单元**：3种氦冷、3种钠钾、4种空间、中子热容

## 配置

- 将`nuclear.lua`内的代码保存到OC电脑的文件中。

- 给OC电脑换上空的EEPROM，执行`flash <文件名>`，按照指引将代码刷写到EEPROM中。

- 在电子装配器中使用\{T1微控制器外壳、T1CPU，T1内存、T1红石卡、转运器、刷写过的EEPROM\}构建微控制器。

备注：EEPROM的存储空间为4KB，源码文件(`nuclear_SourceCode.lua`)过大，务必使用通过重命名变量等方法压缩过的代码(`nuclear.lua`)。

## 使用

- 微控制器需要供能（可以通过ME接口供能）

- 若检测到非预期的情况，微控制器内的程序会中断，正面指示灯会闪烁红光，使用分析器shift右击微控制器即可查看程序中止原因

- 程序运行期间不会自动启动核电，需要给予微控制器红石信号才会启动

- 微控制器需要紧贴核反应仓放置，支持以下两套使用方法

**1.普通容器模式**

- 启动期间搜寻附近容器，若无ME接口自动进入此模式，搜寻只会在启动时执行一次

- 会将包含燃料棒或耐久在30以上的冷却单元的方向标记为输入方向（可以有多个）

- 会将不包含燃料棒与耐久在30以上的冷却单元的一个容器方向标记为输出方向

**2.ME模式**

- 启动期间搜寻附近容器，若存在ME接口或ME二合一接口自动进入此模式，搜寻只会在启动时执行一次

- 燃料棒与冷却单元的输入输出均通过ME接口进行

# Strong Cooling Nuclear Reactor OC Automation
This solution hardcodes the fuel rods, coolant cells, and nuclear reactor layout (six reactor chambers). Identification of fuel rods and coolant cells relies on item IDs from version 2.8.0 onwards.

**Supported fuel rods**: Quad Thorium, Quad Uranium, Quad Enriched Uranium, Quad MOX, Quad Enriched Plutonium, Quad Naquadria, 32‑fold Naquadah, Quad Tiberium, Quad Excited Uranium, Quad Excited Plutonium

**Supported coolant cells**: 3 types of Helium, 3 types of NaK, 4 types of Space, and the Neutronium Heat Capacitor

## Configuration
- Save the code from `nuclear.lua` into a file on the OC computer.

- Insert a blank EEPROM into the OC computer and execute `flash <filename>`. Follow the instructions to flash the code onto the EEPROM.

- In the Assembler, construct a microcontroller using the following components: \{T1 Microcontroller Case, T1 CPU, T1 RAM, T1 Redstone Card, Transposer, the flashed EEPROM\}.

Note: The EEPROM has a storage capacity of 4 KB. The source file (`nuclear_SourceCode.lua`) is too large; be sure to use the compressed code (`nuclear.lua`) obtained by renaming variables and similar methods.

## Usage
- The microcontroller requires power (it can be powered through an ME Interface).

- If an unexpected situation is detected, the program inside the microcontroller will terminate, and the front indicator light will flash red. Use an Analyzer and shift‑right‑click the microcontroller to view the reason for the termination.

- During program operation, the nuclear reactor will not start automatically. It will only start when a redstone signal is given to the microcontroller.

- The microcontroller must be placed directly adjacent to the reactor chamber. Two sets of usage methods are supported:

**1. Normal Container Mode**

- During startup, nearby containers are scanned. If no ME Interface is found, this mode is automatically entered. The scan is performed only once at startup.

- Directions containing fuel rods or coolant cells with durability above 30 are marked as input directions (multiple such directions are allowed).

- One container direction that contains neither fuel rods nor coolant cells with durability above 30 is marked as the output direction.

**2. ME Mode**

- During startup, nearby containers are scanned. If an ME Interface or an ME Dual‑Interface is found, this mode is automatically entered. The scan is performed only once at startup.

- Both input and output of fuel rods and coolant cells are handled through the ME Interface.
