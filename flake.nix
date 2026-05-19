{
  description = "Android dev shells (JDK 11/17 profiles, AS 2025.2.3.9 + scrcpy)";

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

      androidStudio = import ./android-studio.nix {
        inherit pkgs;
        nixpkgsSrc = nixpkgs;
      };

      studioBin = "${androidStudio}/bin/android-studio";

      # Register shell JDK in IDE so Gradle JDK / Project Structure can pick it.
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

      mkShell = { jdk, name }:
        let
          studioJdkTable = mkStudioJdkTable { inherit jdk name; };
          label = "nix-${name}";
        in
        pkgs.mkShell {
          packages = [
            jdk
            pkgs.android-tools
            androidStudio
            pkgs.scrcpy
            pkgs.tmux
          ];

          JAVA_HOME = jdk.home;

          shellHook = ''
            export ANDROID_STUDIO_HOME="$HOME/.android-studio-${name}"
            export ANDROID_STUDIO_PROPERTIES="$ANDROID_STUDIO_HOME/idea.properties"

            mkdir -p "$ANDROID_STUDIO_HOME/config/options" "$ANDROID_STUDIO_HOME/system"

            cat > "$ANDROID_STUDIO_PROPERTIES" <<EOF
idea.config.path=$ANDROID_STUDIO_HOME/config
idea.system.path=$ANDROID_STUDIO_HOME/system
EOF

            cp -f ${studioJdkTable} "$ANDROID_STUDIO_HOME/config/options/jdk.table.xml"

            as() {
              env -u JAVA_HOME \
                STUDIO_PROPERTIES="$ANDROID_STUDIO_PROPERTIES" \
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
            echo " Studio JDK  : ${label} (pick in Settings -> Gradle JDK)"
            echo " Studio IDE  : ${androidStudio.version} (bundled JBR)"
            echo " Studio dir  : $ANDROID_STUDIO_HOME"
            echo " Tools       : adb, scrcpy, tmux"
            echo "========================================"
            echo ""
            echo "  as                     -> Android Studio in background"
            echo "  tmux new -s as-${name}  -> persistent shell (detach: Ctrl-b d)"
          '';
        };

      shells =
        builtins.mapAttrs
          (name: { jdk }: mkShell { inherit jdk name; })
          profiles;

    in {
      devShells.${system} =
        shells // {
          default = shells.jdk17;
        };
    };
}
