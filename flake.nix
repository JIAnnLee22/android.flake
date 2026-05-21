{
  description = "Android Studio launcher (FHS sandbox, JDK 11 + JDK 17 both registered)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { nixpkgs, ... }:
    let
      system = "x86_64-linux";

      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };

      lib = pkgs.lib;

      # Build a (possibly overridden) Android Studio.
      # Consumers: `lib.mkAndroidStudio { version = "..."; sha256Hash = "..."; }`
      mkAndroidStudio = args:
        import ./android-studio.nix ({
          inherit pkgs;
          nixpkgsSrc = nixpkgs;
        } // args);

      defaultAndroidStudio = mkAndroidStudio { };

      jdkLabel = jdk: "nix-jdk${lib.versions.major jdk.version}";

      # jdk.table.xml seed registering all provided JDKs as
      # `nix-jdk11`, `nix-jdk17`, ... so the user can pick either one
      # in Settings -> Build Tools -> Gradle -> Gradle JDK.
      mkStudioJdkTable = { jdks }:
        let
          jdkEntry = jdk:
            let
              home = jdk.home;
              major = lib.versions.major jdk.version;
              label = jdkLabel jdk;
              jrt = module: ''<root url="jrt://${home}/!/${module}" type="simple" />'';
            in
            ''
              <jdk version="2">
                <name value="${label}" />
                <type value="JavaSDK" />
                <version value="${major}" />
                <homePath value="${home}" />
                <roots>
                  <annotationsPath>
                    <root type="composite" />
                  </annotationsPath>
                  <classPath>
                    <root type="composite">
                      ${jrt "java.base"}
                      ${jrt "java.compiler"}
                      ${jrt "java.desktop"}
                    </root>
                  </classPath>
                  <javadocPath>
                    <root type="composite" />
                  </javadocPath>
                  <sourcePath>
                    <root type="composite" />
                  </sourcePath>
                </roots>
              </jdk>
            '';
        in
        pkgs.writeText "as-jdk.table.xml" ''
          <?xml version="1.0" encoding="UTF-8"?>
          <application>
            <component name="ProjectJdkTable">
              ${lib.concatMapStrings jdkEntry jdks}
            </component>
          </application>
        '';

      mkLauncher =
        { name ? "as"
        , defaultJdk ? pkgs.jdk17
        , extraJdks ? [ pkgs.jdk11 ]
        , androidStudio ? defaultAndroidStudio
        }:
        let
          allJdks = [ defaultJdk ] ++ extraJdks;
          studioJdkTable = mkStudioJdkTable { jdks = allJdks; };
          studioBin = "${androidStudio}/bin/android-studio";

          allLabels = lib.concatMapStringsSep ", " jdkLabel allJdks;
          defaultLabel = jdkLabel defaultJdk;

          # AS 内置 Terminal 默认会走 $SHELL，宿主 bash 加载 ~/.bashrc 会把
          # 启动器注入的 PATH / JAVA_HOME / ANDROID_HOME 改没。这里用一个
          # 自定义 rcfile：先 source 用户原本的 ~/.bashrc，再覆盖关键变量，让
          # adb / sdkmanager / gradle 一直可用。
          asTerminalRc = pkgs.writeText "as-terminal-rcfile" ''
            [ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"
            export JAVA_HOME=${defaultJdk.home}
            export ANDROID_HOME="''${ANDROID_HOME:-$HOME/Android/Sdk}"
            export ANDROID_SDK_ROOT="$ANDROID_HOME"
            case ":$PATH:" in
              *:/usr/bin:*) ;;
              *) export PATH="/usr/local/bin:/usr/bin:/bin:$PATH" ;;
            esac
          '';

          asTerminalShell = pkgs.writeShellScript "as-terminal" ''
            exec ${pkgs.bashInteractive}/bin/bash --rcfile ${asTerminalRc} -i "$@"
          '';

          # AS 2025+ 的终端 shellPath 存在 terminal-local.xml 里
          # (TerminalLocalOptions, RoamingType.LOCAL)。
          asTerminalLocalXml = pkgs.writeText "as-terminal-local.xml" ''
            <application>
              <component name="TerminalLocalOptions">
                <option name="shellPath" value="${asTerminalShell}" />
              </component>
            </application>
          '';

          # 旧版 AS 用 terminal.xml + TerminalOptionsProvider/myShellPath；
          # 同时写一份兜底，新版会忽略，旧版能识别。
          asTerminalXml = pkgs.writeText "as-terminal.xml" ''
            <application>
              <component name="TerminalOptionsProvider">
                <option name="myShellPath" value="${asTerminalShell}" />
              </component>
            </application>
          '';

          launchScript = pkgs.writeShellScript "${name}-launch" ''
            set -eu
            export JAVA_HOME=${defaultJdk.home}
            export ANDROID_STUDIO_HOME="$HOME/.android-studio"
            export ANDROID_STUDIO_PROPERTIES="$ANDROID_STUDIO_HOME/idea.properties"
            : "''${ANDROID_HOME:=$HOME/Android/Sdk}"
            export ANDROID_HOME
            export ANDROID_SDK_ROOT="$ANDROID_HOME"

            mkdir -p "$ANDROID_STUDIO_HOME/config/options" \
                     "$ANDROID_STUDIO_HOME/system" \
                     "$ANDROID_HOME"

            cat > "$ANDROID_STUDIO_PROPERTIES" <<EOF
            idea.config.path=$ANDROID_STUDIO_HOME/config
            idea.system.path=$ANDROID_STUDIO_HOME/system
            disable.android.first.run=true
            EOF

            cp -f ${studioJdkTable}     "$ANDROID_STUDIO_HOME/config/options/jdk.table.xml"
            cp -f ${asTerminalLocalXml} "$ANDROID_STUDIO_HOME/config/options/terminal-local.xml"
            cp -f ${asTerminalXml}      "$ANDROID_STUDIO_HOME/config/options/terminal.xml"

            cat > "$ANDROID_STUDIO_HOME/config/options/android.sdk.path.xml" <<EOF
            <application>
              <component name="AndroidSdkPathStore">
                <option name="androidSdkAbsolutePath" value="$ANDROID_HOME" />
              </component>
            </application>
            EOF

            echo "Launching Android Studio"
            echo "  Default JDK : $JAVA_HOME (${defaultLabel})"
            echo "  IDE JDKs    : ${allLabels} (Settings -> Gradle JDK)"
            echo "  Studio IDE  : ${androidStudio.version}"
            echo "  Studio dir  : $ANDROID_STUDIO_HOME"
            echo "  Android SDK : $ANDROID_HOME"

            exec env -u JAVA_HOME \
              STUDIO_PROPERTIES="$ANDROID_STUDIO_PROPERTIES" \
              ANDROID_HOME="$ANDROID_HOME" \
              ANDROID_SDK_ROOT="$ANDROID_HOME" \
              XDG_CACHE_HOME="$ANDROID_STUDIO_HOME/cache" \
              ${studioBin} "$@"
          '';

          fhsEnv = pkgs.buildFHSEnv {
            inherit name;

            # 只把 defaultJdk 放进 FHS 的 /usr，避免 jdk11/jdk17 的
            # `bin/javac` 互相覆盖。其他 JDK 通过绝对 store 路径写进
            # jdk.table.xml，IDE 直接按路径读，照样能用。
            targetPkgs = p: with p; [
              # 完整版 bash（带 readline / progcomp），覆盖 FHS 默认的 bash-minimal，
              # 否则 AS 内置 Terminal 加载 ~/.bashrc 时 `shopt -s progcomp` / `bind`
              # / PS1 转义会全部出错。
              bashInteractive
              bash-completion

              defaultJdk
              android-tools
              androidStudio

              # AAPT2 / sdkmanager / 命令行工具的基础库
              zlib
              stdenv.cc.cc.lib
              ncurses5
              bzip2
              libxml2
              openssl

              # 需要 emulator / layoutlib 预览时再打开这些：
              # libpulseaudio alsa-lib libGL fontconfig freetype
              # xorg.libX11 xorg.libXext xorg.libXrender
              # xorg.libXi xorg.libXrandr xorg.libXcursor xorg.libXtst
              # xorg.libXxf86vm xorg.libxcb
            ];

            runScript = "${launchScript}";
          };

          desktopItem = pkgs.makeDesktopItem {
            inherit name;
            desktopName = "Android Studio";
            genericName = "Android IDE";
            comment = "Android Studio (FHS) with ${allLabels} registered";
            # 用 FHS env 的绝对路径作为 Exec，desktop 文件不依赖
            # `${name}` 被加进 PATH。
            exec = "${fhsEnv}/bin/${name} %U";
            icon = "${androidStudio}/share/pixmaps/android-studio.png";
            categories = [ "Development" "IDE" ];
            startupWMClass = "jetbrains-studio";
            startupNotify = true;
          };
        in
        pkgs.symlinkJoin {
          inherit name;
          paths = [ fhsEnv desktopItem ];
          meta = {
            description = "Android Studio launcher (JDKs: ${allLabels})";
            mainProgram = name;
            platforms = [ system ];
          };
        };

      launcher = mkLauncher { };

      # 命令行环境：FHS 沙箱 + 单一 JDK + android-tools，不带 IDE。
      # 返回的是底层 buildFHSEnv 包本身（含 `bin/<name>` 可执行文件），
      # 既可以装进 systemPackages 直接当命令用，也可以通过 `.env`
      # 暴露成 devShell（`nix develop`）。
      mkAndroidShell = { name, jdk }:
        let
          label = "nix-jdk${lib.versions.major jdk.version}";
        in
        pkgs.buildFHSEnv {
          inherit name;

          targetPkgs = p: with p; [
            bashInteractive
            bash-completion

            jdk
            android-tools

            zlib
            stdenv.cc.cc.lib
            ncurses5
            bzip2
            libxml2
            openssl
          ];

          profile = ''
            export JAVA_HOME=${jdk.home}
            : "''${ANDROID_HOME:=$HOME/Android/Sdk}"
            export ANDROID_HOME
            export ANDROID_SDK_ROOT="$ANDROID_HOME"
            mkdir -p "$ANDROID_HOME"

            echo "========================================"
            echo " ${name} (${label})"
            echo " JAVA_HOME   : $JAVA_HOME"
            echo " ANDROID_HOME: $ANDROID_HOME"
            echo " Tools ready : adb / gradle / aapt2 (FHS sandbox)"
            echo "========================================"
          '';

          runScript = "bash";

          meta = {
            description = "Android CLI shell (${label}) in FHS sandbox";
            mainProgram = name;
            platforms = [ system ];
          };
        };

      shells = {
        androidShell11 = mkAndroidShell { name = "androidShell11"; jdk = pkgs.jdk11; };
        androidShell17 = mkAndroidShell { name = "androidShell17"; jdk = pkgs.jdk17; };
      };

      mkApp = drv: {
        type = "app";
        program = "${drv}/bin/${drv.meta.mainProgram or drv.name}";
      };
    in {
      packages.${system} = {
        as = launcher;
        default = launcher;
        android-studio = defaultAndroidStudio;
      } // shells;

      apps.${system} = {
        as = mkApp launcher;
        default = mkApp launcher;
      } // (lib.mapAttrs (_: mkApp) shells);

      devShells.${system} = (lib.mapAttrs (_: drv: drv.env) shells) // {
        default = shells.androidShell17.env;
      };

      lib.${system} = {
        inherit mkAndroidStudio mkLauncher mkStudioJdkTable mkAndroidShell;
      };
    };
}
