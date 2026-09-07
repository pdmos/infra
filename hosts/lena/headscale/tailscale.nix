{ ... }:
{
  services.tailscale = {
    enable = false; # TODO: needs headscale to be up
    openFirewall = true;
    useRoutingFeatures = "server";
    extraUpFlags = [
      "--advertise-exit-node"
    ];
  };

  networking.firewall.trustedInterfaces = [ "tailscale0" ];
}
