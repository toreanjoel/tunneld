# Tunneld Build & Deploy Runbook

End-to-end steps for building the release on a Mac, deploying it to a tunneld device,
and standing up a NanoPi NEO 3 as a managed machine to test macvlan networking.

> **Who this is for:** a human or an agent that needs to (1) build, (2) deploy, (3) test.
> Each section is self-contained and copy-pasteable.

---

## 1. Build the release on a Mac

### 1.1 Prerequisite: Docker

The build runs inside the official `elixir:1.17-slim` Docker image. **Check Docker first:**

```bash
command -v docker && docker version --client >/dev/null 2>&1 \
  && echo "Docker OK" || echo "Docker MISSING"
```

- If **Docker is missing**, install it first:
  - macOS: `brew install --cask docker` (then open Docker Desktop once and let it start).
  - Linux: `curl -fsSL https://get.docker.com | sh`
- If Docker is installed but the daemon isn't running, start Docker Desktop / `sudo systemctl start docker`.

### 1.2 Run the builder

From the repo root:

```bash
cd /Users/toreanjoel/work/personal/tunneld
./build_release.sh
```

**macOS adaptations** (the script was written for Linux; on macOS):
- The script calls `sudo docker` and `sha256sum`. On macOS Docker Desktop, `sudo` is usually
  unnecessary and `sha256sum` doesn't exist. Use a patched copy:

```bash
sed -e 's/sudo docker/docker/g' \
    -e 's/sudo chown/chown/g' \
    -e 's/sha256sum/shasum -a 256/g' \
    build_release.sh > /tmp/build_release_mac.sh
chmod +x /tmp/build_release_mac.sh
/tmp/build_release_mac.sh
```

- The script deletes `mix.lock` inside the container (which is mounted from the repo). Back it
  up first and restore it after, so the repo stays clean:

```bash
cp mix.lock /tmp/mix.lock.bak
/tmp/build_release_mac.sh
cp /tmp/mix.lock.bak mix.lock
```

### 1.3 Output

The build writes to `~/tunneld_build/`:

| File | Purpose |
|------|---------|
| `tunneld-pre-alpha.tar.gz` | The compiled Elixir release (extracts into `/opt/tunneld`) |
| `checksums.txt` | SHA256 of the tarball |
| `metadata.json` | `{"version": "..."}` |

Verify the checksum matches:

```bash
cd ~/tunneld_build && shasum -a 256 tunneld-pre-alpha.tar.gz && cat checksums.txt
```

### 1.4 Stage into the installer repo (optional)

If you want the device to self-update via the installer, copy the artifacts into the
installer repo's `releases/` dir and push to GitHub:

```bash
cd /Users/toreanjoel/work/personal/tunneld-installer
cp ~/tunneld_build/tunneld-pre-alpha.tar.gz releases/
cp ~/tunneld_build/checksums.txt releases/
cp ~/tunneld_build/metadata.json releases/
git add releases/ && git commit -m "release: v$(cat releases/metadata.json | grep version | cut -d'"' -f4)" && git push
```

---

## 2. Deploy to a device (given an IP)

The device runs the tunneld gateway. The release tarball extracts into `/opt/tunneld`.

### 2.1 Copy the tarball to the device

From the Mac, replace `<user>` with the SSH user for the device (e.g. `root` or `pi`):

```bash
scp ~/tunneld_build/tunneld-pre-alpha.tar.gz <user>@<DEVICE_IP>:/tmp/
```

### 2.2 Extract and restart on the device

SSH in and run:

```bash
sudo tar -xzf /tmp/tunneld-pre-alpha.tar.gz -C /opt/tunneld
sudo systemctl restart tunneld
sudo systemctl status tunneld
```

### 2.3 Verify

From the Mac:

```bash
curl -s -o /dev/null -w "HTTP %{http_code}\n" http://<DEVICE_IP>/
# expect HTTP 200
```

If the service fails, check logs: `sudo journalctl -u tunneld -n 50`.

> **Rollback:** keep the previous tarball (`/tmp/old-tunneld-pre-alpha.tar.gz`) and re-extract
> it the same way if the new build misbehaves.

---

