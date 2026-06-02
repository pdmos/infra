{ ... }:
{
  services.tailscale = {
    enable = true;
    openFirewall = true;
    useRoutingFeatures = "server";
    extraUpFlags = [
      "--advertise-exit-node"
    ];
  };

  networking.firewall.trustedInterfaces = [ "tailscale0" ];
}
