{
  inputs,
  config,
  ...
}:

let
  headscaleUrl = inputs.self.nixosConfigurations.lena.config.services.headscale.settings.server_url;
in
{
  age.secrets.lena-tailscale-preauth-key.file = ../../../secrets/lena-tailscale-preauth-key.age;

  services.tailscale = {
    enable = true;
    openFirewall = true;
    authKeyFile = config.age.secrets.lena-tailscale-preauth-key.path;
    useRoutingFeatures = "server";
    extraUpFlags = [
      "--login-server=${headscaleUrl}"
      "--accept-dns=true" # accept MagicDNS
      "--advertise-exit-node"
    ];
  };

  networking.firewall.trustedInterfaces = [ "tailscale0" ];
}
