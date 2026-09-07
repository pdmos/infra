{ pkgs, ... }:
let
  domain = "chat.pdmos.pt";
in
{
  # Element Web: Matrix client in the browser, served as static files.
  # For security, Element is never served on the same domain as the homeserver.
  services.nginx.virtualHosts.${domain} = {
    addSSL = true;
    enableACME = true;

    root = pkgs.element-web.override {
      conf = {
        default_server_config."m.homeserver" = {
          base_url = "https://matrix.pdmos.pt";
          server_name = "pdmos.pt";
        };
        brand = "PDMOS";
        # Our homeserver only; no guests; no "pick another server".
        disable_custom_urls = true;
        disable_guests = true;
        disable_3pid_login = true;
        # Without federation, other servers' public room directories make no sense.
        room_directory.servers = [ "pdmos.pt" ];
        # Single IdP: keep the SSO button (set to true to skip straight to Pocket ID).
        sso_redirect_options.immediate = false;
        default_theme = "system";
        show_labs_settings = false;
      };
    };
  };
}
