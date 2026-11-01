# ZhanFX · 斩字处决反馈

《影之刃零》UE4SS Lua MOD。普通小怪成对战斗处决确认致死后，显示原版“斩”字 UI，保留原版音效和退出周期。

版本：**0.1.0**

## 使用

- 每次启动游戏默认关闭，进入可操作场景后按 **Alt+F8** 开启，再按一次关闭。
- 开关提示约 2.5 秒后消失，不占用游戏输入。
- 读档保留本次运行的开关选择，重启游戏恢复默认关闭。
- 仅支持已覆盖的成对战斗处决；普通攻击不触发。轻处决、潜行和空中类别默认关闭，煞气武器与抓取路径不支持。
- 不改变伤害、死亡规则或处决动画。

## 安装

适用游戏：Steam Build `26266538` / `CL-301524_JKS-17219`。

1. 退出游戏，安装 Nexus 上的 [OFFICIAL UE4SS for PBZ](https://www.nexusmods.com/phantombladezero/mods/13)，使用 `3.0.1-1188-gf885e8d2` 及对应的 PBZ 配置。将其解压到游戏的 `platform/steam/`，与大型 `PBZ.exe` 同目录。
2. 下载 ZhanFX ZIP，将其中的 `ZhanFX` 文件夹解压到 `platform/steam/ue4ss/Mods/`。
3. 保留 `ZhanFX/enabled.txt`，无需修改共享 `mods.txt`。

安装后的目录：

```text
<游戏根目录>/platform/steam/
├─ PBZ.exe
├─ dwmapi.dll
└─ ue4ss/
   └─ Mods/
      └─ ZhanFX/
         ├─ enabled.txt
         └─ Scripts/
            ├─ main.lua
            ├─ config.lua
            └─ zhanfx/
```

## 语言配置

开关提示默认跟随游戏文字语言，读取失败或语言不受支持时回退英语。原版“斩”字特效和开发日志不翻译。

修改 `ZhanFX/Scripts/config.lua` 中的 `Language` 可以手动指定语言；修改后重启游戏。

| 配置值 | 语言 |
| --- | --- |
| `auto` | 跟随游戏（默认） |
| `en` | 英语 |
| `zh-Hans` / `zh-Hant` | 简体中文 / 繁体中文 |
| `fr` / `de` | 法语 / 德语 |
| `es-ES` / `es-419` | 西班牙语（西班牙 / 拉丁美洲） |
| `ru` / `ja` | 俄语 / 日语 |
| `pt-BR` / `pt-PT` | 葡萄牙语（巴西 / 葡萄牙） |
| `ko` / `it` | 韩语 / 意大利语 |
| `th` / `vi` | 泰语 / 越南语 |

## 停用、更新与卸载

- **临时关闭**：在游戏中按 Alt+F8。
- **持久停用**：退出游戏，移走 `ZhanFX/enabled.txt`；如果手动添加过 `mods.txt` 条目，也需关闭该条目。保留 enabled.txt 时，单独设置 `mods.txt : 0` 不能停用。
- **更新**：退出游戏，把修改过的 `config.lua` 备份到 MOD 目录外，删除旧 `ZhanFX` 文件夹后解压新版，再按需合并配置。
- **卸载**：退出游戏，只删除 `Mods/ZhanFX`；如果手动添加过加载条目，也将其移除。保留 UE4SS 和其他 MOD。

## 开发与构建

需要 Python 3.10+。在仓库根目录运行：

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
.\.venv\Scripts\python.exe tests/run_tests.py
.\.venv\Scripts\python.exe scripts/build.py
```

输出位于 `dist/`：`ZhanFX-0.1.0-manual.zip`、对应 SHA-256 和测试报告。源码或打包输入变化后需重新运行测试。玩家无需安装 Python。

`ZhanFX/Scripts/zhanfx/` 包含处决判定、游戏反射适配、UI 展示、提示、语言和运行时模块；`tests/` 为 Lua 与打包测试，`scripts/` 为构建工具。构建产物和开发环境不入库。

项目采用 [MIT 许可](LICENSE)。第三方组件及游戏资源的权利归属见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
