[![nixos 25.11](https://img.shields.io/badge/NixOS-25.11-blue.svg?&logo=NixOS&logoColor=white)](https://nixos.org)

## Highlights

This repo contains the Nix configurations for my homelab, AMD Ryzen desktop and M1 MacBook Pro.

- ❄️ Nix flakes handle upstream dependencies and track latest stable release of Nixpkgs (currently 25.11)
- 🏠 [home-manager](https://github.com/nix-community/home-manager) manages
  dotfiles
- 🍎 [nix-darwin](https://github.com/LnL7/nix-darwin) manages MacBook
- 🤫 [sops-nix](https://github.com/Mic92/sops-nix) manages secrets
- 🔑 Remote initrd unlock system to decrypt drives on boot
- 🌬️ Root on tmpfs aka
  [impermanence](https://grahamc.com/blog/erase-your-darlings/)
- 🔒 Automatic Let's Encrypt certificate registration and renewal
- 🧩 Tailscale, Nextcloud, Jellyfin, Homebridge, Scrypted, among other nice
  self-hosted applications
- ⚡️ `.justfile` contains useful aliases for many frequent and atrociously long
  `nix` commands
- 🤖 `flake.lock` updated daily via GitHub Action, servers are configured to
  automatically upgrade daily via
  [`modules/nixos/auto-update.nix`](https://github.com/adyshake/shaikhlab/blob/main/modules/nixos/auto-update.nix)
- 🧱 Modular architecture promotes readability for me and copy-and-paste-ability
  for you
- 📦
  [Custom ready-made tarball and ISO](https://github.com/adyshake/shaikhlab/releases)
  for installing NixOS-on-WSL and NixOS, respectively

## Getting started

### macOS

On macOS, this script will install `nix` using the
[Determinate Systems Nix installer](https://zero-to-nix.com/start/install) and
prompt you to install my configuration.

> [!IMPORTANT]
> You'll need to run this script as sudo or have sudo permissions.

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/adyshake/shaikhlab/main/install.sh)"
```

### NixOS (Linux)

> [!IMPORTANT]
> You'll need to run this script as sudo or have sudo permissions.

> [!WARNING]
> This script is primarily meant for my own use. Using it to install
> NixOS on your own hardware will fail. At minimum, you'll need to do the
> following before attemping installation:
>
> 1. Create a configuration for your own device in the `machines/` folder
> 1. Retool your own sops-nix secrets or remove them entirely if you don't use
>    sops-nix
> 1. Add an entry to flake.nix referencing the configuration created in step 1

On Linux, _running this script from the NixOS installation ISO_ will prepare
your system for NixOS by partitioning drives and mounting them.

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/adyshake/shaikhlab/main/install.sh)"
```

> [!TIP]
> When installing NixOS onto a headless local server, place your own
> custom NixOS ISO file onto a USB drive with Ventoy.
> [Ventoy can automatically load the NixOS ISO file](https://adnanshaikh.com/homelab/#remotely-entering-nixos-installer),
> and you can enable connectivity by building your own custom ISO with your own
> personal SSH key.
> [The custom ISO released in this repo](https://github.com/adyshake/shaikhlab/releases)
> is baked with my own key.

### Headless Server Installation

First create a bootable image with SSH enabled using this [repo](https://github.com/splitbrain/nixsshinstall). You'll need to run the docker container on an x86_64 machine and ARM machines won't work.

Once you've booted in, set the password for the `nixos` user on the machine using the BMC's remote management software using

```bash
passwd
```

Then you can log in from your computer with the private key, whose corresponding public key you set while creating the ISO in the first step.

```bash
sshpass -p<password> ssh nixos@192.168.1.94
```

Clone the repository and set git config

```bash
git clone https://github.com/adyshake/shaikhlab.git

git config --global user.email "github@adnanshaikh.com"

git config --global user.name "Adnan Shaikh"
```

Install dependencies

```bash
nix-shell -p gh just sops
```

Login to Github

```bash
gh auth login
```

Run the install script

```bash
sudo ./install.sh
```

Once it's done, take the age public key it spits out in the output and place it in the `.sops.yaml` file next to the machine hostname you're configuring.

```bash
export EDITOR=vim

rm secrets/secrets.yaml

mkdir -p /home/nixos/.config/sops/age/

sudo nix-shell --extra-experimental-features flakes -p ssh-to-age --run 'ssh-to-age -private-key -i /mnt/nix/secret/initrd/ssh_host_ed25519_key -o /home/nixos/.config/sops/age/keys.txt'

sudo chown nixos "/home/nixos/.config/sops/age/keys.txt"
```

Create a hashed version of the username's password and copy the output. The username that gets created is specified in the vars.nix file

```bash
echo "password" | mkpasswd -m SHA-512 -s
```

Finally, run the sops-edit command,

```bash
just sops-edit
```

Add the following line to it, and save

```yaml
user-password: <hashed-password-you-copied>
```

Check git status, commit and save

```bash
git diff

git add .

git commit -m "update secrets"

git push
```

We also need to set up the RAID array. The proceeding install should work even without it, though most services that use the array will fail to start.

```bash
 sudo ./setup-raid.sh
```

Copy the output of the `mdadm --detail --scan` command and place it in the appropriate machines/<hostname>/hardware-configuration.nix within the `environment.etc."mdadm.conf".text` section and then commit those changes as well.

```bash
git diff

git add .

git commit -m "add raid array config"

git push
```

Install NixOS

```bash
sudo nixos-install --no-root-passwd --root /mnt --flake github:adyshake/shaikhlab#svr1shaikh
```

Reboot

```bash
sudo shutdown -r now
```

### Configure Cloudflare Tunnel

After the system has rebooted and you've logged in, set up the Cloudflare tunnel. **Run these commands on your Mac:**

```bash
brew install cloudflared

cloudflared tunnel login

cloudflared tunnel create shaikhlab-01

scp /Users/adnan/.cloudflared/cert.pem <server-username>@<server-ip>:/home/adnan/shaikhlab/secrets/cloudflare-cert.pem

scp /Users/adnan/.cloudflared/<uuid>.json <server-username>@<server-ip>:/home/adnan/shaikhlab/secrets/cloudflare-tunnel
```

On the server, encrypt the files with sops:

```bash
cd /home/adnan/shaikhlab

sops -e -i secrets/cloudflare-cert.pem

sops -e -i secrets/cloudflare-tunnel
```

Commit and push the encrypted files:

```bash
git add secrets/cloudflare-cert.pem secrets/cloudflare-tunnel

git commit -m "add encrypted cloudflare tunnel secrets"

git push

### Windows Subsystem for Linux (WSL)

1. Enable WSL if you haven't done already:

```powershell
wsl --install --no-distribution
```

1. Download `nixos.wsl` from
   [the latest release](https://github.com/adyshake/shaikhlab/releases).

2. Either double-click the `nixos.wsl` file once downloaded or import
   the tarball into WSL:

```powershell
wsl --install --from-file nixos.wsl
```

4. You can now run NixOS:

```powershell
wsl -d NixOS
```

## Useful commands 🛠️

Install `just` to access the simple aliases below

### Locally deploy changes

```bash
just deploy macos
```

```bash
just deploy MACHINE
```

### Remote deployment

To remotely deploy `MACHINE`, which has an IP address of `10.0.10.2`

```bash
just deploy MACHINE 10.0.10.2
```

### Edit secrets

Make sure each machine's public key is listed as entry in `.sops.yaml`. To
modify `secrets/secrets.yaml`:

```bash
just sops-edit
```

### Syncing sops keys for a new machine

```bash
just sops-update
```

## Important caveats

### Changing user passwords

To modify user password, first generate a hash

```bash
echo "password" | mkpasswd -m SHA-512 -s
```

Then run `just sops-edit` to replace the existing decrypted hash with the one
that you just generated. If you use a password manager, sure to update the new
password as necessary.

### Changing SSH keys

Make sure you update the public key as it appears across the repository.

### Installation source

Make sure the Determinate Nix installer one-liner in `install.sh` is consistent
with how it appears on the official website.

## To-do

1. [Secure boot](https://github.com/nix-community/lanzaboote)
2. Binary caching
3. [Wireless remote unlocking](https://discourse.nixos.org/t/wireless-connection-within-initrd/38317/13)

## Frequently used resources

- [Search NixOS options](https://search.nixos.org/options)
- [Home Manager Option Search](https://mipmip.github.io/home-manager-option-search/)
- [Darwin Configuration Options](https://daiderd.com/nix-darwin/manual/index.html)

## Helpful references

- [An outstanding beginner friendly introduction to NixOS and flakes](https://nixos-and-flakes.thiscute.world/)
- [Conditional implementation](https://nixos.wiki/wiki/Extend_NixOS#Conditional_Implementation)
- [Error when using lib.mkIf and lib.mkMerge to set configuration based on hostname](https://stackoverflow.com/questions/77527439/error-when-using-lib-mkif-and-lib-mkmerge-to-set-configuration-based-on-hostname)
- [Handling Secrets in NixOS: An Overview](https://lgug2z.com/articles/handling-secrets-in-nixos-an-overview/)
- [NixOS ❄: tmpfs as root](https://elis.nu/blog/2020/05/nixos-tmpfs-as-root)
- [NixOS on Hetzner Dedicated](https://mhu.dev/posts/2024-01-06-nixos-on-hetzner)
- [Setting up Nix on macOS](https://nixcademy.com/2024/01/15/nix-on-macos/)
- [Users.users.<name>.packages vs home-manager packages](https://discourse.nixos.org/t/users-users-name-packages-vs-home-manager-packages/22240)
- [Declaratively manage dock via nix](https://github.com/dustinlyons/nixos-config/blob/8a14e1f0da074b3f9060e8c822164d922bfeec29/modules/darwin/home-manager.nix#L74)
- [Dealing with post nix-flake god complex](https://www.reddit.com/r/NixOS/comments/kauf1m/dealing_with_post_nixflake_god_complex/)
