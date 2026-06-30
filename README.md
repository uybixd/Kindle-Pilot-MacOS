# Kindle Pilot macOS 使用说明

Kindle Pilot 是一个 macOS Kindle 辅助工具。它可以通过 SSH 控制已越狱 Kindle 翻页、传书、同步摘抄和原生生词本；也支持从本地导入 `My Clippings.txt` 和 `vocab.db`，未越狱 Kindle 也能用来整理笔记和生词。

## 开源许可

本项目使用 GNU General Public License v3.0 only（GPL-3.0-only）开源。你可以自由使用、修改和分发代码；如果分发修改版或基于本项目的衍生作品，也需要按 GPLv3 的要求开放相应源代码。软件按现状提供，不承诺任何担保。

## 安装

推荐使用 DMG 安装包：

1. 打开 `Kindle_Pilot-0.0.1.dmg`。
2. 将 `Kindle Pilot.app` 拖到 `Applications`。
3. 从“应用程序”或 Spotlight 打开 `Kindle Pilot`。

如果 macOS 提示无法验证开发者，在“系统设置 -> 隐私与安全性”里允许打开，或右键点击 app 后选择“打开”。

## 使用说明

1. 所有需要通过 SSH 连接 Kindle 的操作，都需要 Kindle 保持点亮。若 Kindle 锁屏、息屏或进入休眠，连接可能失败、中断，或导致操作没有响应。

## 连接 Kindle

已越狱 Kindle 可以使用完整功能。先在 Kindle 上确认 SSH 可用，然后在 app 设置里填写：

- IP：Kindle 的局域网 IP，例如 `192.168.31.204`
- 用户名：通常是 `root`
- 密码：你的 Kindle SSH 密码，默认是kindle

填好后点击“保存”，再点击“测试连接”。

## 远程翻页

远程翻页需要 Kindle 已越狱，并且可以通过 SSH 写入触控事件。

推荐流程：

1. 在“远程”页面点击“测试连接”。
2. 点击“自动检测”，让 app 查找触控设备。
3. 点击“检查命令”。
4. 如果提示缺少翻页命令，分别录制竖屏/横屏的上一页和下一页。
5. 录制完成后即可使用上一页、下一页按钮，或启用键盘翻页。

录制时请按提示在 Kindle 上完成对应翻页动作。

## 传书

传书功能需要 Kindle 已越狱并可 SSH 连接。

1. 打开“传书”页面。
2. 选择 `.azw3`、`.mobi`、`.epub` 或 `.pdf` 文件。
3. app 会检查 Kindle `/mnt/us/documents` 下是否已有同名书籍。
4. 确认后上传。

## 同步摘抄

已越狱 Kindle 可以直接同步：

1. 打开“摘抄整理”页面。
2. 点击“获取 -> 从 Kindle 同步”。
3. app 会下载 Kindle 上的 `/mnt/us/documents/My Clippings.txt` 并解析。

解析后可以按书籍浏览标注、笔记和书签，也可以导出为 Markdown、CSV 或 TXT。

## 本地导入摘抄

未越狱 Kindle 可以先把文件复制到 Mac，再导入：

1. 用 USB 连接 Kindle。
2. 从 Kindle 的 `documents` 目录复制 `My Clippings.txt` 到 Mac。
3. 打开 app 的“摘抄整理”页面。
4. 点击“获取 -> 导入 My Clippings.txt”。
5. 选择刚复制出来的 `My Clippings.txt`。

导入后 app 会把文件复制到自己的缓存目录，再进行解析。以后可以点击“重新解析缓存”重新读取。

## 同步生词本

已越狱 Kindle 可以直接同步原生生词本：

1. 打开“生词本”页面。
2. 点击“获取 -> 从 Kindle 同步生词本”。
3. app 会下载 Kindle 上的 `/mnt/us/system/vocabulary/vocab.db` 并解析。

生词本会过滤中文词条，并结合摘抄中的单词候选标记重点词。

## 本地导入生词本

未越狱 Kindle 可以先把文件复制到 Mac，再导入：

1. 用 USB 连接 Kindle。
2. 尝试找到并复制 `system/vocabulary/vocab.db` 到 Mac。
3. 打开 app 的“生词本”页面。
4. 点击“获取 -> 导入 vocab.db”。
5. 选择刚复制出来的 `vocab.db`。

注意：不同 Kindle 型号和系统版本对 USB 文件暴露范围不同。老款 Kindle 通常更容易直接看到 `system/vocabulary/vocab.db`；较新的 MTP 设备可能需要 Amazon USB File Manager、OpenMTP 等工具，甚至可能看不到这个文件。

## 常见问题

### 未越狱 Kindle 能用哪些功能

可以使用：

- 本地导入 `My Clippings.txt`
- 本地导入 `vocab.db`，前提是能从 Kindle 复制出来
- 摘抄浏览和导出
- 生词本浏览和导出

不能使用：

- SSH 远程翻页
- 触控事件录制
- SSH 传书
- 从 Kindle 直接同步文件

这些功能都需要越狱后具备 SSH 和系统文件访问能力。
