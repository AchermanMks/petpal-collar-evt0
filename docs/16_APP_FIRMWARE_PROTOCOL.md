# 宠宝 App ⇄ Air8201G 固件通信协议（给 Windows 侧开发用）

版本：2026-09-21，依据 Mac 上当前源码整理（`apps/ios_air8201/PetCollar/Core/AirCollar.swift`、`apps/bridge/air_bridge.py`、`firmware/wearable-evt0/*.lua`）。
读者：在 Windows 上开发固件功能的人 / Claude。目标：**你在 Windows 上写的固件，拿回 Mac 不改 App 界面就能联调。**

每一节都标了状态：
- **【现状】** Mac 侧代码已经这样实现，且 2026-09-20 在板 1 实板验证过。固件必须兼容，否则 App 连不上。
- **【约定·新增】** 目前两边都还没有，这里先定好格式。Windows 侧按此实现固件，Mac 侧（桥和 App 适配层）我按同一份文档补。**不要自己另起一套格式。**

---

## 0. 总体链路

```
iOS App（界面不改）
  └─ 原 ESPClient 调用（/led/on、/stream、/api/gps …）
      └─ AirHardwareProtocol / AirCollar.swift（App 内适配层，把旧路径翻译成新 API）
          └─ HTTP  http://127.0.0.1:8210/v1/devices/{device_id}/…      ← “桥” air_bridge.py（Mac 本机）
              └─ USB 虚拟串口 uart.VUART_0，文本行命令（本文第 1～4 节）   ← 固件 console_app.lua
                  └─ 各功能模块（camera_app / gnss_app / actuator_app / power_app …）写 _G.STATE、执行命令
```

固件侧要对接的只有一层：**USB 命令台（console）+ `_G.STATE` 快照 + command/ack 信封**。HTTP 那层由 Mac 的桥负责，第 5 节列出来只是让你知道 App 最终需要什么。

将来 4G 远程：同一份 command/ack 信封和 telemetry 走 MQTT（`schemas/*.json`），所以信封格式不要为 USB 单独改。

设备编号：板 1 = `collar-evt-003`（加装摄像头后改的号），板 2 = `collar-evt-002`。固件 `config.lua` 的 `device_id`、桥的 `--device`、App 的环境变量 `PETPAL_AIR_DEVICE_ID` 三处必须一致，否则桥报「实际开发板的设备编号不匹配」。

---

## 1. USB 命令台传输层【现状】

| 项 | 规定 |
|---|---|
| 端口 | `uart.VUART_0`（USB 用户虚拟串口）。Windows 上是「用户虚拟串口 COMx」，**不是** soc log 口；macOS 上是 `cu.usbmodem…17` |
| 参数 | 115200 8N1（虚拟口，实际速率由 USB 决定，实测 >500 KB/s） |
| 请求 | 主机发一行 ASCII 文本，`\n` 结尾（`\r` 会被忽略） |
| 回复 | 固件回一行文本，`\r\n` 结尾。**前缀决定类型**：`ok …` 成功、`err …` 失败、`pong …`、`ack {json}`、`frame …`、`jpeg …`、`jpegbin …` |
| 一问一答 | 每条命令**立刻**回且只回一行同步回复。耗时操作先回 `ok … scheduled` / `ack {"status":"accepted"}`，结果以后用**异步行**送达（见下） |
| 异步行 | 只有三种：`frame <id> …` / `err camera <id> <原因>`（拍照结果）、`ack {json}`（命令最终回执）、`ok led done`。主机按前缀和 id 认领 |
| 分段写 | **所有 `uart.write` 必须按 ≤480 字节分段**（`console_app.lua` 的 `send()`）。根因：USB 512 字节满包偶发丢失（板 2 实测）。不要直接 `uart.write` 长字符串 |
| 二进制期间不插话 | `camera read` 发送原始字节期间（`_G.CAMERA.tx_busy=true`），其他文本回复必须排队，发完再补发（`send()` 已实现）。新增模块要回复请统一走 `send()`，不要自己 `uart.write` |
| 请求行长度 | 解析器单行上限 2048，但**未收到换行时缓冲超过 512 字节会被清空** → 命令行请保持 ≤512 字节 |
| 独占 | 同一时刻只能有一个程序打开这个口（桥、usb_cmd.py、Luatools 串口终端三选一），否则互相抢字节 |

### 版本握手（很重要）【现状】

```
→ ping
← pong petpal_evt0 001.000.003
```

