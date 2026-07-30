# KVM / pKVM 内存机制地图

## 四个地址概念

阅读内存代码前先固定术语：

| 名称 | 含义 | 常见上下文 |
| --- | --- | --- |
| HVA | host userspace virtual address | VMM 的 `mmap` 和 memslot |
| HPA/PA | host physical address | backing page、host 页表、DMA |
| GVA | guest virtual address | guest stage-1 页表 |
| GPA/IPA | guest physical/intermediate physical address | KVM memslot 和 stage-2 输入 |

CPU 执行 guest 时通常经历 `GVA --guest stage-1--> IPA --KVM stage-2--> PA`。memslot 不是页表；它描述 GPA 区间与 userspace backing HVA 的关系，真正的 stage-2 项由 fault 或预映射路径建立。

## 普通 KVM 的主链路

```text
userspace VMM
  KVM_SET_USER_MEMORY_REGION
       |
       v
  struct kvm_memory_slot: GPA range <-> userspace HVA
       |
guest stage-2 fault
       |
       +--> lookup memslot / translate GPA to HVA
       +--> inspect VMA and obtain backing page/folio
       +--> choose page or block mapping granularity
       +--> update stage-2 via kvm_pgtable
```

建议交叉阅读：

- `virt/kvm/kvm_main.c`：memslot 生命周期、HVA/GFN 查找、通用 MMU notifier；
- `arch/arm64/kvm/mmu.c`：ARM64 fault、映射/解除映射和 cache/TLB 处理；
- `arch/arm64/kvm/hyp/pgtable.c`：stage-2 walker 与 PTE 更新；
- `mm/gup.c`、`mm/huge_memory.c`、`mm/mmu_notifier.c`：backing memory 的通用 MM 语义。

## pKVM 增加的两类页表

pKVM 不只是给普通 guest stage-2 加权限位。至少要同时区分：

1. host stage-2：由 EL2 限制不可信 host 能访问哪些物理页；
2. protected guest stage-2：把 guest IPA 映射到已经分配给该 guest 的物理页。

因此同一个物理页的变化，需要同时满足 ownership 元数据和相关 stage-2 页表的一致性。`mem_protect.c` 中的状态检查、页表更新、引用计数和回滚路径应作为一个事务阅读。

## ownership、sharing、donation

可以先用抽象状态理解，再以源码检查具体约束：

- owned：某个主体独占页面；
- shared：两个主体都保留允许的访问；
- donated：原主体放弃访问，接收者获得所有权。

不要从单个 API 名字推断完整状态。一次 host/guest share 往往包含 host 侧准备、hypercall、EL2 校验、双方页表更新以及失败回滚。需要沿 host wrapper 一直跟到 `hyp/nvhe/mem_protect.c` 的实现。

## 失效与生命周期

用户态解除映射、改变 VMA、回收 backing memory 或销毁 VM 时，旧 stage-2 映射必须先失效，之后才能安全释放或重用页面。阅读时重点记录：

- `mmu_lock`、`mmap_lock`、SRCU/MMU notifier 的获取顺序；
- PTE 清除与 TLB invalidation 的顺序；
- pin/reference/accounting 在成功、失败和 teardown 路径是否平衡；
- THP split/collapse 后映射粒度和记账单位是否仍一致。

## huge page 不等于 stage-2 block

backing memory 是 THP/hugetlb，只说明存在大页候选。能否生成 stage-2 block 还受 IPA/HVA/PA 对齐、memslot 边界、dirty logging、fault 类型和页表层级等条件限制。验证时至少应分别证明：

1. backing folio 的真实大小；
2. fault 路径选择的映射范围；
3. 最终 stage-2 PTE 所在层级；
4. 后续是否因 notifier、write protection 或 split 被拆除。

这四项不能用一次 `AnonHugePages` 观察或较少的 fault 次数替代。
