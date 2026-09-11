# F0 烧录环境：Mac mini + UTM Windows 11 ARM + Luatools

> 2026-09-07 决定：烧录在 Mac mini（Apple M4，16 GB，macOS 26.3.1）上完成，板子为 **Air8201G-BLMQ**（自带 BTB 调试板，Type-C 直接接 USB）。
> Luatools 只有 Windows 版，所以在 Mac 上跑一个 Windows 11 ARM 虚拟机，把模组 USB 直通给虚拟机。
> **2026-09-11 更新**：F0 已于 9/9 在另一台 Win11 PC 上完成（`docs/09`），本路线改为**长期备用**，避免以后来回搬板子。本次更新并入了 Windows 侧实测出的坑（无 BOOT 键、reset 时机、下载模式重枚举、电池开关）和 Luatools.zip、flash-kit v3 两个新文件。虚拟机与 ISO 尚未创建。

## 已就绪（通过远程终端完成）

| 项 | 位置 | 说明 |
|---|---|---|
| UTM 4.7.5 | `/Applications/UTM.app`，`/opt/homebrew/bin/utmctl` | `brew install --cask utm` |
| CrystalFetch 2.2.0 | `/Applications/CrystalFetch.app` | 生成 Windows 11 ARM64 安装 ISO |
| Luatools_v3.exe（73 MB） | `~/petpal-vm-share/luatools/` | 来自 `https://luatos.com/luatools/download/last`；**优先用下一行的 zip，这个只在 zip 不能用时兜底** |
| **Luatools.zip（282 MB）** | `~/petpal-vm-share/luatools/Luatools.zip` | 9/9 烧录成功那台 Win11 的 `D:\Luatools` 整目录：3.4.9 已自解压、`_temp/ec_download` 已带 EC718HM 资源、`project/petpal-evt.ini` 已配好、`log/` 有历史日志。sha256 `764c24a0…356e2`。**含完整 IMEI，不外传** |
| **petpal-flash-kit-v3.zip（11 MB）** | `~/petpal-vm-share/petpal-flash-kit-v3.zip` | 当前要烧的包（9 个 app lua + libs/exgnss、lbsLoc2 + 同一份 .soc + redact_ids.py），交接单 `docs/10`。sha256 `29f7978a…d397` |
| 底层固件 V2030（最新，2026-03-20） | `~/petpal-vm-share/core_firmware/LuatOS-SoC_V2030_Air780EGH_1.soc` | sha256 `0254182b…334eb`；全部 32 个后缀版本见 `https://cdn18.luatos.com/files/Air780EGH/LuatOS_Air780EGH/LuatOS-SoC_V2030_Air780EGH/` |
| 底层固件 V2016（官方 demo 验证过的版本） | `~/petpal-vm-share/core_firmware/LuatOS-SoC_V2016_Air780EGH.zip`（248 MB，含全部后缀） | sha256 `38b22e7a…a4fd5` |
| 调试脚本副本 | `~/petpal-vm-share/firmware/wearable-evt0/` | **9/7 的第一版，已过时**，留作对照；实际用 v3 zip 解压出来的 |

`~/petpal-vm-share/` 整个目录会作为共享目录挂进虚拟机。

> 固件后缀（`_1`、`_10`、`_101`…）是同一版本的不同功能裁剪。先用 `_1`（标准版）；Luatools 选底层固件时会显示每个后缀的说明，若需要 BLE/音频等再换。

## 磁盘（必须先处理）

数据卷 228 GB。2026-09-11 已按下表清理（ubuntu 镜像、废纸篓、DerivedData、Lark/Claude 缓存、已装应用的安装包），剩余 **34 GB**，满足要求；Chrome 缓存因 Chrome 在运行未删干净，CoreSimulator 无失效项未动。以下清单留作下次参考。Windows 11 ARM ISO 约 5 GB，装完系统约 15 GB，再加 Luatools 与日志，至少要留 25～30 GB。可清理项（都在 mantashark 主目录）：

