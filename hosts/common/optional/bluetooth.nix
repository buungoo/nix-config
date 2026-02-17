# Bluetooth configuration with high-quality codec support
{ ... }:
{
  hardware.bluetooth.enable = true;
  services.blueman.enable = true;

  # Enable high-quality bluetooth audio codecs
  services.pipewire.wireplumber.extraConfig = {
    "10-bluetooth-codecs" = {
      "monitor.bluez.properties" = {
        # Codecs
        "bluez5.enable-sbc-xq" = true;
        "bluez5.enable-msbc" = true;
        "bluez5.enable-aac" = true;
        "bluez5.enable-aptx" = true;
        "bluez5.enable-aptx-hd" = true;
        "bluez5.enable-ldac" = true;

        # Features
        "bluez5.enable-hw-volume" = true;
        "bluez5.auto-switch-profile" = true;
      };
    };
  };
}
