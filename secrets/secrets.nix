let
  sshKeys = import ../ssh-keys.nix;
  inherit (sshKeys) dvcorreia dvcorreia-yubikey;
in
{
  "hetzner-api-token.age".publicKeys = [
    dvcorreia
    dvcorreia-yubikey
  ];
  "opentofu-encryption-key.age".publicKeys = [
    dvcorreia
    dvcorreia-yubikey
  ];
  "cloudflare-dns-token.age".publicKeys = [
    dvcorreia
    dvcorreia-yubikey
  ];
}
