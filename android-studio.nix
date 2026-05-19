# Pinned Android Studio (IDE only, no bundled SDK/NDK).
# Override `version` / `sha256Hash` / `url` to switch versions.
{ pkgs
, nixpkgsSrc
, version ? "2025.2.3.9"
, sha256Hash ? "sha256-mG6myss22nI/LIVQzM19jNPouLe7JEbTqL85u6+Rq8E="
, url ? "https://edgedl.me.gvt1.com/android/studio/ide-zips/${version}/android-studio-${version}-linux.tar.gz"
}:

pkgs.callPackage
  (import "${nixpkgsSrc}/pkgs/applications/editors/android-studio/common.nix" {
    channel = "stable";
    pname = "android-studio";
    inherit version sha256Hash url;
  })
  {
    fontsConf = pkgs.makeFontsConf { fontDirectories = [ ]; };
    tiling_wm = false;
  }
