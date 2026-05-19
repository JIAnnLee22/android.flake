# Pinned Android Studio 2025.2.3.9 (IDE only, no bundled SDK/NDK).
{ pkgs, nixpkgsSrc }:

pkgs.callPackage
  (import "${nixpkgsSrc}/pkgs/applications/editors/android-studio/common.nix" {
    channel = "stable";
    pname = "android-studio";
    version = "2025.2.3.9";
    sha256Hash = "sha256-mG6myss22nI/LIVQzM19jNPouLe7JEbTqL85u6+Rq8E=";
    url = "https://edgedl.me.gvt1.com/android/studio/ide-zips/2025.2.3.9/android-studio-2025.2.3.9-linux.tar.gz";
  })
  {
    fontsConf = pkgs.makeFontsConf { fontDirectories = [ ]; };
    tiling_wm = false;
  }
