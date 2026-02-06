# DirettaOS: Dedicated Linux Distribution Methodology

**Date:** 2026-02-06
**Status:** Design
**Authors:** PCH (architecture), Dominique (implementation), Claude Code (generation)
**Base:** Fedora Server Minimal

---

## 1. Problem Statement

### The Distribution Problem

Both Diretta products (DirettaRendererUPnP-X and squeeze2diretta) require specific system-level configuration that general-purpose Linux distributions do not provide out of the box:

| Requirement | What Users Must Do Today | What Goes Wrong |
|-------------|-------------------------|-----------------|
| Kernel parameters | Manually edit GRUB for `isolcpus`, `nosmt`, `irqaffinity` | Audio-Linux/GentooPlayer editors override or omit these |
| Real-time priority | Configure PAM limits, systemd overrides | Missing `LimitRTPRIO`, `LimitMEMLOCK` causes jitter |
| Network tuning | Set `sysctl` buffers, MTU, firewall rules | Wrong MTU breaks Diretta; firewall blocks SSDP/SlimProto |
| Dependencies | Install FFmpeg-devel, libupnp-devel, build tools | Version mismatches (FFmpeg ABI), missing headers |
| CPU isolation | Run tuner scripts, create systemd slices | Users skip this; shared cores cause scheduling jitter |
| Diretta SDK | Download separately, place in correct path | Wrong version, wrong path, permissions issues |

**Core insight:** Every manual step is an opportunity for the third-party distro editors to introduce variance. A dedicated distribution eliminates this entire class of problems.

### Design Philosophy

Borrow from the audio optimisation methodology:

> **Minimise variance in system configuration, not just average correctness.**

A general-purpose distro configured "mostly right" is worse than a purpose-built distro configured exactly right. This is the distribution equivalent of Pattern 5 (Timing Variance Reduction): we want every installation to be identical and deterministic.

---

## 2. Architecture Overview

### Two-Product, One-Image Strategy

```
DirettaOS ISO
  ├── Fedora Server Minimal (base)
  ├── Kernel: RT or tuned mainline
  ├── Pre-configured: sysctl, GRUB, PAM, firewall
  │
  ├── Product A: DirettaRendererUPnP-X
  │   ├── Binary (architecture-matched)
  │   ├── Systemd service + config
  │   └── Dependencies (FFmpeg, libupnp)
  │
  ├── Product B: squeeze2diretta
  │   ├── Binary (architecture-matched)
  │   ├── Squeezelite (patched, architecture-matched)
  │   ├── Systemd service + config
  │   └── Dependencies (ALSA libs)
  │
  ├── Diretta Host SDK (architecture-matched libraries)
  │
  └── First-Boot Configurator
      ├── Hardware detection (CPU, NIC, architecture)
      ├── Diretta target discovery
      ├── Product selection (A, B, or both)
      └── Network configuration
```

### Target Platforms

| Platform | ARCH_NAME | Notes |
|----------|-----------|-------|
| Intel/AMD (AVX2) | `x64-linux-15v3` | Most common, default |
| Intel/AMD (AVX-512) | `x64-linux-15v4` | Xeon, Ice Lake+ |
| AMD Zen 4 | `x64-linux-15zen4` | Ryzen 7000+ |
| Raspberry Pi 4 | `aarch64-linux-15` | 4KB pages |
| Raspberry Pi 5 | `aarch64-linux-15k16` | 16KB pages |

**Decision:** Build one ISO per architecture, or one ISO with all binaries and runtime detection. Recommend the latter for simplicity (disk is cheap; user confusion is expensive).

---

## 3. Methodology: Four-Phase Build Process

Following the two-phase documentation approach from the Optimisation Methodology, extended to four phases for distribution engineering:

```
Phase 1: Base Image Definition (what to include/exclude)
    ↓
Phase 2: System Tuning Layer (kernel, sysctl, scheduling)
    ↓
Phase 3: Application Layer (products, services, config)
    ↓
Phase 4: First-Boot & Maintenance (configurator, updates)
```

