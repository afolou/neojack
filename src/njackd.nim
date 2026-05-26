import std/[os, logging]
import njackd/[daemon, config]

proc main() =
  let args = commandLineParams()

  if args.len == 1 and args[0] == "--version":
    echo "njackd " & Version
    return

  if args.len > 0 and args[0] != "start":
    quit("Usage: njackd [--version]")

  let cfg = loadConfig()
  addHandler(newConsoleLogger(lvlInfo))
  runDaemon(cfg)

main()
