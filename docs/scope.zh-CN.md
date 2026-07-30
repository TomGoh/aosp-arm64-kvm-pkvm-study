# 裁剪边界

## 原则

这个仓库采用“专题切片”而不是“最小编译闭包”。判断一个目录是否保留，主要看它是否满足以下任一条件：

1. 实现 KVM/pKVM 的直接控制流；
2. 实现虚拟化内存机制所依赖的核心语义；
3. 提供 ARM64 EL2、页表、TLB、中断或 IOMMU 的体系结构背景；
4. 是理解 ABI、锁和生命周期所需的文档或测试；
5. 保留完整头文件能显著降低跨文件查定义的成本。

## 为什么保留整个 `mm/`

KVM 的内存不是孤立子系统。一个 userspace memslot 背后会遇到 VMA、GUP/pinning、folio、huge page、MMU notifier、mmap lock、回收和内存记账。只复制 `mm/gup.c`、`mm/mmu_notifier.c` 等少数文件，会把大量关键条件隐藏在辅助函数里，尤其容易误解 THP、长期 pin 和 teardown。因此本仓库保留完整通用 MM 实现。

## 为什么保留整个 `kernel/`、`lib/` 和 `include/`

pKVM 的 host/hyp 交互高度依赖锁、RCU、per-CPU、调度、workqueue、原子操作和基础数据结构。头文件还包含大量真正的内联实现和配置分支。三者总体仍远小于完整内核树，保留它们可避免把“未复制到”误当成“实现不存在”。

## 为什么包含 IOMMU、VFIO、GIC 和 FF-A

- `drivers/iommu/`：理解 DMA 地址空间、设备隔离和 pKVM IOMMU 接口背景。
- `drivers/vfio/`：理解 KVM 设备直通与用户内存 pin 的交点。
- GIC 文件：连接物理 GIC/ITS 与 `arch/arm64/kvm/vgic/` 的虚拟中断模型。
- `drivers/firmware/arm_ffa/`：理解 pKVM 与固件世界之间的 FF-A 调用背景。

## 有意排除

- `arch/x86/` 等其他体系结构：通用 KVM 概念仍由 `virt/kvm/` 表示；第一阶段聚焦 ARM64 pKVM。
- 网络、存储、图形、声音等驱动全集：它们不是理解 KVM/pKVM 核心机制的前置条件。
- Android 构建基础设施和完整 `scripts/`：裁剪仓库不承诺独立构建。
- `.config`、对象文件、生成头文件、`vmlinux` 等产物：它们依赖具体构建，不能作为 AOSP 源码快照的一部分。
- 当前工作树的实验提交：快照直接取自 `aosp/android15-6.6` 对应对象，不取当前 checkout 内容。

## 边界如何演进

遇到缺失上下文时，先在完整 AOSP 树定位定义，再判断它属于：

- 经常用于解释主路径：加入 `manifest/source-paths.txt`；
- 仅一次性旁支：在学习笔记中链接 AOSP 提交和路径；
- 为了构建而产生的大量传递依赖：不要悄悄扩大范围，应单独设计“最小可编译目标”。

这样能让仓库随着实际学习问题增长，而不是重新膨胀成一棵完整内核。
