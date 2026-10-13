{ config, pkgs, ... }:

let
  # Every series Komga serves lives here, so the sweep is library-wide and does
  # not need to know which feed produced a file.
  libraryRoot = "/srv/manga";

  comicInfo = pkgs.writers.writePython3Bin "komga-comic-info" { } (builtins.readFile ./comic-info.py);
in
{
  systemd.services.komga-comic-info = {
    description = "Add ComicInfo.xml metadata to downloaded comic archives";

    serviceConfig = {
      Type = "oneshot";
      # The archives belong to Transmission; writing as its user keeps the
      # ownership and the group Komga reads through unchanged.
      User = config.services.transmission.user;
      Group = config.services.transmission.group;
      ExecStart = "${comicInfo}/bin/komga-comic-info ${libraryRoot}";
      Nice = 19;
      IOSchedulingClass = "idle";
    };
  };

  systemd.timers.komga-comic-info = {
    wantedBy = [ "timers.target" ];

    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "5min";
    };
  };
}
