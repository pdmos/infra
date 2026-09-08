let
  sshKeys = import ../ssh-keys.nix;

  inherit (sshKeys) lena;

  admins = [
    sshKeys.dvcorreia
    sshKeys.afonso
  ];
in
{
  "hetzner-api-token.age".publicKeys = admins;
  "opentofu-encryption-key.age".publicKeys = admins;
  "cloudflare-dns-token.age".publicKeys = admins;

  "pocket-id.age".publicKeys = [ lena ] ++ admins;
  "headscale-oidc.age".publicKeys = [ lena ] ++ admins;
  "lena-tailscale-preauth-key.age".publicKeys = [ lena ] ++ admins;
}
