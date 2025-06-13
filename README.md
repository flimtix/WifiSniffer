# Public Wi-Fi Security Demo: Manual Setup Guide

> **Goal:**
> Set up an open Wi-Fi hotspot that allows guests to access the internet.
> All DNS queries from connected devices are logged to demonstrate how visible your traffic is on public Wi-Fi.

---

## Requirements

- **1x Laptop** with Kali Linux (or any modern Linux with systemd)
- **1x Ethernet interface** (for internet connection)
- **1x Wi-Fi interface** (supports AP/monitor mode)
- **Root access** on the machine

---

## 1. Preparation

### 1.1. Install Required Packages

```bash
sudo apt update
sudo apt install hostapd dnsmasq iptables -y
```

### 1.2. Identify Network Interfaces

Find the names of your interfaces:

```bash
ip link
```

- Example: `eth0` for ethernet, `wlan0` for Wi-Fi.

**Write down these names!**
- (In the examples below, replace them as needed.)*

---

## 2. Network Interfaces Setup

### 2.1. Bring Interfaces Up

```bash
sudo ip link set wlan0 up
sudo ip link set eth0 up
```

### 2.2. Set Wi-Fi Interface Mode (AP/Managed Mode)

```bash
sudo ip link set wlan0 down
sudo iw dev wlan0 set type managed
sudo ip link set wlan0 up
```

If your card needs `iwconfig` instead:

```bash
sudo iwconfig wlan0 mode managed
```

---

## 3. Assign Static IP to Wi-Fi

Set the Wi-Fi interface to a static IP (e.g. 10.0.0.1):

```bash
sudo ip addr flush dev wlan0
sudo ip addr add 10.0.0.1/24 dev wlan0
```

---

## 4. Configure hostapd (Wi-Fi Access Point)

### 4.1. Create the hostapd Configuration File

```bash
sudo nano /etc/hostapd/hostapd.conf
```

Paste the following (edit SSID and channel as you wish):

```
interface=wlan0
driver=nl80211
ssid=WifiDemo
hw_mode=g
channel=1
```

### 4.2. Edit hostapd Default File

Set the config file location for systemd:

```bash
sudo nano /etc/default/hostapd
```

Add or edit the line:

```
DAEMON_CONF="/etc/hostapd/hostapd.conf"
```

---

## 5. Configure dnsmasq (DHCP and DNS)

### 5.1. Backup and Edit dnsmasq.conf

```bash
sudo mv /etc/dnsmasq.conf /etc/dnsmasq.conf.bak
sudo nano /etc/dnsmasq.conf
```

Paste the following:

```
interface=wlan0
dhcp-range=10.0.0.10,10.0.0.250,12h
dhcp-option=3,10.0.0.1
dhcp-option=6,10.0.0.1
log-queries
log-facility=/var/log/dnsmasq.log
```

---

## 6. Enable IP Forwarding

### 6.1. Temporary (for current session):

```bash
sudo sysctl -w net.ipv4.ip_forward=1
```

### 6.2. Permanent (for reboots):

```bash
sudo nano /etc/sysctl.conf
```

Add or edit this line:

```
net.ipv4.ip_forward=1
```

---

## 7. Set Up NAT with iptables

Replace `eth0` with your internet interface name!

```bash
sudo iptables -t nat -F
sudo iptables -F
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
sudo iptables -A FORWARD -i wlan0 -o eth0 -j ACCEPT
sudo iptables -A FORWARD -i eth0 -o wlan0 -m state --state ESTABLISHED,RELATED -j ACCEPT
```

---

## 8. Start the Services

### 8.1. Start hostapd

```bash
sudo systemctl unmask hostapd
sudo systemctl enable hostapd
sudo systemctl start hostapd
```

Check status:

```bash
sudo systemctl status hostapd
```

### 8.2. Start dnsmasq

```bash
sudo systemctl enable dnsmasq
sudo systemctl restart dnsmasq
```

Check status:

```bash
sudo systemctl status dnsmasq
```

---

## 9. Connect and Test

- Connect a device to the Wi-Fi network (`WifiDemo` or your SSID).
- It should receive an IP in the range (e.g. 10.0.0.10+).
- Try opening a website on the device to test internet access.

---

## 10. Watch DNS Queries in Real Time

See which domains are being requested (demo effect!):

```bash
sudo tail -f /var/log/dnsmasq.log | grep query
```

---

## 11. After the Demo: Cleanup

To clean up and revert:

```bash
sudo systemctl stop hostapd
sudo systemctl stop dnsmasq
sudo iptables -F
sudo iptables -t nat -F
sudo sysctl -w net.ipv4.ip_forward=0
sudo ip addr flush dev wlan0
```

- (Optionally restore your backup configs if you made them.)*

---

## Summary Table

| Step | Command or File             | Purpose                        |
| ---- | --------------------------- | ------------------------------ |
| 1    | `apt install`               | Install packages               |
| 2    | `ip link`                   | Identify and enable interfaces |
| 3    | `ip addr`                   | Assign static IP to Wi-Fi      |
| 4    | `/etc/hostapd/hostapd.conf` | Configure Wi-Fi AP             |
| 5    | `/etc/dnsmasq.conf`         | DHCP & DNS settings            |
| 6    | `sysctl`                    | Enable IP forwarding           |
| 7    | `iptables`                  | Setup NAT for internet access  |
| 8    | `systemctl`                 | Start hostapd and dnsmasq      |
| 9    | `tail /var/log/dnsmasq.log` | View DNS queries               |

---

## Troubleshooting

- **Wi-Fi not showing up?**
  Check if your Wi-Fi card supports AP/monitor mode.
- **Clients get no IP?**
  Check dnsmasq status and config.
- **No internet for clients?**
  Check iptables rules and IP forwarding.

---

> **Note:**
> This setup is intended for scientific demo/awareness only.
> Do not use it for malicious purposes or on networks without permission.
