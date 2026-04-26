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
  - [x] yabai
  - [x] terminal + zsh
  - [x] reset key timings

## In progress

- [ ] set up kopia
  - [x] nextcloud
  - [x] scrypted
  - [x] homebridge
  - [ ] set up backups for \*arr (stub commented out in `services/nixarr.nix`)
  - [ ] set up backups for home assistant (stub commented out in `services/homeassistant.nix`)
- [ ] set up git config with gpg keys (allowed_signers written; signing block still commented out in `modules/home-manager/git.nix`)
- [ ] drive health monitoring — add `mxroute-smtp-password` via `just sops-edit`, then `just deploy svr1shaikh`; see `services/drive-health.nix`

## To do — infra / ops

- [ ] daily `flake.lock` bump bot — GitHub Action that runs `nix flake update` and opens a PR (see [eh8/chenglab](https://github.com/eh8/chenglab): "`flake.lock` updated daily via GitHub Action, servers are configured to automatically upgrade daily via `modules/nixos/auto-update.nix`"); pair with a server-side auto-upgrade module

## To do — services

- [ ] set up immich
- [ ] set up pastebin
- [ ] set up google drive
- [ ] move git to local (self-hosted forge)
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
