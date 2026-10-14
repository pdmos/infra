{ config, pkgs, ... }:

let
  settings = pkgs.writeText "komf-application.yml" ''
    komga:
      baseUri: http://127.0.0.1:${toString config.services.komga.settings.server.port}
      komgaUser: komf@pdmos.pt
      eventListener:
        enabled: true
      metadataUpdate:
        default:
          libraryType: MANGA
          # Keep COMIC_INFO out of updateModes: it makes Komf write ComicInfo.xml
          # into the book archives, and Transmission silently truncates any file
          # larger than its torrent's declared size the next time it opens it
          # (even just to serve a peer), corrupting the archive.
          updateModes: [API]
          aggregate: true
          seriesCovers: true
          overrideExistingCovers: true
          postProcessing:
            seriesTitle: true
            seriesTitleLanguage: en
            alternativeSeriesTitles: true
            alternativeSeriesTitleLanguages: [ja, ja-ro]
            orderBooks: true
    metadataProviders:
      defaultProviders:
        mangaUpdates:
          enabled: true
        mangaDex:
          enabled: true
          priority: 20
    database:
      file: /data/database.sqlite
    server:
      port: 8085
  '';

in
{
  age.secrets.komf-komga-password.file = ../../../secrets/komf-komga-password.age;
  age.secrets.komf-matrix-apprise-url.file = ../../../secrets/komf-matrix-apprise-url.age;

  virtualisation.oci-containers.containers.komf = {
    image = "docker.io/sndxr/komf:2.1.0@sha256:373580779e2e75d4e00e2f05859f789e05691c54600ca83d1cb528f0aad1f7b6";
    networks = [ "host" ];
    environment.KOMF_CONFIG_DIR = "/config/application.yml";
    volumes = [
      "${settings}:/config/application.yml:ro"
      "/var/lib/komf:/data"
      "${config.age.secrets.komf-komga-password.path}:/run/secrets/komga-password:ro"
      "${config.age.secrets.komf-matrix-apprise-url.path}:/run/secrets/matrix-apprise-url:ro"
    ];
    entrypoint = "/bin/sh";
    cmd = [
      "-c"
      ''
        export KOMF_KOMGA_PASSWORD="$(cat /run/secrets/komga-password)"
        export KOMF_APPRISE_URLS="$(cat /run/secrets/matrix-apprise-url)"
        exec java -jar /app/komf-app-1.0.0-SNAPSHOT-all.jar
      ''
    ];
  };

  systemd.services.podman-komf = {
    after = [ "komga.service" ];
    serviceConfig.StateDirectory = "komf";
    serviceConfig.StateDirectoryMode = "0700";
  };
}
