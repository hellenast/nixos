{ config, pkgs, ... }:

{
  # earlyoom: watches free memory+swap and kills the worst offending
  # process before the kernel's own OOM killer would even trigger — the
  # kernel only steps in once memory is *completely* exhausted, by which
  # point the whole system is usually already frozen and unresponsive for
  # a long stretch first. This complements the zram/swappiness tuning in
  # configuration.nix (that's about avoiding disk-swap thrashing under
  # moderate pressure; this is about staying responsive if something still
  # runs away and eats all 60GB anyway — a runaway Electron tab, a container
  # gone wrong, etc).
  #
  # Thresholds: start considering kills once free memory drops under 5% AND
  # free swap drops under 10% (earlyoom's `-m`/`-s`, both conditions must
  # hold since zram means "low swap" alone isn't unusual here). Notifies via
  # libnotify (already installed, home.nix) so a kill isn't a silent
  # mystery.
  services.earlyoom = {
    enable = true;
    freeMemThreshold = 5;
    freeSwapThreshold = 10;
    enableNotifications = true;
  };
}
