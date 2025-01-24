# NoUPSPoweroff

## Problem Statement

The remote server relies on a basic UPS that lacks advanced monitoring capabilities. To ensure the server can be gracefully shut down during a power outage, we need an external method to monitor the power state by using the battery status of another device (e.g., laptop).

### Solution Evaluation

**Benefits:**
- No additional hardware needed
- Simple implementation
- Quick response to power outages

**Considerations:**
- Depends on the laptop being operational
- Single point of monitoring
- Network connectivity required

## Warning

When executing `sudo poweroff`, this assumes the hypervisor can gracefully shut down VMs (e.g., Proxmox). Make sure your hypervisor supports this.

## Prerequisites

- Linux with systemd
- `acpi` package (`sudo apt install acpi`)
- SSH key-based authentication configured
- Passwordless sudo on the remote machine

# Installation

1. Clone the repository and prepare the script:
    ```bash
    git clone https://github.com/vwkyc/NoUPSPoweroff.git
    cd NoUPSPoweroff
    chmod +x NoUPSPoweroff.sh
    ```

## Configuration

1. edit the configuration file `NoUPSPoweroff.conf`

2. Edit username in `NoUPSPoweroff.service`

3. Install the script and service:
    ```bash
    sudo install -m 755 NoUPSPoweroff.sh /usr/local/bin/
    sudo cp NoUPSPoweroff.service /etc/systemd/system/
    sudo cp NoUPSPoweroff.conf /etc/
    sudo systemctl daemon-reload
    sudo systemctl enable NoUPSPoweroff.service --now
    ```

## Remote Poweroff

Allow passwordless poweroff on the remote server:

1. Allow the user `USERNAME` to execute `sudo poweroff` without a password:
    ```bash
    sudo visudo
    ```

2. Add the following line at the end:
    ```plaintext
    USERNAME ALL=(ALL) NOPASSWD: /sbin/poweroff, /sbin/reboot, /sbin/shutdown
    ```

## UPS Runtime Calculation

To determine the appropriate `MINUTES` value for the script, you need to calculate the expected runtime of your server on the UPS. Follow these steps:

1. **Identify Your Server's Power Consumption**:
   - Measure the power usage of your server in watts (W). This can be found in the server's documentation or by using a power meter.

2. **Determine Your UPS Battery's Capacity**:
   - Find the battery's capacity, typically expressed in ampere-hours (Ah) and voltage (V). This information is usually provided by the UPS manufacturer.

3. **Calculate the Battery's Total Energy Storage**:
   - Use the formula:
     ```plaintext
     Battery Energy (Wh) = Battery Capacity (Ah) × Battery Voltage (V)
     ```

4. **Estimate the UPS Runtime**:
   - Apply the formula:
     ```plaintext
     Runtime (hours) = Battery Energy (Wh) / Server Power Consumption (W)
     ```
   - Convert the runtime to minutes by multiplying by 60.

### Example Calculation

Assume your server consumes 90 W, and your UPS has a battery capacity of 7.0 Ah at 12 V:

1. **Calculate Total Battery Energy**:
   ```plaintext
   7.0 Ah × 12 V = 84 Wh
   ```

2. **Determine Runtime**:
   ```plaintext
   Runtime (hours) = 84 Wh / 90 W = 0.933 hours = 56 minutes
   ```

In this scenario, the estimated runtime is approximately 56 minutes. To ensure a safe shutdown before the UPS battery is fully depleted, it's advisable to set the MINUTES variable in your script to a value slightly less than this estimate, accounting for factors like battery aging and efficiency losses.

## Status & Logs

Monitor the service status and logs:
```bash
systemctl status NoUPSPoweroff.service
journalctl -u NoUPSPoweroff.service -f
```

## Troubleshooting

1. Check permissions:
    ```bash
    ls -l /usr/local/bin/NoUPSPoweroff.sh
    ```

2. Check logs:
    ```bash
    journalctl -u NoUPSPoweroff.service -f
    ```

## Uninstallation

To disable and remove the NoUPSPoweroff service, follow these steps:

1. Stop and disable the service:
    ```bash
    sudo systemctl stop NoUPSPoweroff.service
    sudo systemctl disable NoUPSPoweroff.service
    ```

2. Remove the service file and script:
    ```bash
    sudo rm /etc/systemd/system/NoUPSPoweroff.service
    sudo rm /usr/local/bin/NoUPSPoweroff.sh
    ```

3. Reload the systemd daemon to apply changes:
    ```bash
    sudo systemctl daemon-reload
    ```
