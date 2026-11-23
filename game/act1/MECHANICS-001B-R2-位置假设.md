# MECHANICS-001B-R2 追加（第 6 轮）：「移出 stage」假设被证伪，收敛到"位置"

> NO-GO；已回退，`MECH001A_DONE failures=0` / `RESULT failures=0 completion=true`。

## 1. 本轮验证

按上一轮结论，把整组夹爪（`ClampAssembly`）挂到 **`stage` 之外**（`stage.get_parent()` / 场景根），
用世界坐标定位到插座旁：

```
PROBE hinge a=../ClampBracket b=../ClampJaw axis=(0,0,-1) anchor=(5.27,1.52,-4.85)
PROBE impulse30(绕真实轴): 0.000 → 0.000   w=0.000     ❌
PROBE impulse_mask0:       0.000 → 0.000   w=0.000     ❌
PROBE impulse_benchparams: 0.001 → 0.000   w=0.000     ❌
PROBE motor: closed_at=-1 angle=0.000 stalled=true      ❌
```

**结论：父节点不是变量。** 上一轮案例 C 之所以通过，是因为**同时把锁爪挪到了别的位置**，
而不是因为脱离了 `stage`。

## 2. 现在的事实（修正后）

| 实验 | 位置 | 结果 |
|---|---|---|
| 独立台架 | 场景根，原点附近 | ✅ 转 |
| 同场景运行时新建 | 探针根，(0,6,0)/(0,9,0) | ✅ 转 |
| builder 支架 + 新锁爪 | **插座旁 (5.27,1.52,-4.85)** | ❌ 锁死 |
| 新支架 + builder 锁爪（挪到 (0,9,0)） | 远离插座 | ✅ 转 |
| builder 支架移出 stage 但仍在插座旁 | **插座旁** | ❌ 锁死 |

→ 唯一一致的判别量是**位置**：**在插座旁锁死，离开插座就正常**。
而把锁爪 `collision_mask` 置 0 仍在插座旁锁死，说明**不是接触**，而是该位置上的某个约束/几何关系。

## 3. 下一轮的最小判别（一次运行即可）

保持父节点与参数完全不变，只**平移整组夹爪**做三档扫描：
1. 插座旁（已知 ❌）；
2. 插座旁 + 1.0 m（沿 +X）；
3. 插座旁 + 3.0 m。

若 2/3 能转而 1 不能 → 就是位置相关，接着在锁爪原位置**逐块读接触/重叠**
（`PhysicsDirectSpaceState3D.intersect_shape` 列出与该位置重叠的所有 body/shape，
包括 layer 与 mask 为 0 的情况——**重叠查询不看 mask**，这一点之前用 mask=0 是测不出来的）。

这条我预期就是答案：某个静态件（挡块/导轨/插座壳体）与锁爪臂在出生位置**几何重叠**，
Jolt 的关节在"被重叠的静态形状挤住"时会表现为自由度锁死，即使碰撞掩码为 0（mask 只影响
碰撞对，不影响关节求解与时变约束）。

## 4. 当前状态

正式关卡已回退并验证可玩；WIP 与全部台架/探针（chute / clamp / ladder / scene_probe / swap / rebind）
在 `physics_lab/wip_mechanics001b/`，正式测试树已清空探针。