Each phase has its own design document and implementation document, following the established `*-design.md` / `*-impl.md` pattern.

### Claude-Assisted Development Model

The critical accelerator for this project is **Claude Code as an active implementation partner**. This changes the division of labour fundamentally:

| Activity | Who | How |
|----------|-----|-----|
| **Generate kickstart file** | Claude Code | From this spec, produces complete `.ks` file |
| **Generate RPM specs** | Claude Code | From existing `install.sh` + Makefiles, produces `.spec` files |
| **Generate all config files** | Claude Code | sysctl.d, tuned, limits.d, firewalld — all specified in this doc |
| **Generate first-boot TUI** | Claude Code | Dialog-based script from flow diagrams in Section 7 |
| **Generate detect-hardware.sh** | Claude Code | Logic already exists in both `install.sh` scripts |
| **Generate build.sh pipeline** | Claude Code | livemedia-creator invocation with kickstart |
| **Review and adjust** | Dominique | Read Claude's output, request corrections |
| **Test on real hardware** | Dominique | Boot ISO on x64 and RPi targets |
| **Make architectural decisions** | Dominique | Decision log (Section 12) |
| **Test audio playback** | Dominique | Both products with real DAC and Diretta Target |

**Workflow per phase:**

```
1. Dominique opens Claude Code in the DirettaOS repo
2. Points Claude at this methodology document
3. Says: "Implement Phase N"
4. Claude generates all files for that phase
5. Dominique reviews, tests on hardware, reports back
6. Claude fixes issues based on Dominique's feedback
7. Commit and move to next phase
```

This means Dominique's time is spent on **decisions and testing**, not on writing boilerplate. A phase that would take a week of manual scripting compresses to an afternoon of generation + an evening of testing.

---

## 4. Phase 1: Base Image Definition

### 4.1 Starting Point: Fedora Server Minimal

**Why Fedora Server:**
- Stable, well-maintained, regular release cycle
- DNF package manager with good dependency resolution
- systemd-native (both products use systemd services)
- SELinux provides security without manual iptables
- Good RT kernel availability via COPR
- Familiar to enterprise users (RHEL lineage)

**Why Minimal:**
- Smallest attack surface
- Fewest running services competing for CPU time
- Smallest image size
- Fastest boot time

### 4.2 Kickstart Approach

Fedora supports unattended installation via Kickstart files. This is the correct tool for building a reproducible base image.

**Kickstart file structure:**

```
DirettaOS-kickstart.ks
  ├── %packages section (what to install)
  ├── %pre section (pre-install hardware detection)
  ├── %post section (post-install configuration)
  └── Partitioning scheme
```

### 4.3 Package Selection

#### Include (Minimal Audio Server)

| Category | Packages | Rationale |
|----------|----------|-----------|
| **Core OS** | `@core` | Minimal Fedora base |
| **Networking** | `NetworkManager`, `firewalld` | Network management, firewall |
| **Audio libs** | `alsa-lib`, `alsa-utils` | ALSA base (for Squeezelite) |
| **FFmpeg** | `ffmpeg-free-libs` | Runtime libraries for DirettaRendererUPnP-X |
| **UPnP** | `libupnp` | Runtime library for DirettaRendererUPnP-X |
| **Monitoring** | `htop`, `iotop`, `ethtool` | Diagnostic tools |
| **Remote access** | `openssh-server` | SSH for headless operation |
| **Tuning** | `tuned`, `irqbalance` | System tuning framework |
| **Build tools** | `gcc-c++`, `cmake`, `make`, `git`, `patch` | For rebuilds/updates |

#### Exclude (Reduce Surface)

