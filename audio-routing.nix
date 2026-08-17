{ config, pkgs, lib, ... }:

let
  # Virtual mic via PipeWire's PulseAudio-compat layer: a null sink
  # automatically gets a paired ".monitor" source, which is what any host
  # app (Discord, games via Steam/Proton, OBS, ...) picks as its mic input.
  # This is the version that actually runs stably for me — no crashes,
  # unlike my earlier attempts with libpipewire-module-loopback.
  #
  # How I actually use this: with the Windows VM's Dubbing AI running
  # (Listen to myself on, output set to "Speakers"), I route
  # the VM's SPICE playback stream into "DubbingAI_Virtual_Mic" via
  # pavucontrol's Playback tab. Then any host app just picks the paired
  # monitor source ("Monitor of DubbingAI_Virtual_Mic") as its mic input.
  startScript = pkgs.writeShellScript "dubbingai-virtual-mic-start" ''
    if ! ${pkgs.pulseaudio}/bin/pactl list sinks short | grep -q dubbingai_sink; then
      ${pkgs.pulseaudio}/bin/pactl load-module module-null-sink \
        sink_name=dubbingai_sink \
        sink_properties=device.description=DubbingAI_Virtual_Mic
    fi
  '';

  stopScript = pkgs.writeShellScript "dubbingai-virtual-mic-stop" ''
    id=$(${pkgs.pulseaudio}/bin/pactl list modules short | \
      awk '/module-null-sink/ && /sink_name=dubbingai_sink/ {print $1; exit}')
    if [ -n "$id" ]; then
      ${pkgs.pulseaudio}/bin/pactl unload-module "$id"
    fi
  '';
in
{
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
}