Mac 的桥靠这一行找端口，**只认** `pong petpal_evt0 001.000.002` 和 `pong petpal_evt0 001.000.003`。
所以 `main.lua` 里 `PROJECT="petpal_evt0"`、`VERSION="001.000.003"` **先不要改**；用 `config.lua` 的 `c.fw="evt0.0.N"` 区分你的构建（格式必须是 `evt0.数字.数字`，telemetry schema 有正则）。确实要升 VERSION 请在交回时告诉我，我同步改桥。

---

## 2. 命令一览【现状】

| 命令 | 同步回复 | 说明 |
|---|---|---|
| `ping` | `pong <PROJECT> <VERSION>` | 握手 |
| `get` | `ok features {json} override {json}` | 生效的功能开关 + KV 覆盖 |
| `set <feature> 0\|1` | `ok <f>=<v> saved, send reboot to apply` | 写 KV；`config.lua` 里 `ignore_feature_override=true` 时重启后不生效 |
| `clear` | `ok override cleared, send reboot to apply` | |
| `status` | `ok status <st> simid <n> iccid <掩码\|nil> csq <n> rsrp <n> online <bool> mem <n>` | 网络/内存 |
| `capabilities` | `ok {json}` | 见 3.2 |
| `snapshot` | `ok {json}` | **App 所有状态的唯一来源**，见第 3 节 |
| `gnss` | `ok {json}` | 搜星诊断：`on_s, sats_in_view, sats_with_signal, snr_max, fix, sats, ttff_s, tracking, ready` |
| `mode <routine\|lost> [ttl_s]` | `ok mode updated` | |
| `led [pattern] [秒]` | `ok led scheduled`，结束后异步 `ok led done` | **台架直通，不经过时钟/去重校验**；pattern = on/off/blink/breathe |
| `stop` | `ok outputs off` | 关马达 + 关灯，任何时候都必须成功 |
| `locate` | `ok locate requested` | |
| `reboot` | `ok rebooting` | 500 ms 后软复位 |
| `command <json>` | 先一行 `ack {json}`（受理/拒绝），再一行 `ok command processed`；最终结果是稍后的异步 `ack {json}`，见第 4 节 | App 的所有控制动作都走这条 |
| `camera capture <id>` | `ok camera scheduled` 或 `err camera <原因>` | 见第 6 节 |
| `camera read <id> <offset> <len>` | `jpegbin <id> <offset> <n>\r\n` + n 个原始字节 | 快速路径（evt0.0.5 起） |
| `camera chunk <id> <offset>` | `jpeg <id> <offset> <hex>` | 旧的 1 KB 十六进制路径，保留作回退 |
| `camera config k=v …` | `ok camera config quality=.. sum=.. crop=..` | 运行时调参 |
| `camera close <id>` | `ok camera closed` | |
| 未知命令 | `err unknown command <cmd>` | 桥据此判断固件新旧，**不要把未知命令静默吞掉** |

`<id>`：8～64 个字符，仅 `[A-Za-z0-9-]`；桥实际用 32 位十六进制 uuid。

---

## 3. `snapshot` 快照【现状】

`snapshot` 回复 `ok ` + `json.encode(_G.STATE, "7f")`。**必须用 `"7f"`**：LuatOS 默认 `%.7g` 只有 7 位有效数字，经度 114.05xxxx 会被截到约 10 m。

各模块只管往 `_G.STATE` 写自己的字段；没有的数据就不写或写 `nil`，**绝不填假值**（App 对缺字段有明确的「不可用」提示，对假值没有防护）。

### 3.1 App / 桥实际读取的字段

