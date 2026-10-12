{
  config,
  pkgs,
  ...
}:

let
  domain = "manga.pdmos.pt";
  port = config.services.komga.settings.server.port;
in
{
  nixpkgs.overlays = [
    (final: prev: {
      komga = pkgs.unstable.komga; # komga module doesn't have a package option
    })
  ];

  age.secrets.komga-oidc = {
    file = ../../secrets/komga-oidc.age;
    owner = config.services.komga.user;
    group = config.services.komga.group;
  };

  services.komga = {
    enable = true;
    settings = {
      komga.oauth2-account-creation = false;

      spring.config.import = "file:${config.age.secrets.komga-oidc.path}[.properties]";

      server = {
        address = "127.0.0.1";
        port = 25600;
        forward-headers-strategy = "framework";
      };

      spring.security.oauth2.client = {
        registration.fuas-id = {
          client-id = "komga";
          client-name = config.services.pocket-id.settings.APP_NAME;
          client-authentication-method = "client_secret_post";
          authorization-grant-type = "authorization_code";
          scope = [
            "openid"
            "email"
            "profile"
          ];
          redirect-uri = "https://${domain}/login/oauth2/code/fuas-id";
        };
        provider.fuas-id.issuer-uri = config.services.pocket-id.settings.APP_URL;
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d /srv/manga 0750 komga komga - -"
  ];

  services.nginx.virtualHosts.${domain} = {
    addSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString port}";
      proxyWebsockets = true;
    };
  };
}