| 项 | 大小 | 说明 |
|---|---|---|
| `~/Downloads/ubuntu-26.04-desktop-amd64.iso` | 6.1 GB | x86 镜像，M4 上用不了 |
| `~/.Trash` | 2.7 GB | 清空废纸篓 |
| `~/Library/Developer/CoreSimulator` | 9.6 GB | iOS 模拟器；`xcrun simctl delete unavailable` 可清无效部分 |
| `~/Library/Developer/Xcode/DerivedData` | 2.9 GB | 可整目录删除，重编译自动生成 |
| `~/Library/Caches/{LarkShell,Google,com.anthropic.claudefordesktop.ShipIt}` | 约 3.9 GB | 应用缓存 |
| `~/Downloads/` 里的旧安装包（ToDesk、Feishu、Chrome、Claude dmg） | 约 1.3 GB | 已安装可删 |

## 步骤（需要在 Mac 屏幕前操作）

### 1. 生成 Windows 11 ARM ISO

1. 打开 CrystalFetch → Windows 11 → 架构 **ARM64** → 语言任选 → Download。
2. 默认落到 `~/Downloads/`，约 5 GB，耗时取决于网络。

### 2. 创建虚拟机（UTM）

1. 打开 UTM → `+` → **Virtualize** → **Windows**。
2. 勾选 **Install Windows 10 or higher**；**不要**勾 "Use Apple Virtualization"（Apple 虚拟化框架不支持 USB 直通，必须用 QEMU 后端）。
3. Boot ISO 选 CrystalFetch 生成的 ISO。
4. 内存 6144 MB，CPU 4 核，磁盘 40 GB（按需增长，实际只占用已写入部分）。
5. 共享目录选 `~/petpal-vm-share`。
6. 创建后先别启动：进 VM 设置 → **Sharing**，确认 **USB Sharing** 已开启（QEMU 后端默认开）。

### 3. 安装 Windows

1. 启动 VM，出现 "Press any key to boot from CD" 时按任意键。
2. 安装向导走完（若被要求联网登录微软账号，可 `Shift+F10` 输入 `OOBE\BYPASSNRO` 回车重启后选“我没有 Internet 连接”）。
3. 进桌面后 UTM 会挂载 SPICE guest tools 光盘，运行 `spice-guest-tools-*.exe` 安装；重启后共享目录以网络驱动器出现（通常为 `Z:`）。

### 4. Luatools

