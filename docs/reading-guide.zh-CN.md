# KVM / pKVM 阅读路线

## 第一阶段：先建立 KVM 对象模型

从 `Documentation/virt/kvm/api.rst` 看用户态 API，再在 `virt/kvm/kvm_main.c` 中追踪：

```text
open /dev/kvm
  -> KVM_CREATE_VM
  -> VM fd
     -> KVM_CREATE_VCPU
     -> KVM_SET_USER_MEMORY_REGION
     -> KVM_RUN
```

这一阶段需要回答：`struct kvm`、`struct kvm_vcpu` 和 `struct kvm_memory_slot` 分别由谁创建、由哪个 fd 持有、在哪种锁或 SRCU 保护下访问。

## 第二阶段：进入 ARM64 实现

以 `arch/arm64/kvm/arm.c` 为主线，配合：

- `arch/arm64/include/asm/kvm_host.h`：ARM64 对通用 KVM 对象的扩展；
- `arch/arm64/kvm/handle_exit.c`：guest exit 的分发；
- `arch/arm64/kvm/sys_regs.c`：系统寄存器虚拟化；
- `arch/arm64/kvm/vgic/`：虚拟 GIC；
- `arch/arm64/kvm/hyp/entry.S` 与 `hyp/nvhe/switch.c`：EL1/EL2 切换。

先区分三种代码运行位置：普通 host EL1、VHE host EL2、nVHE/pKVM 的独立 EL2。相同名字的 host wrapper 和 `__hyp` 实现不要混为一层。

## 第三阶段：把普通 KVM 内存链路走通

建议按专题查找，而不是顺序通读 `mmu.c`：

1. userspace 如何用 `KVM_SET_USER_MEMORY_REGION` 建立 memslot；
2. stage-2 fault 如何从 IPA 找 memslot 和 HVA；
3. host 如何 pin/取得 backing page；
4. `arch/arm64/kvm/hyp/pgtable.c` 如何创建 stage-2 PTE/block；
5. host VMA 改变时，MMU notifier 如何回收或失效 stage-2 映射；
6. dirty logging、write protection、THP 对映射粒度有什么影响。

同时阅读 `tools/testing/selftests/kvm/` 中的 `demand_paging_test.c`、`kvm_page_table_test.c`、`memslot_*` 和 ARM64 `page_fault_test.c`，把内核分支与可观测行为对应起来。

## 第四阶段：理解 pKVM 的新增不变量

先读 `Documentation/virt/kvm/arm/pkvm.rst`，然后聚焦：

- `arch/arm64/kvm/pkvm.c`：host 侧 pKVM 管理入口；
- `arch/arm64/kvm/hyp/nvhe/pkvm.c`：EL2 侧 protected VM/vCPU 对象；
- `arch/arm64/kvm/hyp/nvhe/mem_protect.c`：host、guest、hyp 间页面所有权/共享转换；
- `arch/arm64/kvm/hyp/nvhe/mm.c`：hyp 自己的地址空间；
- `arch/arm64/kvm/hyp/nvhe/page_alloc.c`：EL2 可用的页分配；
- `arch/arm64/kvm/hyp/pgtable.c`：host stage-2 与 guest stage-2 共用的页表库；
- `arch/arm64/kvm/hyp/nvhe/setup.c`：初始化和内存预留。

每次分析一条转换时，都记录四件事：调用者所在异常级、锁、旧状态、新状态。仅看函数名中的 `share`、`donate`、`unshare` 不足以判断谁仍可访问页面。

## 第五阶段：专题扩展

- 中断：`arch/arm64/kvm/vgic/`、`arch/arm64/kvm/hyp/vgic-v3-sr.c`、`drivers/irqchip/irq-gic-v3*`。
- 设备：`arch/arm64/kvm/iommu.c`、`drivers/iommu/`、`drivers/vfio/`。
- 性能：TLB invalidation、huge mapping、锁竞争、VMID rollover。
- 安全边界：hypercall ABI、host stage-2、hyp VA、页表页所有权和引用计数。

## 阅读时的证据纪律

- Kconfig/Makefile 中出现源码不等于该路径在目标配置中编译。
- 编译成功不等于 protected mode 已启用或某条 hyp 路径运行过。
- 普通 KVM、nVHE 和 pKVM 可能复用页表库，但威胁模型和所有权规则不同。
- page fault 次数、TLBI 次数、页表 block 粒度是不同指标，不应互相代替。
