{ config, pkgs, ... }:
let
  # nixos-26.05 pins matrix-nio 0.25 (libolm); 0.26 in unstable moved to vodozemac.
  python = pkgs.unstable.python3.withPackages (ps: [
    (ps.matrix-nio.override { withVodozemac = true; })
    ps.beautifulsoup4
  ]);

  # Where the bot reads events from. `home` marks the mayor's own municipality:
  # only its events get the daily post; everything else is for replies.
  sources = [
    {
      name = "Porto de Mós";
      kind = "rss";
      url = "https://www.municipio-portodemos.pt/pages/322.rss";
      home = true;
    }
    {
      name = "Batalha";
      kind = "rss";
      url = "https://www.cm-batalha.pt/pages/322.rss";
    }
    {
      name = "Leiria";
      kind = "leiriagenda";
      url = "https://leiriagenda.cm-leiria.pt/pt/agenda";
    }
    {
      name = "Teatros de Leiria";
      kind = "tjls";
      url = "https://teatrojlsilva.pt/programacao/eventos";
    }
  ];
in
{
  age.secrets.jayvala-matrix-password.file = ../../../secrets/jayvala-matrix-password.age;
  age.secrets.jayvala-llm-api-key.file = ../../../secrets/jayvala-llm-api-key.age;

  systemd.services.jayvala = {
    description = "Jay Vala, Matrix bot";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "tuwunel.service"
    ];

    environment = {
      JAYVALA_HOMESERVER = "https://matrix.pdmos.pt";
      JAYVALA_USER = "@jay:pdmos.pt";
      # Room where the daily post goes. The bot must be invited there first.
      JAYVALA_ROOM = "#gabinete-do-presidente:pdmos.pt";
      JAYVALA_SOURCES = builtins.toJSON sources;
      # Any OpenAI-compatible chat endpoint. For Amália on the tailnet, e.g.
      # "http://<host>.pdmos.ts:11434/v1/chat/completions" with the Ollama model
      # name, and drop the llm-api-key credential below.
      JAYVALA_LLM_URL = "https://openrouter.ai/api/v1/chat/completions";
      JAYVALA_LLM_MODEL = "mistralai/mistral-small-3.2-24b-instruct";
      JAYVALA_POST_HOUR = "9";
      JAYVALA_REPLIES_PER_HOUR = "10";
      JAYVALA_TZ = "Europe/Lisbon";
    };

    serviceConfig = {
      ExecStart = "${python}/bin/python ${./jayvala/bot.py}";
      Restart = "on-failure";
      RestartSec = 30;

      DynamicUser = true;
      StateDirectory = "jayvala";
      LoadCredential = [
        "matrix-password:${config.age.secrets.jayvala-matrix-password.path}"
        "llm-api-key:${config.age.secrets.jayvala-llm-api-key.path}"
      ];

      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      NoNewPrivileges = true;
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
      ];
    };
  };
}
