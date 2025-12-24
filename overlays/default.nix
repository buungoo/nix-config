# Custom overlays
{ inputs }:
{
  # This one brings our custom packages from the 'pkgs' directory
  default = final: _prev: import ../pkgs/common { pkgs = final; };

  # Samba 4.23.x overlay for SMB over QUIC support
  samba-overlay = import ./samba-overlay.nix;

  # QUIC kernel module overlay
  quic-kernel-module-overlay = import ./quic-kernel-module-overlay.nix;

  # Fix brew-nix Vivaldi .tar.xz extraction
  vivaldi-fix = import ./vivaldi-fix.nix;
}