| Category | Packages to Exclude | Rationale |
|----------|-------------------|-----------|
| **Desktop** | All X11, Wayland, GNOME, KDE | Headless audio server |
| **Printing** | `cups`, `cups-*` | No printer support needed |
| **Bluetooth** | `bluez`, `bluez-*` | No Bluetooth audio |
| **WiFi** | `wpa_supplicant`, `iwd` | Ethernet only (deterministic) |
| **Containers** | `podman`, `buildah` | No container runtime needed |
| **Mail** | `postfix`, `sendmail` | No mail server |
| **Docs** | `man-pages`, `info` | Minimise disk usage |

### 4.4 Partitioning Scheme

```
/boot       512 MB   ext4    (kernel, initramfs)
/boot/efi   256 MB   vfat    (UEFI bootloader)
/           8 GB     ext4    (OS + applications)
swap        2 GB     swap    (safety net, should never be used)
/data       remainder ext4   (logs, config, optional music cache)
```

**Key:** Keep root filesystem small and fast. No LVM overhead for a single-purpose appliance.

### 4.5 Build Tooling

**Option A: Fedora Image Builder (osbuild-composer)**
- Official Fedora tool for building custom images
- Produces ISO, qcow2, raw, or AMI images
- Blueprint-based (TOML configuration)
- Reproducible builds
- **Recommended for production**

**Option B: Lorax + Kickstart**
- Lower-level, more control
- Produces bootable ISO directly
- Better for custom install workflows
- More complex to maintain

**Option C: Fedora Remix (Respins)**
- Community-supported approach
- Uses `livecd-creator` or `livemedia-creator`
- Good documentation, established workflow
- Suitable for distributing as ISO

**Recommendation:** Start with **Option C (Remix/Respin)** for rapid prototyping, migrate to **Option A (osbuild-composer)** for reproducible CI/CD builds.

---

## 5. Phase 2: System Tuning Layer

### 5.1 Kernel Configuration

#### GRUB Parameters

```bash
# /etc/default/grub
GRUB_CMDLINE_LINUX="nosmt isolcpus=managed_irq,domain,1-N rcu_nocbs=1-N \
  irqaffinity=0 nohz_full=1-N threadirqs processor.max_cstate=1 \
  idle=poll intel_pstate=disable amd_pstate=passive"
```

**Note:** `N` is determined at first boot by the hardware detection script. This is why Phase 4 (first-boot configurator) is critical.

**Parameter rationale:**

| Parameter | Purpose | Audio Impact |
|-----------|---------|--------------|
| `nosmt` | Disable hyperthreading | Eliminates SMT scheduling jitter |
| `isolcpus=managed_irq,domain,1-N` | Isolate audio cores from scheduler | No kernel tasks on audio cores |
| `rcu_nocbs=1-N` | No RCU callbacks on audio cores | Eliminates periodic kernel work |
| `irqaffinity=0` | All IRQs to core 0 | Audio cores never handle interrupts |
| `nohz_full=1-N` | Tickless on audio cores | No timer tick jitter |
| `threadirqs` | Threaded IRQ handlers | IRQs schedulable, not hardirq |
| `processor.max_cstate=1` | Disable deep C-states | No wakeup latency from deep sleep |

#### RT Kernel

```bash
# Option A: Fedora COPR RT kernel
dnf copr enable kwizart/kernel-rt
dnf install kernel-rt kernel-rt-devel

# Option B: Mainline with PREEMPT_RT patch
# More work, but guaranteed latest RT features
```

**Decision point for Dominique:** RT kernel vs tuned mainline. The mainline kernel with `PREEMPT_DYNAMIC=full` (Fedora default since kernel 6.x) may be sufficient. RT kernel adds complexity (separate package source, potential hardware compatibility issues). Recommend starting with tuned mainline and measuring before adding RT.

### 5.2 sysctl Configuration

```bash
# /etc/sysctl.d/90-diretta-audio.conf

# Network buffer sizes (16MB for Diretta UDP)
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.rmem_default = 8388608
net.core.wmem_default = 8388608

# Reduce network latency
net.core.busy_poll = 50
net.core.busy_read = 50
net.ipv4.tcp_low_latency = 1

# Memory management: avoid swapping
vm.swappiness = 1
vm.dirty_ratio = 5
vm.dirty_background_ratio = 2

# Disable transparent hugepages (unpredictable latency)
# (also set via kernel parameter: transparent_hugepage=never)
```