| 字段 | 类型 | 谁用 | 规则 |
|---|---|---|---|
| `device_id` | string | 桥 | 必须等于桥的 `--device`，否则整个请求 503 |
| `fw` | string | 记录 | `evt0.N.N` |
| `position` | object 或缺省 | App GPS 页 | 未定位过就**不要有这个键** |
| `position.source` | `"gnss"` | App | 只有 `"gnss"` 才算有效定位（LBS 回退将来用 `"lbs"`，App 不会当作精确定位） |
| `position.lat` `lng` | number，十进制度 | App | 有限数、范围合法、不能是 0,0 |
| `position.sats` `alt_m` `speed_kmh` `fix_age_s` | number | App | **四个都必须存在**，缺任意一个 App 报「GNSS 原始数据尚不完整」。`fix_age_s` 整数秒；App 以 `≤120` 判定「有定位」 |
| `position.accuracy_m` | number 或缺省 | 围栏 | 估计值；无把握就不写 |
| `last_fix.ts` | number，Unix 秒 | App | ≥1700000000 才显示时间 |
| `last_fix.tick` | number，`mcu.ticks()` | 固件内部 | `fix_age_s` 用它算（GNSS 校 RTC 后 `os.time()` 会跳变） |
| `outputs.led_on` `outputs.motor_on` | bool | App 灯光/马达页 | 由 `actuator_app` 在真实动作时更新 |
| `battery` | `{ready,pct,mv,charging,temp_c?}` | 安全校验 | `ready=false` 时其余不可信 |
| `camera` | `{ready,model,frame_bytes}` 或 `{ready=false,error}` | 诊断 | |
| `gnss` | 见 `gnss` 命令 | 诊断 | |
| `clock_synced` | bool | **命令是否会被拒**，见 4.3 | |
| `capabilities` | object | 诊断 | 见 3.2 |
| `mode` `boot_count` `online` `mqtt_online` `motion` `radio` `seq` `boot_ts` | | 遥测 | |

桥把它包成 HTTP 返回：`{"device_id":…, "online":true, "last_seen_ts":…, "transport":"usb-bench", "telemetry": <上面这个对象>}`。
App 还认一个可选的 `legacy_status`（旧 ESP32 状态页的结构 `ESPStatus`：chip/memory/wifi…）；目前没有提供，App 显示「完整设备诊断数据尚未接入」，属预期，**不要用假的 ESP32/Wi-Fi 数据去填**。

### 3.2 `capabilities`

`{gnss, battery, motion, led, vibration, ble, mqtt, camera, audio, rgb, fota : bool, activity:"experimental_not_health_measurement", arc:false}`
每一项必须反映**真实就绪状态**（例如 `camera` 只有成功拍过一帧才是 true，`vibration` 需要 `motor_verified=true`）。新增功能（如 audio）做通后，把对应项改成真实判断。`arc` 永远 false。

---

## 4. 控制命令信封 `command <json>` 与回执 `ack <json>`【现状】

App 的每个控制动作（开灯、震动、切模式…）都封成同一种信封，经桥原样转给固件：

```
→ command {"id":"6F1C…-UUID","device_id":"collar-evt-002","issued_at":1790000000,"expires_at":1790000120,"type":"LED","args":{"pattern":"on","duration_s":300}}
← ack {"id":"6F1C…","device_id":"collar-evt-002","ts":1790000001,"status":"accepted","expires_at":1790000120}
← ok command processed                      （同步行；桥会忽略它，只认 ack）
…动作执行完…
← ack {"id":"6F1C…","device_id":"…","ts":…,"status":"executed"}          （异步）
```

### 4.1 字段

| 信封字段 | 规则 |
|---|---|
| `id` | 8～64 字符。App 用 UUID（36 字符，含 `-`） |
| `device_id` | 有则必须等于本机，否则 `rejected/wrong_device` |
| `issued_at` `expires_at` | 整数 Unix 秒；App 固定 `expires_at = issued_at + 120` |
| `type` | 见 4.2 |
| `args` | object，可省略 |

| 回执字段 | 规则 |
|---|---|
| `id` | 原命令 id |
| `status` | `accepted`（已受理，还在执行）→ `executed` 或 `rejected`。也可以直接 `executed` / `rejected` |
| `reason` | `rejected` 时必填；枚举见 `schemas/ack.schema.json`（`clock_unsynced`、`cooldown`、`charging`、`low_battery`、`temperature_unknown`、`unsupported`、`hardware_unverified`、`busy`、`no_fix`…）。新增原因要同步加到 schema |
| `applied_args` | 固件裁剪后实际执行的参数（例如震动被限到 500 ms） |
| `device_id` `ts` `expires_at` | |

App 的判定逻辑（不要破坏）：
- 只有 `status=="executed"` 才向用户显示成功；`accepted` 时每 2 s 用**同一个 id** 再查一次，最多 35 次（70 s）；其他状态显示 `reason`。
- **同一个 id 重复到达必须返回已保存的回执，绝不能再执行一次动作**（`command_app.lua` 的 `seen[]`，落 KV `pp_cmds`，最多 24 条）。桥的「查询回执」就是把原信封再发一遍。
- 重启后发现 `accepted` 未完成的 → 改成 `rejected/execution_unknown_after_reboot`，不重放。
- `STOP` 是例外：不查时钟、不查去重、不依赖 Flash，立即关所有输出并回 `executed`。任何新增的执行器都必须挂到 `STOP` 上。

