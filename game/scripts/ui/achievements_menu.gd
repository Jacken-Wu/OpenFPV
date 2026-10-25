class_name AchievementsMenu
extends PanelContainer
signal closed
var store: ProgressStore
var rows: Dictionary = {}
func _ready() -> void:
	theme = UIStyle.theme()
	custom_minimum_size = Vector2(980, 760)
	var column := UIStyle.column(self, 10)
	column.add_child(UIStyle.label("探索成就", 28, Color("70d7cb")))
	column.add_child(UIStyle.label("记录当前世界的探索与收集 · 无额外奖励", 17))
	var progress := AchievementBook.counts(store.data, store.catalog)
	var earned := 0
	for definition: AchievementDefinition in store.catalog.manifest.achievements:
		earned += int(store.data.achievements.unlocked.has(definition.id))
	column.add_child(UIStyle.label("已解锁 %d / %d" % [earned, store.catalog.manifest.achievements.size()], 20))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var list := GridContainer.new()
	list.columns = 2
	list.add_theme_constant_override("h_separation", 12)
	list.add_theme_constant_override("v_separation", 10)
	scroll.add_child(list)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for definition: AchievementDefinition in store.catalog.manifest.achievements:
		var unlocked: bool = store.data.achievements.unlocked.has(definition.id)
		var total := AchievementBook.target(definition, store.catalog)
		var text := "%s  %s · %d / %d\n%s" % ["◆" if unlocked else "◇", definition.display_name, mini(progress[definition.metric], total), total, definition.description]
		if unlocked:
			text += "\n解锁于 " + String(store.data.achievements.unlocked[definition.id]).replace("T", " ")
		var card := PanelContainer.new()
		card.custom_minimum_size.x = 440
		list.add_child(card)
		var label := UIStyle.label(text, 17, Color("e5ca88") if unlocked else Color("b3c9d2"))
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(label)
		rows[definition.id] = label
	column.add_child(UIStyle.button("返回", func(): closed.emit()))
