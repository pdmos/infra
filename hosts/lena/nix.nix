{ pkgs, ... }:

{
  nix = {
    package = pkgs.nixVersions.latest;

    settings = {
      experimental-features = [
        "flakes"
        "nix-command"
      ];

      trusted-users = [
        "root"
        "@wheel"
        "dvcorreia"
      ];

      substituters = [
        "https://nix-community.cachix.org"
      ];

      trusted-public-keys = [
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];

      warn-dirty = false;
    };

    gc = {
      automatic = true;
      options = "--delete-older-than 14d";
      dates = "weekly";
    };
  };
}
