# typed: false
# frozen_string_literal: true

class MuslCrossClang < Formula
  desc "Linux cross compilers based on clang and musl libc"
  homepage "https://github.com/jthat/musl-cross-make"
  url "https://github.com/jthat/musl-cross-make/archive/refs/tags/v1.1.1.tar.gz"
  sha256 "9437f4a0252a7f4a183664e6bffea0dd4286d6cec1725150e60f2c5b6e4cc7bd"
  head "https://github.com/jthat/musl-cross-make.git", branch: "master"

  LINUX_VER      = "4.19.295"
  LLVM_VER       = "17.0.2"
  MUSL_VER       = "1.2.4"

  OPTION_TARGET_MAP = {
    "x86"       => "i686-linux-musl",
    "x86_64"    => "x86_64-linux-musl",
    "x86_64x32" => "x86_64-linux-muslx32",
    "aarch64"   => "aarch64-linux-musl",
    "arm"       => "arm-linux-musleabi",
    "armhf"     => "arm-linux-musleabihf",
    "mips"      => "mips-linux-musl",
    "mips64"    => "mips64-linux-musl",
    "powerpc"   => "powerpc-linux-musl",
    "powerpc64" => "powerpc64-linux-musl",
    "s390x"     => "s390x-linux-musl",
  }.freeze

  DEFAULT_TARGETS = %w[x86_64].freeze

  OPTION_TARGET_MAP.each do |option, target|
    if DEFAULT_TARGETS.include? option
      option "without-#{option}", "Do not build cross-compilers for #{target}"
    else
      option "with-#{option}", "Build cross-compilers for #{target}"
    end
  end

  keg_only "it conflicts with `musl-cross-gcc`"

  option "with-all-targets", "Build cross-compilers for all targets"

  depends_on "cmake" => :build
  depends_on "make" => :build
  depends_on "ninja" => :build
  depends_on "python@3.11" => :build
  depends_on "swig" => :build

  depends_on :linux
  depends_on "zstd"

  uses_from_macos "libedit"
  uses_from_macos "ncurses"
  uses_from_macos "zlib"

  resource "linux-#{LINUX_VER}.tar.xz" do
    url "https://cdn.kernel.org/pub/linux/kernel/v#{LINUX_VER.sub(/^([^.])\..*$/, '\1')}.x/linux-#{LINUX_VER}.tar.xz"
    sha256 "b732c2e4f08576a9dd5bb14213cead3835acbb101a91aaba3d6ace302fd538ac"
  end

  resource "llvm-project-#{LLVM_VER}.src.tar.xz" do
    url "https://github.com/llvm/llvm-project/releases/download/llvmorg-#{LLVM_VER}/llvm-project-#{LLVM_VER}.src.tar.xz"
    sha256 "351562b14d42fcefcbf00cc1f327680a1062bbbf67a1e1ca6acb64c473b06394"
  end

  resource "musl-#{MUSL_VER}.tar.gz" do
    url "https://www.musl-libc.org/releases/musl-#{MUSL_VER}.tar.gz"
    sha256 "7a35eae33d5372a7c0da1188de798726f68825513b7ae3ebe97aaaa52114f039"
  end

  def install
    targets = []
    OPTION_TARGET_MAP.each do |option, target|
      targets.push target if build.with?(option) || build.with?("all-targets")
    end

    (buildpath/"resources").mkpath
    resources.each do |resource|
      cp resource.fetch, buildpath/"resources"/resource.name
    end

    pkgversion = "Homebrew Clang musl cross #{pkg_version} #{build.used_options*" "}".strip
    bugurl = "https://github.com/jthat/homebrew-musl-cross/issues"

    llvm_config = %W[
      -DPACKAGE_VENDOR=#{pkgversion}
      -DBUG_REPORT_URL=#{bugurl}
    ]

    (buildpath/"config.mak").write <<~EOS
      COMPILER = clang

      SOURCES = #{buildpath/"resources"}
      OUTPUT = #{libexec}

      # Versions
      LINUX_VER = #{LINUX_VER}
      LLVM_VER = #{LLVM_VER}
      MUSL_VER = #{MUSL_VER}

      #{llvm_config.map { |o| "LLVM_CONFIG += '#{o}'\n" }.join}

      TARGETS = #{targets.join(" ")}
    EOS

    make = OS.mac? ? Formula["make"].opt_bin/"gmake" : "make"

    system make, "install"

    bin.install_symlink Dir["#{libexec}/bin/*"]
  end

  TEST_OPTION_MAP = {
    "objdump" => ["-ldSC"],
    "size"    => [],
    "nm"      => [],
    "strip"   => [],
  }.freeze

  test do
    targets = []
    OPTION_TARGET_MAP.each do |option, target|
      targets.push target if build.with?(option) || build.with?("all-targets")
    end

    (testpath/"hello.c").write <<-EOS
      #include <stdio.h>
      int main(void) {
          puts("Hello World!");
          return 0;
      }
    EOS

    (testpath/"hello.cpp").write <<-EOS
      #include <iostream>
      int main(void) {
          std::cout << "Hello World!" << std::endl;
          return 0;
      }
    EOS

    targets.each do |target|
      test_prog = "hello-cc-#{target}"
      system bin/"#{target}-cc", "-O2", "hello.c", "-o", test_prog
      assert_equal 0, $CHILD_STATUS.exitstatus
      assert_predicate testpath/test_prog, :exist?
      TEST_OPTION_MAP.each do |prog, options|
        assert_match((prog == "strip") ? "" : /\S+/,
                     shell_output([bin/"#{target}-#{prog}", *options, test_prog].join(" ")))
      end

      test_prog = "hello-c++-#{target}"
      system bin/"#{target}-c++", "-O2", "hello.cpp", "-o", test_prog
      assert_equal 0, $CHILD_STATUS.exitstatus
      assert_predicate testpath/test_prog, :exist?
      TEST_OPTION_MAP.each do |prog, options|
        assert_match((prog == "strip") ? "" : /\S+/,
                     shell_output([bin/"#{target}-#{prog}", *options, test_prog].join(" ")))
      end
    end
  end
end
