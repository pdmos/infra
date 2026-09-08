{ ... }:
{
  services.nginx.virtualHosts."pdmos.pt" = {
    addSSL = true;
    enableACME = true;
    locations."/" = {
      return = ''200 '<img src="https://visite.portodemos.pt/thumbs/cmportodemos-turismo/uploads/geo_article/image/117/1_foto_livroportomos_portomos_castelo_00002_1_2500_2500.jpg" />' '';
      extraConfig = ''
        default_type text/html;
      '';
    };
  };
}
