import std/[os, strutils, strformat]
import njackd/[daemon, config]

proc showHelp() =
   echo """njackctl — control njackd daemon

Usage:
  njackctl <command> [args]

Commands:
  list                          List monitored clients with current volumes
  set-volume <client> <0.0-1.0> Set volume for a client
  get-volume <client>           Show current volume for a client
  mute <client>                 Mute a client (volume 0, restores on unmute)
  unmute <client>               Unmute a client (restores previous volume)
  set-master-volume <0.0-1.0>   Set master volume
  get-master-volume             Show current master volume
  monitor                       Subscribe to real-time client updates
  status                        Show daemon status
  config                        Show current configuration
  config set <key> <value>      Set a config value and save
  config reset                  Reset config to defaults
  quit                          Shut down the daemon
  help                          Show this help"""

proc cmdConfig(args: seq[string]) =
  if args.len == 0:
    let cfg = loadConfig()
    echo "Config file: ", configPath()
    echo "  default_volume = ", cfg.defaultVolume
    echo "  master_volume = ", cfg.masterVolume
    echo "  ignored_clients = ", cfg.ignoredClients.join(", ")
    echo "  poll_interval = ", cfg.pollInterval
    echo "  socket_path = ", cfg.socketPath

  elif args.len >= 2 and args[0] == "set":
    let key = args[1]
    let value = args[2..^1].join(" ")
    var cfg = loadConfig()
    case key
    of "default_volume":
      cfg.defaultVolume = parseFloat(value)
    of "master_volume":
      cfg.masterVolume = parseFloat(value)
    of "ignored_clients":
      cfg.ignoredClients = value.splitWhitespace()
    of "poll_interval":
      cfg.pollInterval = parseFloat(value)
    of "socket_path":
      cfg.socketPath = value
    else:
      quit("error: unknown config key: " & key)
    saveConfig(cfg)
    echo "ok: ", key, " = ", value

  elif args.len == 1 and args[0] == "reset":
    deleteConfig()
    echo "ok: config reset to defaults"

  else:
    echo "Usage: njackctl config [set <key> <value>|reset]"

proc main() =
  let args = commandLineParams()
  if args.len == 0:
    showHelp()
    return

  if args.len == 1 and args[0] == "--version":
    echo "njackctl " & Version
    return

  let cfg = loadConfig()
  let sock = cfg.socketPath

  case args[0]
  of "list":
    let resp = sendCommand(sock, "list")
    if resp.startsWith("ok:"):
      let items = resp[3..^1].split(',')
      if items.len == 0 or items[0] == "":
        echo "No clients monitored."
      else:
        echo "CLIENT".alignLeft(26) & " " & "VOLUME".alignLeft(10) & " MUTE"
        echo repeat('-', 42)
        for item in items:
          let parts = item.split({'=', ':'})
          if parts.len >= 2:
            let vol = parseFloat(parts[1])
            let muted = parts.len >= 3 and parts[2] == "1"
            let bar = repeat("█", int(vol * 20))
            let muteTag = if muted: "M" else: " "
            echo &"{parts[0]:<26} {vol:<8.2f} {bar} {muteTag}"
    else:
      echo resp

  of "set-volume":
    if args.len < 3:
      quit("Usage: njackctl set-volume <client> <0.0-1.0>")
    let resp = sendCommand(sock, "set-volume " & args[1] & " " & args[2])
    echo resp

  of "get-volume":
    if args.len < 2:
      quit("Usage: njackctl get-volume <client>")
    let resp = sendCommand(sock, "get-volume " & args[1])
    if resp.startsWith("ok:"):
      echo resp[3..^1]
    else:
      echo resp

  of "mute":
    if args.len < 2:
      quit("Usage: njackctl mute <client>")
    let resp = sendCommand(sock, "mute " & args[1])
    echo resp

  of "unmute":
    if args.len < 2:
      quit("Usage: njackctl unmute <client>")
    let resp = sendCommand(sock, "unmute " & args[1])
    echo resp

  of "set-master-volume":
    if args.len < 2:
      quit("Usage: njackctl set-master-volume <0.0-1.0>")
    let resp = sendCommand(sock, "set-master-volume " & args[1])
    echo resp

  of "get-master-volume":
    let resp = sendCommand(sock, "get-master-volume")
    if resp.startsWith("ok:"):
      echo resp[3..^1]
    else:
      echo resp

  of "monitor":
    monitorMode(sock)

  of "status":
    let resp = sendCommand(sock, "status")
    if resp.startsWith("ok:"):
      for part in resp[3..^1].split('|'):
        let kv = part.split('=')
        if kv.len == 2:
          echo &"{kv[0]}: {kv[1]}"
    else:
      echo resp

  of "config":
    cmdConfig(args[1..^1])

  of "quit":
    let resp = sendCommand(sock, "quit")
    echo resp

  of "help":
    showHelp()

  else:
    showHelp()

main()
