# njackd + njackctl

JACK Audio Connection Kit volume manager daemon and control CLI.

**njackd** — daemon that monitors JACK clients and inserts volume control proxies.
**njackctl** — CLI to query and control the daemon.

## Architecture

```
app → app-sink:in → [per-app gain] → app-sink:out → device-sink:in → [master gain] → device-sink:out → system:playback
```

Each application gets its own proxy client (`{name}-sink`) for per-app volume.
A device proxy (`device-sink`) sits between all app proxies and system for
master volume. Both proxies are run in the JACK RT thread and only apply
gain — no resampling or mixing.

## Usage

```sh
njackd                         # start daemon (foreground)
njackd --version               # show version
njackctl list                  # list clients with volumes
njackctl set-volume <client> <0.0-1.0>
njackctl get-volume <client>
njackctl set-master-volume <0.0-1.0>
njackctl get-master-volume
njackctl monitor               # real-time client updates
njackctl status                # daemon status (clients, xruns, uptime)
njackctl config                # show configuration
njackctl config set <key> <value>
njackctl config reset          # reset config to defaults
njackctl quit                  # shutdown daemon
```

**njackd auto-starts the JACK server** if it isn't already running.
Only one njackd instance can run at a time (socket lock).

## Configuration

Config file: `~/.config/njackd/config.json`

| Key | Default | Description |
|-----|---------|-------------|
| `default_volume` | `0.75` | Default per-app volume |
| `master_volume` | `1.0` | Master volume (device proxy) |
| `ignored_clients` | `[]` | Client names to skip |
| `poll_interval` | `2.0` | Seconds between port scans |
| `socket_path` | `$XDG_RUNTIME_DIR/njackd.sock` | IPC socket path |

## PortAudio / Firefox

PortAudio auto-reconnects its ports to `system:playback` when it detects a
disconnection. njackd enforces proxy routes every scan cycle: if an app
port is found directly connected to system, it is disconnected and
re-routed through the per-app proxy.

## Build

```sh
cd neojack
nimble build
```

Requires `jacket` (nimble package) and libjack at runtime.
