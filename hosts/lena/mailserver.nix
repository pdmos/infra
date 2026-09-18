{
  inputs,
  config,
  lib,
  ...
}:
let
  admins = [
    "diogo@pdmos.pt"
    "afonsojanuario@pdmos.pt"
  ];
in
{
  imports = [
    inputs.nixos-mailserver.nixosModules.default
  ];

  age.secrets =
    lib.genAttrs [ "mailserver-diogo-password" "mailserver-afonsojanuario-password" ]
      (name: {
        file = ../../secrets/${name}.age;
        owner = config.mailserver.storage.owner;
        group = config.mailserver.storage.group;
      });

  mailserver = {
    enable = true;
    stateVersion = 5;
    fqdn = "mail.pdmos.pt";
    domains = [ "pdmos.pt" ];
    systemContact = "postmaster@pdmos.pt";

    x509.useACMEHost = config.mailserver.fqdn;

    enableSubmission = true;

    fullTextSearch = {
      enable = true;
      autoIndex = true;
      fallback = false;
    };

    dmarcReporting.enable = true;

    srs = {
      enable = true;
      domain = "srs.pdmos.pt";
    };

    accounts = {
      "diogo@pdmos.pt".hashedPasswordFile = config.age.secrets.mailserver-diogo-password.path;
      "afonsojanuario@pdmos.pt".hashedPasswordFile =
        config.age.secrets.mailserver-afonsojanuario-password.path;
    };

    # postmaster@ and abuse@ are delivered to every admin mailbox
    aliases = lib.genAttrs [ "postmaster@pdmos.pt" "abuse@pdmos.pt" ] (_: admins);
  };

  services.nginx.virtualHosts.${config.mailserver.fqdn} = {
    enableACME = true;
    forceSSL = true;
  };
}
