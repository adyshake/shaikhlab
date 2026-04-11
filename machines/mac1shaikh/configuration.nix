{
  config,
  inputs,
  lib,
  outputs,
  pkgs,
  vars,
  ...
}: let
  blockedDomains = [
    "news.ycombinator.com"
  ];
  blockedHostsBody =
    lib.concatStringsSep "\n" (map (d: "0.0.0.0 ${d}\n::1 ${d}") blockedDomains);
  blockedHostsMarkerBegin = "# BEGIN shaikhlab blocked domains (mac1shaikh)";
  blockedHostsMarkerEnd = "# END shaikhlab blocked domains (mac1shaikh)";
  blockedHostsSnippet = pkgs.writeText "mac1shaikh-blocked-hosts-snippet" ''
    ${blockedHostsMarkerBegin}
    ${blockedHostsBody}
    ${blockedHostsMarkerEnd}
  '';
in {
  imports = [
    inputs.home-manager.darwinModules.home-manager

    ./hardware-configuration.nix

    ./../../modules/macos/base.nix
    ./../../modules/macos/yabai.nix
  ];

  home-manager = {
    extraSpecialArgs = {inherit inputs outputs vars;};
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "backup";
    backupCommand = "${pkgs.trash-cli}/bin/trash-put";
    users = {
      ${vars.userName} = {
        imports = [
          ./../../modules/home-manager/alacritty.nix
          ./../../modules/home-manager/base.nix
          ./../../modules/home-manager/librewolf/default.nix
          ./../../modules/home-manager/fonts.nix
          ./../../modules/home-manager/git.nix
        ];
      };
    };
  };

  networking = {
    hostName = "mac1shaikh";
    computerName = "mac1shaikh";
    localHostName = "mac1shaikh";
  };

  # nix-darwin only runs built-in activation fragments; hook postActivation so this actually runs.
  system.activationScripts.postActivation.text = lib.mkAfter ''
    set -euo pipefail
    hosts=/etc/hosts
    tmp=$(mktemp)
    if grep -qF '${blockedHostsMarkerBegin}' "$hosts" 2>/dev/null; then
      awk -v b='${blockedHostsMarkerBegin}' -v e='${blockedHostsMarkerEnd}' '
        $0 == b { skip = 1; next }
        $0 == e { skip = 0; next }
        skip == 0 { print }
      ' "$hosts" > "$tmp"
      mv "$tmp" "$hosts"
    fi
    cat ${blockedHostsSnippet} >> "$hosts"
    echo >&2 "shaikhlab: updated blocked domains in /etc/hosts"
  '';
}
