# PetPal 宠宝：Air8201G-BLMQ 硬件烧录需求与交接单

日期：2026-09-16。接收方：另一台可直接识别开发板 USB 的 Windows 电脑及烧录/调试人员。

## 1. 本次必须完成的任务

将配套的 **PetPal Air8201G 摄像头专用 003/r2 脚本**烧录到现有开发板，确认新版本启动、USB 命令台可用，并取得真实摄像头 JPEG。之后将板子交回用于原宠宝界面的实况联调。

用户约束：

- 保留上一版 ESP32 固件、代码、App，不覆盖、不修改。
- Air8201G 使用独立 iOS 工程与 Bundle ID，但原 App 页面、布局、导航和操作方式不变，只更换后台硬件实现。
- 摄像头实况为第一优先级；其余项圈功能按第 8 节分阶段移植。本次不是“全功能已完成”的量产固件。
- 不允许使用静态图片、演示视频、随机数据或循环缓存画面冒充实况。

本次交接原因：Mac 能看到 AirM2M USB，但 UTM Windows 的 USB 直通/下载模式握手不稳定，尚未完成新包烧录。先前板上实际日志仍为 `001.000.001`，新包尝试在握手阶段超时、进度 0%。不能将这些尝试记作烧录成功。

## 2. 硬件与软件基线

| 项目 | 指定内容 |
|---|---|
| 核心板 | Air8201G-BLMQ；核对板上标签，不按其他型号猜测 |
| 扩展底板 | 用户照片显示 `EXB_AIR8201G_BTB_V1.4` |
| 摄像头 | 已接在 CAMERA 接口；排线 `KCS001 V2.0` 不是传感器型号，运行时读取 ID |
| 烧录电脑 | 能直接枚举此开发板 USB 的 Windows；此次不依赖 Mac 虚拟机 |
| 烧录工具 | 官方 LuaTools；此前使用 3.4.10，记录接收电脑实际版本 |
| 指定核心 | `LuatOS-SoC_V2030_Air780EGH_1.soc`，本项目既有核心，不因名称含 Air780EGH 就换成其他固件 |
| 脚本项目名/版本 | `petpal_evt0` / `001.000.003` |
| 配置固件标记 | `evt0.0.3` |
| 默认设备 ID | `collar-evt-001`，单板台架使用；多板部署需另行分配唯一 ID |

