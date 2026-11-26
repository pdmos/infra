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

      service = {
        DISABLE_REGISTRATION = true;
        # hide the local login form; sign-in page redirects to the single OAuth2 provider
        ENABLE_INTERNAL_SIGNIN = false;
      };

      oauth2_client = {
        ENABLE_AUTO_REGISTRATION = true;
        ACCOUNT_LINKING = "auto";
        UPDATE_AVATAR = true;
        USERNAME = "preferred_username";
      };

    };
  };

  # Custom logo, but the PNG lives in the site assets; the navbar template
  # references logo.svg, so we wrap the PNG as an embedded data URI.
  systemd.tmpfiles.rules =
    let
      inherit (cfg) customDir user group;
      public = "${customDir}/public";
      logoSvg = pkgs.runCommand "logo.svg" { } ''
        printf '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 400"><image href="data:image/png;base64,%s" width="400" height="400"/></svg>' \
          "$(${pkgs.coreutils}/bin/base64 -w0 ${../../site/static/logo.png})" > $out
      '';
    in
    [
      "d '${public}' 0750 ${user} ${group} - -"
      "d '${public}/assets' 0750 ${user} ${group} - -"
      "d '${public}/assets/img' 0750 ${user} ${group} - -"
      "C+ '${public}/assets/img/logo.svg' - ${user} ${group} - ${logoSvg}"
    ];

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
