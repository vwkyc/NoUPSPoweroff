# BlackoutGrace

## Overview

BlackoutGrace is a lightweight utility that detects mains power loss from a battery-powered monitoring host and performs graceful shutdowns of remote servers via SSH. It's designed for simple UPS setups without monitoring functionality.

Key features:
- No extra hardware required
- Multi-server support via SSH
- Configurable shutdown delay and battery thresholds
- Stable-power detection to avoid reacting to short flickers

## Installation

Clone the repository and make the script executable:

```bash
git clone https://github.com/vwkyc/blackoutgrace.git
cd blackoutgrace
chmod +x blackoutgrace.sh
```

## Deployment

1. Copy files to system locations (adjust usernames as needed):

```bash
sudo install -m 755 blackoutgrace.sh /usr/local/bin/
sudo cp blackoutgrace.service /etc/systemd/system/
sudo cp blackoutgrace.conf /etc/
```

2. Reload systemd and enable the service:

```bash
sudo systemctl daemon-reload
sudo systemctl enable blackoutgrace.service --now
```

## Configuration

Edit `/etc/blackoutgrace.conf` to set the shutdown delay, battery thresholds, and the target servers (use `[serverN]` sections with `user` and `host` keys).

Core parameters in the `[general]` section include:
- `minutes`: Shutdown delay on battery power (default: 25)
- `sleep_interval`: Check frequency in seconds (default: 5)
- `min_battery`: Critical battery threshold for immediate shutdown (default: 10)
- `ac_stable_time`: Time AC must remain stable before cancelling shutdown (default: 300)

## Server setup

Ensure the target servers allow passwordless sudo for shutdown commands and that SSH key-based authentication is configured.

Add to sudoers (via `visudo`) on each target server:

```text
USERNAME ALL=(ALL) NOPASSWD: /sbin/poweroff, /sbin/reboot, /sbin/shutdown
```

## Monitoring & Logs

View status and logs with systemd/journalctl:

```bash
sudo systemctl status blackoutgrace.service
journalctl -u blackoutgrace.service -f
```

## Uninstallation

To remove the service and script:

```bash
sudo systemctl stop blackoutgrace.service
sudo systemctl disable blackoutgrace.service
sudo rm /etc/systemd/system/blackoutgrace.service
sudo rm /usr/local/bin/blackoutgrace.sh
sudo systemctl daemon-reload
```