## 3. NanoPi NEO 3 as a managed machine + macvlan test

The NanoPi is a **managed machine** (an Incus host reached over SSH), *not* the tunneld
gateway. Tunneld creates containers on it, and a **macvlan** container gets its own MAC + DHCP
lease straight from the gateway's dnsmasq, so it appears on the subnet as an independent device.

### 3.1 Architecture check (important)

Tunneld's release is built for **ARM64**. The NanoPi only needs to run **Incus**, not the
tunneld release — but Incus requires a **64-bit OS**. Verify before going further:

```bash
uname -m   # expect aarch64 / arm64
```

If it reports `armv7l` / `armhf` (32-bit), Incus won't run and macvlan testing on this board
isn't possible — use a 64-bit board instead.

### 3.2 Install a Debian-based OS (Armbian)

1. Download the **Armbian** image for the NanoPi NEO 3 (Debian bookworm, 64-bit).
2. Flash it to a microSD card:
   ```bash
   # macOS: find the SD card device (e.g. /dev/rdisk2) and write the image
   diskutil list
   sudo dd if=Armbian_*.img of=/dev/rdisk2 bs=4m status=progress
   ```
3. Boot the NanoPi, find its IP (router DHCP), and SSH in (default user `root`, password set
   on first boot).

### 3.3 Install Incus

```bash
sudo apt update && sudo apt install -y incus
sudo incus admin init --minimal
sudo usermod -aG incus-admin "$USER"   # or the group your distro uses
```

### 3.4 Enroll the NanoPi in tunneld

1. Open the tunneld dashboard: `http://<DEVICE_IP>/`
2. **Machines → Enroll machine**, enter the NanoPi's IP + SSH port.
3. Tunneld generates an Ed25519 keypair and shows the **public half** — install it on the
   NanoPi so tunneld can SSH in:
   ```bash
   # on the NanoPi, add the shown public key to authorized_keys
   echo "<tunneld_public_key>" >> ~/.ssh/authorized_keys
   ```
4. Back in the dashboard, confirm the machine probes to **ready** and shows Incus capability.

### 3.5 Create a macvlan container (via the dashboard)

1. **Machines → the NanoPi → New Container/VM**
2. Name it (e.g. `macvlan-test`), pick an image (e.g. `ubuntu/24.04`), type **container**.
3. Set **Networking mode = macvlan**.
4. Create.

### 3.6 Verify macvlan

