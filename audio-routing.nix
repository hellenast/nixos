{ config, pkgs, lib, ... }:

let
  # My virtual mic, via PipeWire's PulseAudio-compat layer: a null sink
  # automatically gets a paired ".monitor" source. That monitor source is
  # what I used to have to pick manually as my mic input, but PipeWire tags
  # monitor sources as "device.class = monitor", and most pickers
  # (caelestia's UI, pavucontrol's Input Devices tab, and any app that just
  # uses "the default mic" like Sober/Zapzap) filter monitor sources out of
  # the input list entirely — so it can never be set as default. My fix:
  # module-remap-source wraps the monitor in a plain source that isn't
  # tagged as a monitor, so it shows up as a normal input device and can be
  # set as the system default source.
  # This is the version that actually runs stably for me — no crashes,
  # unlike my earlier attempts with libpipewire-module-loopback.
  #
  # How I actually use this: with the Windows VM's Dubbing AI running
  # (Listen to myself on, output set to "Speakers"), I route
  # the VM's SPICE playback stream into "DubbingAI_Virtual_Mic" via
  # pavucontrol's Playback tab. Then I set "DubbingAI_Mic" (the remapped
  # source) as my default input device, and any host app picks it up.
  startScript = pkgs.writeShellScript "dubbingai-virtual-mic-start" ''
    if ! ${pkgs.pulseaudio}/bin/pactl list sinks short | grep -q dubbingai_sink; then
      ${pkgs.pulseaudio}/bin/pactl load-module module-null-sink \
        sink_name=dubbingai_sink \
        sink_properties=device.description=DubbingAI_Virtual_Mic
    fi

    # module-null-sink always starts muted-out at 0% volume, which silently
    # kills everything downstream even though the routing is otherwise fine.
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
