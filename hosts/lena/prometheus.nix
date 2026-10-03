{ config, ... }:

let
  nodeExporter = {
    listenAddress = "127.0.0.1";
    port = 9001;
  };
in
{
  services.prometheus = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = 9000;

    scrapeConfigs = [
      {
        job_name = "lena";
        static_configs = [
          {
            targets = [
              "${nodeExporter.listenAddress}:${toString nodeExporter.port}"
            ];
          }
        ];
      }
    ];

    exporters.node = {
      enable = true;

      inherit (nodeExporter) listenAddress port;

      enabledCollectors = [
        "systemd"
        "processes"
      ];
    };
  };
}
