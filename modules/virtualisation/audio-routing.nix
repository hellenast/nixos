{ pkgs, ... }:

# A virtual microphone for the Windows VM's voice changer (windows-vm.nix):
# the VM's processed audio plays into it, and host apps (Discord, games,
# ...) record from it as if it were a normal mic. Day-to-day routing steps
# are in docs/virtualisation.md.

let
  # Built with pactl through PipeWire's PulseAudio layer:
  #  - a null sink, "DubbingAI_Virtual_Mic", that the VM's audio plays into;
  #  - its ".monitor" source, wrapped by module-remap-source as
  #    "DubbingAI_Mic", which becomes the default input.
  # The wrapper is needed because PipeWire tags monitor sources as
  # device.class=monitor, and most input pickers (caelestia's UI,
  # pavucontrol's Input Devices tab, apps that just use "the default mic")
  # hide those, so the raw monitor can't be made the default. The remapped
  # source is an ordinary input.
  #
  # (libpipewire-module-loopback was tried first and crashed; this setup is
  # stable.)
  startScript = pkgs.writeShellScript "dubbingai-virtual-mic-start" ''
    if ! ${pkgs.pulseaudio}/bin/pactl list sinks short | grep -q dubbingai_sink; then
      ${pkgs.pulseaudio}/bin/pactl load-module module-null-sink \
        sink_name=dubbingai_sink \
        sink_properties=device.description=DubbingAI_Virtual_Mic
    fi

    # A new null sink starts at 0% volume, which silently mutes everything
    # downstream even when the routing is right.
    ${pkgs.pulseaudio}/bin/pactl set-sink-volume dubbingai_sink 100%

    if ! ${pkgs.pulseaudio}/bin/pactl list sources short | grep -q dubbingai_mic; then
      ${pkgs.pulseaudio}/bin/pactl load-module module-remap-source \
        master=dubbingai_sink.monitor \
        source_name=dubbingai_mic \
        source_properties=device.description=DubbingAI_Mic
    fi

    ${pkgs.pulseaudio}/bin/pactl set-default-source dubbingai_mic
  '';

  stopScript = pkgs.writeShellScript "dubbingai-virtual-mic-stop" ''
    remap_id=$(${pkgs.pulseaudio}/bin/pactl list modules short | \
      awk '/module-remap-source/ && /source_name=dubbingai_mic/ {print $1; exit}')
    if [ -n "$remap_id" ]; then
      ${pkgs.pulseaudio}/bin/pactl unload-module "$remap_id"
    fi

    id=$(${pkgs.pulseaudio}/bin/pactl list modules short | \
      awk '/module-null-sink/ && /sink_name=dubbingai_sink/ {print $1; exit}')
    if [ -n "$id" ]; then
      ${pkgs.pulseaudio}/bin/pactl unload-module "$id"
    fi
  '';
in
{
  # Set up whenever the user's PipeWire session starts, torn down with it.
  systemd.user.services.dubbingai-virtual-mic = {
    description = "DubbingAI virtual mic (null-sink + monitor, via pactl)";
    wantedBy = [ "pipewire-pulse.service" ];
    after = [ "pipewire-pulse.service" ];
    partOf = [ "pipewire-pulse.service" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${startScript}";
      ExecStop = "${stopScript}";
    };
  };

  environment.systemPackages = with pkgs; [
    pavucontrol  # per-app mixer; routes the VM's playback into the virtual mic
    qpwgraph     # PipeWire patchbay, for inspecting/rewiring the nodes by hand
  ];
}