官方说明 Air8201 系列无需另装专用驱动。若 Windows 未枚举，先查供电、数据线和设备管理器，不随意安装第三方驱动。[合宙烧录故障排查](https://docs.openluat.com/common/howtodown/)

核心 SHA-256：

```text
0254182b72465409097c3f17186f8c4867eb175f9ed1da6d5b23b3e8eaa334eb
```

## 3. 交付文件与禁止混用项

使用配套 `PetPal_Air8201G_Flash_Handoff_20260916.zip`。解压后应有：

```text
PetPal_Air8201G_Flash_Handoff_20260916/
  README_FLASH_REQUIREMENTS.md       本交接单（中文内容）
  FLASH_REPORT_TEMPLATE.md           结果回传模板
  SHA256SUMS.txt                     交付文件校验清单
  core/LuatOS-SoC_V2030_Air780EGH_1.soc
  scripts/                          摄像头 003/r2 完整脚本
    manifest.json                   每个 Lua 文件的 SHA-256
    main.lua, config.lua, bench_defaults.lua, ...
  tools/usb_cmd.py                   USB 命令测试，Windows 必须指定 --port
  tools/air_bridge.py                真实 JPEG 校验及本机 HTTP 桥
  tools/redact_ids.py                日志设备标识打码
```

`scripts` 应恰好有以下 **21 个 Lua 文件**，全部加入 LuaTools 脚本列表；JSON、Markdown、Python、校验清单不烧入脚本区：

```text
activity_app.lua  actuator_app.lua  bench_defaults.lua  ble_app.lua
camera_app.lua  command_app.lua  config.lua  console_app.lua
excamera.lua  exgnss.lua  gc0310.lua  gc032a.lua  gnss_app.lua
gsensor_app.lua  lbsLoc2.lua  main.lua  mqtt_app.lua  net_app.lua
outbox_app.lua  power_app.lua  runtime_app.lua
```

不要使用旧 `petpal-flash-kit-v3`、hello_world、bench_002、legacy_ui_002 或不带 `_r2` 的 camera_003 中间包替代本次脚本。早期交接单中“清除 FS/KV”“无 BOOT 下载条件”的做法不适用于此次交接，以本单为准。

包内 `config.lua` 已正确配置，**不从 config.example.lua 重新生成**。生效功能应为：

```text
camera=true, power=true
mqtt=false, gnss=false, gsensor=false, actuator=false, ble=false, lowpower=false
ignore_feature_override=true
```

该配置忽略旧 KV 功能开关，但不删除旧 KV。摄像头与 DA267 共用 I2C1，现阶段摄像头独占，不得通过 `set` 打开其他功能。`net_app` 仍会执行 SIM/网络诊断；无 SIM 不应阻止 USB 摄像头测试，不要求本轮配 MQTT、SIM 或外网服务。

## 4. 烧录前检查

1. 解压到短本地路径，例如 `D:\PetPal_Air8201G_Flash_Handoff_20260916`，不要沿用旧电脑的 `Z:` 共享盘路径。
2. 核对核心 SHA-256，例如 PowerShell：

   ```powershell
   Get-FileHash .\core\LuatOS-SoC_V2030_Air780EGH_1.soc -Algorithm SHA256
   (Get-ChildItem .\scripts\*.lua).Count
   ```

   文件数必须为 21；逐文件校验按 `scripts/manifest.json` 或 `SHA256SUMS.txt`。校验不符先停，不自行替换文件。
3. 记录板型、当前核心/脚本版本、正常模式的 COM 号与原启动日志；日志包含 IMEI/ICCID 等标识时，回传前打码。
4. 未取得旧固件分区的可恢复备份。旧源码保留不等于设备分区备份；本次会替换设备当前脚本，不能承诺可恢复未知旧分区。
5. 确保电池/供电正常、无明显发热或鼓包，USB 数据线可靠，首次调试有人在场。不要给宠物佩戴正在烧录或调试的样机。
6. 关闭其他占用开发板串口的工具。首次只验证正常模式枚举；COM 号不要照抄此前 COM4/COM13。

## 5. LuaTools 项目配置与下载

1. 新建独立项目，例如 `petpalcamera003_r2`，避免改动旧项目。
2. CORE 选择包内指定 `.soc`。不要点“下载最新固件”，不要擅自改核心版本。
3. 导入 `scripts` 下全部 21 个 Lua 文件，确认包含相机驱动与 `bench_defaults.lua`。语法/依赖检查须通过；如果报缺库，先检查导入列表，不用默认扩展库替换已固定版本的文件。
4. **“清除 FS 分区”和“清除 KV 分区”均不勾选。** 不勾“忽略脚本依赖性”。如工具提示必须清分区或更换核心，先回报并暂停，不能自行扩大操作范围。
5. 关闭项目管理器后，在 LuaTools 主界面项目下拉框再次明确选中 `petpalcamera003_r2`；此前仅在项目管理器选中后关闭曾回退至旧项目。截图核对 CORE 和脚本列表。
6. 已确认板上核心为同一指定版本时，优先“下载脚本”；核心不同或无法确认时才用包内核心执行“全量下载（底层+脚本）”，并记录理由。不清 FS/KV。
7. 按下载，等准备完成、界面进入等待设备/BOOT 的提示阶段，再控制模组进入下载模式。不要在压缩/准备阶段过早上电，下载模式有等待窗口。[官方操作时序](https://docs.openluat.com/common/howtodown/)

### 正常下载失败时：强制 BOOT

底板有 RESET、PWKEY、wakeup 按键，但不能把它们当作 BOOT 键。核心板照片可见标注 `vdd_ext` 与 `boot` 的两个小圆焊盘。

1. 确认模组真正断电，而不是只拔 USB；本块板此前观测需要电池开关供电，USB 插拔不一定使模组断电。
2. 对照板上丝印/原理图确认 **BOOT 与 VDD_EXT**；无法可靠辨认时停止，请懂硬件的人员确认。
3. LuaTools 已进入等待下载阶段时，在**上电前**连接 BOOT 与 VDD_EXT，保持连接并给模组上电；未启动时保持 BOOT 条件再操作 PWKEY。
4. 看到工具实际开始下载/写入后撤去临时连接。期间保持数据线与供电稳定。
5. 下载结束、解除 BOOT 条件，再正常重启检查新版本。

只允许连接已核实的 BOOT/VDD_EXT，不短接 BAT、VIN、GND 或其他邻近焊盘，不外接猜测电压，不带电随机试探。官方 USB_BOOT 规则是上电前拉至 VDD_EXT；正常启动后再连接不能强制进入 BOOT。引用为对应核心系列的通用规则，实际焊盘位置以这块板为准。[官方 USB_BOOT 说明](https://docs.openluat.com/air780epm/luatos/hardware/boot/)

遇到重启超时/通信错误：最多做 3 次核实过的完整时序尝试；记录普通模式与下载模式的设备变化和错误截图，然后停下排查。不能用反复随机短接替代诊断。

## 6. 烧录后分级验收

### A. 固件与 USB 命令台（烧录电脑必须验收）

- LuaTools 明确显示下载成功；保存成功截图及项目配置截图。
- 正常启动日志出现 `petpal_evt0 001.000.003 collar-evt-001 evt0.0.3`（日志前缀可不同）。仍出现 `001.000.001` 即本轮未成功更新。
- 记录至少 3 分钟启动日志，核对功能开关；不得有连续异常重启、缺库、Lua 错误。
- 用户虚拟串口 `uart.VUART_0` 使用 115200、8N1，文本命令以换行结束。SOC log 口不是命令口，用 `ping` 找到回复的端口。
- 测试前让 LuaTools/串口终端释放用户口，同一端口不能被两个进程同时打开。

若接收电脑安装 Python 3 与 pyserial，在包根目录执行（COM13 仅为示例）：

```powershell
py -m pip install pyserial
py .\tools\usb_cmd.py --port COM13 ping
py .\tools\usb_cmd.py --port COM13 get
py .\tools\usb_cmd.py --port COM13 capabilities
py .\tools\usb_cmd.py --port COM13 snapshot
```

`ping` 必须回复 `pong petpal_evt0 001.000.003`。`get` 必须显示本单开关配置；`snapshot` 中设备 ID 正确。不要发 `set`、`clear` 或随意 `reboot`。旧 KV 的 override 可能仍显示，但不应改变本摄像头配置。

### B. 真实摄像头 JPEG（烧录电脑优先完成）

1. 释放用户串口，在 Windows 运行包内桥，显式指定上述用户 COM 口：

   ```powershell
   py .\tools\air_bridge.py --port COM13
   ```

   默认只监听 `127.0.0.1:8210`；Windows 上不指定 `--port` 的自动发现不适用。如已设 `PETPAL_BRIDGE_TOKEN`，请求需提供对应 Bearer Token，不在截图/日志泄漏密钥。
2. 在同一台电脑浏览器打开以下地址，取得按需新拍 JPEG：

   ```text
   http://127.0.0.1:8210/v1/devices/collar-evt-001/camera/frame
   ```

3. 连续请求至少 30 秒，改变镜头方向或移动镜头前物体，核对每次画面确实变化。浏览器的单张显示不是连续播放器，本步骤只验真实采集/传输；不能据此标记 iOS 实况通过。
4. 桥会校验设备 ID、帧 ID、偏移、长度、JPEG 起止标记和 Adler32。记录成功/失败请求数、每帧字节数、实际尺寸、采集到显示耗时、测试时长与期间内存变化。没有实测前不承诺分辨率或帧率；代码初始化使用 640×480，但实际输出须解码确认。
5. 可另外用串口检查：`camera capture test0001` 先可能回复 `ok camera scheduled`，随后必须出现 `frame test0001 <字节数> <adler32十六进制>`；这只是帧头，不是完整 JPEG。`camera chunk test0001 0` 返回首块十六进制；完整图片须拉取全部分块并校验，可由上述桥完成。最后 `camera close test0001` 释放。不要只收到帧头就宣称取得图片。

传感器探测规则：I2C1 / 地址 0x21 / 寄存器 F0、F1，识别 GC032A 的 0x232A 或 GC0310 的 0xA310。相机 GPIO22 电源、GPIO5 PWDN，GPIO28/24/26 用于该 BTB 例程总线供电/上拉，Camera1 MCLK 24MHz。这是指定板型的代码配置，不是允许给另一块板照接的通用引脚表。

未知 ID、`camera_core_unavailable`、`camera_open_failed`、拍照超时或校验失败：回传原始错误和板型，停止相机验收；不能猜测驱动、更换底层版本或绕过 JPEG 校验。当前核心能否完成这一摄像头路径仍需实板验证。[官方 Air8201 摄像头例程](https://github.com/openLuat/LuatOS/tree/master/module/Air8201/demo/camera)

### C. 原宠宝 iOS 实况页（交回 Mac 后联调）

独立工程：`apps/ios_air8201/PetPalAir8201G.xcodeproj`，scheme `PetCollar`，Bundle ID `com.petpal.air8201g`。Windows 仅烧录不要求构建 iOS；iOS 工程不在本烧录包内，保留在项目开发电脑。

链路：板载摄像头 → 新 JPEG → USB VUART → 同一台 Mac 的本机 HTTP 桥 → Core 层转换为 MJPEG → 原 App 实况页面。原 `/stream`、`/capture` 语义由底层适配，不修改页面。

- 将板子物理接回 Mac，停止 Windows 工具占用，运行项目现有 `apps/bridge/air_bridge.py`。
- 用新 iOS 工程运行模拟器，进入原“实况”页，观察移动场景至少 30 秒并记录刷新速度、延迟与断流。
- 原“停止”操作应停止新增采集请求；断 USB 后旧画面应在现有 10 秒无新帧保护内清掉并进入原重连提示，不把冻结帧持续标为 LIVE。
- 当前是 **JPEG 实时连拍台架**，不是已验收的高帧率视频流、音视频通话或 4G 远程直播。
- Windows 桥的 `127.0.0.1` 不能由 Mac 模拟器跨电脑访问；iPhone 真机也不能访问电脑的 loopback。不要为方便直接将图像接口改成公开监听。
- 真机/4G 远程实况需另行实现认证 HTTPS 服务、蜂窝图像上传/传输、带宽与重连管理、授权及隐私保护。这属于后续开发，不是烧一次包即可获得的能力。

## 7. App 与硬件通信需求

所有硬件状态必须来自板子/服务的真实数据；未知/未接入状态明确返回不可用，不能显示虚构电量、定位或执行成功。普通连接成功不等于某个外设已准备好。

当前本机桥协议：

- `GET /v1/devices/{id}/snapshot`：真实状态及 capabilities。
- `GET /v1/devices/{id}/camera/frame`：本次请求的新 JPEG，禁缓存、逐块校验。
- `POST /v1/devices/{id}/commands`：命令信封。
- `GET /v1/devices/{id}/commands/{command_id}`：相同命令 ID 的回执；只在 `executed` 时让 App 显示已执行。超时不能自动用新 ID 重发执行器动作。

后续保持旧 ESPClient 的调用兼容，仅在 Core/硬件适配/服务端层调整。设备 ID 不符必须拒绝，失败必须显示原有错误/重连提示。不改原版 UI，不卸载旧 ESP32 App，不共用其配置存档。照片默认仅 RAM 内临时传输，不自动保存或上传第三方；如为验收主动保存样片，应先取得用户同意并确认无隐私内容。

## 8. 其余项圈功能的迁移需求（不包含在本次摄像头验收）

| 功能 | Air8201G 迁移要求 | 当前边界及验收条件 |
|---|---|---|
| GNSS / 最后位置 | UART2、GPIO21 供电，向原 GPS 页面提供真实经纬度、时间、卫星/定位状态；失效显式显示 | 已有代码待实板；室外冷启动/移动/失锁验证；LBS 回退与历史轨迹服务待开发 |
| 活动/运动 | DA267 I2C1 数据供原活动视图，传感器掉线报不可用 | 已有活动估计代码；不能当校准步数/健康指标；摄像头共存需先解决 I2C1 资源生命周期 |
| 电量/充电/低电量 | ADC0 电压换算、充电状态及低电保护，未知值不伪造 | 本包 power 已启用但需万用表对照与电量曲线校准；不因此证明充电/电池安全 |
| 灯光 | 原按钮对应真实 LED 开关/闪烁及执行回执 | 板载 GPIO16 单色 LED 代码待测；RGB/亮度能力不能假定存在，本包 actuator 关闭 |
| 震动/停止 | 确认驱动电路、MOSFET、引脚和温度，保留原控制方式及固件本地限幅/紧急停止 | 无验证马达引脚，默认禁用；≤500ms×3、至少30s冷却；低电/充电/异常温度拒绝；不得绕过安全校验 |
| 声音/自定义声音/录音 | 确认功放、扬声器/麦克风、接口、存储、音频固件与控制协议 | 未实现；缺少硬件和接口确认，不能靠现有相机包获得 |
| BLE 近距离 | 保持原 App 入口，按已验证广播/连接能力提供真实状态 | 现有广播代码不等于测距、配网或手机连接；BLMQ 路径/核心库需验证，本包关闭 |
| 模式/走失/围栏 | 日常/静止/走失 TTL、误差带与连续定位判断、状态持久化，原页面接真实事件 | 已有逻辑待实板定位/边界/重启验证；配置命令须有鉴权与回执 |
| 4G 远程控制/离线补传 | 真实 SIM、TLS broker/CA/ACL、时钟门控、命令过期与去重、PUBACK 后删队列 | 已有部分固件代码待网络实测；新 App 的远程服务未部署，本包 MQTT 关闭 |
| 升级/远程日志 | 自有认证发布服务、签名/版本检查、失败回退、日志脱敏 | FOTA 未启用；不得自行打开第三方诊断/图像上传 |
| 低功耗/续航 | 电流、睡眠/唤醒、看门狗、USB 与蜂窝恢复实测后再启用 | 本包保持 USB，不进入真实低功耗；无续航承诺 |
| 电弧/高压 | 原旧源码保留，新宠物佩戴硬件版本不提供此输出 | 不实现、不接线；原界面请求应明确报不支持 |

商城、虚拟宠物等非硬件业务界面不在此次烧录范围，不将其演示数据当作板载功能。后续集成包要另行发布和校验，不能在本摄像头包里将全部 features 设 true 充当完整产品。

## 9. 停止条件、回传与回退

遇到板型不符、无法辨认 BOOT 焊盘、文件校验不符、必须清分区、供电异常/发热、连续重启、缺库或相机错误时暂停，回报具体证据。不现场重写协议、不猜引脚、不更改原 ESP32 工程。

请填写包内 `FLASH_REPORT_TEMPLATE.md`，至少回传：

1. Windows/LuaTools 版本、下载方式、核心文件哈希、21 文件列表截图、FS/KV 未清除截图。
2. 写入成功截图，3 分钟脱敏日志，新版本启动行和 ping/get/capabilities/snapshot 实际回复。
3. 正常用户 COM 口、SOC log 口、下载设备信息，以及是否使用 BOOT 焊盘。
4. 真实图像采集结果：传感器型号、JPEG 尺寸/字节数、30 秒成功帧数/失败数、延迟、内存与异常；可用无隐私场景录像作为证明，保存/回传需用户同意。
5. 分别勾选 A 固件命令台、B 真实 JPEG、C iOS 实况；没做的写“未测试”，失败写原始错误，不能合并成“全部完成”。

执行 `py .\tools\redact_ids.py <日志文件>` 后回传生成的 `.redacted.txt`；回传前再人工检查手机号、凭据、定位和图片隐私。不要发送未经打码的设备标识或密码。

本次不提供未知旧设备分区的完整回退镜像。若需回退，先停并联系项目负责人确认已保存的旧核心和匹配脚本；不将 hello_world 或恢复出厂当作无损回退。

## 10. 给接收电脑操作人员/AI 的简短任务

> 请先阅读本单，核对 Air8201G-BLMQ / EXB_AIR8201G_BTB_V1.4，用包内指定 V2030 核心和 scripts 下全部 21 个 Lua 文件新建独立 LuaTools 摄像头项目，不清 FS/KV，不混用旧工程。完成烧录后证明 `001.000.003` 真正在板上运行，验证用户 USB 命令台，并用 tools/air_bridge.py 显式指定 Windows COM 口获取随场景变化的新 JPEG。填写结果模板、回传脱敏日志。其余功能依本单列为后续迁移，不改 ESP32 旧代码，不改宠宝界面，不把 USB JPEG 台架称为已完成 4G 直播。需要清分区、换核心、改引脚或出现硬件异常时停止并询问。
