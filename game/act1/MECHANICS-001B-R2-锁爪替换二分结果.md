# MECHANICS-001B-R2 追加（第 5 轮）：锁爪替换二分成功定位元凶

> 结论：**NO-GO**（未交付可用锁爪），但**根因已定位到具体节点层级**；已回退，001A 基线通过。

---

## 1. 本轮的三组替换实验（决定性）

在同一 act01 实例里，先解绑原关节，再用**新关节**做替换二分：

```
PROBE A  builder 的支架 + **全新**锁爪刚体        → w=0.000   ❌ 锁死
PROBE B  **全新**支架 + builder 的锁爪刚体        → changed=true ✅ 转动
PROBE C  builder 的支架**移出 stage**后 + 原锁爪  → changed=true ✅ 转动
```

**结论**：
* 元凶**不是**锁爪刚体（案例 B：builder 的锁爪换了支架就能转）；
* 元凶**不是**关节参数、质量、碰撞、轴取向（前面几轮已逐条排除）；
* 关键变量是**整组夹爪挂在 `stage` 子树里**——把它移出 `stage`（`reparent` 到场景其它节点）后立刻能转。

## 2. 一次失败的修复尝试（也很有价值）

我试过在 `stage` 下再套一个**恒等变换的中性节点** `ClampAssembly`，把支架/锁爪/铰链都挂进去：

```
PROBE impulse30(绕真实轴): 0.000 → 0.000   w=0.000
PROBE motor: closed_at=-1 angle=0.000 stalled=true
```
**仍然锁死。** 说明问题不在"直接父节点"，而在**整个 `stage` 子树**这一层。
结合案例 C（移出 `stage` 即可转），下一步应当把整组夹爪挂到 `stage` **之外**。

## 3. 下一轮的最小修复方案（已明确，按优先级）

1. **把夹爪装配体挂到 `stage` 的父节点（或场景树根）**，用世界坐标定位到插座旁：
   ```
   var host: Node = stage.get_parent() if stage.get_parent() != null else get_tree().current_scene
   host.add_child(clamp_root)
   clamp_root.global_position = Vector3(SOCKET.x + 1.02, SOCKET.y + 0.18, SOCKET.z + 0.10)
   ```
   然后在 `clamp_root` 里照旧建支架/锁爪/铰链（`transform` 前置、`Basis(UP, π/2)`）。
   预期：锁爪能转（案例 C 已证明）。
2. 若 `stage` 没有父节点（它是场景根），则查 `stage` 的**祖先链类型**：
   打印 `stage.get_class()` 与每一级祖先，确认是否有物理体/AnimatableBody 祖先在其中作祟。
3. 锁爪转起来后，再接滑槽与通电门控（滑槽问题仍是"模块不走坡面"，需同样的台架 vs 场景对照）。

## 4. 当前状态

```
MECH001A_DONE failures=0            ← 001A 专项 5 项
RESULT failures=0 completion=true   ← 第一幕 21 项全流程
```
已回退，正式关卡可玩。WIP 与全部台架/探针在 `physics_lab/wip_mechanics001b/`（含 `bench/`），
正式测试树已清空探针脚本。`game/act1/` 仍不在 Git 跟踪内。
