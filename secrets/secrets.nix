let
  sshKeys = import ../ssh-keys.nix;
  inherit (sshKeys) dvcorreia lena;
in
{
  "hetzner-api-token.age".publicKeys = [
    dvcorreia
  ];
  "opentofu-encryption-key.age".publicKeys = [
    dvcorreia
  ];
  "cloudflare-dns-token.age".publicKeys = [
    dvcorreia
  ];
  "pocket-id.age".publicKeys = [
    dvcorreia
    lena
  ];
  "headscale-oidc.age".publicKeys = [
    dvcorreia
    lena
  ];
}
