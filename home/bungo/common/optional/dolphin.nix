# Dolphin file manager with KIO SMB support
#
# TODO: KIO SMB worker silently fails with QUIC transport (no network traffic
# reaches the server). smbclient CLI works fine with the same smb.conf/samba
# 4.23.5/ngtcp2 stack. Likely a bug in how KIO's SMB worker initializes
# libsmbclient's QUIC context. TCP fallback also didn't work in testing.
# For now, use `smbclient` from the terminal.
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    kdePackages.dolphin
    kdePackages.kio-extras # KIO workers including SMB
    kdePackages.kdegraphics-thumbnailers
    kdePackages.ffmpegthumbs
  ];

  # Network shortcut for NAS media share (visible in Dolphin's Network folder)
  xdg.dataFile."remoteview/nas-media.desktop".text = ''
    [Desktop Entry]
    Type=Link
    URL[$e]=smb://samba_media@files.bungos.xyz/media
    Icon=network-server
    Name=NAS Media
  '';
}
