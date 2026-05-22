# androidShell

为安卓开发提供的 Nix flake，单一启动入口 `as` 直接拉起 Android Studio。
启动时会把 **JDK 11 与 JDK 17** 同时注册进 IDE 的 JDK 列表（`nix-jdk11` / `nix-jdk17`），
在 Settings 里随时切换；命令行 / Gradle 默认走 JDK 17。

启动器跑在 [`buildFHSEnv`](https://nixos.org/manual/nixpkgs/stable/#sec-fhs-environments)
用户态沙箱里，`/lib64/ld-linux-x86-64.so.2` 等 FHS 路径都存在，所以 Gradle 从 Maven 拉的
`aapt2`、`sdkmanager` 等预编译二进制无需 patchelf 直接能跑。

> **不需要 `nix develop`**：这个 flake 暴露 `apps` + `packages`，可以直接
> `nix run` 启动，也可以装进 `environment.systemPackages` / `home.packages`。
> 装进去后会自动注册 `.desktop`，rofi / wofi / krunner / GNOME Activities
> 等启动器都能搜到 **Android Studio**。
>
> AS 内置 Terminal 已经被注入了正确的 `JAVA_HOME` / `ANDROID_HOME` / `PATH`，命令行
> Gradle / adb 都能直接用。

## 包含

- **Android Studio 2025.2.3.9**（pin 在 `android-studio.nix`，可覆写，详见下文）
- **JDK 11 & JDK 17**（都注册进 IDE，CLI 默认走 JDK 17）
- **android-tools**（`adb`、`fastboot` 等）
- **git + openssh**（IDE / 内置 Terminal 的 VCS 推送；会读取 `~/.ssh/config` 里的 Host 规则）
- **FHS 库**（zlib / libstdc++ / ncurses / openssl 等，足够跑 aapt2、sdkmanager）

> **SSH 说明**：FHS 沙箱里 `/nix/store` 文件属主会变成 `nobody`，OpenSSH 无法直接跟随 Home Manager 的 `~/.ssh/config` 符号链接。启动时会复制到 `~/.cache/androidShell/ssh/config`，并通过 `GIT_SSH_COMMAND` / `ssh -F` 使用；从 rofi 启动时还会自动探测 `SSH_AUTH_SOCK`（systemd user `ssh-agent` 等）。

## 启动

启动后在 **Settings → Build, Execution, Deployment → Build Tools → Gradle → Gradle JDK**
里就能看到两个选项：

| 选项 | 来源 |
|------|------|
| `nix-jdk17` | OpenJDK 17（默认 `JAVA_HOME`） |
| `nix-jdk11` | OpenJDK 11 |

> AS IDE 本身始终用自带 JBR 运行（2025+ 不支持用 JDK 11 跑 IDE），
> JDK 列表只影响 Gradle / 命令行编译。

配置目录为 `~/.android-studio/`（独立于宿主可能已有的其它 AS 配置）。

## 快速使用

### 临时启动（不安装）

```bash
# GUI Android Studio
nix run /path/to/androidShell                                     # = .#as
nix run /path/to/androidShell &> /tmp/as.log & disown             # 后台

# 进 CLI 沙箱
nix run /path/to/androidShell#androidShell11
nix run /path/to/androidShell#androidShell17

# 或者用 devShell 形式（带 PS1 / PATH 集成）
nix develop /path/to/androidShell#androidShell11
nix develop /path/to/androidShell#androidShell17
```

可以临时换 SDK 路径：

```bash
ANDROID_HOME=/path/to/sdk nix run /path/to/androidShell
```

### 安装到 NixOS / home-manager（在 rofi / 终端里直接用）

三个包都暴露了 `bin/<名字>` 可执行文件：

| 包 | 命令 | 用途 |
|----|------|------|
| `as` | `as` | 启动 GUI Android Studio（也注册 desktop entry） |
| `androidShell11` | `androidShell11` | 进入 JDK 11 + android-tools 的 FHS 沙箱终端 |
| `androidShell17` | `androidShell17` | 进入 JDK 17 + android-tools 的 FHS 沙箱终端 |

GUI 包另外输出 `share/applications/as.desktop`，装进系统 / 用户环境后
rofi、wofi、krunner、GNOME Activities 等都能搜到 **Android Studio**。

NixOS（`configuration.nix`）：

```nix
{ inputs, pkgs, ... }: {
  environment.systemPackages = with inputs.androidShell.packages.${pkgs.system}; [
    as              # rofi 里搜 "Android Studio"
    androidShell11  # 终端命令
    androidShell17  # 终端命令
  ];
}
```

home-manager（`home.nix`）：

```nix
{ inputs, pkgs, ... }: {
  home.packages = with inputs.androidShell.packages.${pkgs.system}; [
    as
    androidShell11
    androidShell17
  ];
}
```

装好之后：

```bash
androidShell17     # 直接进 JDK 17 沙箱
$ java -version    # OpenJDK 17
$ adb devices
$ exit             # 退回宿主 shell

androidShell11     # JDK 11 沙箱（同理）
```

Desktop entry 用的 `Exec` 是 launcher 的绝对 Nix store 路径，所以不依赖
`as` 在 PATH 里也能正确启动。

## 作为依赖引用

### 方式一：NixOS 全局 registry（推荐）

在 `configuration.nix` 里加：

```nix
nix.registry.androidShell = {
  from = { type = "indirect"; id = "androidShell"; };
  to   = {
    type  = "github";
    owner = "JIAnnLee22";
    repo  = "androidShell";
    # ref = "master";   # 或固定到 commit
  };
};
```

之后在任意目录：

```bash
nix run androidShell
```

### 方式二：用户级 registry（不改系统配置）

```bash
nix registry add androidShell github:JIAnnLee22/androidShell
```

### 方式三：在别的 flake 里作为 input

```nix
{
  inputs = {
    nixpkgs.url      = "github:NixOS/nixpkgs/nixos-unstable";
    androidShell.url = "github:JIAnnLee22/androidShell";
  };

  outputs = { self, nixpkgs, androidShell, ... }: {
    apps = androidShell.apps;

    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ({ pkgs, ... }: {
          environment.systemPackages = [
            androidShell.packages.${pkgs.system}.as
          ];
        })
        # ...其他模块
      ];
    };
  };
}
```

之后：

```bash
nix run                # 默认 = as
# 或者重建系统后直接在 rofi 里搜 "Android Studio"
```

`androidShell` 的版本会被锁进**你自己的 `flake.lock`**，升级用：

```bash
nix flake update androidShell
```

### 方式四：本地路径

```nix
nix.registry.androidShell.to = {
  type = "path";
  path = "/home/jiannlee22/flake/androidShell";
};
```

未提交修改会有 `Git tree is dirty` 警告，但仍可用。

## 覆写 / 自定义

flake 暴露了 `lib.x86_64-linux.{ mkAndroidStudio, mkLauncher, mkStudioJdkTable }`
与 `packages.x86_64-linux.{ as, android-studio }`，消费者可以在自己的 flake 里
换 AS 版本或换 JDK 组合而不用改这边代码。

### 换 Android Studio 版本

```nix
{
  inputs.androidShell.url = "github:JIAnnLee22/androidShell";

  outputs = { androidShell, ... }:
    let
      as = androidShell.lib.x86_64-linux.mkLauncher {
        androidStudio = androidShell.lib.x86_64-linux.mkAndroidStudio {
          version    = "2025.3.4.6";
          sha256Hash = "sha256-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx=";
          # url 默认按 version 拼成 edgedl.me.gvt1.com 链接，特殊渠道才需要传
        };
      };
    in {
      packages.x86_64-linux.as = as;
      apps.x86_64-linux.as = { type = "app"; program = "${as}/bin/as"; };
    };
}
```

### 换 JDK 组合

```nix
androidShell.lib.x86_64-linux.mkLauncher {
  defaultJdk = pkgs.jdk21;
  extraJdks  = [ pkgs.jdk17 pkgs.jdk11 ];   # 都会被注册成 nix-jdkXX
}
```

`sha256Hash` 取法：

```bash
nix-prefetch-url https://edgedl.me.gvt1.com/android/studio/ide-zips/<ver>/android-studio-<ver>-linux.tar.gz
nix hash to-sri --type sha256 <上面输出的 hash>
```

或者偷懒法：先填一个全 A 的假 hash 触发构建，nix 会在错误里打印真实 hash，复制过去即可。

## 文件

- `flake.nix` — 启动器定义、`buildFHSEnv` 沙箱、`makeDesktopItem`、JDK 注册、`lib` 覆写入口
- `android-studio.nix` — 可参数化的 AS 包装（默认 2025.2.3.9）
- `flake.lock` — nixpkgs 版本锁

## 常见操作

```bash
# 启动 IDE
nix run .#as

# 后台启动
nix run .#as &> /tmp/as.log & disown

# 升级 nixpkgs（重新生成 flake.lock）
nix flake update
```
