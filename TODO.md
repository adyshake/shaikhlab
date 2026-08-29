## Done

- [x] ~~Replace firefox with librewolf~~
- [x] configure home-assistant to be declarative
- [x] configure dns to block based on different devices (blocky `clientGroupsBlock`)
- [x] Add Kagi to the Nix config (librewolf default + Privacy Pass extension)
- [x] Install betterdisplay
- [x] Install itsycal
- [x] Install cursor
- [x] Install hammerspoon (cask only)
- [x] Install meetingbar
- [x] set up mac to be declarative
  - [x] terminal + zsh
  - [x] reset key timings
- [x] drive health monitoring on `svr1shaikh` — `smartd` + `mdadm-notify` + monthly digest via MXroute (see [`services/drive-health.nix`](services/drive-health.nix), runbook at [`docs/disk-replacement.md`](docs/disk-replacement.md))
- [x] self-host git — Forgejo at `git.adnanshaikh.com` (Tailscale-only, state on `/data`, admin user reconciled from sops on every deploy); see [`services/forgejo.nix`](services/forgejo.nix)
- [x] self-host beancount UI — Fava at `beancount.adnanshaikh.com` (Tailscale-only, working copy on NVMe synced every 5 min from the Forgejo bare repo); see [`services/fava.nix`](services/fava.nix)
- [x] self-host music — Navidrome at `music.adnanshaikh.com` (Tailscale-only, library `/data/fun/library/music` shared with Lidarr); Amperfy on iOS talks Subsonic to it; see [`services/nixarr.nix`](services/nixarr.nix)
- [x] add airgradient to home assistant — `airgradient` in `extraComponents`; Living Room ONE at `192.168.1.94` added via UI (see [`services/homeassistant.nix`](services/homeassistant.nix))
- [x] add sui — startpage at `start.adnanshaikh.com` (Tailscale-only, black theme, local services); see [`services/sui.nix`](services/sui.nix)
- [x] Add Yomu to dock — already present at `/Applications/Yomu.app`, order matches `local.dock.entries` in [`modules/macos/base.nix`](modules/macos/base.nix)
- [x] linear mouse settings — Rival 3 scheme in [`modules/home-manager/linearmouse.nix`](modules/home-manager/linearmouse.nix)
- [x] encrypt Grafana `secret_key` — rotated off the public nixpkgs default into sops (`secrets/grafana-secret-key`); provisioned datasources use `$__file` so `grafana.db` stays intact
- [x] `homebrew.masApps` — Infuse, Tailscale, Yomu via mas 6.0.1; `darwin-rebuild switch` no longer hangs (see [`modules/macos/_packages.nix`](modules/macos/_packages.nix))

## In progress

- [ ] set up kopia
  - [ ] set up backups for \*arr (stub commented out in `services/nixarr.nix`)
  - [ ] set up backups for home assistant (stub commented out in `services/homeassistant.nix`)
  - [ ] set up backups for forgejo (`/data/forgejo` — repos + SQLite DB)
  - [ ] set up backups for navidrome (`/var/lib/navidrome` — SQLite DB, playlists, ratings; library files themselves live under `/data/fun/library/music`)
  - [ ] set up backups for immich (`/data/immich` library + `/data/postgresql` — photos are not a backup until this exists)
  - [ ] _no kopia needed for fava_ — `/var/lib/fava/ledger` is a regenerable mirror of the forgejo bare repo above

## To do — infra / ops

- [ ] daily `flake.lock` bump bot — GitHub Action that runs `nix flake update` and opens a PR (see [eh8/chenglab](https://github.com/eh8/chenglab): "`flake.lock` updated daily via GitHub Action, servers are configured to automatically upgrade daily via `modules/nixos/auto-update.nix`"); pair with a server-side auto-upgrade module

## To do — services

- [x] set up immich — Tailscale-only at `photos.adnanshaikh.com` (localhost + nginx, library + Postgres on `/data`); see [`services/immich.nix`](services/immich.nix). Not in a public jail; not on the Cloudflare tunnel.
- [x] set up pastebin — wastebin in a public jail at `paste.adnanshaikh.com` (nspawn, tmpfs + cgroup cap, nginx rate limits, Cloudflare tunnel); reusable via [`modules/nixos/public-jail.nix`](modules/nixos/public-jail.nix) / [`services/wastebin.nix`](services/wastebin.nix)
- [ ] set up google drive
- [ ] customize home assistant interface
- [ ] security (define scope)
