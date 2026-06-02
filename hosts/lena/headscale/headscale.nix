{ config, pkgs, ... }:
let
  domain = "ts.pdmos.pt";
  tailnetDomain = "pdmos.ts";
in
{
  age.secrets.headscale-oidc = {
    file = ../../../secrets/headscale-oidc.age;
    owner = config.services.headscale.user;
    group = config.services.headscale.group;
  };

  environment.systemPackages = with pkgs; [ headscale ];

  services.headscale = {
    enable = true;
    address = "127.0.0.1";
    port = 8080;

    settings = {
      server_url = "https://${domain}";
      dns = {
        magic_dns = true;
        override_local_dns = true;
        base_domain = tailnetDomain;
        search_domains = [ tailnetDomain ];
        nameservers.global = [
          "1.1.1.1"
          "1.0.0.1"
          "2606:4700:4700::1111"
          "2606:4700:4700::1001"
        ];
      };
      oidc = {
        issuer = "https://id.pdmos.pt";
        client_id = "headscale";
        client_secret_path = config.age.secrets.headscale-oidc.path;
        pkce.enabled = true;
        allowed_users = [
          "dv_correia@hotmail.com"
        ];
      };
      policy.path = ./policies.jsonc;
    };
  };

  users.groups.${config.services.headscale.group}.members = [
    "nginx"
    "dvcorreia"
  ];

  services.nginx.virtualHosts.${domain} = {
    addSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://localhost:${toString config.services.headscale.port}";
      proxyWebsockets = true;
    };
  };
}
