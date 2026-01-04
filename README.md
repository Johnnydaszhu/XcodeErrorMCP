# XcodeErrorMCP

一个轻量的 Model Context Protocol（MCP）服务器：运行 `xcodebuild`，并只返回 **build errors**（不包含 warnings），方便在 AI/自动化流程里快速定位编译失败原因。

## Features（功能）
- 通过 stdio JSON-RPC 提供 MCP 工具：`xcode_build_errors`、`xcode_last_errors`。
- 自动从 `.xcactivitylog` 提取诊断信息；如果找不到日志则回退解析 `xcodebuild` 输出。
- 支持指定/自动发现 `workspace` 或 `project`（当前目录仅有一个时可自动发现）。

## Requirements（环境要求）
- macOS 13+
- Xcode（需要 `/usr/bin/xcodebuild` 可用）
- Swift toolchain（随 Xcode 提供）

## Install（NPM 安装）
> 仅支持 macOS。安装时会通过 `swift build -c release` 从源码编译二进制（需要已安装 Xcode）。

- 全局安装：`npm i -g xcodeerrormcp`
- 验证：`xcodeerrormcp`（或 `xcode-error-mcp`；启动 MCP server，等待 stdin 的 JSON-RPC 消息）
- 如果你看到 `E404 Not Found`（说明该包未发布到 npm），可用下面任意方式安装：
  - 从源码目录：`npm i -g /path/to/XcodeErrorMCP`
  - 从本地 tarball：`npm i -g /path/to/xcodeerrormcp-0.1.0.tgz`（可用 `npm pack` 生成）
  - 从 GitHub：`npm i -g git+https://github.com/Johnnydaszhu/XcodeErrorMCP.git`

## One-shot Prompt（复制给 AI 一次性完成安装/配置）
把下面这一段原样复制给你的 AI（Cursor / Claude / ChatGPT 等），让它按步骤在你的机器上完成安装与 MCP 配置：

```text
你是我的 macOS 终端/配置助手。请帮我安装并配置一个 MCP server：xcodeerrormcp（XcodeErrorMCP）。

要求：
1) 检查环境：macOS 13+、Node.js >= 18、Xcode 可用（/usr/bin/xcodebuild），Swift 可用（swift --version）。
2) 全局安装：npm i -g xcodeerrormcp（不要用 sudo）。
3) 验证命令：xcodeerrormcp 能启动（它会等待 stdin 的 JSON-RPC 消息）。
4) 帮我把 MCP 客户端配置里新增一个 server（配置文件路径请你告诉我，例如 Claude Desktop / Cursor），并插入下面这段配置：

{
  "mcpServers": {
    "xcode-error-mcp": {
      "command": "xcodeerrormcp",
      "args": []
    }
  }
}

5) 给出一个最小可用的示例：如何设置 XCODE_SCHEME（必填）以及可选的 XCODE_WORKSPACE/XCODE_PROJECT、XCODE_DESTINATION、XCODE_DERIVED_DATA_PATH。

遇到报错时：请直接解释原因并给出我可以复制粘贴的修复命令。
```

## MCP Client Config（在客户端里配置）
示例（Claude Desktop / Cursor 等类似配置结构）：

```json
{
  "mcpServers": {
    "xcode-error-mcp": {
      "command": "xcodeerrormcp",
      "args": []
    }
  }
}
```

## Tools（可用工具）
### `xcode_build_errors`
运行 `xcodebuild build` 并返回错误摘要（无 warning）。常用参数：
- `scheme`（必填：参数或环境变量 `XCODE_SCHEME`）
- `workspace` / `project`（二选一；不填时会尝试自动发现）
- `configuration`（默认 `Debug`）
- `destination`、`sdk`、`derivedDataPath`、`resultBundlePath`、`clonedSourcePackagesDirPath`
- `extraArgs`（`xcodebuild` 额外参数数组，追加在 `build` action 前）
- `workingDirectory`（用于自动发现工程/相对路径）
- `codeSigningAllowed`（默认 `false`，会设置 `CODE_SIGNING_ALLOWED=NO`）

也支持通过环境变量传参（参数优先生效），常用：`XCODE_SCHEME`、`XCODE_WORKSPACE`/`XCODE_PROJECT`、`XCODE_DESTINATION`、`XCODE_DERIVED_DATA_PATH`。

### `xcode_last_errors`
从最新的 `.xcactivitylog` 中提取错误（无 warning）。参数：
- `derivedDataPath`（可选；未提供时默认使用 `~/Library/Developer/Xcode/DerivedData`）
- `sinceSeconds`（可选；只考虑最近 N 秒内修改的日志）

## Security Note（安全提示）
该服务器会执行 `xcodebuild`，而 `xcodebuild` 可能触发项目里的脚本/构建步骤。只在你信任的代码仓库上使用。

## License
MIT
