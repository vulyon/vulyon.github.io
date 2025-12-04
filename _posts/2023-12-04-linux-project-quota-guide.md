---
title: "Linux Project Quota 磁盘限额配置指南"
last_modified_at: 2023-12-04T12:00:00+08:00
categories:
  - Linux
  - 运维
tags:
  - XFS
  - ext4
  - Quota
  - 磁盘管理
---

本文介绍如何在 Linux 系统上使用 **Loop 设备**模拟块设备，并配置 **XFS** 和 **ext4** 文件系统的 Project Quota 磁盘限额功能。

<!--more-->

## 一、XFS Project Quota 配置

在没有额外独立硬盘挂载到服务器上时，可以创建文件，以 **Loop 设备**的形式模拟块设备。

### 1. 创建镜像文件

创建 10G 大小的文件 `xfs.img`：

```bash
[root@host ~]# dd if=/dev/zero of=xfs.img bs=1G count=10
10+0 records in
10+0 records out
1048576000 bytes (1.0 GB, 1000 MiB) copied, 0.915589 s, 1.1 GB/s
```

### 2. 绑定 Loop 设备

查找第一个可用的 `loop` 设备：

```bash
[root@host ~]# losetup -f
/dev/loop0
```

将文件绑定到 `loop` 设备，并验证：

```bash
[root@host ~]# losetup /dev/loop0 xfs.img
[root@host ~]# lsblk
NAME    MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
loop0     7:0    0   10G  0 loop
sda       8:0    0  500G  0 disk
├─sda1    8:1    0    1G  0 part /boot
└─sda2    8:2    0   49G  0 part
```

### 3. 格式化为 XFS 文件系统

将 `loop0` 设备格式化为 **XFS 文件系统**：

```bash
[root@host ~]# mkfs.xfs /dev/loop0
meta-data=/dev/loop0             isize=512    agcount=4, agsize=655360 blks
         =                       sectsz=512   attr=2, projid32bit=1
         =                       crc=1        finobt=1, sparse=1, rmapbt=0
         =                       reflink=1    bigtime=0 inobtcount=0
data     =                       bsize=4096   blocks=2621440, imaxpct=25
         =                       sunit=0      swidth=0 blks
naming   =version 2              bsize=4096   ascii-ci=0, ftype=1
log      =internal log           bsize=4096   blocks=2560, version=2
         =                       sectsz=512   sunit=0 blks, lazy-count=1
realtime =none                   extsz=4096   blocks=0, rtextents=0
Discarding blocks...Done.
```

### 4. 挂载并启用 Project Quota

创建挂载点并挂载文件系统，启用 **project quota**：

```bash
[root@host ~]# mkdir -p /mnt/xfs
[root@host ~]# mount -o prjquota /dev/loop0 /mnt/xfs/
```

验证挂载状态：

```bash
[root@host ~]# mount | grep xfs
/dev/loop0 on /mnt/xfs type xfs (rw,relatime,attr2,inode64,logbufs=8,logbsize=32k,prjquota)
```

---

## 二、ext4 Project Quota 配置

本节介绍如何在 **ext4** 文件系统上配置 Project Quota 限额。

### 1. 准备磁盘镜像文件

创建一个 10G 大小的文件 `ext4.img`：

```bash
[root@host ~]# dd if=/dev/zero of=ext4.img bs=1G count=10
```

查找并绑定 Loop 设备：

```bash
# 查找第一个可用的 loop 设备
[root@host ~]# losetup -f
/dev/loop1

# 将文件绑定到 loop 设备
[root@host ~]# losetup /dev/loop1 ext4.img

# 验证绑定结果
[root@host ~]# lsblk
NAME    MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
loop0     7:0    0   10G  0 loop /mnt/xfs
loop1     7:1    0   10G  0 loop
```

### 2. 格式化为 ext4 文件系统

