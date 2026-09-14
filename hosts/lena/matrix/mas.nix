{ config, ... }:
let
  domain = "auth.pdmos.pt";

  # Unique id of the Pocket ID provider inside MAS. It is part of the callback
  # URL registered in Pocket ID, so it must never change.
  pocketId = "01M2G3S82ZREQKCSKDT0EWCEJP";
in
{
  # Client secret of the "Matrix" application in Pocket ID. Loaded as a systemd
  # credential, so it stays root-owned.
  age.secrets.matrix-oidc.file = ../../../secrets/matrix-oidc.age;

  # A YAML fragment holding a single `secrets:` block: the database/cookie
  # encryption key and the token signing keys. Merged with the generated config.
  age.secrets.mas-secrets.file = ../../../secrets/mas-secrets.age;

  # Shared secret between MAS and Synapse. Synapse reads it directly, MAS gets it
  # as a systemd credential because it runs with DynamicUser.
  age.secrets.mas-synapse-secret = {
    file = ../../../secrets/mas-synapse-secret.age;
    owner = "matrix-synapse";
    group = "matrix-synapse";
  };

  services.matrix-authentication-service = {
    enable = true;
    createDatabase = true;

    extraConfigFiles = [ config.age.secrets.mas-secrets.path ];

    credentials = {
      synapse-secret = config.age.secrets.mas-synapse-secret.path;
      pocket-id-secret = config.age.secrets.matrix-oidc.path;
    };

    settings = {
      http = {
        public_base = "https://${domain}/";
        # Behind nginx on this host; never bind to a public address.
        listeners = [
          {
            name = "web";
            binds = [
              {
                host = "127.0.0.1";
                port = 8080;
              }
            ];
            resources = [
              { name = "discovery"; }
              { name = "human"; }
              { name = "oauth"; }
              { name = "compat"; }
              { name = "graphql"; }
              { name = "assets"; }
            ];
          }
          {
            name = "internal";
            binds = [
              {
                host = "127.0.0.1";
                port = 8081;
              }
            ];
            resources = [ { name = "health"; } ];
          }
        ];
      };

      database.uri = "postgresql:///matrix-authentication-service?host=/run/postgresql&user=matrix-authentication-service";

      matrix = {
        homeserver = "pdmos.pt";
        endpoint = "http://127.0.0.1:8008/";
        secret_file = "\${CREDENTIALS_DIRECTORY}/synapse-secret";
      };

      # Pocket ID is the only way in.
      passwords.enabled = false;

      upstream_oauth2.providers = [
        {
          id = pocketId;
          human_name = "Fuas ID";
          issuer = "https://id.pdmos.pt";
          client_id = "matrix";
          client_secret_file = "\${CREDENTIALS_DIRECTORY}/pocket-id-secret";
          token_endpoint_auth_method = "client_secret_basic";
          scope = "openid profile email";
          claims_imports = {
            # `suggest` shows the account on first login and lets the person edit
            # it, so the Matrix id is chosen once and is not tied to Pocket ID.
            localpart = {
              action = "suggest";
              template = "{{ user.preferred_username }}";
            };
            displayname = {
              action = "suggest";
              template = "{{ user.name }}";
            };
            email = {
              action = "suggest";
              template = "{{ user.email }}";
            };
          };
        }
      ];
    };
  };

  services.nginx.virtualHosts.${domain} = {
    addSSL = true;
    enableACME = true;
    locations."/".proxyPass = "http://127.0.0.1:8080";
  };
}