### 5.3 PAM / Security Limits

```bash
# /etc/security/limits.d/90-diretta-audio.conf
*    -    rtprio     95
*    -    memlock    unlimited
*    -    nice       -20
root -    rtprio     99
root -    memlock    unlimited
```

### 5.4 Firewall

```bash
# /etc/firewalld/services/diretta.xml
# Pre-configured firewall service definition

# DirettaRendererUPnP-X:
#   - SSDP multicast: 239.255.255.250:1900/udp
#   - UPnP HTTP: 4005/tcp (configurable)
#   - Diretta protocol: dynamic UDP

# squeeze2diretta:
#   - SlimProto: 3483/tcp, 3483/udp
#   - LMS web: 9000/tcp (outbound to LMS)

# Both:
#   - SSH: 22/tcp (remote management)
```

### 5.5 CPU Governor

```bash
# /etc/tuned/diretta-audio/tuned.conf
[main]
summary=DirettaOS Audio Profile

[cpu]
governor=performance
energy_perf_bias=performance
min_perf_pct=100

[sysctl]
# (sysctl values from 5.2 above)

[scheduler]
# Disable autogroup scheduling
kernel.sched_autogroup_enabled=0
```

### 5.6 Disabled Services

```bash
# Services to mask (never run):
systemctl mask bluetooth.service
systemctl mask cups.service
systemctl mask avahi-daemon.service   # We use our own SSDP, not Avahi
systemctl mask ModemManager.service
systemctl mask fwupd.service          # No firmware updates on appliance
systemctl mask packagekit.service     # No background package updates
systemctl mask thermald.service       # We control C-states via kernel params

# Services to disable (available but not running):
systemctl disable dnf-makecache.timer # No background repo syncs
```

---

## 6. Phase 3: Application Layer

### 6.1 Directory Structure

```
/opt/diretta/
  ├── bin/
  │   ├── DirettaRendererUPnP          # Product A binary
  │   ├── squeeze2diretta              # Product B binary
  │   └── squeezelite                  # Patched Squeezelite
  ├── lib/
  │   ├── x64-v3/                      # SDK libs per arch
  │   ├── x64-v4/
  │   ├── x64-zen4/
  │   ├── aarch64/
  │   └── aarch64-k16/
  ├── conf/
  │   ├── diretta-renderer.conf        # Product A config
  │   └── squeeze2diretta.conf         # Product B config
  ├── scripts/
  │   ├── first-boot.sh                # First-boot configurator
  │   ├── detect-hardware.sh           # Architecture detection
  │   ├── detect-targets.sh            # Diretta target discovery
  │   └── distribute-threads.sh        # CPU affinity assignment
  └── sdk/
      └── DirettaHostSDK_148/          # Pre-installed SDK
```

### 6.2 Architecture-Matched Binary Selection

At first boot (or at service start), detect the architecture and symlink the correct binaries:

```bash
#!/bin/bash
# detect-hardware.sh

ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    if grep -q "avx512" /proc/cpuinfo; then
        if grep -q "znver4" /proc/cpuinfo 2>/dev/null || \
           lscpu | grep -q "Zen 4"; then
            VARIANT="x64-zen4"
        else
            VARIANT="x64-v4"
        fi
    elif grep -q "avx2" /proc/cpuinfo; then
        VARIANT="x64-v3"
    else
        VARIANT="x64-v2"
    fi
elif [ "$ARCH" = "aarch64" ]; then
    PAGESIZE=$(getconf PAGESIZE)
    if [ "$PAGESIZE" = "16384" ]; then
        VARIANT="aarch64-k16"
    else
        VARIANT="aarch64"
    fi
fi

echo "$VARIANT"
```

### 6.3 Systemd Services

