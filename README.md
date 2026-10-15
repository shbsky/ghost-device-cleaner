# Ghost Device Cleaner（幽灵设备一键清理）

一个用于 Windows 的**幽灵设备（Phantom Device）批量清理**小工具，单脚本、免安装。

## 这是什么

设备（尤其是 USB 串口设备、USB 音频设备）反复插拔后，Windows 会永久保留每次的旧设备记录。
设备管理器「查看 → 显示隐藏的设备」里那些灰色的条目就是它们：

- **幽灵 COM 口越积越多**：USB Serial Port、USB 串行设备 从 COM10 一路涨到 COM128+
- **幽灵音频设备堆积**：iLoud Micro Monitor、Ruark 等USB 音箱反复插拔后残留几十个
- 换测新产品后 COM 号越来越大、驱动列表越来越乱

本工具扫描并**只删除"当前未接入"的幽灵设备**，正在使用的设备永远不会被动到。

## 适用场景

- 音响/电子产品测试治具电脑（频繁插拔 USB 串口、USB 音频）
- 频繁插 U 盘、手机、USB 转串口（FTDI / CH340 / CP210x 等）的机器
- 任何想让 COM 号"归零重排"的场合

## 安全原则

1. **只删未接入设备**：通过 `Present = false` 判定，正在线上的治具/外设绝不会被删除
2. **只碰 USB 系总线**：仅处理 `USB\`、`FTDIBUS\`（FTDI 串口）、`SWD\MMDEVAPI\`（音频端点）开头的实例
3. **系统虚拟设备白名单外不碰**：RAS 适配器、远程桌面键鼠、虚拟 DVD、VHD、卷影副本等一律不动
4. **先列清单再确认**：删除前展示完整清单，输入 `Y` 才执行

## 使用方法

### 方式一：一键运行（推荐）

1. 把 `一键清理幽灵设备.bat` 和 `Clean-GhostDevices.ps1` 放在**同一文件夹**
2. 双击 `一键清理幽灵设备.bat`（会自动弹出 UAC 提权）
3. 查看扫描清单 → 输入 `Y` 回车 → 等待跑完

### 方式二：手动命令行

```powershell
# 只扫描、不删除（预览模式）
powershell -ExecutionPolicy Bypass -File .\Clean-GhostDevices.ps1

# 扫描并清理
powershell -NoProfile -ExecutionPolicy Bypass -File .\Clean-GhostDevices.ps1 -Clean
```

## 系统要求

- Windows 10 2004 或更高（依赖 `pnputil /remove-device`；仅作后备引擎）
- **管理员权限**（删除设备必需）

## 清理引擎说明

- **快速引擎**：SetupAPI 进程内移除（`SetupDiCallClassInstaller` / `DIF_REMOVE`），比逐台调用 pnputil 快 50~100 倍
- **后备引擎**：快速引擎对个别设备失败时，自动逐台退回 `pnputil /remove-device` 重试
- 失败的设备会实时列出并显示 Win32 错误信息

## 常见问题

**Q: `SWD\MMDEVAPI`（扬声器）删不掉？**
音频端点幽灵比较顽固，删除失败属正常，属无害残留，重启一次电脑通常会自动清掉。

**Q: 清理后 COM 号会变回 COM3、COM4 吗？**
会。重新插入设备后 Windows 会从最小的可用编号重新分配。

**Q: 会不会删掉正在测试的产品？**
不会。引擎只处理「当前未接入」的设备，插着的设备完全不受影响。

## 文件说明

| 文件 | 作用 |
|---|---|
| `一键清理幽灵设备.bat` | 一键入口：自动提权 → 扫描 → 确认 → 清理 |
| `Clean-GhostDevices.ps1` | 核心逻辑，可单独以「预览模式」运行 |
