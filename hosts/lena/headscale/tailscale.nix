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

  # The login server is the headscale on this host. At boot tailscaled first
  # tries it before nginx is listening and only retries about two minutes
  # later, past the default 90 s start timeout.
  systemd.services.tailscaled-autoconnect.serviceConfig.TimeoutStartSec = "5min";

  networking.firewall.trustedInterfaces = [ "tailscale0" ];
}
