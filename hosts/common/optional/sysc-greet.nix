# sysc-greet display manager configuration
{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:
{
  imports = [ inputs.sysc-greet.nixosModules.default ];
  services.greetd = {
    enable = true;
    useTextGreeter = true;
  };
  services.sysc-greet = {
    enable = true;
    compositor = "hyprland";
  };

  # Override greeter's Hyprland config to use Swedish keyboard layout
  environment.etc."greetd/hyprland-greeter-config.conf" =
    let
      pkg = inputs.sysc-greet.packages.${pkgs.stdenv.hostPlatform.system}.default;
    in
    {
      source = lib.mkForce (
        pkgs.runCommand "hyprland-greeter-config" { } ''
                cp ${pkg}/etc/greetd/hyprland-greeter-config.conf $out
                chmod +w $out
                cat >> $out <<'EOF'

          input {
              kb_layout = se
              kb_variant = nodeadkeys
          }
          EOF
        ''
      );
    };

  services.gnome.gnome-keyring.enable = true;
  security.pam.services = {
    greetd.enableGnomeKeyring = true;
    hyprlock = { };
  };
}
