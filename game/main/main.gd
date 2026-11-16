class_name GameLauncher
extends Node
## Entry point (game/main/main.tscn): the title screen, or straight into a game when one is
## waiting: a new game from the character creator or a loaded save (both reload this scene, so no
## view keeps state from before). The walkthrough (tools/walkthrough.ps1) also starts a game
## directly, except in the scenarios that go through the title, and so does `-- --new-game`
## (tools/check_project.ps1 runs the game that way).

## Walkthrough scenarios that start on the title screen (game/debug/walkthrough_driver.gd).
const TITLE_SCENARIOS: PackedStringArray = ["menu", "manual"]

var session: GameSession = null
var title: TitleScreen = null


func _ready() -> void:
	InputBindings.ensure_defaults()
	if GameSession.has_pending_start() or _starts_in_game():
		session = GameSession.new()
		session.name = "Session"
		add_child(session)
		return
	title = TitleScreen.new()
	title.name = "Title"
	add_child(title)
	if WalkthroughDriver.requested_dir() != "":
		WalkthroughDriver.attach_title(title)


static func _starts_in_game() -> bool:
	if OS.get_cmdline_user_args().has("--new-game"):
		return true
	return WalkthroughDriver.requested_dir() != "" and not TITLE_SCENARIOS.has(WalkthroughDriver.requested_scenario())


## Starts a new game with this look (from the character creator).
static func start_new_game(tree: SceneTree, look: Dictionary) -> void:
	GameSession.prepare_new_game(look)
	_reload(tree)


## Loads the saved game. Returns {"ok", "message"}; on success the scene is rebuilt with it.
static func load_saved_game(tree: SceneTree) -> Dictionary:
	var r := SaveService.read()
	if not r["ok"]:
		return r
	GameSession.prepare_load(r["document"])
	_reload(tree)
	return {"ok": true, "message": TranslationServer.translate("Cargando la partida…")}


## Leaves the game for the title screen (whatever was not saved is lost).
static func back_to_title(tree: SceneTree) -> void:
	GameSession.clear_pending()
	_reload(tree)


static func _reload(tree: SceneTree) -> void:
	tree.paused = false
	tree.reload_current_scene.call_deferred()
