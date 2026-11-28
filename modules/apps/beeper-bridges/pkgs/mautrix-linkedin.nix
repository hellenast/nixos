{ lib, buildGoModule, fetchFromGitHub }:

# The LinkedIn bridge (../bridges.nix). Not in nixpkgs; built like
# nixpkgs' mautrix-whatsapp, with goolm instead of the insecure libolm.
buildGoModule (finalAttrs: {
  pname = "mautrix-linkedin";
  version = "26.11";
  tag = "v0.2611.0";

  src = fetchFromGitHub {
    owner = "mautrix";
    repo = "linkedin";
    inherit (finalAttrs) tag;
    hash = "sha256-If4IipwjrFEfAy84Ea2QWnynlbAHalX2vf3CszQaPYg=";
  };

  vendorHash = "sha256-mjL+Dyq/f1A1nShVXo0TH5VxuVFNvsG45OnUSfpW6O0=";
  subPackages = [ "cmd/mautrix-linkedin" ];
  tags = [ "goolm" ];
  ldflags = [ "-s" "-w" "-X" "main.Tag=${finalAttrs.tag}" ];

  meta = {
    description = "Matrix-LinkedIn puppeting bridge";
    homepage = "https://github.com/mautrix/linkedin";
    license = lib.licenses.agpl3Plus;
    mainProgram = "mautrix-linkedin";
  };
})
