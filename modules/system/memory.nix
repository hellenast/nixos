{ ... }:

# Memory pressure handling: avoid pointless disk swapping, and stay
# responsive if something eats all the RAM anyway. Tuned on the desktop's
# 60GB, but nothing here depends on that much.
{
  # Default is 60, which starts swapping idle pages out well before memory
  # is actually tight — wasted I/O with this much RAM. 10 means "swap only
  # under real pressure". Hibernation is disabled (power.nix), so swap
  # doesn't need to be kept free for it.
  boot.kernel.sysctl."vm.swappiness" = 10;

  # zram: compressed swap in RAM. The kernel prefers the swap device with
  # the higher priority, and zram's default (5) beats the disk swapfile's
  # (-2, from disko.nix), so zram is used first and the disk swapfile only
  # once zram is full — at the default 50% of RAM, that's a lot of headroom.
  zramSwap = {
    enable = true;
    algorithm = "zstd";
  };

  # earlyoom kills the worst offender before the kernel's own OOM killer
  # would. The kernel only acts once memory is completely exhausted, by
  # which point the desktop has usually been frozen for a while.
  #
  # Both thresholds must be crossed (less than 5% free RAM and less than 10%
  # free swap): with zram, low swap on its own is normal. Notifications go
  # through systembus-notify, which enableNotifications turns on. Upstream
  # warns this lets any local user spam the session with notifications —
  # fine on a single-user desktop.
  services.earlyoom = {
    enable = true;
    freeMemThreshold = 5;
    freeSwapThreshold = 10;
    enableNotifications = true;
  };
}
