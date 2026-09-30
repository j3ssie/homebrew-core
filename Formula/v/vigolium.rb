class Vigolium < Formula
  desc "Web vulnerability scanner with native and AI scanning engines"
  homepage "https://vigolium.com/"
  url "https://github.com/vigolium/vigolium/archive/refs/tags/v0.5.1.tar.gz"
  sha256 "be0eb6ab5c5826902b96fdf03c1a47ec69e6159bb17957edaf39635fb84cbde3"
  license "MIT"
  head "https://github.com/vigolium/vigolium.git", branch: "main"

  depends_on "bun" => :build
  depends_on "go" => :build

  on_linux do
    depends_on "icu4c@78"
  end

  deny_network_access! :test

  def install
    ENV["CGO_ENABLED"] = "0"
    ENV["BUN_INSTALL_CACHE_DIR"] = buildpath/"bun-cache"
    ENV["VIGOLIUM_AUDIT_BUILD_NO_INSTALL"] = "1"

    cd "platform/jstangle" do
      system "bun", "install", "--frozen-lockfile", "--linker", "isolated", "--ignore-scripts"
    end
    system "make", "build-jstangle-current"

    cd "platform/vigolium-audit" do
      system "bun", "install", "--frozen-lockfile"
      system "bun", "run", "build"
    end
    os = OS.mac? ? "darwin" : "linux"
    arch = Hardware::CPU.arm? ? "arm64" : "x64"
    (buildpath/"pkg/audit/bin/_bin").install \
      "platform/vigolium-audit/build/dist/vigolium-audit-#{os}-#{arch}" => "vigolium-audit"

    system "make", "build", "VERSION=#{version}", "GOPATH_BIN=#{buildpath}/gobin"
    libexec.install "bin/vigolium"
    (bin/"vigolium").write_env_script libexec/"vigolium", VIGOLIUM_DISABLE_UPDATE_CHECK: "1"
    generate_completions_from_executable(bin/"vigolium", "completion")
  end

  service do
    run [opt_bin/"vigolium", "server", "--host", "127.0.0.1"]
    keep_alive true
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/vigolium version")

    database = testpath/"test.sqlite"
    projects = JSON.parse(shell_output("#{bin}/vigolium --db #{database} project list --json"))
    assert_equal "Default Project", projects.first.fetch("name")
    assert_path_exists database

    stats = JSON.parse(shell_output("#{bin}/vigolium --db #{database} db stats --json"))
    assert_equal "sqlite", stats.fetch("items").fetch("database").fetch("driver")
    assert_equal 0, stats.fetch("items").fetch("records").fetch("http_records")
  end
end