### 4.2 已支持的 `type`

| type | args | 固件行为 | App 入口 |
|---|---|---|---|
| `LED` | `pattern`: on/off/blink/breathe；`duration_s`: 0～300 | `ACT.led()`，板载单色灯 GPIO16 | 灯光页 开 → `on,300`；关 → `off,0` |
| `VIBRATE` | `duration_ms` 50～500，`count` 1～3 | 硬上限 500 ms × 3、冷却 30 s；充电/低电/温度未知拒绝；马达引脚未核实时 `unsupported` | 马达页（只接受 intensity=255，duration≤500） |
| `STOP` | — | 关马达 + 关灯 | 马达/声音/电弧页的「停止」 |
| `SET_MODE` | `mode`: routine/lost，`ttl_s` 60～7200 | | |
| `SET_GEOFENCE` | `enabled` 或 `lat,lng,radius_m(50～50000)` | 落 KV | |
| `LOCATE_NOW` | — | 常开模式下直接返回当前状态 | |
| `GET_STATE` | — | | |

桥对 `type` 有白名单（上表 7 个），其他一律 HTTP 422。**新增 type 要告诉我，我加白名单。**

### 4.3 已知缺口：时钟闸门【现状 + 约定·新增】

`command_app.validate()` 在时钟未同步（`os.time() < 1700000000`）时**拒绝除 STOP 外的所有命令**，原因 `clock_unsynced`。台架上没 SIM、GNSS 又没定位时时钟永远不同步 → **App 里点「开灯」会失败，而命令台直发 `led on` 却能亮**（那条路不校验）。如果你在 Windows 上「灯已经调好」是用 `led …` 验的，拿回 Mac 用 App 点仍可能被拒。

约定的解决办法（请在固件里实现，Mac 侧桥我来配合）：

```
→ time <unix秒>                 例：time 1790000000
← ok time set 1790000000        仅当当前时钟无效（<1700000000）时才接受；已同步则回 ok time kept <当前值>
← err time invalid              参数不是 1700000000～4102444800 的整数
```

固件用 `rtc.set` / `os` 对应接口写入；桥在发现 `snapshot.clock_synced=false` 时自动先发一次。不要为了绕过而删掉时钟校验（4G 远程时它防重放）。

---

## 5. 桥的 HTTP API（App 实际调用的，供参考）【现状】

基址 `http://127.0.0.1:8210`，只监听本机；带 `Origin` 头或 Host 非本机的请求 403；可选 `Authorization: Bearer $PETPAL_BRIDGE_TOKEN`。

| 方法 路径 | 对应固件 | 返回 |
|---|---|---|
| `GET /v1/devices/{id}/snapshot` | `snapshot` | 3.1 的包装对象 |
| `GET /v1/devices/{id}/camera/frame` | 第 6 节 | `image/jpeg`，一帧新拍的图 |
| `POST /v1/devices/{id}/commands`（JSON 信封，≤1800 字节） | `command {…}` | ack；`accepted` → 202，其余 200 |
| `GET /v1/devices/{id}/commands/{command_id}` | 同一信封重发 | 已保存的 ack（180 s 内） |
| 任意错误 | | `503 {"error":"…"}`，App 原样显示 error 文本 |

App 旧路径 → 新 API 的映射（`AirCollar.swift`）：

| App 原调用 | 现在的去向 | 状态 |
|---|---|---|
| `/stream`（实况页） | 循环 `camera/frame`，包成 MJPEG；帧间隔 250 ms | ✅ 板 1 实测 |
| `/capture` | `camera/frame` | ✅ |
| `/led/on` `/led/off` | `LED on,300` / `LED off,0` | ✅（受 4.3 影响） |
| `/led/rgb?r=&g=&b=` | **App 内直接拒绝**「RGB 外设尚未接入」 | 无 RGB 硬件，不实现 |
| `/motor/vibrate?duration=&intensity=` | `VIBRATE` | 马达引脚未核实前固件回 `unsupported` |
| `/motor/stop` `/speaker/stop` `/arc/stop` | `STOP` | ✅ |
| `/motor/status` | `snapshot.outputs.motor_on` | ✅ |
| `/api/gps` | `snapshot.position` + `last_fix` | ✅ 固件实现；板 1 还没收到卫星 |
| `/api/status` | `snapshot.legacy_status` | 未提供（预期） |
| `/speaker/beep?freq=&duration=&volume=` | **App 内直接拒绝** | 见第 7 节 |
| `/speaker/meow?volume=` `/speaker/test` | 同上 | 见第 7 节 |
| `/speaker/files` `/speaker/play?name=&volume=` `/speaker/upload?name=`(POST PCM) `/speaker/delete?name=` | 同上 | 见第 7 节 |
| `/arc/*`（除 stop） | App 内拒绝 | **永不实现**（宠物佩戴版禁止电弧/高压） |

