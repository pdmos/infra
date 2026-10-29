{ config, ... }:

let
  domain = "rtc.pdmos.pt";
  inherit (config.services) livekit lk-jwt-service;
in
{
  # "<key>: <secret>", shared by livekit and lk-jwt-service
  age.secrets.livekit-keys.file = ../../../secrets/livekit-keys.age;

  services.matrix-tuwunel.settings.global.well_known.livekit_url = "https://${domain}";

  services.livekit = {
    enable = true;
    keyFile = config.age.secrets.livekit-keys.path;
    settings = {
      # signalling stays behind nginx; ICE still binds all interfaces
      bind_addresses = [ "127.0.0.1" ];
      rtc = {
        tcp_port = 7881;
        use_external_ip = true;
      };
      # only full-access users of lk-jwt-service may create rooms
      room.auto_create = false;
    };
  };

  services.lk-jwt-service = {
    enable = true;
    port = 8081; # 8080 is headscale
    livekitUrl = "wss://${domain}";
    keyFile = config.age.secrets.livekit-keys.path;
  };

  systemd.services.lk-jwt-service.environment.LIVEKIT_FULL_ACCESS_HOMESERVERS =
    config.services.matrix-tuwunel.settings.global.server_name;

  # not openFirewall: it would also expose the signalling port
  networking.firewall = {
    allowedTCPPorts = [ livekit.settings.rtc.tcp_port ];
    allowedUDPPortRanges = [
      {
        from = livekit.settings.rtc.port_range_start;
        to = livekit.settings.rtc.port_range_end;
      }
    ];
  };

  services.nginx.virtualHosts.${domain} = {
    addSSL = true;
    enableACME = true;
    locations = {
      "~ ^/(sfu/get|get_token|healthz)$".proxyPass = "http://127.0.0.1:${toString lk-jwt-service.port}";
      "/" = {
        proxyPass = "http://127.0.0.1:${toString livekit.settings.port}";
        proxyWebsockets = true;
      };
    };
  };
}
