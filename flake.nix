{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    agenix-shell.url = "github:aciceri/agenix-shell";
  };

  outputs =
    {
      self,
      nixpkgs,
      agenix,
      agenix-shell,
      ...
    }@inputs:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);

      sshKeys = import ./ssh-keys.nix;

      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [
              agenix.overlays.default
            ];
          };

          installationScript = agenix-shell.lib.installationScript system {
            secrets = {
              TF_VAR_hcloud_token.file = ./secrets/hetzner-api-token.age;
              TF_VAR_passphrase.file = ./secrets/opentofu-encryption-key.age;
            };
          };
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              git
              openssh
              opentofu
              pkgs.agenix
              nixos-rebuild
            ];

            TF_VAR_ssh_pub_key = self.sshKeys.dvcorreia-yubikey;

            shellHook = ''
              source ${pkgs.lib.getExe installationScript}
            '';
          };
        }
      );
    };
}
