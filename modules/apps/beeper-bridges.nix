{ gpus, ... }:

# Self-hosted Beeper bridges and voice message transcription, on this
# machine (docs/beeper-bridges.md). Both run as system services: the bridges
# connect the Beeper account's chat networks without counting against its
# account limit, and the transcriber attaches Whisper transcripts to
# incoming voice messages.
#
# Only one machine may run them at a time — two copies of a bridge would
# fight over the same accounts — so the laptops leave this out
# (disabledModules), and the desktop will too once the cloud server
# (server/) takes over; the server imports the two parts below directly.
{
  imports = [
    ./beeper-bridges/bridges.nix
    ./beeper-bridges/transcriber.nix
  ];

  # Whisper on the GPU (Vulkan) with the full-precision model, instead of
  # the server's CPU setup.
  beeperTranscriber.gpu = gpus != [ ];
}
