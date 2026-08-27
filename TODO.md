## Done

- [x] ~~Replace firefox with librewolf~~
- [x] configure home-assistant to be declarative
- [x] configure dns to block based on different devices (blocky `clientGroupsBlock`)
- [x] Add Kagi to the Nix config (librewolf default + Privacy Pass extension)
- [x] Install betterdisplay
- [x] Install itsycal
- [x] Install cursor
- [x] Install hammerspoon (cask only; script still TODO)
- [x] Install meetingbar
- [x] set up mac to be declarative
  - [x] terminal + zsh
  - [x] reset key timings
- [x] drive health monitoring on `svr1shaikh` — `smartd` + `mdadm-notify` + monthly digest via MXroute (see [`services/drive-health.nix`](services/drive-health.nix), runbook at [`docs/disk-replacement.md`](docs/disk-replacement.md))
- [x] self-host git — Forgejo at `git.adnanshaikh.com` (Tailscale-only, state on `/data`, admin user reconciled from sops on every deploy); see [`services/forgejo.nix`](services/forgejo.nix)
- [x] self-host beancount UI — Fava at `beancount.adnanshaikh.com` (Tailscale-only, working copy on NVMe synced every 5 min from the Forgejo bare repo); see [`services/fava.nix`](services/fava.nix)
- [x] self-host music — Navidrome at `music.adnanshaikh.com` (Tailscale-only, library `/data/fun/library/music` shared with Lidarr); Amperfy on iOS talks Subsonic to it; see [`services/nixarr.nix`](services/nixarr.nix)
## In progress

- [ ] set up kopia
  - [ ] set up backups for \*arr (stub commented out in `services/nixarr.nix`)
  - [ ] set up backups for home assistant (stub commented out in `services/homeassistant.nix`)
  - [ ] set up backups for forgejo (`/data/forgejo` — repos + SQLite DB)
  - [ ] set up backups for navidrome (`/var/lib/navidrome` — SQLite DB, playlists, ratings; library files themselves live under `/data/fun/library/music`)
  - [ ] _no kopia needed for fava_ — `/var/lib/fava/ledger` is a regenerable mirror of the forgejo bare repo above
- [ ] set up git config with gpg keys (allowed_signers written; signing block still commented out in `modules/home-manager/git.nix`)

## To do — infra / ops

- [ ] daily `flake.lock` bump bot — GitHub Action that runs `nix flake update` and opens a PR (see [eh8/chenglab](https://github.com/eh8/chenglab): "`flake.lock` updated daily via GitHub Action, servers are configured to automatically upgrade daily via `modules/nixos/auto-update.nix`"); pair with a server-side auto-upgrade module

## To do — services

- [ ] encrypt Grafana `secret_key` — still the old public nixpkgs default in `services/grafana.nix`; move it to sops and rotate if `grafana.db` has encrypted secrets
- [ ] set up immich
- [ ] set up pastebin
- [ ] set up google drive
- [ ] add airgradient to home assistant
- [ ] customize home assistant interface
- [ ] add sui
- [ ] security (define scope)

## To do — macOS / apps

- [ ] fix `homebrew.masApps` hanging on `darwin-rebuild switch` (block is commented out in `modules/macos/_packages.nix` — candidates queued: Infuse, Tailscale, Yomu EBook Reader; see https://discourse.nixos.org/t/nix-darwin-homebrew-masapps-is-hanging/60828)
- [ ] Add Yomu to dock (blocked on masApps fix; placeholder comment in `modules/macos/base.nix`)
- [ ] Add hammerspoon script

## To do — declarative settings for already-installed apps

- [ ] linear mouse settings (cask installed; settings not declared)
- [ ] vimium keys to exclude (extension installed via librewolf policies; excluded keys not declared)
  ```
  # disable the mini player from being triggered
  https?://www.youtube.com/*, i
  ```
- [ ] better way to block hackernews (currently via blocky `customBlocking`)
