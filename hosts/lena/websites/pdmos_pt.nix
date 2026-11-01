{ pkgs, ... }:

let
  stateDir = "/var/lib/pdmos-site";
  site = ../../../site;
in
{
  services.nginx.virtualHosts."pdmos.pt" = {
    addSSL = true;
    enableACME = true;
    root = "${stateDir}/public";
    locations."/".extraConfig = ''
      add_header Content-Security-Policy "default-src 'none'; img-src 'self'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'" always;
      add_header Referrer-Policy "no-referrer" always;
      add_header X-Content-Type-Options "nosniff" always;
    '';
  };

  users.users.pdmos-site = {
    isSystemUser = true;
    group = "pdmos-site";
  };
  users.groups.pdmos-site = { };

  # Hugo fetches the municipality events feed at build time, so the site is rebuilt on boot,
  # on every deploy that changes it, and once a day. A failed build (feed down) leaves the
  # previous pages in place.
  # Not DynamicUser: its state would live under /var/lib/private (0700), which nginx can't read
  systemd.services.pdmos-site = {
    description = "Build pdmos.pt";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    startAt = "*-*-* 06:00:00";
    serviceConfig = {
      Type = "oneshot";
      User = "pdmos-site";
      Group = "pdmos-site";
      StateDirectory = "pdmos-site";
      StateDirectoryMode = "0755";
      CacheDirectory = "pdmos-site";
      ExecStart = "${pkgs.hugo}/bin/hugo --source ${site} --destination ${stateDir}/public --cacheDir /var/cache/pdmos-site --noBuildLock";
    };
  };

  systemd.timers.pdmos-site.timerConfig.Persistent = true;
}