Both services are pre-installed but disabled. The first-boot configurator enables the user's choice.

```bash
# /etc/systemd/system/diretta-renderer.service (pre-installed, disabled)
# /etc/systemd/system/squeeze2diretta.service (pre-installed, disabled)
```

### 6.4 Systemd Audio Slice

```ini
# /etc/systemd/system/audio-isolated.slice
[Unit]
Description=Isolated CPU slice for audio processing

[Slice]
# AllowedCPUs set by first-boot configurator
# based on detected core count
CPUQuota=100%
```

### 6.5 Pre-built vs Build-on-Target

**Decision point:** Ship pre-built binaries for each architecture, or build from source on the target?

| Approach | Pros | Cons |
|----------|------|------|
| Pre-built | Fast install, no build deps needed | Larger image, FFmpeg ABI must match |
| Build-on-target | Always matches system libs | Slow (RPi: 10+ min), needs build deps |
| Hybrid | Pre-built + rebuild option | Best of both, moderate complexity |

**Recommendation:** Hybrid. Ship pre-built binaries matched to the Fedora version's FFmpeg. Include a `/opt/diretta/scripts/rebuild.sh` for users who need custom FFmpeg or want to update.

---

## 7. Phase 4: First-Boot Configurator

### 7.1 Purpose

The first-boot configurator bridges the gap between "generic ISO" and "configured appliance". It runs once on first boot (or on demand) and handles all hardware-specific decisions.

### 7.2 Design: Text UI (Dialog-Based)

Use `dialog` or `whiptail` for a simple TUI that works over SSH and serial console. No X11 dependency.

### 7.3 Configurator Flow

```
┌─────────────────────────────────────────┐
│          DirettaOS First Boot           │
│                                         │
│  Welcome to DirettaOS v1.0              │
│  Detected: AMD Ryzen 7 7700X (8 cores) │
│  Architecture: x64-v3 (AVX2)           │
│                                         │
│  [Continue]                             │
└─────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────┐
│  Step 1: Network Configuration          │
│                                         │
│  Detected interfaces:                   │
│  ○ eth0: 192.168.1.100 (1 Gbps)        │
│  ○ eth1: 10.0.0.1 (10 Gbps)            │
│                                         │
│  Configure MTU?                         │
│  ○ Standard (1500)                      │
│  ● Jumbo Frames (9014)  [Recommended]   │
│  ○ Extended Jumbo (16128)               │
│                                         │
│  [Next]                                 │
└─────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────┐
│  Step 2: Diretta Target Discovery       │
│                                         │
│  Scanning for Diretta targets...        │
│                                         │
│  Found 2 targets:                       │
│  1. GentooPlayer-DAC (192.168.1.50)     │
│  2. MemoryPlay-USB (10.0.0.50)          │
│                                         │
│  Select target: [1]                     │
│                                         │
│  [Next]                                 │
└─────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────┐
│  Step 3: Product Selection              │
│                                         │
│  Which product(s) to enable?            │
│                                         │
│  ☑ DirettaRendererUPnP-X               │
│    (UPnP/DLNA → Diretta)               │
│    Control from: JPlay, BubbleUPnP,     │
│    Roon, MinimServer                    │
│                                         │
│  ☐ squeeze2diretta                      │
│    (LMS/Squeezelite → Diretta)          │
│    Requires: Lyrion Music Server        │
│    LMS Server IP: [____________]        │
│                                         │
│  [Next]                                 │
└─────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────┐
│  Step 4: CPU Isolation                  │
│                                         │
│  8 physical cores detected (SMT off)    │
│                                         │
│  Recommended layout:                    │
│  Core 0: System (IRQs, kernel)          │
│  Cores 1-7: Audio processing            │
│                                         │
│  ○ Apply recommended layout             │
│  ○ Custom core assignment               │
│  ○ Skip (no CPU isolation)              │
│                                         │
│  [Apply & Reboot]                       │
└─────────────────────────────────────────┘
```

### 7.4 What the Configurator Writes

