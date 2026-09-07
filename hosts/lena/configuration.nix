{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

{
  imports = [
    ./disko.nix
    ./nix.nix
    ./acme.nix
    ./pocket-id.nix
    ./headscale
    ./websites
    ./matrix
    inputs.srvos.nixosModules.server
    inputs.srvos.nixosModules.hardware-hetzner-cloud
    inputs.agenix.nixosModules.default
    inputs.disko.nixosModules.disko
  ];

  networking.hostName = "lena";

  environment.systemPackages = with pkgs; [
    git
    ghostty # fixes 'xterm-ghostty': unknown terminal type
  ];

  users.users =
    let
      inherit (inputs.self) sshKeys;
    in
    {
      root.openssh.authorizedKeys.keys = [
        sshKeys.dvcorreia-yubikey
        sshKeys.afonso-yubikey
      ];

      dvcorreia = {
        isNormalUser = true;
        extraGroups = [ "wheel" ];

        openssh.authorizedKeys.keys = [
          sshKeys.dvcorreia
        ];
      };

      afonso = {
        isNormalUser = true;
        extraGroups = [ "wheel" ];

        openssh.authorizedKeys.keys = [
          sshKeys.afonso
          sshKeys.afonso-yubikey
        ];
      };

      debug = {
        isNormalUser = true;
        extraGroups = [ "systemd-journal" ];

        openssh.authorizedKeys.keys = [
          sshKeys.dvcorreia
          sshKeys.afonso
        ];
      };
    };

  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "prohibit-password";
  };

  system.stateVersion = "25.11";
}
