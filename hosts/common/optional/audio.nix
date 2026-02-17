{ ... }:
{
  # Disable PulseAudio in favor of Pipewire
  services.pulseaudio.enable = false;

  # Required for realtime audio priority
  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # jack.enable = true; # Uncomment for JACK applications
  };
}
