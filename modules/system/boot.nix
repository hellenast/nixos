{ pkgs, ... }:

let
  # A Plymouth theme in caelestia's "hard" dark scheme colours
  # (~/.local/state/caelestia/scheme.json -> background/primary). The assets
  # (lock icon, password dots, keyboard/capslock indicators, spinner) are
  # catppuccin-plymouth's mocha set, driven by Plymouth's built-in `two-step`
  # plugin; only the .plymouth ini with my colours is new.
  #
  # A static snapshot, not derived from the live scheme: if caelestia's
  # scheme changes, update the hex values below by hand.
  caelestiaPlymouthTheme = pkgs.runCommand "caelestia-hard-plymouth-theme" { } ''
    themeDir=$out/share/plymouth/themes/caelestia-hard
    mkdir -p "$themeDir"
    cp ${pkgs.catppuccin-plymouth.override { variant = "mocha"; }}/share/plymouth/themes/catppuccin-mocha/*.png "$themeDir"/

    cat > "$themeDir"/caelestia-hard.plymouth <<EOF
    [Plymouth Theme]
    Name=caelestia-hard
    Description=Matches caelestia-shell's "hard" dark scheme
    ModuleName=two-step

    [two-step]
    Font=Noto Sans 12
    TitleFont=Noto Sans Light 30
    ImageDir=$themeDir
    DialogHorizontalAlignment=.5
    DialogVerticalAlignment=.5
    TitleHorizontalAlignment=.5
    TitleVerticalAlignment=.5
    HorizontalAlignment=.5
    VerticalAlignment=.5
    WatermarkHorizontalAlignment=.5
    WatermarkVerticalAlignment=.5
    Transition=none
    TransitionDuration=0.0
    BackgroundStartColor=0x020305
    BackgroundEndColor=0x020305
    ProgressBarBackgroundColor=0x090b0f
    ProgressBarForegroundColor=0xb4c7ed
    MessageBelowAnimation=true

    [boot-up]
    UseEndAnimation=false

    [shutdown]
    UseEndAnimation=false

    [reboot]
    UseEndAnimation=false
    EOF
  '';
in
{
  # systemd-boot on UEFI. On a legacy-BIOS machine, replace these two lines
  # with:
  #   boot.loader.grub.enable = true;
  #   boot.loader.grub.device = "/dev/sda";
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # A systemd-based initrd is what lets Plymouth draw the LUKS passphrase
  # prompt (disko.nix). The classic initrd asks for the passphrase as plain
  # console text before Plymouth starts; systemd's systemd-ask-password
  # talks to Plymouth directly instead.
  boot.initrd.systemd.enable = true;

  # Themed splash + LUKS unlock screen. No NixOS logo watermark: Plymouth
  # only wires that up for the stock catppuccin theme names, not a custom
  # one. For the splash to render at native resolution from the first frame,
  # amdgpu is also loaded in the initrd (hardware.nix).
  boot.plymouth = {
    enable = true;
    theme = "caelestia-hard";
    themePackages = [ caelestiaPlymouthTheme ];
  };
}