| Step | Files Modified |
|------|---------------|
| Network | `/etc/NetworkManager/...`, `/etc/sysctl.d/`, firewall rules |
| Target | `/opt/diretta/conf/*.conf` (TARGET= line) |
| Product | `systemctl enable/disable` the chosen service(s) |
| CPU | `/etc/default/grub`, `/etc/systemd/system/audio-isolated.slice`, service overrides |
| Reboot | `grub2-mkconfig`, then `reboot` |

### 7.5 Re-Configuration

The configurator should be re-runnable:

```bash
sudo /opt/diretta/scripts/first-boot.sh --reconfigure
```

---

## 8. Build Pipeline

### 8.1 Repository Structure

```
DirettaOS/
  ├── kickstart/
  │   └── direttaos.ks              # Kickstart file
  ├── packages/
  │   ├── diretta-renderer.spec     # RPM spec for Product A
  │   ├── squeeze2diretta.spec      # RPM spec for Product B
  │   └── direttaos-config.spec     # RPM spec for system config
  ├── scripts/
  │   ├── first-boot.sh
  │   ├── detect-hardware.sh
  │   └── rebuild.sh
  ├── config/
  │   ├── sysctl.d/
  │   ├── tuned/
  │   ├── limits.d/
  │   ├── firewalld/
  │   └── grub/
  ├── branding/
  │   ├── motd                      # Login banner
  │   └── issue                     # Console banner
  └── build.sh                      # ISO build script
```

### 8.2 Build Steps

```
1. Start with Fedora Server netinstall ISO
       ↓
2. Apply kickstart (package selection, partitioning)
       ↓
3. Install RPM packages (products, config, scripts)
       ↓
4. Apply system tuning (sysctl, tuned, limits)
       ↓
5. Install Diretta SDK libraries
       ↓
6. Configure first-boot service
       ↓
7. Generate ISO with livemedia-creator
       ↓
8. Test in VM, then on target hardware
```

### 8.3 RPM Packaging

Package each product as an RPM. This enables clean installation, upgrades, and removal.

```spec
# diretta-renderer.spec (sketch)
Name:           diretta-renderer
Version:        2.0
Release:        1%{?dist}
Summary:        DirettaRendererUPnP-X audio renderer

Requires:       ffmpeg-free-libs >= 6.0
Requires:       libupnp >= 1.14

%install
install -D -m 755 bin/DirettaRendererUPnP %{buildroot}/opt/diretta/bin/
install -D -m 644 systemd/diretta-renderer.service %{buildroot}/etc/systemd/system/
install -D -m 644 conf/diretta-renderer.conf %{buildroot}/opt/diretta/conf/
```

### 8.4 SDK Distribution

The Diretta Host SDK is personal-use and cannot be redistributed. Two options:

**Option A: Separate download (safe, legal)**
- ISO ships without SDK
- First-boot configurator prompts user to provide SDK path (USB stick, NFS, URL)
- Script copies SDK libraries to `/opt/diretta/sdk/`

**Option B: Bundled with license agreement (requires Diretta.link permission)**
- Include SDK in ISO behind a license acceptance prompt
- Simplest UX but requires legal agreement with Diretta

**Recommendation:** Start with Option A. Negotiate Option B once the distro is proven.

---

## 9. Update Strategy

### 9.1 Appliance Updates

An audio appliance should update deliberately, not automatically.

```
┌───────────────────────────────────┐
│  DirettaOS updates available:     │
│                                   │
│  ○ Security updates only          │
│  ○ Full system update             │
│  ○ Product update only            │
│  ○ Skip                           │
│                                   │
│  [Apply]                          │
└───────────────────────────────────┘
```

### 9.2 Version Pinning

Pin FFmpeg and libupnp versions to prevent ABI breakage:

```bash
# /etc/dnf/dnf.conf
exclude=ffmpeg* libupnp*
```

Only update these through the DirettaOS update channel after ABI compatibility testing.

### 9.3 Rollback

