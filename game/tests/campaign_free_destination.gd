extends SceneTree

## 临时自由选星开关：确认四颗星球都不再被起飞核心/归航资源门槛拦住。
## 该测试不修改正式默认，只显式打开 CampaignNavigation.debug_free_destination。

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	var nav := CampaignNavigation.new()
	nav.enabled = true
	nav.navigation_restored = false
	nav.energy = 0
	nav.supplies = 0
	nav.debug_free_destination = true
	for destination: String in ["demo", "electromagnetic", "ruin", "earth"]:
		check(nav.block_reason(destination).is_empty(), "自由选星仍拦截 %s：%s" % [destination, nav.block_reason(destination)])
		check(nav.depart(destination), "自由选星无法出发到 %s" % destination)
		check(nav.location == destination, "自由选星出发后位置不对：%s" % destination)

	nav.debug_free_destination = false
	nav.location = "demo"
	nav.grounded = true
	nav.home_reached = false
	check(not nav.block_reason("demo").is_empty(), "关闭调试后起飞核心限制没有恢复")
	check(not nav.depart("earth"), "关闭调试后仍然可以直接返航地球")

	print("CAMPAIGN_FREE_DESTINATION: %d checks, %d failures" % [checks, failures.size()])
	quit(1 if failures.size() > 0 else 0)


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)
