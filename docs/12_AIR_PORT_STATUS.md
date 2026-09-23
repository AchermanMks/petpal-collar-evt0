# 宠宝 Air8201G 功能移植状态（2026-09-16）

范围来源：原 `/Users/mantashark/pet-collar` 的 ESPClient/项圈方案与现有 Air EVT0 工程。按系统设计技能将板载能力、外设、App 和服务端分层，避免把软件实现误报成整机完成。旧 ESP32 代码不变，新 iOS App 另建。

| 功能 | 当前实现 | 尚需验证/条件 |
|---|---|---|
| GNSS/最后位置 | UART2/GPIO21，当前官方库十进制度模式2；速度节→km/h；不编造精度 | 新包烧录、室外实测；LBS 回退尚未接入 |
| 运动/活动 | DA267 GPIO24/28/I2C1/INT20；10Hz 活动峰值/活跃时长估计 | WHOAMI/三轴实测；宠物步态校准、非健康指标 |
| 电池/充电/低电量 | ADC0 分压、有效范围、充电检测、未知值保护 | 电压对照/曲线/温度硬件，不证明电池已安全 |
| 模式/围栏 | 日常/静止/走失TTL/低电/充电覆盖；误差带+连续2定位围栏；KV保存 | 实物移动、定位和事件验证 |
| 灯/震动/停止 | 板载LED16；马达未验证不碰GPIO；≤500ms×3、30s冷却；并发与取消保护；紧急OFF不依赖时钟/Flash | 用户提供 MOSFET、实际引脚、温度与台架确认；无RGB |
| 4G/TLS/指令 | SIM自动选择、网络恢复、TLS/时钟门控、过期/去重/持久化回执 | 当前旧日志无SIM；真实broker/CA/ACL；新App网络桥尚未接MQTT |
| 离线补传 | 有界KV队列，重启扫描恢复；PUBACK后删除；保留ACK空间，满时显式失败 | 真实断线重连/PUBACK/掉电/Flash寿命与容量；服务器按device+boot+seq去重 |
| 独立iOS App | 原界面/导航/按钮不改；Core适配层将旧ESPClient调用转成Air服务，USB台架HTTP桥；不再新增Air页 | 已重新编译/模拟器运行；真机签名/HTTPS服务；原设备诊断页完整数据待接入 |
| BLE | 原广播模块保留并记录广播状态，不冒充测距 | 核心库/BLMQ路径/手机广播验证；BLE近距离能力待实现 |
| 声音/自定义文件/录音 | 未实现，App能力明确为false | 音频器件、接口与引脚、存储、合适核心库 |
| 摄像头/直播 | AIR003专用包：器件ID探测、官方excamera JPEG拍照；USB按需分块校验；Core转成MJPEG供原实况页播放；断流/10s无新帧清掉旧画面 | 尚未烧录/收到真实画面；实际帧率待测；当前仅电脑USB→模拟器台架，不是4G远程视频直播 |
| FOTA/远程日志 | 未启用；自动第三方错误上传默认关闭 | 自有发布服务、认证/签名/回退策略、真实升级验证 |
| 低功耗/续航 | 防止未经验证直接关闭USB | 电流实测、唤醒/看门狗/网络重连验证 |
| 电弧/高压 | **不提供宠物佩戴版**，旧台面演示代码保留在旧工程 | 不属于安全宠物项圈输出 |

测试：`tools/luacheck.py` 编译 Lua；`tools/test_firmware.py` 执行生产模块的确定性硬件mock测试（限制、取消、状态恢复、围栏、KV队列、去重、重启、时间/存储失败、GNSS API字段）；`tools/selftest.py` 原验收工具合成数据回归；`tools/test_bridge.py` HTTP鉴权/跨站/协议测试。以上均不能替代实板验收。

台架包用 `tools/build_bench.py` 创建新目录，拒绝覆盖旧包，并输出 SHA256 manifest。只开板载 GNSS/运动/电池/LED，禁用马达/MQTT/BLE/FOTA/真实低功耗。未备份未知旧固件分区，不清FS/KV、不冒充出厂还原包。

实测记录：新iOS App已编译/安装/启动；按用户最新要求撤销新增Air页，恢复原RootView及所有硬件导航，仅更换Core通信。`tools/test_ios_preservation.py` 验证原源码snapshot零变化及新App页面/主题/资源逐字节一致；`tools/test_air_adapter.py` 用测试专用HTTP fixture运行实际Swift适配代码，验证原ESPClient接口、执行回执、GPS转换、输出状态及未实现功能拒绝；不等同实板验收。HTTP桥真实查询返回“未找到AIR002命令台”。旧板日志仍为001.000.001且SIM未插入，新包未成功烧录。UTM出现灰色局部刷新异常后停止不可见下载操作，未清分区/未误烧旧hello项目。新完整包在 `/Users/mantashark/petpal-vm-share/PetPal_Air8201G_legacy_ui_002`，此前iOS_bench_002包保留不覆盖。

API核对来源：[官方 exgnss 扩展库文档](https://wiki.luatos.com/api/libs/exgnss.html)及本仓库官方源码注释（rmc/gga模式2）；[官方fskv文档](https://wiki.luatos.com/api/fskv.html)（单value最大4095字节，代码写入前检查长度）。
