# OC Automation for Actively Cooled Nuclear Reactors

This solution operates reliably in low-TPS environments and allows restarting the game server while it is running.

There are no placement restrictions; the containers mentioned simply need to be adjacent to the microcontroller.

**Supported fuel rods**: Quad Thorium, Quad Uranium, Quad High-Density Uranium, Quad MOX, Quad High-Density Plutonium, Quad Naquadria, "Core", Quad Tiberium, Quad Excited Uranium, Quad Excited Plutonium

- Supports hybrid rods: "Core" + Excited Uranium, "Core" + Excited Plutonium

**Supported coolant cells**: 3 types of helium coolant cells, 3 types of NaK coolant cells, 4 types of space coolant cells, Neutronium Heat Capacitor

**Limitations**:

- Only supports six-chamber actively-cooled configurations (missing a reactor chamber will cause an error)

- Only one type of fuel rod and one type of coolant cell (or the hybrid rods above) may be used; otherwise an error occurs

- Coolant cell durability consumption per second must not exceed 10% (a mismatch between heat generation and heat capacity will cause an error)

- When using MOX fuel rods, manual preheating is required

## Setup

- Save the code from `nuclear.lua` to a file on your OC computer.

- Insert a blank EEPROM into the computer, run `flash <filename>`, and follow the instructions to flash the code onto the EEPROM.

- In an Electronics Assembler, place the following in order: T1 Microcontroller Case, Transposer, T1 Redstone Card, T1 CPU, T1 RAM, and the flashed EEPROM; then click "Assemble".

Note: The EEPROM has only 4 KB of storage. The source file (`nuclear_SourceCode.lua`) is too large; you must use the compressed code (`nuclear.lua`) that employs variable renaming and other minifications.

## Usage

- The microcontroller requires power (it can be powered via an ME Interface).

- If an unexpected condition is detected, the program will throw an error and exit, and the front indicator light will flash red.

- The program will not start the nuclear reactor on its own; a redstone signal of strength **2 or greater** must be supplied to the microcontroller to start the reactor.

- The redstone control signal must not be passed directly to the reactor; turning the reactor on and off should be left to the microcontroller.

- A single microcontroller can control multiple reactors, but **do not** let the microcontroller touch two faces of the same reactor.

- The microcontroller must be placed adjacent to a reactor chamber. It supports the following two operating modes.

**1. Regular Container Mode**

- During startup, the microcontroller scans nearby containers. If no ME Interface is found, it automatically enters this mode. Scanning is performed only once at startup.

- Directions containing fuel rods or coolant cells with durability **above 30** are marked as input directions (there can be multiple).

- One container direction that contains neither fuel rods nor coolant cells with durability above 30 is marked as the output direction.

**2. ME Mode**

- During startup, the microcontroller scans nearby containers. If an ME Interface or ME Dual Interface is found, it automatically enters this mode. Scanning is performed only once at startup.

- Both input and output of fuel rods and coolant cells are handled through this ME Interface.


# Code Compression Process

## 1. Preprocessing

Apply the following find-and-replace operations to the source code:

- side --> a

- .wakeTime --> .b

- .task --> .c

- check --> d

- replace --> e

- .sleep --> .f

- :sleep --> :f

## 2. luamin

Use `luamin` to minify the code, renaming all local variables to single or double letters.

## 3. Post-processing

Replace `function`, `local`, and `end` in the luamin output with `$`, `&`, and `@` respectively, then embed the resulting text into the following skeleton code:

~~~lua
local t='the replaced text'; t=t:gsub("%$","function"); t=t:gsub("&","local"); t=t:gsub("@","end"); load(t)()
~~~