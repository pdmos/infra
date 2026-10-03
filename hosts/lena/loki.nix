{ config, ... }:

let
  inherit (config.services) loki;
  listenAddress = "127.0.0.1";
in
{
  services.loki = {
    enable = true;
    configuration = {
      auth_enabled = false;

      server = {
        http_listen_address = listenAddress;
        http_listen_port = 3100;
        grpc_listen_address = listenAddress;
      };

      common = {
        path_prefix = loki.dataDir;
        instance_addr = listenAddress;
        ring = {
          kvstore.store = "inmemory";
        };
        replication_factor = 1;
      };

      schema_config.configs = [
        {
          from = "2026-05-30"; # 🎉
          store = "tsdb";
          object_store = "filesystem";
          schema = "v13";
          index = {
            prefix = "index_";
            period = "24h";
          };
        }
      ];

      storage_config.filesystem.directory = "${loki.dataDir}/chunks";

      compactor = {
        working_directory = "${loki.dataDir}/compactor";
        retention_enabled = true;
        delete_request_store = "filesystem";
      };
      limits_config.retention_period = "336h";
    };
  };

  services.alloy.enable = true;
  systemd.services.alloy.serviceConfig.SupplementaryGroups = [ config.services.nginx.group ];
  environment.etc."alloy/config.alloy".text = ''
    loki.relabel "journal" {
      forward_to = []

      rule {
        source_labels = ["__journal__systemd_unit"]
        target_label  = "unit"
      }
    }

    loki.source.journal "systemd" {
      labels        = {host = "${config.networking.hostName}"}
      max_age       = "12h"
      relabel_rules = loki.relabel.journal.rules
      forward_to    = [loki.write.local.receiver]
    }

    loki.source.file "nginx" {
      targets = [
        {__path__ = "/var/log/nginx/access.log", job = "nginx", host = "${config.networking.hostName}"},
      ]
      tail_from_end = true
      forward_to    = [loki.write.local.receiver]

      file_match {
        enabled = true
      }
    }

    loki.write "local" {
      endpoint {
        url = "http://${loki.configuration.server.http_listen_address}:${toString loki.configuration.server.http_listen_port}/loki/api/v1/push"
      }
    }
  '';
}
