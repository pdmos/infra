{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.forgejo;
  inherit (config.services) pocket-id;
  domain = "git.pdmos.pt";

  oidc = {
    name = pocket-id.settings.APP_NAME;
    clientId = "forgejo";
    scopes = [
      "openid"
      "email"
      "profile"
      "groups"
    ];
    adminGroup = "admin";
  };
in
{
  age.secrets.forgejo-oidc = {
    file = ../../secrets/forgejo-oidc.age;
    owner = config.services.forgejo.user;
    group = config.services.forgejo.group;
  };

  services.forgejo = {
    enable = true;
    lfs.enable = true;
    dump.enable = true;

    settings = {
      server = {
        DOMAIN = domain;
        ROOT_URL = "https://${domain}/";
        HTTP_ADDR = "127.0.0.1";
      };

      session.COOKIE_SECURE = true;

      service.DISABLE_REGISTRATION = true;

      oauth2_client = {
        ENABLE_AUTO_REGISTRATION = true;
        ACCOUNT_LINKING = "auto";
        UPDATE_AVATAR = true;
        USERNAME = "preferred_username";
      };
    };
  };

  # Declaratively provision the Pocket ID OAuth2 source.
  # The client must exist in Pocket ID with callback URL:
  # ${cfg.settings.server.ROOT_URL}user/oauth2/Fuas%20ID/callback
  systemd.services.forgejo.preStart =
    let
      auth = "${lib.getExe cfg.package} admin auth";
      secretFile = config.age.secrets.forgejo-oidc.path;
      args = lib.escapeShellArgs (
        [
          "--name"
          oidc.name
          "--provider"
          "openidConnect"
          "--key"
          oidc.clientId
          "--auto-discover-url"
          "${pocket-id.settings.APP_URL}/.well-known/openid-configuration"
          "--group-claim-name"
          "groups"
          "--admin-group"
          oidc.adminGroup
          "--skip-local-2fa"
        ]
        ++ lib.concatMap (scope: [
          "--scopes"
          scope
        ]) oidc.scopes
      );
    in
    lib.mkAfter ''
      id=$(${auth} list | ${lib.getExe pkgs.gnugrep} -w ${lib.escapeShellArg oidc.name} | cut -f1 || true)

      if [ -n "$id" ]; then
        ${auth} update-oauth --id "$id" ${args} --secret "$(< ${secretFile})"
      else
        ${auth} add-oauth ${args} --secret "$(< ${secretFile})"
      fi
    '';

  services.nginx.virtualHosts.${domain} = {
    addSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString cfg.settings.server.HTTP_PORT}";
      proxyWebsockets = true;
      extraConfig = ''
        client_max_body_size 512M;
      '';
    };
  };
}
