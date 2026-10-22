{ pkgs, ... }:

let
  stateDir = "/var/lib/pdmos-site";
  feed = "https://www.municipio-portodemos.pt/pages/322.rss";
  headers = ''
    add_header Content-Security-Policy "default-src 'none'; img-src 'self'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'" always;
    add_header Referrer-Policy "no-referrer" always;
    add_header X-Content-Type-Options "nosniff" always;
  '';
in
{
  services.nginx.virtualHosts."pdmos.pt" = {
    addSSL = true;
    enableACME = true;
    locations."/" = {
      root = ./pdmos_pt/www;
      extraConfig = ''
        ssi on;
        ${headers}
      '';
    };
    locations."~ \\.webp$" = {
      root = ./pdmos_pt/www;
      extraConfig = ''
        expires 30d;
        ${headers}
      '';
    };
    # Only reachable through the SSI include in index.html
    locations."= /agenda.html" = {
      alias = "${stateDir}/agenda.html";
      extraConfig = "internal;";
    };
  };

  users.users.pdmos-site = {
    isSystemUser = true;
    group = "pdmos-site";
  };
  users.groups.pdmos-site = { };

  # Not DynamicUser: its state lives under /var/lib/private (0700), which nginx can't read
  systemd.services.pdmos-agenda = {
    description = "Refresh the events list on pdmos.pt";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    startAt = "*-*-* 06:00:00";
    serviceConfig = {
      Type = "oneshot";
      User = "pdmos-site";
      Group = "pdmos-site";
      StateDirectory = "pdmos-site";
      StateDirectoryMode = "0755";
      ExecStart = "${pkgs.python3.interpreter} ${./pdmos_pt/agenda.py} --url ${feed} --out ${stateDir}";
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
    };
  };

  systemd.timers.pdmos-agenda.timerConfig.Persistent = true;
}
