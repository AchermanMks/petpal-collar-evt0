# libs — 随脚本一起烧录的 LuatOS 扩展库

`gnss_app.lua` 依赖 `exgnss`，它是脚本层扩展库，Air780EGH V2030 底层固件不内置；`exgnss` 内部又 `require("lbsLoc2")`。2026-09-09 Windows 烧录时 Luatools 报「合并失败: 缺少 exgnss.lua」，即因交接包漏了这两个文件。

| 文件 | 来源 | 上游最后修改 |
|---|---|---|
| `exgnss.lua` | https://raw.githubusercontent.com/openLuat/LuatOS/master/script/libs/exgnss.lua | commit `c14415f`，2026-07-05 |
| `lbsLoc2.lua` | https://raw.githubusercontent.com/openLuat/LuatOS/master/script/libs/lbsLoc2.lua | commit `80e19bd`，2026-07-30 |

拉取日期 2026-09-10，MIT License，不要在这里改代码。烧录时把这两个文件与 `../*.lua`、`config.lua` 一起加入 Luatools 项目。
