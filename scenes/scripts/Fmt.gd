extends RefCounted
## Stateless UI formatting helpers.

const SECONDS_PER_MINUTE: float = 60.0
const SECONDS_PER_HOUR: float = 3600.0
const SECONDS_PER_DAY: float = 86400.0


static func duration(seconds: float) -> String:
	var total: float = maxf(0.0, ceilf(seconds))
	var days: int = floori(total / SECONDS_PER_DAY)
	var hours: int = floori(fmod(total, SECONDS_PER_DAY) / SECONDS_PER_HOUR)
	var minutes: int = floori(fmod(total, SECONDS_PER_HOUR) / SECONDS_PER_MINUTE)
	var secs: int = floori(fmod(total, SECONDS_PER_MINUTE))
	if days > 0:
		return "%dд %dч" % [days, hours]
	if hours > 0:
		return "%dч %dм" % [hours, minutes]
	if minutes > 0:
		return "%dм %dс" % [minutes, secs]
	return "%dс" % secs


static func reward(grant: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	if grant.has("coins"):
		parts.append("%d монет" % int(grant["coins"]))
	if grant.has("seeds"):
		parts.append("%d семян" % int(grant["seeds"]))
	if grant.has("feed"):
		parts.append("%d корма" % int(grant["feed"]))
	if grant.has("xp"):
		parts.append("%d опыта" % int(grant["xp"]))
	return ", ".join(parts)
