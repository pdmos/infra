{ config, ... }:
{
  age.secrets.pocket-id = {
    file = ../../secrets/pocket-id.age;
    owner = config.services.pocket-id.user;
    group = config.services.pocket-id.group;
  };

  services.pocket-id = {
    enable = true;
    settings = {
      APP_URL = "https://id.pdmos.pt";
      UNIX_SOCKET = "/run/pocket-id/pocket-id.sock";
      UNIX_SOCKET_MODE = "0660";
      ENCRYPTION_KEY_FILE = config.age.secrets.pocket-id.path;
      APP_NAME = "Fuas ID";
      TRUST_PROXY = true;
      EMAILS_VERIFIED = true;
      UI_CONFIG_DISABLED = true;
      ANALYTICS_DISABLED = true;
    };
  };

  systemd.services.pocket-id.serviceConfig = {
    RuntimeDirectory = "pocket-id";
    RuntimeDirectoryMode = "750";
  };

  users.groups.pocket-id.members = [ "nginx" ];

  services.nginx.virtualHosts = {
    "id.pdmos.pt" = {
      addSSL = true;
      enableACME = true;
      locations."/".proxyPass = "http://unix:${config.services.pocket-id.settings.UNIX_SOCKET}";
    };

    "pdmos.pt".locations = {
      "/.well-known/webfinger" =
        let
          response = builtins.toJSON {
            subject = "acct:dv_correia@hotmail.com";
            links = [
              {
                rel = "http://openid.net/specs/connect/1.0/issuer";
                href = "https://id.pdmos.pt";
              }
            ];
          };
        in
        {
          return = "200 '${response}' ";
          extraConfig = ''
            default_type application/jrd+json;
          '';
        };
    };
  };
}
