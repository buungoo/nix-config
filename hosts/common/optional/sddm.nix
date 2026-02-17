# SDDM display manager configuration
{ pkgs, ... }:
{
  services.xserver.enable = true;
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
    package = pkgs.kdePackages.sddm; # Qt6 version required for this theme
    theme = "Elegant";
    extraPackages = with pkgs; [
      kdePackages.qtsvg # for SVG rendering
      kdePackages.qt5compat
    ];
  };

  # Theme must be in systemPackages to be linked to /run/current-system/sw/share/sddm/themes/
  environment.systemPackages = [ pkgs.elegant-sddm ];
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.sddm.enableGnomeKeyring = true;
}
