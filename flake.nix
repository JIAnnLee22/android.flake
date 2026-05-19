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

      androidStudio = import ./android-studio.nix {
        inherit pkgs;
        nixpkgsSrc = nixpkgs;
      };

      studioBin = "${androidStudio}/bin/android-studio";

      jdkHome = jdk:
        if builtins.hasAttr "home" jdk then jdk.home else "${jdk}";

      profiles = {
        jdk11 = { jdk = pkgs.jdk11; };
        jdk17 = { jdk = pkgs.jdk17; };
      };

      mkShell = { jdk, name }:
        pkgs.mkShell {
          packages = [
            jdk
            pkgs.android-tools
            androidStudio
            pkgs.scrcpy
          ];

          JAVA_HOME = jdkHome jdk;

          shellHook = ''
            export ANDROID_STUDIO_HOME="$HOME/.android-studio-${name}"
            export ANDROID_STUDIO_PROPERTIES="$ANDROID_STUDIO_HOME/idea.properties"

            mkdir -p \
              "$ANDROID_STUDIO_HOME/config/plugins" \
              "$ANDROID_STUDIO_HOME/system/log" \
              "$ANDROID_STUDIO_HOME/cache"

            # JetBrains isolation: config/system/lock/port must not be shared between instances.
            # XDG_* alone is not enough; studio.sh still uses default paths for locks/caches.
            cat > "$ANDROID_STUDIO_PROPERTIES" <<EOF
idea.config.path=$ANDROID_STUDIO_HOME/config
idea.system.path=$ANDROID_STUDIO_HOME/system
idea.plugins.path=$ANDROID_STUDIO_HOME/config/plugins
idea.log.path=$ANDROID_STUDIO_HOME/system/log
EOF

            as() {
              env -u JAVA_HOME -u STUDIO_JDK \
                STUDIO_PROPERTIES="$ANDROID_STUDIO_PROPERTIES" \
                XDG_CACHE_HOME="$ANDROID_STUDIO_HOME/cache" \
                ${studioBin} "$@"
            }

            export -f as

            echo "========================================"
            echo " Android Dev Shell (${name})"
            echo " Project JDK : ${jdk.pname or jdk.name} ($JAVA_HOME)"
            echo " Studio      : ${androidStudio.version} (bundled JBR)"
            echo " Studio cfg  : $ANDROID_STUDIO_HOME/config"
            echo " Studio sys  : $ANDROID_STUDIO_HOME/system"
            echo " Tools       : adb, scrcpy"
            echo "========================================"
            echo ""
            echo "  as  -> Android Studio (isolated; can run jdk11 + jdk17 at once)"
            echo "  Tip : open one shell per profile, run 'as' in each terminal"
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