1. 把 `Z:\luatools\Luatools.zip` 复制进虚拟机本地盘解压（不要在 Z: 上直接运行，共享盘慢且路径带反斜杠问题）。解压后得到 `Luatools\` 目录，里面 `Luatools_v3.exe` 直接运行，不需要再联网自解压，EC718HM 的下载资源已经在 `_temp\ec_download\`。
2. 放的位置尽量是 `D:\Luatools`，这样 `project\petpal-evt.ini` 里的路径不用改；虚拟机只有 C 盘时放 `C:\Luatools`，然后要么改 ini 里的两处路径（core_path 与脚本目录段名），要么在「项目管理」里重建项目（步骤见 `docs/09` §3、§7.3）。
3. 兜底：zip 解压后跑不起来，再用 `Z:\luatools\Luatools_v3.exe` 复制到桌面运行，它会自解压并联网更新（需要 VM 联网），首次会下载 EC718 资源。
4. Luatools 在 Windows 11 ARM 上走 x86 转译，能用但比原生慢。

### 5. 接板子

1. 先看板子：**电池拨动开关置“通”**，USB 不给模组供电，开关断开时插 USB 只亮充电灯、按键全部无效。电池先充满（9/8 曾因电池掉到 3.0 V 假死，见 `docs/06`）。
2. BLMQ 的 Type-C 接 Mac mini，USB 数据线要带数据线芯。
3. 在 Mac 上确认枚举：`ls /dev/cu.usbmodem*` 应出现 3 个口（`…13/15/17`），设备名 AirM2M Compo USB，VID:PID **19D1:0001**（已记入 `bringup_log.csv`）。当前固件 `lowpower=false`，USB 常在；若以后开了 lowpower，USB 会被物理关掉，先按 `reset` 再找设备。
4. **Mac 侧先停掉 `tools/usb_log.py` / `usb_cmd.py`**，同一时刻只能一边占用端口。
5. UTM 窗口工具栏 USB 图标 → 勾选 AirM2M Compo USB，直通给 VM。
6. Windows 设备管理器应出现 2 个 "USB 串行设备 (COMx)"：soc log 口 + 用户虚拟串口（Win11 PC 上是 COM12/COM13）。Windows 11 ARM 自带 `usbser.sys` 处理 CDC-ACM 类设备；Luatools 自带的驱动安装包是 x86 的，不需要也装不上。若设备带黄色感叹号，这是第一个要解决的问题，记入 `records/bringup_checklist.md` 问题记录。

### 6. 烧录（以 flash-kit v3 为例，细节以 `docs/10` 为准）

1. 把 `Z:\petpal-flash-kit-v3.zip` 解压到虚拟机本地盘，`config.example.lua` 复制为 `config.lua`，填 `device_id`、`fw`，features 全 false。**`config.lua` 只留在虚拟机或共享目录，不要复制回仓库。**
2. Luatools 主界面右上角「项目管理」（窗口最大化才看得见）→ 沿用 zip 里自带的 `petpal-evt` 项目或新建。底层 CORE 选 v3 包内的 `.soc`（与 `Z:\core_firmware\` 是同一文件，sha256 `0254182b…334eb`），**不要点“下载最新固件”**。
3. 脚本列表清空后加入 12 个文件：9 个 app lua + `libs/exgnss.lua` + `libs/lbsLoc2.lua` + `config.lua`。勾「清除KV分区」「清除FS分区」「添加默认扩展库」，「忽略脚本依赖性」不勾。
4. **时机**：板上没有 BOOT 键，Luatools 只能在模组刚开机的头几秒软重启它进下载模式。做法：USB 已直通、模组在跑 → 按板上 `reset` → 虚拟机里 COM 重新出现后**立即**点「全量下载(底层+脚本)」。模组跑久了再点会报「模块重启超时」（30 s），按 reset 重来即可。
5. **盯 USB 菜单**（本路线特有）：进下载模式时模组会重新枚举，在 Win11 PC 上下载口从 COM12/13 变成了 COM15。QEMU 的 USB 直通按 VID/PID 绑定：PID 不变会自动接回虚拟机；PID 变了虚拟机会丢设备，Luatools 30 s 后超时。点下载后立刻看 UTM 的 USB 菜单，出现新设备名就马上勾上。第一次烧就能判断是哪种情况，把结果记到 `bringup_checklist.md` 问题记录。
6. 成功标志：Luatools 日志「下载成功 脚本区总空间:512KB,已使用 …KB」，随后自动复位，trace 窗口出现 `I/user.main petpal_evt0 …` 与 `docs/10` §5 的三行新增日志。
7. 记录：`records/bringup_log.csv` 填 `fw_hash`；`records/bringup_checklist.md` 写日志文件名。回传/归档前用 `tools/redact_ids.py` 打码（底层日志会打印完整 IMEI）。

### 7. 之后的日志采集

烧录完成后把 USB 从 VM 断开（UTM USB 图标取消勾选），在 Mac 上直接：

```bash
cd ~/petpal-collar-evt0 && ./.venv/bin/python tools/usb_log.py --auto --device collar-evt-001 --tag F2
```

`usb_log.py` 读 `…13` 口并解码 Luatools 帧格式（`serial_log.py` 只适用于普通文本串口，读不到）。v3 起功能开关用 `tools/usb_cmd.py` 经用户虚拟串口写 KV，不用再进虚拟机重烧；只有换底层固件或脚本时再把 USB 直通回 VM。

## 已知风险

| 风险 | 应对 |
|---|---|
| Windows 11 ARM 对模组 USB CDC 枚举失败 | 先看设备管理器 VID/PID；退路是 Parallels（USB 直通更成熟）或另找 x86 Windows 电脑 |
| Luatools x86 转译下载超时 | 降低下载波特率；或改用 V2016 对比 |
| 下载模式重枚举后 VM 丢设备（PID 变化） | 点下载后盯 UTM USB 菜单手动勾新设备；仍不行则此路线只能用于“不换底层固件”的场景，底层烧录回 Windows PC（`docs/11`） |
| 磁盘 18 GB 不够装 Windows | 先按上表清盘到 ≥30 GB 再开始 |
| 磁盘不足导致 Windows 安装中途失败 | 装前确认剩余 ≥ 30 GB |
| CrystalFetch 无法访问微软服务器 | 换用 Mac 上的代理；或在其它机器下 ISO 拷过来 |