---

## 6. 摄像头协议【现状，evt0.0.5 起；板 1 实测 6.9 fps】

```
→ camera capture <id>
← ok camera scheduled                         （或 err camera camera_busy / camera_wiring_unverified / …）
← frame <id> <size> <checksum8hex> [crc32]    （异步；失败则 err camera <id> <原因>）
→ camera read <id> <offset> <len>             len ≤ 16384
← jpegbin <id> <offset> <n>\r\n<n 个原始字节>  （n 可能小于 len：到帧尾）
  … 重复直到取满 size …
→ camera close <id>
← ok camera closed
```

- 校验：第 4 个字段是 `crc32` 时用 CRC-32（zlib 同款，`crypto.crc32`），否则 Adler-32。桥默认发 `camera config sum=crc32`（Lua 逐字节 Adler-32 要 1.3 s/帧，CRC32 走 C 实现）。
- 传感器在连拍期间保持打开，空闲 6 s 自动断电；设备只保留 2 帧（一帧在传 + 一帧预取），帧 20 s 无人读取自动释放。
- 上一帧还在传时就可以发下一条 `capture`（预取）；传感器忙回 `err camera camera_busy`，主机稍后重试。
- 单帧上限 256 KiB；必须以 `FF D8` 开头、`FF D9` 结尾。
- 摄像头与 G-sensor 共用 I2C1：`features.gsensor=true` 时 `capture` 直接拒绝。
- 画面必须是本次请求新拍的；不允许静态图、缓存重放、演示视频。

---

## 7. 声音功能【约定·新增】（硬件：ES8311 + AW8010B，功放使能 GPIO25，喇叭接 SPK+/SPK-）

目前 App 适配层对 `/speaker/*`（除 stop）一律本地拒绝，固件也没有音频模块。Windows 侧实现固件时请按下面的格式；Mac 侧我据此改 `AirCollar.swift` 和桥的白名单。

### 7.1 命令 type：`BUZZ`（schema 里已预留）

| args | 含义 | App 入口 |
|---|---|---|
| `{"kind":"beep","freq_hz":100～8000,"duration_ms":100～10000,"volume":0～100}` | 单音 | `/speaker/beep?freq=&duration=&volume=` |
| `{"kind":"meow","volume":0～100}` | 内置猫叫音效（固件自带文件） | `/speaker/meow` |
| `{"kind":"test"}` | 自检音 | `/speaker/test` |
| `{"kind":"file","name":"xxx","volume":0～100}` | 播放已存文件 | `/speaker/play?name=&volume=` |
| `{"kind":"tts","text":"≤60 字","volume":0～100}` | 文字转语音（底层 V2030_1 带 TTS）| 暂无 App 入口，台架用 |

回执规则同第 4 节：开始播放回 `accepted`，播完回 `executed`；被 `STOP` 打断回 `rejected/cancelled`。`STOP` 必须能立即停声并关功放（GPIO25 拉低）。
安全：固件侧设**音量硬上限**（建议先按 60 封顶，`applied_args.volume` 回报实际值，`reason` 可带 `limit_clamped`）；单次播放 ≤10 s；低电量拒绝。播放结束或出错都要关功放、关 ES8311 供电。
`snapshot` 增加 `outputs.speaker_on: bool`；`capabilities.audio` 只有 ES8311 初始化成功后才为 true。

### 7.2 文件管理（第二阶段，先做 7.1）

```
→ audio files
← ok {"files":[{"name":"meow.pcm","bytes":12345}],"total":<分区字节>,"used":<已用字节>}     ← 字段名与 App 的 SpeakerFilesResponse 一致
→ audio delete <name>
← ok audio deleted
```
上传（主机→设备的二进制）还没有现成通道，先不要自己发明；需要时告诉我，两边一起定（会做成与 `camera read` 对称的带校验分块写）。文件名只允许 `[A-Za-z0-9_.-]`，≤32 字符。

---

## 8. 实板踩过的坑（2026-09-20 板 1，全部是真实发生的崩溃/故障）

