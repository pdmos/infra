let
  sshKeys = import ../ssh-keys.nix;
  inherit (sshKeys) dvcorreia dvcorreia-yubikey lena;
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
  "pocket-id.age".publicKeys = [
    dvcorreia
    lena
  ];
}
