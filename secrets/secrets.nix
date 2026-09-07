let
  sshKeys = import ../ssh-keys.nix;
  inherit (sshKeys) dvcorreia afonso lena;
in
{
  "hetzner-api-token.age".publicKeys = [
    dvcorreia
    afonso
  ];
  "opentofu-encryption-key.age".publicKeys = [
    dvcorreia
    afonso
  ];
  "cloudflare-dns-token.age".publicKeys = [
    dvcorreia
    afonso
  ];
  "pocket-id.age".publicKeys = [
    dvcorreia
    afonso
    lena
  ];
  "headscale-oidc.age".publicKeys = [
    dvcorreia
    afonso
    lena
  ];
}
