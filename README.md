# androidShell

为安卓开发提供的 Nix flake，按 JDK 版本拆分 dev shell，每个 shell 自带一份**配置隔离**的
Android Studio，并把当前 shell 的 JDK 自动注册到 IDE 的 JDK 列表里供 Gradle 选择。

每个 dev shell 都跑在 [`buildFHSEnv`](https://nixos.org/manual/nixpkgs/stable/#sec-fhs-environments)
用户态沙箱里，`/lib64/ld-linux-x86-64.so.2` 等 FHS 路径都存在，所以 Gradle 从 Maven 拉的
`aapt2`、`sdkmanager` 等预编译二进制无需 patchelf 直接能跑。

## 包含

- **Android Studio 2025.2.3.9**（pin 在 `android-studio.nix`，可覆写，详见下文）
- **JDK 11 / JDK 17**（按 profile 切换）
- **android-tools**（`adb`、`fastboot` 等）
- **scrcpy**（设备投屏）
- **tmux**（终端复用）
- **FHS 库**（zlib / libstdc++ / ncurses / openssl 等，足够跑 aapt2、sdkmanager）

## Dev shells

| 名称 | Shell 的 `JAVA_HOME` | AS 里可选的 JDK |
|------|----------------------|------------------|
| `jdk11`   | OpenJDK 11 | `nix-jdk11` |
| `jdk17`   | OpenJDK 17 | `nix-jdk17` |
| `default` | 同 `jdk17` |                  |

每个 profile 的 AS 配置目录独立：

```
~/.android-studio-jdk11/   # config / system / cache / 日志
~/.android-studio-jdk17/
```

因此 `jdk11` 和 `jdk17` 的 AS 可以**同时启动**互不干扰。

## 快速使用

直接从 flake 路径进入：

```bash
nix develop /path/to/androidShell          # 默认 jdk17
nix develop /path/to/androidShell#jdk11
```

进入后会自动：

- 设置 `JAVA_HOME` 为当前 profile 的 JDK
- 写出隔离的 `idea.properties`
- 把当前 JDK 注册到 `~/.android-studio-<profile>/config/options/jdk.table.xml`
- 提供 `as` 函数：后台启动 AS（不占用终端，日志写到 `studio.launch.log`）

启动 AS 后，在 **Settings → Build, Execution, Deployment → Build Tools → Gradle → Gradle JDK**
里选 `nix-jdk11` 或 `nix-jdk17` 即可让 Gradle 使用 shell 的 JDK。

> AS IDE 本身始终用自带 JBR 运行（2025+ 不支持用 JDK 11 跑 IDE），
> shell 的 `JAVA_HOME` 只影响 Gradle / 命令行编译。

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
nix develop androidShell
nix develop androidShell#jdk11
```

### 方式二：用户级 registry（不改系统配置）

```bash
nix registry add androidShell github:JIAnnLee22/androidShell
```

### 方式三：在别的 flake 里作为 input

如果你已经在维护自己的 flake（比如 NixOS 系统 flake），把 `androidShell` 加进
`inputs`，再把它的 `devShells` 透传到自己的 outputs，就能用同样的命令进开发环境。

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    androidShell.url = "github:JIAnnLee22/androidShell";
  };

  outputs = { self, nixpkgs, androidShell, ... }: {
    # 直接透传
    devShells = androidShell.devShells;

    # 或者和自己原有的 devShells 合并：
    # devShells.x86_64-linux = androidShell.devShells.x86_64-linux // {
    #   myShell = ...;
    # };

    # 其它 outputs（nixosConfigurations 等）照旧
  };
}
```

之后在**你自己 flake 的目录**或通过路径：

```bash
nix develop                # 默认 = jdk17
nix develop .#jdk11
nix develop /etc/nixos#jdk17     # 假设你的系统 flake 在这
```

好处是 `androidShell` 的版本会被锁进**你自己的 `flake.lock`**，升级用：

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

## 覆写 Android Studio 版本

flake 暴露了 `lib.x86_64-linux.mkAndroidStudio` / `mkShells` 与
`packages.x86_64-linux.android-studio`，消费者可以在自己的 flake 里换版本而不用改这边代码。

```nix
{
  inputs.androidShell.url = "github:JIAnnLee22/androidShell";

  outputs = { androidShell, ... }: {
    devShells.x86_64-linux = androidShell.lib.x86_64-linux.mkShells {
      androidStudio = androidShell.lib.x86_64-linux.mkAndroidStudio {
        version    = "2025.3.4.6";
        sha256Hash = "sha256-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx=";
        # url 默认按 version 拼成 edgedl.me.gvt1.com 链接，特殊渠道才需要传
      };
    };
  };
}
```

不传任何参数即沿用默认版（当前 2025.2.3.9）。

`sha256Hash` 取法：

```bash
nix-prefetch-url https://edgedl.me.gvt1.com/android/studio/ide-zips/<ver>/android-studio-<ver>-linux.tar.gz
nix hash to-sri --type sha256 <上面输出的 hash>
```

或者偷懒法：先填一个全 A 的假 hash 触发构建，nix 会在错误里打印真实 hash，复制过去即可。

## 文件

- `flake.nix` — devShell 定义、`buildFHSEnv` 沙箱、JDK 注册、`as` 启动函数、`lib` 覆写入口
- `android-studio.nix` — 可参数化的 AS 包装（默认 2025.2.3.9）
- `flake.lock` — nixpkgs 版本锁

## 常见操作

```bash
# 后台启动 AS（在 dev shell 内）
as

# 在 tmux 里挂着开发会话
tmux new -s as-jdk17        # detach: Ctrl-b d
tmux attach -t as-jdk17

# 连设备 + 投屏
adb devices
scrcpy

# 升级 nixpkgs（重新生成 flake.lock）
nix flake update
```
