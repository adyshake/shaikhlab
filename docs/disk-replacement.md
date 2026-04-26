# Replacing a failed disk in `svr1shaikh`

This is the runbook for swapping a drive in the `/dev/md0` RAID5 array on
`svr1shaikh`. The procedure is **cold-swap** (power the server off, swap, power
on) — your chassis isn't a hot-swap one and there's no benefit to risking arc
damage on the SATA power rails.

## How you'll find out a drive is dying

You'll get one of these emails (delivered via MXroute, configured in
[`services/mail.nix`](../services/mail.nix) and
[`services/drive-health.nix`](../services/drive-health.nix)):

| Trigger | Subject | Sent by |
| --- | --- | --- |
| Threshold breach during routine SMART poll | `[svr1shaikh] SMART error ...` | `smartd.service` |
| RAID event (`Fail`, `FailSpare`, `DegradedArray`, `RebuildStarted`, ...) | `[svr1shaikh] mdadm: <event> on /dev/mdX` | `mdmonitor.service` → `mdadm-notify` |
| Monthly digest with a non-OK verdict | `[svr1shaikh] drive health: REPLACE /dev/sdX` | `drive-health-report.service` |

The **monthly digest** is the most actionable — it prints the model and serial
of the failing drive in an "Action" block, plus the exact `mdadm` commands you'd
run if the chassis were hot-swap. For the cold-swap procedure below, ignore the
hot-swap commands in the email and follow this doc instead.

## What you should already have on hand

- **One spare 2 TB SATA SSD in a drawer.** A second WD Blue SA510 is ideal
  (matches the rest of the array), but anything ≥ 2 TB SATA works. Buy this
  *before* a failure, not after — the day you actually need it the array is
  sitting one more failure away from total loss.
- A small Phillips screwdriver for the drive caddy.

## The procedure

### 1. Identify the failing drive by serial — *before* opening the case

```bash
ssh adnan@svr1shaikh
ls -l /dev/disk/by-id/ | grep -E 'ata-.* -> .*/sd[a-d]$'
# ata-WD_Blue_SA510_2.5_2TB_2530Q3D01948 -> ../../sda
# ata-WD_Blue_SA510_2.5_2TB_2530Q3D01968 -> ../../sdb
# ata-WD_Blue_SA510_2.5_2TB_2530Q3D01973 -> ../../sdc
# ata-WD_Blue_SA510_2.5_2TB_2530Q3D01989 -> ../../sdd
```

The "Action" block in the alert email tells you which `/dev/sdX` failed; map
that to a serial above and **write it down**. The serial is also printed on the
metal lid of the SA510 itself.

> [!WARNING]
> Pulling the wrong physical drive turns a recoverable single-disk failure
> into a two-disk failure (= total data loss on RAID5). Triple-check the
> serial before you unplug anything.

### 2. Power off

```bash
sudo systemctl poweroff
```

### 3. Swap the drive

Open the case, find the disk whose label matches the serial you wrote down,
unplug its SATA + power, pull it out. Plug the new drive into the same SATA
cable and the same power lead, screw it into the same bay, close up.

The SATA *port* doesn't have to be the same — mdadm finds members by their
on-disk UUID, not by `/dev/sdX` letter. But keeping it in the same physical
slot keeps device naming stable and makes future-you less confused.

### 4. Power on, verify the array auto-assembled in degraded mode

```bash
ssh adnan@svr1shaikh
cat /proc/mdstat
# Personalities : [raid6] [raid5] [raid4]
# md0 : active raid5 sdb[0] sdc[1] sdd[3]      ← only 3 members listed
#       5860147200 blocks ... [4/3] [_UUU]      ← gap = the missing one
```

`/data` will mount as normal because LUKS sits *above* md0 — it has no idea a
member is missing.

### 5. Confirm the new disk is the new one (sanity check)

```bash
sudo smartctl -i /dev/sda | grep -E 'Serial|Model'
```

Expect a serial that does **not** match any of the four you cataloged in step 1.

### 6. Wipe leftover signatures (no-op for brand-new disks; required for used ones)

```bash
sudo wipefs -a /dev/sda
```

Skip this and `mdadm --add` will refuse if the disk has stale RAID metadata or
a partition table.

### 7. Add it back to the array

```bash
sudo mdadm --manage /dev/md0 --add /dev/sda
```

Rebuild starts immediately. Watch progress:

```bash
watch -n 5 cat /proc/mdstat
# md0 : active raid5 sda[4] sdb[0] sdc[1] sdd[3]
#       5860147200 blocks ... [4/3] [_UUU]
#       [==>..................]  recovery = 12.7% (...) finish=178.4min speed=185000K/sec
```

Expect **~3–4 hours** for a 2 TB rebuild. The array is online and `/data` is
fully readable/writable the whole time, but I/O is degraded — try to avoid
heavy writes (Sonarr/Radarr imports, big rsyncs) until it finishes.

### 8. Confirm and close out

```bash
cat /proc/mdstat                                       # [UUUU]
sudo mdadm --detail /dev/md0                           # State : clean
sudo /run/current-system/sw/bin/drive-health-report    # fresh "ALL OK" digest in your inbox
```

Reorder the spare drawer.

## Things you do *not* need to do

- **Edit `/etc/mdadm.conf`** — it matches the array by UUID, which doesn't
  change when you swap a member. The
  [`environment.etc."mdadm.conf"`](../machines/svr1shaikh/hardware-configuration.nix)
  block in the nix config keeps working forever as long as the new disk is
  ≥ 2 TB.
- **Re-unlock LUKS or rotate keys.** The LUKS volume is on top of `/dev/md0`,
  not on the individual member. Member swaps are invisible to it.
- **Re-deploy the flake.** Nothing in nix needs to change for a member swap.
- **Touch the boot drive** (`nvme0n1`). It's not part of the array. If *that*
  one ever dies, you reinstall NixOS from this flake and re-attach `/data`.

## When a second drive fails during the rebuild

You're now beyond what RAID5 can recover. Stop writing to `/data`, pull the
backup tarballs from Kopia (see [`services/kopia.nix`](../services/kopia.nix)
once it lands), rebuild the array from scratch with
[`setup-raid.sh`](../setup-raid.sh), and restore.

This is also why a **5th disk as a hot spare** is worth considering — the
controller has 6 SATA ports and only 4 are populated. A spare member that
mdadm activates the moment a failure is detected closes the multi-hour window
where a second failure is fatal.
