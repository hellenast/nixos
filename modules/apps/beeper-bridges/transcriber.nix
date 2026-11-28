{ config, lib, pkgs, ... }:

# Voice message transcription for the Beeper account
# (docs/beeper-bridges.md): the transcriber (pkgs/beeper-transcriber) sends
# each new voice message to a local whisper.cpp server and attaches the text
# the way Beeper Plus does, so it shows under the message in every Beeper
# app. Nothing leaves the machine except the transcript, back to Beeper.
let
  cfg = config.beeperTranscriber;
  home = "/var/lib/beeper-transcriber";
  transcriber = pkgs.callPackage ./pkgs/beeper-transcriber/package.nix { };
  whisperPort = 8178;

  # Whisper large-v3-turbo. On a GPU at full precision (an 8 s voice
  # message takes ~0.6 s on the desktop's RX 9060 XT). On a CPU with 8-bit
  # weights: close to full precision on transcription quality, but half the
  # size (~0.9 GB) and faster; its _q5_0 sibling is faster still, for a
  # little more error.
  whisperModel =
    if cfg.gpu then pkgs.fetchurl {
      url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin";
      hash = "sha256-H8cPd0046xaZk6w5Huo1fvR8iHV+9y7llDh5t+jivGk=";
    } else pkgs.fetchurl {
      url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q8_0.bin";
      hash = "sha256-MX62nBFnPJ3h4fDUWbJTmZgE7HGsTCPBfs9fviTiWaE=";
    };
  # Vulkan works on AMD, Intel and NVIDIA alike; whisper.cpp takes the
  # first GPU Vulkan lists, which puts discrete ones first.
  whisperCpp = if cfg.gpu then pkgs.whisper-cpp.override { vulkanSupport = true; } else pkgs.whisper-cpp;

  environment = {
    # Voice messages you send too, not only the ones you receive (Beeper's
    # own auto-transcribe does incoming only).
    TRANSCRIBE_OWN = "true";
    TRANSCRIBER_STATE_DIR = home;
    WHISPER_URL = "http://127.0.0.1:${toString whisperPort}";
    WHISPER_MODEL_NAME = "whisper.cpp/${lib.removePrefix "ggml-" (lib.removeSuffix ".bin" whisperModel.name)}";
  };

  # The transcriber as the service's user, with its settings and state.
  asService = "${pkgs.util-linux}/bin/runuser -u beeper-transcriber -- env ${lib.concatStringsSep " " (lib.mapAttrsToList (k: v: "${k}=${v}") environment)} ${lib.getExe transcriber}";

  # The one-time interactive login (Beeper email code + recovery code).
  loginCommand = pkgs.writeShellScriptBin "beeper-transcriber-login" ''
    set -e
    ${asService} login
    systemctl restart beeper-transcriber
    echo "Transcriber started: journalctl -fu beeper-transcriber"
  '';

  # Goes over the voice messages of the last PERIOD (2d, 12h, ...):
  # transcribes the ones without a transcript, sends the others' again. It
  # uses the service's device, so the service is stopped meanwhile;
  # anything arriving then is caught up on when it's back.
  backfillCommand = pkgs.writeShellScriptBin "beeper-transcriber-backfill" ''
    set -e
    if [ $# -ne 1 ]; then
      echo "usage: beeper-transcriber-backfill PERIOD   (e.g. 2d, 12h)" >&2
      exit 2
    fi
    systemctl start whisper-server
    systemctl stop beeper-transcriber
    trap 'systemctl start beeper-transcriber' EXIT
    ${asService} backfill "$1"
  '';

  # Both services wait for beeper-transcriber-login: until then there's
  # nothing to transcribe, and the model would just sit in (video) memory.
  loggedIn = "${home}/session.json";
in
{
  options.beeperTranscriber.gpu = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Run Whisper on the GPU (Vulkan) with the full-precision model, instead of on the CPU with the 8-bit one.";
  };

  config = {
    users.users.beeper-transcriber = {
      isSystemUser = true;
      group = "beeper-transcriber";
      inherit home;
      createHome = true;
    };
    users.groups.beeper-transcriber = { };

    environment.systemPackages = [ loginCommand backfillCommand transcriber ];

    systemd.services.beeper-transcriber = {
      description = "Voice message transcription for Beeper";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" "whisper-server.service" ];
      after = [ "network-online.target" "whisper-server.service" ];
      unitConfig.ConditionPathExists = loggedIn;
      inherit environment;
      serviceConfig = {
        User = "beeper-transcriber";
        Group = "beeper-transcriber";
        ExecStart = "${lib.getExe transcriber} run";
        Restart = "always";
        RestartSec = 30;

        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ home ];
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
      };
    };

    systemd.services.whisper-server = {
      description = "whisper.cpp server, for the Beeper transcriber";
      wantedBy = [ "multi-user.target" ];
      unitConfig.ConditionPathExists = loggedIn;
      # --convert decodes Ogg/Opus voice messages through ffmpeg.
      path = [ pkgs.ffmpeg ];
      serviceConfig = {
        ExecStart = lib.concatStringsSep " " ([
          "${whisperCpp}/bin/whisper-server"
          "--host 127.0.0.1 --port ${toString whisperPort}"
          "--model ${whisperModel}"
          "--language auto --convert"
        ] ++ lib.optional (!cfg.gpu) "--threads 2"); # the cloud server's two cores
        DynamicUser = true;
        # --convert writes its temporary WAV files to the working directory.
        RuntimeDirectory = "whisper-server";
        WorkingDirectory = "%t/whisper-server";
        Restart = "always";
        RestartSec = 10;
        # Whatever else the machine is doing keeps priority for the CPU.
        Nice = 10;
      };
    };
  };
}
