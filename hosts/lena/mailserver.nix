{ inputs, config, ... }:
{
  imports = [
    inputs.nixos-mailserver.nixosModules.default
  ];

  age.secrets = {
    mailserver-diogo-password = {
      file = ../../secrets/mailserver-diogo-password.age;
      owner = config.mailserver.storage.owner;
      group = config.mailserver.storage.group;
    };
  };

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
    };

    aliases = {
      "postmaster@pdmos.pt" = "diogo@pdmos.pt";
      "abuse@pdmos.pt" = "diogo@pdmos.pt";
    };
  };

  services.nginx.virtualHosts.${config.mailserver.fqdn} = {
    enableACME = true;
    forceSSL = true;
  };
}
