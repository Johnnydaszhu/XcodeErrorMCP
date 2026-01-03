class XcodeErrorMcp < Formula
  desc "MCP server that runs xcodebuild and returns only build errors (no warnings)"
  homepage "https://github.com/Johnnydaszhu/XcodeErrorMCP"
  license "MIT"

  head "https://github.com/Johnnydaszhu/XcodeErrorMCP.git", branch: "main"

  depends_on macos: :ventura

  def install
    ENV["CLANG_MODULE_CACHE_PATH"] = (buildpath/"clang-module-cache")

    cache = buildpath/"swiftpm-cache"
    config = buildpath/"swiftpm-config"
    security = buildpath/"swiftpm-security"

    system "swift", "build", "-c", "release",
      "--product", "xcode-error-mcp",
      "--cache-path", cache,
      "--config-path", config,
      "--security-path", security,
      "--manifest-cache", "local",
      "--disable-sandbox"

    bin.install ".build/release/xcode-error-mcp"
  end

  test do
    body = '{"jsonrpc":"2.0","id":1,"method":"ping"}'
    input = "Content-Length: #{body.bytesize}\r\n\r\n#{body}"
    output = pipe_output("#{bin}/xcode-error-mcp", input, 0)
    assert_match "\"ok\":true", output
  end
end