使用 `mkfs.ext4` 命令格式化，并**启用 `project` 和 `quota` 特性**：

```bash
[root@host ~]# mkfs.ext4 -O project,quota /dev/loop1
```

验证特性是否开启：

```bash
[root@host ~]# dumpe2fs -h /dev/loop1 | grep -i quota
dumpe2fs 1.46.5 (30-Dec-2021)
Filesystem features:      has_journal ext_attr resize_inode dir_index filetype extent 64bit flex_bg sparse_super large_file huge_file dir_nlink extra_isize metadata_csum quota project
```

### 3. 挂载并启用限额

创建挂载点并挂载：

```bash
[root@host ~]# mkdir -p /mnt/ext4
[root@host ~]# mount -o prjquota /dev/loop1 /mnt/ext4/
```

验证 Quota 状态：

```bash
[root@host ~]# quotaon -Ppv /mnt/ext4/
quotaon: Enforcing project quota already on /dev/loop1
```

---

## 三、配置 Project Quota 限额

### 1. XFS 配置限额

使用 `xfs_quota` 命令配置限额：

```bash
# 设置 project ID 和目录
[root@host ~]# echo "1:/mnt/xfs/project1" >> /etc/projects
[root@host ~]# echo "project1:1" >> /etc/projid

# 初始化 project
[root@host ~]# xfs_quota -x -c 'project -s project1' /mnt/xfs

# 设置限额（软限制 5G，硬限制 6G）
[root@host ~]# xfs_quota -x -c 'limit -p bsoft=5g bhard=6g project1' /mnt/xfs

# 查看限额报告
[root@host ~]# xfs_quota -x -c 'report -p -h' /mnt/xfs
```

### 2. ext4 配置限额

使用 `setquota` 和相关工具配置：

```bash
# 设置 project ID 和目录
[root@host ~]# echo "2:/mnt/ext4/project2" >> /etc/projects
[root@host ~]# echo "project2:2" >> /etc/projid

# 为目录设置 project ID
[root@host ~]# mkdir -p /mnt/ext4/project2
[root@host ~]# chattr +P -p 2 /mnt/ext4/project2

# 设置限额（软限制 5G，硬限制 6G）
[root@host ~]# setquota -P 2 5242880 6291456 0 0 /mnt/ext4

# 查看限额
[root@host ~]# repquota -P /mnt/ext4
```

---

## 四、开机自动挂载

为了在系统重启后自动挂载，需要配置 `/etc/fstab` 和相关服务。

### 1. 配置 fstab

```bash
# 添加到 /etc/fstab
/root/xfs.img  /mnt/xfs  xfs   loop,prjquota  0 0
/root/ext4.img /mnt/ext4 ext4  loop,prjquota  0 0
```

### 2. 使用 systemd 服务（推荐）

创建 systemd 服务文件确保 loop 设备在挂载前绑定：

```bash
# /etc/systemd/system/loop-xfs.service
[Unit]
Description=Setup loop device for XFS
Before=local-fs.target

[Service]
Type=oneshot
ExecStart=/sbin/losetup /dev/loop0 /root/xfs.img
ExecStop=/sbin/losetup -d /dev/loop0
RemainAfterExit=yes

[Install]
WantedBy=local-fs.target
```

启用服务：

```bash
[root@host ~]# systemctl enable loop-xfs.service
```

---

## 总结

| 文件系统 | 格式化命令 | 挂载选项 | 配额管理工具 |
|---------|-----------|---------|-------------|
| XFS | `mkfs.xfs` | `prjquota` | `xfs_quota` |
| ext4 | `mkfs.ext4 -O project,quota` | `prjquota` | `setquota`, `repquota` |

**注意事项：**
- Loop 设备仅适用于测试环境，生产环境建议使用独立磁盘
- Project Quota 基于 Project ID 进行限额，不依赖用户或组
- XFS 原生支持 Project Quota，ext4 需要在格式化时启用特性

