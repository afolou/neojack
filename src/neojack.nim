import std/[os]
import neojack/daemon

proc main() =
  let args = commandLineParams()
  let socketPath = getEnv("XDG_RUNTIME_DIR", "/tmp") / "neojack.sock"

  if args.len == 0 or args[0] == "start":
    runDaemon(socketPath)
  elif args[0] == "list":
    echo sendCommand(socketPath, "list")
  elif args[0] == "set-volume":
    if args.len < 3:
      quit("Usage: neojack set-volume <client> <volume>")
    echo sendCommand(socketPath, "set-volume " & args[1] & " " & args[2])
  elif args[0] == "monitor":
    monitorMode(socketPath)
  else:
    quit("Usage: neojack [start|list|set-volume <client> <volume>|monitor]")

main()
