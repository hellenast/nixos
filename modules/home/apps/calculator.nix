{ pkgs, ... }:

# GNOME Calculator. It's a libadwaita app, so caelestia's own GTK theming
# (theme.enableGtk, home/caelestia.nix) already colours it: on every scheme
# change the CLI writes libadwaita's named colours (accent, window,
# headerbar, popover, ...) into ~/.config/gtk-4.0/gtk.css. GTK reads that
# file once at startup, so an open calculator keeps the old colours until
# it's restarted.
let
  # Currency conversions download exchange rates over HTTPS, which needs
  # GIO's TLS module from glib-networking. nixpkgs leaves that to the GNOME
  # desktop module (services.gnome.glib-networking), which isn't used here,
  # so every download failed with "TLS support is not available". Its
  # .desktop entry runs plain `gnome-calculator`, so launcher starts get
  # the wrapper too.
  gnomeCalculator = pkgs.symlinkJoin {
    name = "gnome-calculator-tls";
    paths = [ pkgs.gnome-calculator ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = "wrapProgram $out/bin/gnome-calculator --prefix GIO_EXTRA_MODULES : ${pkgs.glib-networking}/lib/gio/modules";
  };
in
{
  home.packages = [ gnomeCalculator ];
}
