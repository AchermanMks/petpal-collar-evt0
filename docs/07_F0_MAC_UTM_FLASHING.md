# F0 烧录环境：Mac mini + UTM Windows 11 ARM + Luatools

> 2026-09-07 决定：烧录在 Mac mini（Apple M4，16 GB，macOS 26.3.1）上完成，板子为 **Air8201G-BLMQ**（自带 BTB 调试板，Type-C 直接接 USB）。
> Luatools 只有 Windows 版，所以在 Mac 上跑一个 Windows 11 ARM 虚拟机，把模组 USB 直通给虚拟机。

## 已就绪（通过远程终端完成）

| 项 | 位置 | 说明 |
|---|---|---|
| UTM 4.7.5 | `/Applications/UTM.app`，`/opt/homebrew/bin/utmctl` | `brew install --cask utm` |
| CrystalFetch 2.2.0 | `/Applications/CrystalFetch.app` | 生成 Windows 11 ARM64 安装 ISO |
| Luatools_v3.exe（73 MB） | `~/petpal-vm-share/luatools/` | 来自 `https://luatos.com/luatools/download/last` |
| 底层固件 V2030（最新，2026-03-20） | `~/petpal-vm-share/core_firmware/LuatOS-SoC_V2030_Air780EGH_1.soc` | sha256 `0254182b…334eb`；全部 32 个后缀版本见 `https://cdn18.luatos.com/files/Air780EGH/LuatOS_Air780EGH/LuatOS-SoC_V2030_Air780EGH/` |
| 底层固件 V2016（官方 demo 验证过的版本） | `~/petpal-vm-share/core_firmware/LuatOS-SoC_V2016_Air780EGH.zip`（248 MB，含全部后缀） | sha256 `38b22e7a…a4fd5` |
| 调试脚本副本 | `~/petpal-vm-share/firmware/wearable-evt0/` | 与仓库 `firmware/wearable-evt0/` 相同；`config.lua` 要在这里填 |

`~/petpal-vm-share/` 整个目录会作为共享目录挂进虚拟机。

> 固件后缀（`_1`、`_10`、`_101`…）是同一版本的不同功能裁剪。先用 `_1`（标准版）；Luatools 选底层固件时会显示每个后缀的说明，若需要 BLE/音频等再换。

## 磁盘（必须先处理）

数据卷 228 GB，剩余约 **23 GB**。Windows 11 ARM ISO 约 5 GB，装完系统约 15 GB，再加 Luatools 与日志，至少要留 25～30 GB。可清理项（都在 mantashark 主目录）：

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

1. 从 `Z:\luatools\Luatools_v3.exe` 复制到 Windows 桌面运行（首次会自解压并联网更新，需要 VM 联网）。
2. Luatools 在 Windows 11 ARM 上走 x86 转译，能用但比原生慢。

### 5. 接板子

1. BLMQ 的 Type-C 接 Mac mini，USB 数据线要带数据线芯。
2. 在 Mac 上确认枚举：`ls /dev/cu.*` 应多出 `cu.usbmodem*`；`ioreg -p IOUSB -l -w0 | grep -E 'Product Name|idVendor|idProduct'` 记下 VID/PID，填到 `records/bringup_log.csv` notes。
3. UTM 窗口工具栏 USB 图标 → 勾选该设备，直通给 VM。**Mac 侧不要同时开 `tools/serial_log.py`**，同一时刻只能一边占用端口。
4. Windows 设备管理器应出现若干 "USB 串行设备 (COMx)"。Windows 11 ARM 自带 `usbser.sys` 处理 CDC-ACM 类设备；Luatools 自带的驱动安装包是 x86 的，不需要也装不上。若设备带黄色感叹号，这是第一个要解决的问题，记入 `records/bringup_checklist.md` 问题记录。

### 6. 烧录

1. Luatools → 项目管理测试 → 新建项目 `wearable-evt0`。
2. 底层固件：选 `Z:\core_firmware\LuatOS-SoC_V2030_Air780EGH_1.soc`（若异常回退 V2016 同后缀对比）。
3. 脚本：`Z:\firmware\wearable-evt0\` 下 8 个 `.lua` + 自己填好的 `config.lua` + `ca.crt`。**`config.lua` 只放在共享目录，不要复制回仓库。**
4. 下载 → 看 Luatools 日志窗口，应看到 `PROJECT`/`VERSION`、`pm.lastReson()` 输出（F1）。
5. 记录：`records/bringup_log.csv` 填 `fw_hash`（底层固件版本 + 脚本版本）；`records/bringup_checklist.md` F0/F1 打钩，写日志文件名。

### 7. 之后的日志采集

烧录完成后可以把 USB 从 VM 断开（UTM USB 图标取消勾选），在 Mac 上直接：

```bash
cd ~/petpal-collar-evt0 && ./.venv/bin/python tools/serial_log.py /dev/cu.usbmodemXXXX --device collar-evt-001
```

日志落 `records/raw/`，远程终端就能看，不用再进虚拟机。只有重新烧录时再把 USB 直通回 VM。

## 已知风险

| 风险 | 应对 |
|---|---|
| Windows 11 ARM 对模组 USB CDC 枚举失败 | 先看设备管理器 VID/PID；退路是 Parallels（USB 直通更成熟）或另找 x86 Windows 电脑 |
| Luatools x86 转译下载超时 | 降低下载波特率；或改用 V2016 对比 |
| 磁盘不足导致 Windows 安装中途失败 | 装前确认剩余 ≥ 30 GB |
| CrystalFetch 无法访问微软服务器 | 换用 Mac 上的代理；或在其它机器下 ISO 拷过来 |
