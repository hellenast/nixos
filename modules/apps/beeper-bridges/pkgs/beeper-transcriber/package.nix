{ lib, buildGoModule }:

# Voice message transcription for a Beeper account, with Whisper — see
# main.go. Built from the source next to this file.
buildGoModule {
  pname = "beeper-transcriber";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.fileFilter (file: lib.hasSuffix ".go" file.name || file.name == "go.mod" || file.name == "go.sum") ./.;
  };

  vendorHash = "sha256-lvT2lNiJVVmdE4Wdz2w0A8+C4/KCeYW79tb9oHXgG+8=";

  # mautrix-go's pure-Go Olm implementation, instead of libolm (which
  # nixpkgs marks insecure).
  tags = [ "goolm" ];
  ldflags = [ "-s" "-w" ];

  meta = {
    description = "Transcribes voice messages on a Beeper account with Whisper, shown natively in Beeper's apps";
    mainProgram = "beeper-transcriber";
    platforms = lib.platforms.linux;
  };
}
