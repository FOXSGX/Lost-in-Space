class_name LISFirstPersonIntent
extends RefCounted
## LIS Physics SDK · 一次交互意图
##
## 把"玩家想做什么"与"物理世界怎么响应"分开：
##   本地玩家 → 采样输入 → LISFirstPersonIntent
##   主机     → 收到远端意图 → 同一个 LISGrabber 施同一份力
##
## 这样本地与远端走**完全同一条施力代码路径**，
## "第一人称交互力的实际作用点与多人世界一致"才有保证。

enum Kind {
	GRAB,        ## 抓握（准星选中的物体）
	RELEASE,     ## 松手（保留惯性）
	THROW,       ## 抛掷（按质量给冲量）
	ROTATE,      ## 旋转持有物（±度）
	PUSH,        ## 用身体推（方向 + 强度）
	NONE,
}

var kind: Kind = Kind.NONE
## 玩家身份。
var player_id: int = 1
## 目标刚体（GRAB / RELEASE / THROW 时为 null 表示"当前持有物"）。
var target: Node = null
## 意图发生时的相机世界坐标与前向（远端代理据此重建作用点）。
var eye: Vector3 = Vector3.ZERO
var forward: Vector3 = Vector3.FORWARD
## 输入强度 0..1（PUSH / 抓握力度）。
var strength: float = 1.0
## ROTATE 的角度（度）。
var degrees: float = 0.0
## 意图时间戳（秒）。主机用它丢弃过期意图。
var stamp: float = 0.0


static func make(p_kind: Kind, p_player_id: int, p_target: Node = null) -> LISFirstPersonIntent:
	var it := LISFirstPersonIntent.new()
	it.kind = p_kind
	it.player_id = p_player_id
	it.target = p_target
	it.stamp = float(Time.get_ticks_msec()) / 1000.0
	return it


func describe() -> String:
	return "Intent(%s pid=%d target=%s s=%.2f)" % [
		Kind.keys()[kind], player_id,
		str(target.name) if target != null else "none", strength]
