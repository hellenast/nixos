{ pkgs, modulesPath, inputs, ... }:

# hyena-cloud: an always-on server for the self-hosted Beeper bridges and
# voice message transcription (modules/apps/beeper-bridges/) — see
# docs/beeper-bridges.md. It's an Oracle Cloud Always Free Ampere A1 VM
# (aarch64), installed over Oracle's stock Ubuntu image with nixos-anywhere and
# deployed from the desktop over SSH. It shares nothing with the desktop and
# laptop configs (no desktop, no home-manager) and has only SSH open: the
# bridges and the transcriber connect out to Beeper.
let
  vars = import ./variables.nix;
in
{
  imports = [
    "${modulesPath}/profiles/qemu-guest.nix"
    inputs.disko.nixosModules.disko
    ./disko.nix
    # The same bridges and transcriber the desktop runs until this server
    # exists (modules/apps/beeper-bridges.nix), on the CPU here.
    ../modules/apps/beeper-bridges/bridges.nix
    ../modules/apps/beeper-bridges/transcriber.nix
  ];

  assertions = [{
    assertion = vars.sshAuthorizedKeys != [ ];
    message = "server/variables.nix: add an SSH public key to sshAuthorizedKeys, or nobody can log in to the server.";
  }];

  nixpkgs.hostPlatform = "aarch64-linux";
  networking.hostName = vars.hostname;
  time.timeZone = (import ../variables.nix).timeZone;
  i18n.defaultLocale = "en_US.UTF-8";
  # The NixOS release first installed here; like the desktop's, never bump it.
  system.stateVersion = "26.11";

  # --- Boot ---
  # Oracle's A1 VMs boot UEFI. Their firmware doesn't keep NVRAM boot
  # entries, so the loader has to be at the fallback path
  # (EFI/BOOT/BOOTAA64.EFI), which systemd-boot also installs to.
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 10;
  boot.loader.efi.canTouchEfiVariables = false;
  # From nixpkgs' oci-common.nix (Oracle's own Ubuntu image): the serial
  # console, for Oracle's web console when SSH is unreachable, and the
  # timeouts its storage needs.
  boot.kernelParams = [
    "nvme.shutdown_timeout=10"
    "nvme_core.shutdown_timeout=10"
    "console=tty1"
    "console=ttyAMA0,115200"
  ];

  # --- Network ---
  networking.useNetworkd = true;
  networking.useDHCP = true;
  # Oracle's NTP service.
  networking.timeServers = [ "169.254.169.254" ];
  # Only SSH. Oracle's own firewall (the VCN security list) also allows just
  # port 22 by default.
  networking.firewall.enable = true;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };
  users.users.root.openssh.authorizedKeys.keys = vars.sshAuthorizedKeys;
  # Repeated failed logins get banned for a while; any public IP on port 22
  # sees constant password guessing.
  services.fail2ban.enable = true;

  # --- Nix ---
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    # Deploys copy builds in as root over SSH.
    trusted-users = [ "root" ];
    auto-optimise-store = true;
  };
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  # --- Memory ---
  # Compressed in-RAM swap, as on the desktop (system/memory.nix).
  zramSwap = {
    enable = true;
    algorithm = "zstd";
  };
  services.journald.settings.Journal.SystemMaxUse = "500M";

  environment.systemPackages = with pkgs; [ htop jq sqlite ];
}
