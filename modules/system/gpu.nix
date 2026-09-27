{ lib, pkgs, gpus, gpuBusIds, ... }:

# GPU drivers, from the machine's `gpus` (hosts/<name>/variables.nix).
# AMD and Intel run on the kernel's own drivers and Mesa, so they need
# little here. NVIDIA gets its proprietary driver, and on a laptop that
# also has the CPU's integrated graphics (Optimus), PRIME render offload.
let
  has = gpu: lib.elem gpu gpus;

  # NVIDIA next to integrated graphics: the integrated GPU runs the desktop
  # and the built-in screen, and the NVIDIA one only what's offloaded to it.
  hybrid = has "nvidia" && (has "amd" || has "intel");
in
{
  # 32-bit support is for 32-bit games under Steam/Proton, and Wine (Bottles).
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    # Hardware video decoding (VA-API) on Intel, for browsers and VLC:
    # Broadwell (2014) and newer. AMD's is part of Mesa already.
    extraPackages = lib.optionals (has "intel") [ pkgs.intel-media-driver ];
  };

  # The GPU driver loads by itself, but only once stage 2 gets to it. Until
  # then, Plymouth's splash and the LUKS prompt (boot.nix) run on the
  # firmware's framebuffer, at whatever resolution it picked. Loading it in
  # the initrd gives Plymouth real modesetting from the first frame. (On the
  # newest Intel GPUs, which use the xe driver, i915 just doesn't bind.) Not
  # NVIDIA's: it's huge, and on a hybrid laptop it doesn't drive the screen.
  boot.initrd.kernelModules =
    lib.optional (has "amd") "amdgpu"
    ++ lib.optional (has "intel") "i915";

  # --- NVIDIA ---
  # The switch for the proprietary driver, X server or not;
  # hardware.nvidia below configures it.
  services.xserver.videoDrivers = lib.mkIf (has "nvidia") [ "nvidia" ];

  hardware.nvidia = lib.mkIf (has "nvidia") {
    # The open kernel modules, which NVIDIA recommends for Turing (GTX 16xx,
    # RTX 20xx) and newer. Older cards need the closed ones: false.
    open = true;
    # Keeps video memory across suspend, so apps don't wake up to corrupted
    # graphics.
    powerManagement.enable = true;
    # Hybrid laptops: powers the NVIDIA GPU off entirely whenever nothing is
    # offloaded to it, which is most of the time.
    powerManagement.finegrained = hybrid;

    prime = lib.mkIf hybrid {
      # Apps run on the integrated GPU unless started through
      # `nvidia-offload <command>` (for a Steam game: `nvidia-offload
      # %command%` in its launch options).
      offload.enable = true;
      offload.enableOffloadCmd = true;
      # PCI addresses of the two GPUs, from gpuBusIds (fresh-install.sh
      # detects them).
      nvidiaBusId = gpuBusIds.nvidia or "";
      amdgpuBusId = gpuBusIds.amd or "";
      intelBusId = gpuBusIds.intel or "";
    };
  };
}
