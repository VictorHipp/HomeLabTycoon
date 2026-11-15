class_name Shell
extends RefCounted
## Command interpreter of one terminal session on a simulated host (docs/TERMINAL_DESIGN.md §4–6).
## Prototype set: help, clear, echo, hostname, whoami, history, exit, ip, ping.
## Honesty rule: real commands not implemented yet say so; unknown ones answer like bash.
## Output formats imitate the real tools; exact texts per locale are [POR VERIFICAR].

const IMPLEMENTED: PackedStringArray = ["help", "clear", "echo", "hostname", "whoami", "history", "exit", "ip", "ping"]
const KNOWN_UNIMPLEMENTED: PackedStringArray = [
	"ls", "cd", "pwd", "cat", "mkdir", "touch", "rm", "rmdir", "cp", "mv", "ln", "find", "tree", "grep",
	"less", "more", "head", "tail", "nano", "vi", "vim", "chmod", "chown", "chgrp", "umask", "sudo", "su",
	"useradd", "usermod", "userdel", "passwd", "groups", "id", "ps", "top", "htop", "kill", "killall",
	"systemctl", "journalctl", "service", "apt", "apt-get", "dpkg", "ss", "netstat", "ifconfig", "route",
	"arp", "dhclient", "netplan", "nmcli", "ssh", "scp", "rsync", "curl", "wget", "dig", "nslookup", "host",
	"traceroute", "tracepath", "mtr", "df", "du", "free", "mount", "umount", "lsblk", "fdisk", "uname",
	"date", "uptime", "env", "export", "alias", "which", "man", "tar", "gzip", "crontab", "reboot",
	"shutdown", "poweroff", "who", "w", "last", "ip6tables", "iptables", "nft", "ufw"]
const PING_KNOWN_OPTIONS: PackedStringArray = ["-i", "-W", "-w", "-s", "-t", "-q", "-4", "-6", "-I", "-n", "-v", "-f", "-D"]
const PING_DEFAULT_COUNT := 4
const PING_MAX_COUNT := 50

var device_id: int
var user: String
var history: Array[String] = []


func _init(on_device: int, login_user: String) -> void:
	device_id = on_device
	user = login_user


func prompt(world: SimWorld) -> String:
	var host := world.get_device(device_id).host
	return "%s@%s:~%s " % [user, host.hostname, "#" if user == "root" else "$"]


## Runs one line. Returns {"output": String, "clear": bool, "exit": bool}.
func run(world: SimWorld, line: String) -> Dictionary:
	var result := {"output": "", "clear": false, "exit": false}
	var text := line.strip_edges()
	if text.is_empty():
		return result
	history.append(text)
	var tokens := _tokenize(text)
	if tokens.is_empty():
		result["output"] = TranslationServer.translate("bash: error sintáctico: falta cerrar unas comillas")
		return result
	for token: Dictionary in tokens:
		if token["op"] in ["|", ">", ">>", "<", "&"]:
			result["output"] = TranslationServer.translate("bash: las tuberías, las redirecciones y los procesos en segundo plano («%s») aún no están implementados en HomeLab Tycoon.") % token["op"]
			return result
	var outputs: Array[String] = []
	var status := 0
	var words: Array[String] = []
	var pending_op := ";"
	tokens.append({"op": ";", "word": ""})
	for token: Dictionary in tokens:
		if token["op"] == "":
			words.append(token["word"])
			continue
		if not words.is_empty():
			var skip := (pending_op == "&&" and status != 0) or (pending_op == "||" and status == 0)
			if not skip:
				var r := _execute(world, words)
				status = r["status"]
				if r["output"] != "":
					outputs.append(r["output"])
				if r.get("clear", false):
					result["clear"] = true
					outputs.clear()
				if r.get("exit", false):
					result["exit"] = true
					break
		words = []
		pending_op = token["op"]
	result["output"] = "\n".join(outputs)
	return result


# --------------------------------------------------------------- tokenizer --

## Words and operators. Returns [] when a quote is left open.
func _tokenize(text: String) -> Array[Dictionary]:
	var tokens: Array[Dictionary] = []
	var word := ""
	var has_word := false
	var quote := ""
	var i := 0
	while i < text.length():
		var c := text[i]
		if quote != "":
			if c == quote:
				quote = ""
			elif c == "\\" and quote == "\"" and i + 1 < text.length():
				i += 1
				word += text[i]
			else:
				word += c
		elif c == "'" or c == "\"":
			quote = c
			has_word = true
		elif c == "\\" and i + 1 < text.length():
			i += 1
			word += text[i]
			has_word = true
		elif c == " " or c == "\t":
			if has_word:
				tokens.append({"op": "", "word": word})
				word = ""
				has_word = false
		else:
			var op := ""
			for candidate: String in ["&&", "||", ">>", ";", "|", ">", "<", "&"]:
				if text.substr(i, candidate.length()) == candidate:
					op = candidate
					break
			if op != "":
				if has_word:
					tokens.append({"op": "", "word": word})
					word = ""
					has_word = false
				tokens.append({"op": op, "word": ""})
				i += op.length() - 1
			else:
				word += c
				has_word = true
		i += 1
	if quote != "":
		return []
	if has_word:
		tokens.append({"op": "", "word": word})
	return tokens


