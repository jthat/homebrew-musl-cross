# typed: false
# frozen_string_literal: true

class MuslCrossGcc < Formula
  desc "Linux cross compilers based on gcc and musl libc"
  homepage "https://github.com/jthat/musl-cross-make"
  url "https://github.com/jthat/musl-cross-make/archive/refs/tags/v1.3.0.tar.gz"
  sha256 "479a3cc22068ceeb09d5168c084eb6449d5e1e33579fcccf55435249170a28fd"
  head "https://github.com/jthat/musl-cross-make.git", branch: "master"

  bottle do
    root_url "https://github.com/jthat/homebrew-musl-cross/releases/download/musl-cross-gcc-1.3.0"
    sha256 cellar: :any, arm64_sequoia: "19354d8dfa27a5f4ff19ecac7cb55fab013f3a7669daaa147d4fad616447e41b"
    sha256 cellar: :any, ventura:       "d39bc6453eb647fad2442df67272efce9c3e8119f8c6109028c4c7071899f1fb"
  end

  LINUX_VER      = "4.19.325"
  GCC_VER        = "15.1.0"
  BINUTILS_VER   = "2.44"
  MUSL_VER       = "1.2.5"
  CONFIG_SUB_REV = "00b159274960"

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

  keg_only "it conflicts with `musl-cross-clang`"

  option "with-all-targets", "Build cross-compilers for all targets"

  depends_on "bison"   => :build
  depends_on "gnu-sed" => :build
  depends_on "make"    => :build

  depends_on "gmp"
  depends_on "isl"
  depends_on "libmpc"
  depends_on "mpfr"
  depends_on "zstd"

  uses_from_macos "flex" => :build
  uses_from_macos "zlib"

  resource "linux-#{LINUX_VER}.tar.xz" do
    url "https://cdn.kernel.org/pub/linux/kernel/v#{LINUX_VER.sub(/^([^.])\..*$/, '\1')}.x/linux-#{LINUX_VER}.tar.xz"
    sha256 "607bed7de5cda31a443df4c8a78dbe5e8a9ad31afde2a4d28fe99ab4730e8de1"
  end

  resource "gcc-#{GCC_VER}.tar.xz" do
    url "https://ftp.gnu.org/gnu/gcc/gcc-#{GCC_VER}/gcc-#{GCC_VER}.tar.xz"
    sha256 "e2b09ec21660f01fecffb715e0120265216943f038d0e48a9868713e54f06cea"
  end

  resource "binutils-#{BINUTILS_VER}.tar.xz" do
    url "https://ftp.gnu.org/gnu/binutils/binutils-#{BINUTILS_VER}.tar.xz"
    sha256 "ce2017e059d63e67ddb9240e9d4ec49c2893605035cd60e92ad53177f4377237"
  end

  resource "musl-#{MUSL_VER}.tar.gz" do
    url "https://www.musl-libc.org/releases/musl-#{MUSL_VER}.tar.gz"
    sha256 "a9a118bbe84d8764da0ea0d28b3ab3fae8477fc7e4085d90102b8596fc7c75e4"
  end

  resource "config.sub" do
    url "https://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.sub;hb=#{CONFIG_SUB_REV}"
    sha256 "11c54f55c3ac99e5d2c3dc2bb0bcccbf69f8223cc68f6b2438daa806cf0d16d8"
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

    languages = %w[c c++]

    pkgversion = "Homebrew GCC musl cross #{pkg_version} #{build.used_options*" "}".strip
    bugurl = "https://github.com/jthat/homebrew-musl-cross/issues"

    common_config = %W[
      --disable-nls
      --enable-checking=release
      --enable-languages=#{languages.join(",")}
      --with-gmp=#{Formula["gmp"].opt_prefix}
      --with-mpfr=#{Formula["mpfr"].opt_prefix}
      --with-mpc=#{Formula["libmpc"].opt_prefix}
      --with-isl=#{Formula["isl"].opt_prefix}
      --with-zstd=#{Formula["zstd"].opt_prefix}
      --with-system-zlib
      --with-pkgversion=#{pkgversion}
      --with-bugurl=#{bugurl}
      --with-debug-prefix-map=#{buildpath}=
    ]

    gcc_config = %w[
      --disable-libquadmath
      --disable-decimal-float
      --disable-libitm
      --disable-fixed-point
    ]

    (buildpath/"config.mak").write <<~EOS
      SOURCES = #{buildpath/"resources"}
      OUTPUT = #{libexec}

      # Versions
      LINUX_VER = #{LINUX_VER}
      BINUTILS_VER = #{BINUTILS_VER}
      GCC_VER  = #{GCC_VER}
      MUSL_VER = #{MUSL_VER}
      CONFIG_SUB_REV = #{CONFIG_SUB_REV}

      # Use libs from Homebrew
      GMP_VER  =
      MPC_VER  =
      MPFR_VER =
      ISL_VER  =

      # https://llvm.org/bugs/show_bug.cgi?id=19650
      # https://github.com/richfelker/musl-cross-make/issues/11
      ifeq ($(shell $(CXX) -v 2>&1 | grep -c "clang"), 1)
      TOOLCHAIN_CONFIG += CXX="$(CXX) -fbracket-depth=512"
      endif

      #{common_config.map { |o| "COMMON_CONFIG += #{o}\n" }.join}
      #{gcc_config.map { |o| "GCC_CONFIG += #{o}\n" }.join}
    EOS

    if OS.mac?
      ENV.prepend_path "PATH", "#{Formula["gnu-sed"].opt_libexec}/gnubin"
      make = Formula["make"].opt_bin/"gmake"
    else
      make = "make"

      # Linux build fails because gprofng finds Java SDK
      # https://github.com/jthat/homebrew-musl-cross/issues/6
      begin
        # Cause binutils gprofng to find a fake jdk, and thus disable Java profiling support
        fakejdk_bin = buildpath/"fakejdk/bin"
        fakejdk_bin.mkpath
        %w[javac java].each do |b|
          (fakejdk_bin/b).write <<~EOS
            #!/bin/sh
            exit 1
          EOS
          chmod "+x", fakejdk_bin/b
        end
        ENV.prepend_path "PATH", fakejdk_bin
      end

    end
    targets.each do |target|
      system make, "install", "TARGET=#{target}"
    end

    bin.install_symlink Dir["#{libexec}/bin/*"]
  end

  TEST_OPTION_MAP = {
    "readelf" => ["-a"],
    "objdump" => ["-ldSC"],
    "strings" => [],
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
      assert_path_exists testpath/test_prog
      TEST_OPTION_MAP.each do |prog, options|
        assert_match((prog == "strip") ? "" : /\S+/,
                     shell_output([bin/"#{target}-#{prog}", *options, test_prog].join(" ")))
      end

      test_prog = "hello-c++-#{target}"
      system bin/"#{target}-c++", "-O2", "hello.cpp", "-o", test_prog
      assert_equal 0, $CHILD_STATUS.exitstatus
      assert_path_exists testpath/test_prog
      TEST_OPTION_MAP.each do |prog, options|
        assert_match((prog == "strip") ? "" : /\S+/,
                     shell_output([bin/"#{target}-#{prog}", *options, test_prog].join(" ")))
      end
    end
  end
end
