{ config, ... }:
let
  serverName = "pdmos.pt";
  domain = "matrix.${serverName}";
  port = 6167;
in
{
  age.secrets.matrix-oidc = {
    file = ../../../secrets/matrix-oidc.age;
    owner = config.services.matrix-tuwunel.user;
    group = config.services.matrix-tuwunel.group;
  };

  services.matrix-tuwunel = {
    enable = true;
    settings = {
      global = {
        server_name = serverName;
        address = [ "127.0.0.1" ];
        port = [ port ];
        max_request_size = 50 * 1024 * 1024;
        ip_source = "rightmost_x_forwarded_for";

        allow_federation = false;
        allow_registration = false;
        login_with_password = false;
        login_via_existing_session = false;
        require_auth_for_profile_requests = true;
        show_all_local_users_in_user_directory = true;

        refresh_token_ttl = 259200;
        oidc_rc_per_second = 2;
        oidc_rc_burst_count = 10;
        # Clients whose redirect target is listed here sign in without the
        # approval page; anything else is shown to the user first
        # (oidc_require_client_approval, default true). Element X iOS redirects
        # to https://element.io/..., Android to the private-use scheme
        # io.element.android:/ (needs tuwunel >= 1.9.1, see overlays/patches.nix).
        oidc_registration_allowed_redirect_hosts = [
          "element.io"
          "io.element.android"
        ];

        well_known = {
          client = "https://${domain}";
          support_contact.admin = {
            role = "m.role.admin";
            email_address = "dv_correia@hotmail.com";
          };
        };

        identity_provider = [
          {
            brand = "Pocket ID";
            name = config.services.pocket-id.settings.APP_NAME;
            default = true;
            issuer_url = config.services.pocket-id.settings.APP_URL;
            client_id = "matrix";
            client_secret_file = config.age.secrets.matrix-oidc.path;
            scope = [
              "openid"
              "profile"
              "email"
            ];
            userid_claims = [
              "preferred_username"
              "email"
            ];
            unique_id_fallbacks = false;
            registration = true;
          }
        ];
      };
    };
  };

  services.nginx.virtualHosts = {
    ${domain} = {
      addSSL = true;
      enableACME = true;
      extraConfig = ''
        client_max_body_size 50M;
      '';
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString port}";
        proxyWebsockets = true;
      };
    };

    ${serverName}.locations = {
      "= /.well-known/matrix/client" =
        let
          response = builtins.toJSON {
            "m.homeserver".base_url = "https://${domain}";
          };
        in
        {
          return = "200 '${response}'";
          extraConfig = ''
            default_type application/json;
            add_header Access-Control-Allow-Origin *;
          '';
        };

      "= /.well-known/matrix/support".proxyPass = "http://127.0.0.1:${toString port}";
    };
  };
}
