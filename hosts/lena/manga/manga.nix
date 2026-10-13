{ ... }:
{
  services.nyaa-si = {
    enable = true;

    feeds.one-piece = {
      category = "3_1";
      query = "One Piece";
      accept = [ "^One Piece \\d+$" ];
      path = "/srv/manga/One Piece";
    };
  };
}
