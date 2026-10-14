{
  config,
  lib,
  ...
}:

let
  cfg = config.services.nyaa-si;

  flexgetConfig = {
    tasks = lib.mapAttrs (
      name: feed:
      {
        rss = feed.url;
        seen = "local";
        transmission = {
          host = "127.0.0.1";
          port = config.services.transmission.settings.rpc-port;
          path = feed.path;
        };
      }
      // lib.optionalAttrs (feed.accept != [ ] || feed.reject != [ ]) {
        regexp =
          (lib.optionalAttrs (feed.accept != [ ]) {
            accept = feed.accept;
          })
          // (lib.optionalAttrs (feed.reject != [ ]) {
            reject = feed.reject;
          });
      }
    ) cfg.feeds;
  };

  # The Transmission service runs in a sandbox that only sees explicitly bound
  # paths, so bind the parent of every download destination.
  bindPaths = lib.unique (map (feed: builtins.dirOf feed.path) (lib.attrValues cfg.feeds));
in
{
  options.services.nyaa-si = {
    enable = lib.mkEnableOption "downloading nyaa.si feeds through Transmission";

    interval = lib.mkOption {
      type = lib.types.str;
      default = "15m";
      description = "How often the feeds are polled. See systemd.time(7).";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "komga";
      description = "Group that owns and can read the downloaded files.";
    };

    feeds = lib.mkOption {
      default = { };
      description = "Feeds to poll, keyed by an arbitrary task name.";
      type = lib.types.attrsOf (
        lib.types.submodule (
          { config, ... }:
          {
            options = {
              url = lib.mkOption {
                type = lib.types.str;
                default = "https://nyaa.si/?page=rss&c=${config.category}&q=${
                  lib.replaceStrings [ " " ] [ "+" ] config.query
                }";
                description = "RSS URL to poll. Defaults to a nyaa.si search.";
              };

              category = lib.mkOption {
                type = lib.types.str;
                default = "0_0";
                description = "nyaa.si category id, e.g. 3_1 for English-translated literature.";
              };

              query = lib.mkOption {
                type = lib.types.str;
                default = "";
                description = "nyaa.si search query.";
              };

              accept = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "Regular expressions a release title must match.";
              };

              reject = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "Regular expressions a release title must not match.";
              };

              path = lib.mkOption {
                type = lib.types.str;
                example = "/srv/downloads/manga";
                description = "Absolute download directory for this feed.";
              };
            };
          }
        )
      );
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = lib.concatLists (
      lib.mapAttrsToList (name: feed: [
        {
          assertion = lib.hasPrefix "/" feed.path;
          message = "services.nyaa-si.feeds.${name}.path must be an absolute path.";
        }
      ]) cfg.feeds
    );

    users.groups.flexget = { };
    users.users.flexget = {
      isSystemUser = true;
      group = "flexget";
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/flexget 0750 flexget flexget - -"
    ]
    # setgid + group-write so Transmission can add files that the group can read.
    # The parent directories need not exist beforehand; tmpfiles creates them.
    # The quoting is required: tmpfiles splits fields on whitespace.
    ++ map (feed: "d \"${feed.path}\" 2770 ${config.services.transmission.user} ${cfg.group} - -") (
      lib.attrValues cfg.feeds
    );

    services.flexget = {
      enable = true;
      user = "flexget";
      homeDir = "/var/lib/flexget";
      interval = cfg.interval;
      # lib.generators.toYAML is an alias for toJSON, so this renders the tasks
      # as a flow mapping. It must stay nested under the block key `tasks`: the
      # flexget module appends `schedules: no`, which would start a second YAML
      # document if our config were the root flow mapping.
      config = "tasks: " + lib.generators.toYAML { } flexgetConfig.tasks;
    };

    services.transmission = {
      enable = true;
      inherit (cfg) group;
      settings = {
        # Localhost RPC used by FlexGet.
        rpc-authentication-required = false;
        rpc-whitelist-enabled = true;
        rpc-whitelist = "127.0.0.1";

        # Seed fairly without becoming a long-term host: stop once the swarm
        # has been quiet for two hours, or once we have given back twice what
        # we downloaded. Torrents are paused; files stay in place for Komga.
        idle-seeding-limit = 120; # minutes without peer activity
        idle-seeding-limit-enabled = true;
        ratio-limit = 2.0;
        ratio-limit-enabled = true;
      };
    };

    systemd.services.transmission.serviceConfig.BindPaths = bindPaths;
  };
}