Use BTRFS snapshots or LVM snapshots before updates:

```bash
# Before update
btrfs subvolume snapshot / /snapshots/pre-update-$(date +%Y%m%d)

# After failed update
btrfs subvolume set-default /snapshots/pre-update-20260206
reboot
```

**Alternative (simpler):** Keep two root partitions (A/B scheme, like ChromeOS). Update the inactive partition, swap on success.

---

## 10. Implementation Roadmap

With Claude Code as the generation engine, Dominique's effort is focused on **decisions, review, and hardware testing**. Claude generates all config files, scripts, specs, and kickstart content directly from this document.

### Session 1: Foundation (one evening)

| Task | Who Generates | Dominique Does | Time |
|------|--------------|----------------|------|
| 1.1 | Claude: kickstart file with package selection | Review package list | 10 min |
| 1.2 | Claude: sysctl.d, tuned, limits.d, firewalld configs | Verify values match existing tuner scripts | 10 min |
| 1.3 | Claude: `build.sh` (livemedia-creator wrapper) | Run on Fedora build machine | 30 min (build time) |
| 1.4 | — | Boot ISO in VM, test SSH + network | 30 min |

**Gate:** Base ISO boots, SSH works, `tuned-adm active` shows `diretta-audio`.

### Session 2: Products (one evening)

| Task | Who Generates | Dominique Does | Time |
|------|--------------|----------------|------|
| 2.1 | Claude: RPM spec for DirettaRendererUPnP-X | Review deps, run `rpmbuild` | 15 min |
| 2.2 | Claude: RPM spec for squeeze2diretta + Squeezelite | Review deps, run `rpmbuild` | 15 min |
| 2.3 | Claude: RPM spec for direttaos-config (tuning bundle) | Review, run `rpmbuild` | 10 min |
| 2.4 | Claude: updated kickstart with local RPM repo | Rebuild ISO, install in VM | 30 min |
| 2.5 | — | Test both products with real Diretta Target | 1 hour |

**Gate:** Both products run on ISO. `sudo squeeze2diretta --list-targets` and `sudo DirettaRendererUPnP --list-targets` find the target.

### Session 3: First-Boot Configurator (one evening)

| Task | Who Generates | Dominique Does | Time |
|------|--------------|----------------|------|
| 3.1 | Claude: `detect-hardware.sh` (from existing install.sh logic) | Verify on x64 + RPi | 10 min |
| 3.2 | Claude: `first-boot.sh` TUI (dialog-based, full flow) | Walk through on VM | 20 min |
| 3.3 | Claude: systemd oneshot service for first-boot trigger | Test reboot cycle | 10 min |
| 3.4 | — | End-to-end: fresh ISO → first-boot → configure → play music | 1 hour |

**Gate:** Cold install to music playing in under 10 minutes.

### Session 4: Polish + Release (one evening)

| Task | Who Generates | Dominique Does | Time |
|------|--------------|----------------|------|
| 4.1 | Claude: MOTD, issue banner, hostname config | Review branding | 5 min |
| 4.2 | Claude: `direttaos-update.sh` (version-pinned DNF wrapper) | Test update/rollback | 20 min |
| 4.3 | Claude: README + quick-start guide for end users | Review, adjust tone | 15 min |
| 4.4 | — | Test on all target platforms (x64, RPi4, RPi5) | 1-2 hours |
| 4.5 | — | Tag release, upload ISO to GitHub Releases | 15 min |

**Gate:** ISO tested on at least x64 + one ARM platform. README is clear.

### Total Estimated Effort

| | Claude Code | Dominique |
|--|-------------|-----------|
| Generation / scripting | ~2 hours across 4 sessions | — |
| Review / adjustment | — | ~1.5 hours across 4 sessions |
| Hardware testing | — | ~4 hours across 4 sessions |
| **Total** | **~2 hours** | **~5.5 hours** |
| **Calendar time** | | **4 evenings over 1-2 weeks** |

