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
    inputs.srvos.nixosModules.server
    inputs.srvos.nixosModules.hardware-hetzner-cloud
    inputs.agenix.nixosModules.default
    inputs.disko.nixosModules.disko
  ];

  networking.hostName = "lena";

  environment.systemPackages = [
    pkgs.git
  ];

  users.users =
    let
      inherit (inputs.self) sshKeys;
    in
    {
      root.openssh.authorizedKeys.keys = [
        sshKeys.dvcorreia-yubikey
      ];

      dvcorreia = {
        isNormalUser = true;
        extraGroups = [ "wheel" ];

        openssh.authorizedKeys.keys = [
          sshKeys.dvcorreia
        ];
      };
    };

  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "prohibit-password";
  };

  system.stateVersion = "25.11";
}