# ---------------------------------------------------------------- dispatch --

func _execute(world: SimWorld, words: Array[String]) -> Dictionary:
	var name := words[0]
	var args := words.slice(1)
	var host := world.get_device(device_id).host
	match name:
		"help":
			return _ok(_help())
		"clear":
			return {"status": 0, "output": "", "clear": true}
		"echo":
			if not args.is_empty() and args[0] == "-n":
				args = args.slice(1)
			return _ok(" ".join(args))
		"hostname":
			if not args.is_empty():
				return _err(TranslationServer.translate("hostname: cambiar el nombre del equipo aún no está implementado en HomeLab Tycoon."), 1)
			return _ok(host.hostname)
		"whoami":
			return _ok(user)
		"history":
			var lines: Array[String] = []
			for i: int in history.size():
				lines.append("%5d  %s" % [i + 1, history[i]])
			return _ok("\n".join(lines))
		"exit":
			return {"status": 0, "output": "", "exit": true}
		"ip":
			return ShellIp.run(world, self, args)
		"ping":
			return _ping(world, args)
	if KNOWN_UNIMPLEMENTED.has(name):
		return _err(TranslationServer.translate("%s: es una orden real de Linux, pero aún no está implementada en HomeLab Tycoon. Escribe «help» para ver las disponibles.") % name, 127)
	return _err(TranslationServer.translate("bash: %s: orden no encontrada") % name, 127)


func _help() -> String:
	return "\n".join([
		TranslationServer.translate("Órdenes disponibles en esta versión de HomeLab OS:"),
		"  ip address [show]                 " + TranslationServer.translate("ver interfaces y direcciones"),
		"  ip address add IP/PREFIJO dev IF  " + TranslationServer.translate("añadir una dirección (root)"),
		"  ip address del IP/PREFIJO dev IF  " + TranslationServer.translate("quitar una dirección (root)"),
		"  ip link [show] | ip link set IF up|down",
		"  ip route [show] | ip route add default via IP",
		"  ping [-c N] DESTINO               " + TranslationServer.translate("comprobar la conectividad"),
		"  hostname · whoami · echo · history · clear · exit",
		TranslationServer.translate("Más órdenes llegarán en próximas versiones; las que aún no existen te lo dirán."),
	])


func _ping(world: SimWorld, args: Array[String]) -> Dictionary:
	var count := PING_DEFAULT_COUNT
	var explicit := false
	var target := ""
	var i := 0
	while i < args.size():
		var a := args[i]
		if a == "-c":
			if i + 1 >= args.size() or not args[i + 1].is_valid_int() or args[i + 1].to_int() < 1:
				return _err("ping: invalid argument: '%s'" % (args[i + 1] if i + 1 < args.size() else ""), 2)
			count = mini(args[i + 1].to_int(), PING_MAX_COUNT)
			explicit = true
			i += 2
			continue
		if a.begins_with("-c") and a.length() > 2 and a.substr(2).is_valid_int():
			count = mini(a.substr(2).to_int(), PING_MAX_COUNT)
			explicit = true
		elif a.begins_with("-"):
			if PING_KNOWN_OPTIONS.has(a):
				return _err(TranslationServer.translate("ping: la opción «%s» existe en la herramienta real, pero aún no está implementada en HomeLab Tycoon.") % a, 2)
			return _err("ping: invalid option -- '%s'" % a.trim_prefix("-"), 2)
		else:
			target = a
		i += 1
	if target == "":
		return _err("ping: usage error: Destination address required", 1)
	var r := NetworkEngine.ping(world, world.get_device(device_id), target, count)
	var output: String = r["output"]
	if not explicit and r["received"] >= 0 and output.begins_with("PING"):
		output += "\n" + TranslationServer.translate("(Nota del juego: sin -c, ping se detiene tras %d paquetes; el ping real sigue hasta que pulsas Ctrl+C.)") % PING_DEFAULT_COUNT
	return {"status": 0 if r["received"] > 0 else 1, "output": output}


static func _ok(text: String) -> Dictionary:
	return {"status": 0, "output": text}


static func _err(text: String, status: int) -> Dictionary:
	return {"status": status, "output": text}
