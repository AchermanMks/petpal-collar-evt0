# Air8201G 摄像头实况：实现及待验收

用户要求：原 PetPal 界面不改，先实现摄像头实况。旧 ESP32 源码不改。

当前代码链路：SPI 摄像头 → LuatOS/excamera 拍 JPEG → USB VUART → 电脑本机 HTTP `/v1/devices/{id}/camera/frame` → Core/AirHardwareProtocol 拼 multipart MJPEG → 原 MJPEGStream → 原 CameraStreamView。服务端每次请求触发新采集，不循环重放缓存或演示视频。原 `/stream`、`/capture` 调用适配至新硬件。

这是 JPEG 实时连拍台架，不承诺视频帧率。官方 Air8201G 例程提供拍照/扫码，不是成熟 Cat.1 视频推流；参见[合宙摄像头方案说明](https://docs.openluat.com/faq/2026-09-05/)及[官方 Air8201G SPI 摄像头例程](https://github.com/openLuat/LuatOS/tree/master/module/Air8201/demo/camera)。实时帧率、尺寸与延迟需真实画面测试后记录。

## 专用测试包

目录：`/Users/mantashark/petpal-vm-share/PetPal_Air8201G_camera_003_r2`，完整 Lua 脚本与 manifest，同名 zip。先前 camera_003 是开发中间包，保留但不要使用。

LuaTools 新建摄像头项目，选择已有 `core_firmware/LuatOS-SoC_V2030_Air780EGH_1.soc`，添加本目录**全部 Lua 文件**（包含 config.lua、bench_defaults.lua、excamera.lua、gc032a.lua、gc0310.lua 等）。不使用旧 hello 工程，不清 FS/KV，不宣称未知旧分区已备份。脚本日志须出现 `petpal_evt0 001.000.003`。

2026-09-16 台架记录：Windows LuaTools 3.4.10 已保存独立项目 `petpalcamera003`，递归导入 `Z:\PetPal_Air8201G_camera_003_r2`，界面显示“语法检查成功”。主界面项目下拉框须显式选择该项目；仅在项目管理器选择并关闭可能回退至旧8201，发现回退后已在准备阶段退出，未给旧项目执行物理复位。摄像头项目的脚本下载及同版核心+脚本下载均在握手阶段“模块重启超时”，进度0%，未显示写入成功；重接后真实日志仍为001.000.001。复位会让19D1:0001设备回到macOS，已尝试立即重新直通UTM，但仍只见普通软件重启，未成功进入下载模式。清FS/KV始终关闭；下一步确认核心板BOOT/VDD_EXT焊盘后采用强制下载，不继续重复普通复位。

此包仅开 camera/power，禁用 MQTT/GNSS/gsensor/马达/BLE/低功耗。原因：官方 excamera.close 会关闭 I2C1，与 DA267 共享；摄像头首验先独占总线，后续共存需另外管理总线资源，不能误报其他板载功能同时工作。

按照片确认 EXB_AIR8201G_BTB_V1.4；引脚按官方 G 型 BTB 例程：I2C1、摄像头电源 GPIO22、PWDN GPIO5、总线上拉/电源 GPIO28/24/26，SPI Camera1 24MHz。提供 MCLK 后读 I2C0x21 的 F0/F1 识别 GC032A/GC0310；不把 KCS001 排线丝印当作传感器型号。未知 ID、核心库缺失、拍摄失败均拒绝，不随机尝试不支持的驱动。

## 运行与验收

1. 完成烧录；确认日志版本003。Windows LuaTools 停止串口占用，在 UTM USB 菜单将 AirM2M 交回 macOS。
2. 项目根运行 `.venv/bin/python apps/bridge/air_bridge.py`，仅监听127.0.0.1:8210，不公开暴露图像接口，不上传第三方。
3. 新 iOS 工程运行模拟器，进入原“实况”页；原默认 esp32-led.local:81 在 Core 中映射本机桥，无需改界面。真机不能访问电脑127.0.0.1；远程4G/HTTPS服务未部署。
4. 对准真实场景，移动镜头，确认画面随之变化并连续采集至少30秒；记录帧数增量、耗时、JPEG尺寸和内存。当前尚未收到真实画面，不能标记验收通过。
5. 点击原“停止”，确认不再新增采集请求；断USB后应清掉旧帧并显示原重连提示，不能将冻结画面标为LIVE。

USB 协议：`camera capture <id>` 异步回 `frame <id> <size> <adler32hex>`；`camera chunk <id> <offset>` 回1024字节以内的十六进制片段；`camera close <id>` 释放。单张最大256KiB；请求ID/偏移/长度/完整JPEG标记/Adler32验证，拉取应答后才请求下一块，不一次性灌满串口；图片仅RAM缓存，20秒无拉取自动释放。传感器和编码缓冲采集后立即关闭释放。错误响应不会提前开启MJPEG；停止取消网络循环，已在途采集由超时及RAM清理收尾。

验证：Lua编译；`tools/test_camera.py` 生产Lua模块硬件mock及USB分块/校验；`tools/test_bridge.py` HTTP图像接口鉴权；`tools/test_air_adapter.py` 实际Swift单帧和连续两帧multipart及取消；`tools/test_ios_preservation.py` UI/旧源码保护。均不是实板摄像头验收。