- **Dashboard:** the container should appear in the **Devices** list with its own MAC + IP
  (a fresh DHCP lease from the gateway's dnsmasq) — not behind the NanoPi's IP.
- **From the subnet:** ping the container's IP:
  ```bash
  ping <container_ip>
  ```
- **Underlying Incus commands** (on the NanoPi, to confirm what tunneld did):
  ```bash
  incus list
  incus config show macvlan-test
  # expect a device: eth0 nic network=lxdbr0 nictype=macvlan
  ```

> **Note:** macvlan is only valid for **containers** (not VMs) on **local** targets. A macvlan
> container is reachable from the subnet but not from the NanoPi host itself (macvlan isolation).

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `docker: command not found` | Install Docker (see 1.1) |
| `Permission denied (publickey,password)` on deploy | Wrong SSH user/key; use the device's real user |
| `systemctl restart tunneld` fails | `sudo journalctl -u tunneld -n 50` |
| `uname -m` shows `armv7l` | Board is 32-bit; Incus/macvlan won't work — use 64-bit |
| macvlan container not in Devices list | Confirm it's a container (not VM) and network=macvlan; check `incus list` on the NanoPi |

---

## 4. Verify on a HyperV Linux VM (bridge network)

The user's Windows machine runs a Linux VM via HyperV on a **bridge** network, so the VM
sits directly on the LAN (like the NanoPi). This section verifies the full machines/incus
control plane end-to-end on that VM.

### 4.1 Prerequisites on the VM

- The VM is on the LAN (bridge adapter) and reachable from the gateway.
- The VM runs a 64-bit Debian/Ubuntu-based OS (Incus requires 64-bit).
- The SSH user has passwordless sudo (or is in the `sudo` group with NOPASSWD).

### 4.2 Enroll the VM in tunneld

1. Open the tunneld dashboard: `http://<GATEWAY_IP>/`
2. **Machines → Add Machine**, enter the VM's IP + SSH port + SSH user.
3. Tunneld generates an Ed25519 keypair and shows the **public half** — install it on the VM:
   ```bash
   # on the VM
   echo "<tunneld_public_key>" >> ~/.ssh/authorized_keys
   ```
4. Back in the dashboard, click **Probe** (or wait for startup recovery). The machine should
   show **ready** with Incus capability (version, CPU, RAM, KVM).

### 4.3 Install Incus (if not already installed)

- If the machine shows "Incus is not installed", click **Install Incus** in the sidebar.
  Tunneld detects the distro and runs the right package-manager command (apt/apk/dnf),
  falling back to the Zabbly repo on older Ubuntu/Debian.
- After install it auto-probes and shows the Incus version.

### 4.4 Create a container and verify it is reachable

1. **Machines → the VM → New Container/VM**, name it (e.g. `vm-test`), pick an image
   (e.g. `images:debian/12`), type **container**, network **bridge**.
2. The container appears **live** in the sidebar with its IP and a copyable
   `ssh root@<ip>` command.
3. Verify from the VM host:
   ```bash
   incus list
   incus exec vm-test -- bash -c "apt-get update && apt-get install -y openssh-server && echo root:test | chpasswd && sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config && systemctl restart ssh"
   ```
4. SSH into the container from the VM host (bridge-NAT containers are reached via the host):
   ```bash
   ssh -p 22 root@<container_ip>
   ```
5. To reach the container's service from the LAN, add a **port** (e.g. `8080:80`) at creation
   (Incus proxy device on the host IP), or use **expose** for remote machines.

### 4.5 Verify startup recovery

Restart the tunneld service on the gateway (`sudo systemctl restart tunneld`). On boot,
tunneld asynchronously probes every enrolled machine, installs Incus where missing, and
re-opens any reverse-SSH expose tunnels. The dashboard should show the VM as **ready**
without a manual probe.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `docker: command not found` | Install Docker (see 1.1) |
| `Permission denied (publickey,password)` on deploy | Wrong SSH user/key; use the device's real user |
| `systemctl restart tunneld` fails | `sudo journalctl -u tunneld -n 50` |
| `uname -m` shows `armv7l` | Board is 32-bit; Incus/macvlan won't work — use 64-bit |
| macvlan container not in Devices list | Confirm it's a container (not VM) and network=macvlan; check `incus list` on the NanoPi |
| VM shows "Incus is not installed" | Click **Install Incus** in the sidebar; tunneld auto-installs on Ubuntu/Debian/Alpine/Fedora |
| Container not reachable from LAN | Bridge-NAT containers are reached via the VM host IP; add a port (proxy device) or use **expose** |
| Machine shows unreachable after restart | Confirm the SSH key is installed and the VM is on; tunneld marks unreachable machines on startup |

### 4.6 Make freshly-created containers reachable (DHCP + NAT on the default network)

A freshly-created container only gets a reachable IP if the incus bridge it uses
provides DHCP. On a fresh install the default network often has **no IPv4/DHCP**
(`incus network show <net>` shows `config: {}`), so containers boot with only a
link-local IPv6 and no IPv4 — the tunneld UI shows an empty IP.

Give the default network a DHCP range + NAT (run as a user with sudo, since the
network lives in the `default` project):

```bash
sudo incus network set incusbr-1000 ipv4.address=10.133.114.1/24
sudo incus network set incusbr-1000 ipv4.nat=true
sudo incus network set incusbr-1000 ipv4.dhcp=true
sudo incus network set incusbr-1000 ipv4.dhcp.ranges=10.133.114.2-10.133.114.254
```

Then restart the container so it picks up a lease. Verify with `incus list` — the
container should show an IPv4. If it still has none, check the bridge's dnsmasq is
running (`ps aux | grep dnsmasq`) and that UFW allows forwarding on that bridge
(`sudo ufw route allow in on incusbr-1000`).

> **Note:** the `test` user is restricted to project `user-1000` and cannot modify
> the `default`-project network — use `sudo` for these commands.
