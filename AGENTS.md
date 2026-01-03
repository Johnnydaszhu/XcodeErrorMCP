# Repository Guidelines

## Project Structure & Module Organization
- `Package.swift`: SwiftPM manifest (macOS 13+), builds the `xcode-error-mcp` executable.
- `Sources/XcodeErrorMCP/`: implementation of the MCP stdio JSON-RPC server and tools.
  - `XcodeErrorMCPMain.swift`: request routing + tool catalog (`xcode_build_errors`, `xcode_last_errors`).
  - `XCActivityLogErrorExtractor.swift`: extracts error diagnostics from `.xcactivitylog`.
  - `DerivedDataLogFinder.swift`: finds the most recent build log under DerivedData.
- `.build/` and `DerivedData/`: local artifacts (ignored by `.gitignore`); do not commit.

## Build, Test, and Development Commands
- `swift build`: build the executable in debug.
- `swift build -c release`: optimized build (useful for distribution/perf checks).
- `swift run xcode-error-mcp`: launch the server (it waits for JSON-RPC messages on stdin).
- `XCODE_ERROR_MCP_DEBUG=1 swift run xcode-error-mcp`: enable verbose request/response logging to stderr.
- `swift test`: run tests (there is no `Tests/` target yet; keep this passing if/when added).
- `npm run build`: build the release binary used by the npm wrapper (`bin/xcode-error-mcp`).
- `npm pack`: create a publishable tarball for the npm package.

## Configuration & Environment
- Tool args take precedence over env vars; most common env vars are `XCODE_WORKSPACE`/`XCODE_PROJECT`, required `XCODE_SCHEME`, and optional `XCODE_DESTINATION`, `XCODE_SDK`, `XCODE_DERIVED_DATA_PATH`.

## Coding Style & Naming Conventions
- Indentation: 4 spaces, no tabs; keep lines readable and prefer early exits.
- Naming: Swift API Design Guidelines (types `UpperCamelCase`, members `lowerCamelCase`).
- Formatting/linting: no tool is enforced; keep diffs tidy and use Xcode’s formatter if needed.
- When adding/changing a tool:
  - Update `ToolCatalog.tools` (name, description, JSON schema).
  - Update `XcodeErrorMCPHandler.handleToolsCall` to route the tool name.

## Testing Guidelines
- If you add tests, use XCTest under `Tests/XcodeErrorMCPTests/` with files named `*Tests.swift`.
- Focus coverage on log parsing edge cases and error normalization/deduping.

## Commit & Pull Request Guidelines
- Git history is minimal; use short, imperative commit summaries (e.g., “Fix xcactivitylog parsing”).
- PRs should include: what changed, how you validated (`swift build`), and example tool output when behavior changes.

## Agent-Specific Notes
- After code changes, call the MCP tool `xcode_build_errors`; if errors are returned, fix and repeat until it returns none.
