{ config, pkgs, ... }:
let
  # Matrix identity: users are @name:pdmos.pt
  serverName = "pdmos.pt";
  # Where the homeserver actually answers
  fqdn = "matrix.${serverName}";
  baseUrl = "https://${fqdn}";

  # Served at https://pdmos.pt/.well-known/matrix/client — this is how Element X
  # and other clients discover the homeserver from "pdmos.pt".
  clientConfig."m.homeserver".base_url = baseUrl;

  mkWellKnown = data: ''
    default_type application/json;
    add_header Access-Control-Allow-Origin *;
    return 200 '${builtins.toJSON data}';
  '';
in
{
  # Client secret of the "Matrix" application created in Pocket ID.
  age.secrets.matrix-oidc = {
    file = ../../../secrets/matrix-oidc.age;
    owner = "matrix-synapse";
    group = "matrix-synapse";
  };

  services.postgresql = {
    enable = true;
    # Synapse requires a database with "C" collation. This script only runs on
    # the first initialisation of the PostgreSQL cluster.
    initialScript = pkgs.writeText "synapse-init.sql" ''
      CREATE ROLE "matrix-synapse";
      CREATE DATABASE "matrix-synapse" WITH OWNER "matrix-synapse"
        TEMPLATE template0
        LC_COLLATE = "C"
        LC_CTYPE = "C";
    '';
  };

  services.matrix-synapse = {
    enable = true;

    settings = {
      server_name = serverName;
      public_baseurl = baseUrl;

      # Client API only, on loopback, behind nginx.
      # No "federation" resource: this server does not talk to other homeservers.
      listeners = [
        {
          port = 8008;
          bind_addresses = [ "127.0.0.1" ];
          type = "http";
          tls = false;
          x_forwarded = true;
          resources = [
            {
              names = [ "client" ];
              compress = true;
            }
          ];
        }
      ];

      # Federation off: an empty whitelist means no domain is allowed.
      federation_domain_whitelist = [ ];
      allow_public_rooms_over_federation = false;

      # Pocket ID is the only way in. No passwords, no open registration.
      enable_registration = false;
      password_config.enabled = false;

      oidc_providers = [
        {
          idp_id = "pocket-id";
          idp_name = "Fuas ID";
          issuer = "https://id.pdmos.pt";
          client_id = "matrix";
          client_secret_path = config.age.secrets.matrix-oidc.path;
          scopes = [
            "openid"
            "profile"
            "email"
          ];
          # Creates the Matrix account on first login; the localpart comes from
          # the Pocket ID username (Synapse normalises it to lowercase).
          user_mapping_provider.config = {
            localpart_template = "{{ user.preferred_username }}";
            display_name_template = "{{ user.name }}";
            email_template = "{{ user.email }}";
          };
        }
      ];

      # Keep display name and avatar in sync with Pocket ID on every login.
      sso.update_profile_information = true;

      # Closed server for a handful of people: everyone can find everyone in the
      # user directory without having to share a room first.
      user_directory.search_all_users = true;

      # Media: 7 people and 40 GB of disk. Without federation there is no remote cache.
      max_upload_size = "50M";

      # Usage reports to matrix.org: no.
      report_stats = false;
    };
  };

  services.nginx.virtualHosts = {
    ${fqdn} = {
      addSSL = true;
      enableACME = true;
      # Must match max_upload_size above.
      extraConfig = ''
        client_max_body_size 50M;
      '';
      locations."/".extraConfig = ''
        return 404;
      '';
      # Matrix API (no trailing slash, on purpose).
      locations."/_matrix".proxyPass = "http://127.0.0.1:8008";
      # SSO flow (the OIDC callback lands here).
      locations."/_synapse/client".proxyPass = "http://127.0.0.1:8008";
    };

    # Homeserver discovery lives on the root domain (vhost defined in
    # pocket-id.nix / websites/pdmos_pt.nix), next to the Pocket ID webfinger.
    ${serverName}.locations."= /.well-known/matrix/client".extraConfig = mkWellKnown clientConfig;
  };
}
