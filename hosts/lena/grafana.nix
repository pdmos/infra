{ config, ... }:

let
  inherit (config.services) pocket-id prometheus grafana;
in
{
  age.secrets.grafana-secret-key = {
    file = ../../secrets/grafana-secret-key.age;
    owner = "grafana";
    group = "grafana";
  };

  age.secrets.grafana-oauth2-client-secret = {
    file = ../../secrets/grafana-oauth2-client-secret.age;
    owner = "grafana";
    group = "grafana";
  };

  services.grafana = {
    enable = true;
    settings = {
      analytics.reporting_enabled = false; # (default)

      server = {
        http_addr = "127.0.0.1"; # (default)
        http_port = 2342;
        enforce_domain = true;
        enable_gzip = true;
        domain = "monitor.pdmos.pt";
        root_url = "https://monitor.pdmos.pt/";
      };

      security = {
        disable_initial_admin_creation = true;
        secret_key = "$__file{${config.age.secrets.grafana-secret-key.path}}";
        cookie_secure = true;
        disable_gravatar = true;
        hide_version = true;
      };

      auth.disable_login_form = true;
      "auth.generic_oauth" = {
        enabled = true;
        name = pocket-id.settings.APP_NAME;
        allow_sign_up = true;
        client_id = "grafana";
        client_secret = "$__file{${config.age.secrets.grafana-oauth2-client-secret.path}}";
        scopes = "openid email profile groups";
        auth_url = "${pocket-id.settings.APP_URL}/authorize";
        token_url = "${pocket-id.settings.APP_URL}/api/oidc/token";
        api_url = "${pocket-id.settings.APP_URL}/api/oidc/userinfo";
        use_pkce = true;
        role_attribute_path = "contains(groups[*], 'admin') && 'Editor' || 'Viewer'";
      };
    };

    provision = {
      enable = true;
      datasources.settings.datasources = [
        {
          name = "prometheus (lena)";
          type = "prometheus";
          url = "http://${prometheus.listenAddress}:${toString prometheus.port}";
          isDefault = true;
          editable = false; # (default)
        }
      ];
    };
  };

  services.nginx.virtualHosts.${grafana.settings.server.domain} = {
    addSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString grafana.settings.server.http_port}";
      proxyWebsockets = true;
    };
  };
}
