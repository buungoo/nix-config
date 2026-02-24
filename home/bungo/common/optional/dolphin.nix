# Dolphin file manager with KIO SMB support
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    kdePackages.dolphin
    kdePackages.kio-extras # KIO workers including SMB
    kdePackages.kdegraphics-thumbnailers
    kdePackages.ffmpegthumbs
  ];

  # SMB bookmark for NAS media share
  xdg.dataFile."kio/bookmarks.xml".text = ''
    <?xml version="1.0" encoding="UTF-8"?>
    <xbel>
      <bookmark href="smb://files.bungos.xyz/media">
        <title>NAS Media</title>
      </bookmark>
    </xbel>
  '';
}
