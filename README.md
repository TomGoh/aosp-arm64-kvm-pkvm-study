# KVM / pKVM 内核源码学习集

这是从 AOSP `kernel/common` 的 Android 15 / Linux 6.6 分支中提取的学习型源码仓库。它保留 KVM、ARM64 pKVM、虚拟化内存管理主路径，以及理解这些代码所需的内核核心子系统；不包含设备驱动全集、其他体系结构实现和本地构建产物。

当前快照锁定在：

- AOSP 分支：`android15-6.6`
- 提交：`9f24219bc984bd97d696773f1a6045e9b49bbee3`
- 内核版本：`6.6.142`
- 详细来源：[`SOURCE.lock`](SOURCE.lock)

## 这个仓库适合做什么

- 沿 `/dev/kvm` ioctl、VM、vCPU、memslot 主线阅读通用 KVM。
- 对照 ARM64 host KVM、nVHE EL2 与 protected KVM 三层实现。
- 集中研究 GUP、MMU notifier、memslot、stage-2 页表和 pKVM 页面所有权转换。
- 用 upstream 文档与 selftests 把源码路径对应到用户态行为。
- 在源码更新时，通过固定清单重新生成同一范围的快照。

它不是一棵可直接构建的完整内核树。虽然保留了原始路径、Kconfig 和 Makefile，但大量无关驱动、构建脚本及平台代码被有意移除。这里的验证目标是“来源准确、阅读闭环、裁剪可重现”，不是证明它能独立产出 `Image`。

## 保留范围

| 层次 | 主要目录 | 学习目的 |
| --- | --- | --- |
| KVM core | `virt/kvm/` | ioctl、VM/vCPU 生命周期、memslot、irqfd/eventfd |
| ARM64 KVM/pKVM | `arch/arm64/kvm/` | guest entry/exit、stage-2、VGIC、nVHE、页面所有权 |
| ARM64 core | `arch/arm64/{include,kernel,mm}/` | 异常级、页表、TLB、启动、异常与体系结构定义 |
| 通用内存管理 | `mm/` | GUP、mmap、folio、huge page、MMU notifier、回收 |
| 内核核心 | `kernel/`、`lib/`、`include/` | 调度、锁、RCU、workqueue、基础数据结构和 API 定义 |
| 虚拟化相关设备 | `drivers/{iommu,vfio}/`、GIC、FF-A | 设备直通、DMA 隔离、中断与固件内存共享 |
| 文档与测试 | `Documentation/`、`tools/testing/selftests/` | 设计文档、ABI 和可执行示例 |

精确范围及裁剪理由见 [`manifest/source-paths.txt`](manifest/source-paths.txt) 和 [`docs/scope.zh-CN.md`](docs/scope.zh-CN.md)。

## 建议入口

第一次阅读建议按下面顺序：

1. `Documentation/virt/kvm/api.rst`：先理解用户态 KVM API。
2. `virt/kvm/kvm_main.c`：跟踪 `/dev/kvm`、VM/vCPU fd 和 memslot。
3. `arch/arm64/kvm/arm.c`：ARM64 VM/vCPU 生命周期及运行入口。
4. `arch/arm64/kvm/mmu.c`：host 侧 stage-2 fault、映射与失效。
5. `arch/arm64/kvm/hyp/pgtable.c`：真正的 stage-2 页表遍历和更新。
6. `Documentation/virt/kvm/arm/pkvm.rst`：建立 pKVM 的威胁模型。
7. `arch/arm64/kvm/hyp/nvhe/mem_protect.c`：页面所有权与共享状态转换。

更细的调用链和专题顺序见 [`docs/reading-guide.zh-CN.md`](docs/reading-guide.zh-CN.md) 与 [`docs/memory-mechanisms.zh-CN.md`](docs/memory-mechanisms.zh-CN.md)。

## 更新和校验

从本地 AOSP 内核仓库同步：

```bash
scripts/sync-from-aosp.sh /path/to/kernel/common aosp/android15-6.6
```

确认所有被清单管理的源码（内容、可执行位和符号链接目标）都等于锁定提交：

```bash
scripts/verify-source.sh /path/to/kernel/common
```

校验只读取源仓库的 git 树对象，不解压文件，因此源仓库用 `--filter=blob:none` 的 blobless 克隆即可。

注意事项：

- 目标目录必须位于大小写敏感的文件系统上。`include/uapi/linux/netfilter*` 下有只差大小写的头文件（如 `xt_MARK.h` 与 `xt_mark.h`），同步脚本在大小写不敏感的卷上会直接拒绝执行。macOS 默认卷不满足要求，可新建 “APFS（区分大小写）” 卷。
- 内核自带的部分 `.gitignore` 会命中被跟踪的源码（例如 `tools/testing/selftests/kvm/` 先忽略全部再白名单放行），普通 `git add` 会漏掉它们。同步脚本会列出这些文件，请用 `git add -f` 提交。
- 同步脚本不会删除旧版本已经消失的文件。因此更新版本时，应在干净分支执行同步，再用 `verify-source.sh` 检查：多余、缺失或被修改的文件都会以 diff 形式列出；必要时人工删除已经从上游消失的源文件。

## 来源和许可证

内核源码保持原 SPDX 标识和原目录结构，许可证文本位于 `COPYING` 与 `LICENSES/`。本仓库用单独的快照提交保存裁剪结果，不保留 AOSP 的完整提交历史；需要逐行历史时，请在完整 `kernel/common` 仓库中执行：

```bash
git blame 9f24219bc984bd97d696773f1a6045e9b49bbee3 -- arch/arm64/kvm/mmu.c
```