The bottleneck is never code generation — it's always **hardware access and real-world testing**. Claude eliminates the scripting work entirely; Dominique's time is spent on what only a human with physical hardware can do.

---

## 11. Risk Matrix

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| FFmpeg ABI mismatch between Fedora updates | High | Service crash | Pin FFmpeg version in DNF |
| Diretta SDK redistribution blocked | Medium | No SDK in ISO | First-boot download prompt (Option A) |
| Hardware not detected correctly | Medium | Wrong binary, crash | Fallback to x64-v2 baseline |
| Kernel RT patches break NIC drivers | Low | No network | Ship both mainline and RT kernels |
| User expects GUI | Low | Confusion | Clear "headless appliance" messaging |
| Fedora EOL before next DirettaOS release | Low | No security updates | Use Fedora LTS or CentOS Stream |
| livemedia-creator quirks on first attempt | Medium | Build fails | Claude iterates on errors in real time |
| RPM spec mistakes | Low | Package won't install | Claude fixes from `rpmbuild` error output |

**Note on risk with Claude-assisted workflow:** Most scripting/config risks are self-correcting. When Claude generates a kickstart file and it fails to build, Dominique pastes the error back and Claude fixes it immediately. The traditional risk of "developer spends 2 days debugging RPM spec syntax" becomes "Claude fixes it in 30 seconds". The only irreducible risks are hardware-specific (NIC drivers, kernel compatibility, Diretta Target behaviour) — these require physical testing that no tool can shortcut.

---

## 12. Decision Log

Decisions for Dominique to make **before Session 1**. These are the only blockers — once decided, Claude Code can generate everything in one pass.

| # | Decision | Options | Recommendation | Blocking |
|---|----------|---------|----------------|----------|
| D1 | Base image tool | osbuild-composer / Lorax / Remix | Remix (fastest start) | Session 1 |
| D2 | Kernel | Mainline tuned / COPR RT / Custom RT | Mainline tuned (simpler) | Session 1 |
| D3 | SDK distribution | Download at first boot / Bundle with license | Download at first boot | Session 3 |
| D4 | Binary strategy | Pre-built per arch / Build on target / Hybrid | Hybrid | Session 2 |
| D5 | Filesystem | ext4 / BTRFS (snapshots) / XFS | ext4 (simplest, lowest overhead) | Session 1 |
| D6 | Multi-arch ISO | One ISO per arch / One fat ISO | One fat ISO (user simplicity) | Session 2 |
| D7 | Fedora version | F41 (current) / F42 (upcoming) / CentOS Stream 10 | F41 (stable, known deps) | Session 1 |
| D8 | Update channel | DNF repo / GitHub releases / Manual USB | GitHub releases (simplest) | Session 4 |

**Minimum viable decisions for Session 1:** D1, D2, D5, D7. If Dominique accepts all four recommendations, Claude Code can generate the complete kickstart + configs immediately.

### How to Start

Dominique's first Claude Code session:

```
1. Create a new repo: github.com/cometdom/DirettaOS
2. Clone it locally
3. Copy this methodology document into docs/
4. Open Claude Code in the repo root
5. Tell Claude: "Read docs/2026-02-06-DirettaOS-Methodology.md and implement
   Session 1. Use Fedora Remix, mainline kernel, ext4, Fedora 41."
6. Claude generates all files. Review, commit, build.
```

---

## 13. References

- Fedora Remix guidelines: https://fedoraproject.org/wiki/Remix
- osbuild-composer: https://www.osbuild.org/
- Kickstart syntax: https://pykickstart.readthedocs.io/
- Fedora RT kernel COPR: search `kernel-rt` on copr.fedorainfracloud.org
- Existing tuner scripts: `squeeze2diretta-tuner.sh`, `diretta-renderer-tuner-nosmt.sh`, `audiophile_tuner.sh`
- Optimisation Methodology: `DirettaRendererUPnP-X/docs/plans/2026-01-17-Optimisation_Methodology.md`
