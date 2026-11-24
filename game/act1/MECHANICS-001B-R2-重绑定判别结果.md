# MECHANICS-001B-R2 追加（第 4 轮）：重绑定判别结果

> 结论不变：**NO-GO**；已回退，001A 基线 `MECH001A_DONE failures=0` / `RESULT failures=0 completion=true`。

---

## 1. 本轮验证的假设与结果

**假设**：`builder` 在刚体尚未稳定时绑定关节，之后 `reset_all()` 把关节拉出误差 → 自由度锁死。

**判别方法**（探针 `mech001b_r2_rebind`）：
1. 加载 act01，等 120 帧；
2. 把原关节 `node_a/node_b` 置空（解绑）；
3. 用**完全相同的参数**在探针根节点下重新绑定同一对刚体（`ClampBracket` + `ClampJaw`）；
4. 绕新关节的真实轴施加 30 N·m·s 角冲量。

**结果**：
```
PROBE jaw_pos_before=(5.27,1.52,-4.85)
PROBE scales jaw=(1.0,1.0,1.0) app=(1.0,1.0,1.0) parent=(1.0,1.0,1.0)   ← 无缩放，排除锚点算错
PROBE REBIND axis=(0,0,-1) w=0.000 angle=0.000 rot_changed=false        ← 重绑定后仍锁死
```
→ **假设被证伪**：不是"陈旧绑定"，重新绑一次同样锁死。

## 2. 现在的事实矩阵

| 组合 | 结果 |
|---|---|
| 台架：新支架 + 新 22 kg 刚体 + 新关节（独立场景） | ✅ 转动 0.802 rad，反向 78 帧回位 |
| 同场景运行时：新支架 + 新 22 kg 刚体 + 新关节 | ✅ `rot_changed=true` |
| 同场景：`builder` 的支架 + `builder` 的锁爪 + **新关节** | ❌ 锁死 |
| 同场景：`builder` 的锁爪（改 22 kg / 无重力 / 低阻尼 / mask 0）+ 原关节 | ❌ 锁死 |
| 同场景：`builder` 锁爪 + 原关节 + 直接角冲量（绕真实轴） | ❌ 锁死 |

**结论收敛**：问题**只存在于 `builder` 创建的那一对刚体中的某一个**，与关节、参数、碰撞、缩放都无关。
已排除：质量/重力/角阻尼、碰撞掩码与接触、与支架重叠、轴取向、局部基、缩放、绑定时机。

## 3. 下一轮的最小二分（很便宜，按顺序做一定能定位）

对 `builder` 的两个刚体分别做"替换实验"，一次只换一个：

1. 保持 `builder` 的支架，**新建一个 22 kg 刚体**（台架参数）作为 node_b → 能转吗？
   * 能转 → 问题在 `ClampJaw` 刚体本身（下一步逐个复制它的属性：`continuous_cd`、
     `can_sleep`、子节点结构、`physics_material_override`、`lock_rotation` 之外的隐式配置）；
   * 不能转 → 问题在 `ClampBracket`（下一步换成台架那样 `mask=0` / 冻结刚体对照）。
2. 用 `PhysicsServer3D.body_get_*` 读一次 `ClampJaw` 的**实际服务器状态**
   （惯量、轴锁、motion mode、`body_get_param` 各项），与运行时那只逐项对比。

我预期答案是第 1 步的某一项（最可能是 `ClampJaw` 上某个我没意识到的隐式约束或子节点结构），
因为除此之外的所有可测量差异都已被逐条排除。

## 4. 归档

```
physics_lab/backup_mechanics001b/     001A 末态（已使用，回退后验证通过）
physics_lab/wip_mechanics001b/        WIP（锁爪构造 + 绕真实轴测角 + 启动宽限 + 滑槽 _ramp_basis）
physics_lab/wip_mechanics001b/bench/  chute / clamp / ladder / scene_probe / rebind 五个台架 + .gdignore
```
正式测试树已清空全部探针脚本；`game/act1/` 仍不在 Git 跟踪内。
