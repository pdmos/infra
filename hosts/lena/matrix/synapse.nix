{ config, pkgs, ... }:
let
  # Matrix identity: users are @name:pdmos.pt
  serverName = "pdmos.pt";
  # Where the homeserver actually answers
  fqdn = "matrix.${serverName}";
  baseUrl = "https://${fqdn}";

  # Authentication is delegated to MAS; clients are pointed at it from here.
  masBaseUrl = config.services.matrix-authentication-service.settings.http.public_base;
  masEndpoint = "http://127.0.0.1:8080/";
  # nginx rejects proxy_pass with a URI part in a regex location, and a trailing
  # slash counts as one.
  masUpstream = "http://127.0.0.1:8080";

  # Served at https://pdmos.pt/.well-known/matrix/client — this is how clients
  # discover both the homeserver and the authentication service from "pdmos.pt".
  clientConfig = {
    "m.homeserver".base_url = baseUrl;
    "org.matrix.msc2965.authentication" = {
      issuer = masBaseUrl;
      account = "${masBaseUrl}account/";
    };
  };

  mkWellKnown = data: ''
    default_type application/json;
    add_header Access-Control-Allow-Origin *;
    return 200 '${builtins.toJSON data}';
  '';
in
{
  services.postgresql = {
    enable = true;
    # Synapse requires a database with "C" collation. This script only runs on
    # the first initialisation of the PostgreSQL cluster.
    initialScript = pkgs.writeText "synapse-init.sql" ''
      CREATE ROLE "matrix-synapse" WITH LOGIN;
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

      # All authentication is handled by MAS: no local passwords, no OIDC here.
      matrix_authentication_service = {
        enabled = true;
        endpoint = masEndpoint;
        secret_path = config.age.secrets.mas-synapse-secret.path;
      };

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
      # Login lives in MAS, not in Synapse. Regex locations are matched before
      # the prefix ones below, so this wins for these three endpoints.
      locations."~ ^/_matrix/client/(.*)/(login|logout|refresh)".proxyPass = masUpstream;
      # Matrix API (no trailing slash, on purpose).
      locations."/_matrix".proxyPass = "http://127.0.0.1:8008";
      locations."/_synapse/client".proxyPass = "http://127.0.0.1:8008";
      # Endpoints Synapse exposes for MAS itself.
      locations."/_synapse/mas".proxyPass = "http://127.0.0.1:8008";
    };

    # Homeserver discovery lives on the root domain (vhost defined in
    # pocket-id.nix / websites/pdmos_pt.nix), next to the Pocket ID webfinger.
    ${serverName}.locations."= /.well-known/matrix/client".extraConfig = mkWellKnown clientConfig;
  };
}
