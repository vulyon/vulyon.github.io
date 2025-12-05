---
title: "从 Linux Namespace 到 Docker 容器隔离"
last_modified_at: 2023-12-11T12:00:00+08:00
categories:
  - docker
tags:
  - docker
  - namespaces
  - cgroups

---


# 从 Linux Namespace 到 Docker 容器隔离：原理详解与分析

------

## 目录

- 一、容器的本质：它不是虚拟机
- 二、Linux Namespace：实现隔离的核心机制
  - 2.1 Namespace 是什么
  - 2.2 7 大 Namespace 类型
- 三、Docker 如何使用 Namespace 构建容器
  - 3.1 Docker 的构造步骤
  - 3.2 为什么容器看起来像“轻量虚拟机”
- 四、深入理解 Namespace：API、生命周期与示例
  - 4.1 三个关键系统调用
  - 4.2 Namespace 生命周期机制
  - 4.3 Go 示例：手写一个简易容器
- 五、总结：理解 Namespace 的价值

------

# 一、容器的本质：它不是虚拟机

我们经常说 Docker 容器“像虚拟机”，但本质上：

> **容器 = 一组使用 namespace + cgroups + rootfs 隔离后的普通 Linux 进程。**

传统虚拟机（VM）：

- 需要虚拟化 CPU、内存、硬盘、网络；
- 运行独立内核；
- 启动慢、占用资源大。

Docker 容器：

- 不虚拟化硬件 → **共享宿主机内核**；
- 只是隔离进程看到的“世界”；
- 启动快（毫秒级）、资源占用极低。

因此，容器 ≠ VM。

它更像是：

> **运行在隔离空间中的 Linux 进程组。**

------

# 二、Linux Namespace：实现隔离的核心机制

## 2.1 Namespace 是什么？

Namespace 是 Linux 内核提供的资源“视图隔离”技术。

加入不同 namespace 的进程：

- 看不到彼此的文件系统
- 看不到彼此的 PID
- 看不到彼此的网络设备
- 看不到彼此的主机名或用户
- …

**最关键：不同 namespace 内的操作互不影响。**

所以容器内：

- `hostname` 改了不会影响宿主机；
- `ps` 看不到宿主机进程；
- 网络 IP 和宿主机完全不同；
- 查看挂载点时就是独立 rootfs。

这就是容器“像虚拟机”的原因。

------

## 2.2 7 大 Namespace 类型（Docker 重点使用）

| Namespace  | 隔离内容                   | 容器中的表现                 |
| ---------- | -------------------------- | ---------------------------- |
| **pid**    | 进程号                     | 容器中 PID 从 1 开始         |
| **mnt**    | 挂载点、文件系统           | 挂载 rootfs，不影响宿主机    |
| **uts**    | 主机名/域名                | 每个容器独立 hostname        |
| **ipc**    | 进程间通信                 | shm 不共享                   |
| **net**    | 网络协议栈、设备、IP、路由 | 各容器独立网络               |
| **user**   | UID/GID 空间               | 容器内 root = 宿主机普通用户 |
| **cgroup** | 资源控制组                 | 隔离 cgroup 视图             |

> Docker 用到了所有这些 namespace。

------

# 三、Docker 如何使用 Namespace 构建容器

## 3.1 Docker 构建容器的步骤简述

当你执行：

```
docker run -it ubuntu bash
```

Docker 主要做了 4 件事：

------

### ① 创建隔离环境（namespace）

Docker 调用了系统调用 `clone()` 创建新进程：

```
CLONE_NEWPID     # 进程号隔离
CLONE_NEWNS      # 挂载隔离
CLONE_NEWUTS     # 主机名隔离
CLONE_NEWIPC     # IPC 隔离
CLONE_NEWNET     # 网络隔离
CLONE_NEWUSER    # 用户隔离
```

每一项都让容器看起来像“独立系统”。

------

### ② 使用 cgroups 限制资源

例如：

- 限制 1 CPU
- 限制 512MB RAM
- 限制 IO 读写速度

------

### ③ 准备 root 文件系统（rootfs）

例如从 `ubuntu` 镜像读取：

- 只读层（镜像）
- 可写层（容器运行时产生）

形成：

```
overlayfs
 ├─ lowerdir（镜像只读层）
 └─ upperdir（容器写层）
```

------

### ④ 在 namespace 中执行用户进程

最终执行：

```
bash
```

→ 并且它运行在隔离的 world 中。

------

## 3.2 为什么容器看起来像“轻量虚拟机”？

因为：

- 文件系统独立（mnt namespace）
- 主机名独立（uts namespace）
- 网络独立（net namespace）
- 进程号独立（pid namespace）
- IPC 独立（ipc namespace）

进程感觉自己处在一个完整系统中，但实质上只是一个被隔离的 Linux 进程。

------

# 四、深入理解 Namespace：API、生命周期与示例

## 4.1 三个关键系统调用

### ① `clone()`

创建一个新进程，并指定要创建新的 namespace。

```
clone(CLONE_NEWPID | CLONE_NEWUTS | ...);
```

### ② `unshare()`

让当前进程脱离原 namespace，加入新的 namespace。

```
unshare(CLONE_NEWNET);
```

### ③ `setns()`

让当前进程加入到已有 namespace。

```
fd = open("/proc/1234/ns/net", O_RDONLY);
setns(fd, 0);
```

这是 Docker 附加容器、进入容器时的底层方式。

------

## 4.2 Namespace 生命周期

- Namespace 绑定到 **进程数量 > 0** 才存在
- 当 namespace 中所有进程退出后 → namespace 自动销毁
- 可以通过 `/proc/<pid>/ns/` 查看进程的 namespace

示例：

```
ls -l /proc/$$/ns
```

------

## 4.3 Go 示例：从零构建一个简易“容器”

下面是一个用 Go 实现“进入隔离环境”的示例：

```
cmd := exec.Command("/bin/bash")

cmd.SysProcAttr = &syscall.SysProcAttr{
    Cloneflags: syscall.CLONE_NEWUTS |
                syscall.CLONE_NEWPID |
                syscall.CLONE_NEWNS |
                syscall.CLONE_NEWNET |
                syscall.CLONE_NEWIPC,
}

cmd.Run()
```

运行后：

- `hostname` 独立
- `ps` 只能看到少量进程
- 网络隔离
- 挂载点隔离

这是实现 toy-container 的核心原理。

------

# 五、总结：理解 Namespace 的价值

理解 Namespace，等于理解 Docker 70% 的底层机制。

### Namespace 为什么重要？

- 解释 Docker 为什么轻量
- 解释容器如何实现隔离
- 解释 K8s Pod 为什么“本质上是进程组”
- 解释容器之间为何需要 CNI 才能通信
- 解释 rootfs + namespace 的组合为何能“模拟完整系统”

### 一句话总结：

> **容器不是虚拟机，它是现代 Linux 最重要的进程隔离技术的产品。
>  Namespace 是容器技术的基础，Docker 只是它的组合与封装。**

> 