1. **`tonumber(nil)` 在实板 V2030 上直接报错**（标准 Lua 返回 nil）。凡是 `tonumber(x)` 且 x 可能为 nil，一律写 `tonumber(x or "")`。
2. **`fskv.get(不存在的键)` 无返回值**（不是 nil）。不要把它直接包在 `tonumber()`/`type()` 里。
3. 启动阶段任何 Lua 错误 = `Lua VM exit!! reboot in 15000ms` 无限重启，USB 每 15 s 掉一次。烧完**一定看 40 s 日志**，features 行之后不能有 `E/main`。
4. libgnss / exgnss 在未定位时返回 nil 或缺字段，读取要 `pcall` + 类型判断。
5. USB 回复按 ≤480 字节分段写（见第 1 节）。
6. **GPIO26 是 I2C1 总线电源**：拉低它 DA267 和摄像头一起消失。不要把它当普通 IO（旧配置 `motor_gpio=26` 就是这个坑）。
7. `features.lowpower=true` 会物理关闭 USB，日志和命令台一起消失；台架包保持 false。
8. 板子从一台电脑换插到另一台后要按一次 `reset` 才会重新枚举；真断电后要长按 `PWRKEY`。
9. Luatools 要勾「忽略脚本依赖性」，否则动态 `require` 的文件（`gc032a`、`gc0310`、`bench_defaults`）会被裁掉。
10. 电池供电路径压降大：摄像头一工作 ADC0 掉约 180 mV，出现过 `lastReson 0 0 5` 自发重启。新增耗电外设（功放）时注意，播放期间最好插着 USB。
11. mock 测试（`tools/test_firmware.py`、`tools/test_camera.py`）已按 1、2 两条改成和实板一致；新模块请照着加测试，先在 mock 里跑过再烧。

---

## 9. 在 Windows 上自测兼容性（不需要 Mac）

```powershell
py -m pip install pyserial
py tools\usb_cmd.py --port COM15 ping          # 必须回 pong petpal_evt0 001.000.003
py tools\usb_cmd.py --port COM15 snapshot      # 看 device_id / clock_synced / outputs / capabilities
py tools\air_bridge.py --port COM15 --device collar-evt-002     # 起桥（同一时刻不要再开别的串口工具）
# 浏览器：
#   http://127.0.0.1:8210/v1/devices/collar-evt-002/snapshot
#   http://127.0.0.1:8210/v1/devices/collar-evt-002/camera/frame
# 发一条和 App 完全一样的开灯命令（PowerShell）：
$now=[int][double]::Parse((Get-Date -UFormat %s)); $id=[guid]::NewGuid().ToString()
$body=@{id=$id;device_id="collar-evt-002";issued_at=$now;expires_at=$now+120;type="LED";args=@{pattern="on";duration_s=300}}|ConvertTo-Json -Compress
Invoke-RestMethod -Method Post -Uri http://127.0.0.1:8210/v1/devices/collar-evt-002/commands -ContentType application/json -Body $body
Invoke-RestMethod -Uri http://127.0.0.1:8210/v1/devices/collar-evt-002/commands/$id      # 直到 status=executed
```

判定标准：上面最后一步回 `executed` 且灯真的亮；回 `rejected/clock_unsynced` 就是 4.3 的缺口，先实现 `time` 命令。
`usb_cmd.py`、`air_bridge.py` 请用随本文档一起给的版本（Mac 上 2026-09-20 更新过，旧版不支持二进制取帧）。

---

## 10. 交回 Mac 时请带上

1. 改过/新增的全部 `.lua`（整个 scripts 目录最稳妥）和 `config.lua` 里的 `device_id`、`fw`。
2. 基于哪份源码改的。**Mac 上的固件在 2026-09-20 改了 7 个文件**（`camera_app` `console_app` `gnss_app` `runtime_app` `excamera` `config.*` + 测试），Windows 上如果还是 9/16～9/20 的 r2 基线，请先把随文档给的 `firmware/` 合进去再开发，否则回来要手工合并。
3. 新增的命令行、新增的 command `type`、新增的 `reason`、`snapshot` 新增字段——逐条列出来（哪怕和本文一致也请确认一句）。
4. 40 s 启动日志（打码 IMEI/ICCID：`py tools\redact_ids.py <日志>`）和第 9 节自测的实际输出。
5. 硬件接线变化（喇叭、马达接在哪个脚、灯有没有换脚）。未核实的引脚不要写进默认配置。
