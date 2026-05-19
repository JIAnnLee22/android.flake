{
  description = "Android dev shells (JDK 11/17 profiles, pinned AS + scrcpy, FHS sandbox)";

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

      # jdk.table.xml seed so AS picks up the shell's JDK.
      mkStudioJdkTable = { jdk, name }:
        let
          home = jdk.home;
          label = "nix-${name}";
          jrt = module: ''<root url="jrt://${home}/!/${module}" type="simple" />'';
          javaVersion = lib.versions.major jdk.version;
        in
        pkgs.writeText "as-${name}-jdk.table.xml" ''
          <?xml version="1.0" encoding="UTF-8"?>
          <application>
            <component name="ProjectJdkTable">
              <jdk version="2">
                <name value="${label}" />
                <type value="JavaSDK" />
                <version value="${javaVersion}" />
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
            </component>
          </application>
        '';

      profiles = {
        jdk11 = { jdk = pkgs.jdk11; };
        jdk17 = { jdk = pkgs.jdk17; };
      };

      mkShell = { jdk, name, androidStudio ? defaultAndroidStudio }:
        let
          studioJdkTable = mkStudioJdkTable { inherit jdk name; };
          studioBin = "${androidStudio}/bin/android-studio";
          label = "nix-${name}";
        in
        (pkgs.buildFHSEnv {
          name = "android-shell-${name}";

          targetPkgs = p: with p; [
            jdk
            android-tools
            androidStudio
            scrcpy
            tmux

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

          profile = ''
            export JAVA_HOME=${jdk.home}
            export ANDROID_STUDIO_HOME="$HOME/.android-studio-${name}"
            export ANDROID_STUDIO_PROPERTIES="$ANDROID_STUDIO_HOME/idea.properties"
            : "''${ANDROID_HOME:=$HOME/Android/Sdk}"
            export ANDROID_HOME
            export ANDROID_SDK_ROOT="$ANDROID_HOME"

            mkdir -p "$ANDROID_STUDIO_HOME/config/options" "$ANDROID_STUDIO_HOME/system" "$ANDROID_HOME"

            cat > "$ANDROID_STUDIO_PROPERTIES" <<EOF
            idea.config.path=$ANDROID_STUDIO_HOME/config
            idea.system.path=$ANDROID_STUDIO_HOME/system
            EOF

            cp -f ${studioJdkTable} "$ANDROID_STUDIO_HOME/config/options/jdk.table.xml"

            cat > "$ANDROID_STUDIO_HOME/config/options/android.sdk.path.xml" <<EOF
            <application>
              <component name="AndroidSdkPathStore">
                <option name="androidSdkAbsolutePath" value="$ANDROID_HOME" />
              </component>
            </application>
            EOF

            as() {
              env -u JAVA_HOME \
                STUDIO_PROPERTIES="$ANDROID_STUDIO_PROPERTIES" \
                ANDROID_HOME="$ANDROID_HOME" \
                ANDROID_SDK_ROOT="$ANDROID_HOME" \
                XDG_CACHE_HOME="$ANDROID_STUDIO_HOME/cache" \
                ${studioBin} "$@" \
                >> "$ANDROID_STUDIO_HOME/studio.launch.log" 2>&1 &
              disown
              echo "Android Studio started in background (log: $ANDROID_STUDIO_HOME/studio.launch.log)"
            }
            export -f as

            echo "========================================"
            echo " Android Dev Shell (${name})"
            echo " Shell JDK   : $JAVA_HOME"
            echo " Android SDK : $ANDROID_HOME"
            echo " Studio JDK  : ${label} (pick in Settings -> Gradle JDK)"
            echo " Studio IDE  : ${androidStudio.version} (bundled JBR, FHS sandbox)"
            echo " Studio dir  : $ANDROID_STUDIO_HOME"
            echo " Tools       : adb, scrcpy, tmux"
            echo "========================================"
            echo ""
            echo "  as                     -> Android Studio in background"
            echo "  tmux new -s as-${name}  -> persistent shell (detach: Ctrl-b d)"
            echo "  Override SDK location: ANDROID_HOME=/path/to/sdk nix develop ..."
          '';

          runScript = "bash";
        }).env;

      # Build all shells, optionally with an overridden AS.
      mkShells = { androidStudio ? defaultAndroidStudio }:
        let
          shells = builtins.mapAttrs
            (name: { jdk }: mkShell { inherit jdk name androidStudio; })
            profiles;
        in
        shells // { default = shells.jdk17; };

    in {
      devShells.${system} = mkShells { };

      packages.${system}.android-studio = defaultAndroidStudio;

      lib.${system} = {
        inherit mkAndroidStudio mkShell mkShells;
      };
    };
}
