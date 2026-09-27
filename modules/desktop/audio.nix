{ ... }:

# PipeWire, with the ALSA and PulseAudio compatibility layers so every app
# finds a server it knows how to talk to.
{
  # Lets PipeWire request realtime scheduling, to avoid audio dropouts.
  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true; # 32-bit games (Steam/Proton) and Wine
    pulse.enable = true;
  };
}
