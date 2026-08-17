{ config, pkgs, lib, username, ... }:

{
  # --- Docker ---
  virtualisation.docker.enable = true;
  # `enableOnBoot` (a NixOS-specific option, distinct from Docker's own
  # "enable") defaults to true, which starts dockerd at boot regardless of
  # whether anything's using it. false here means dockerd only starts on
  # demand instead, via docker.socket's own systemd socket activation —
  # the very first `docker ...` command transparently starts it, so
  # nothing changes about how docker is actually used, it just doesn't
  # run when idle/unused.
  virtualisation.docker.enableOnBoot = false;
  # Lets me run `docker` without `sudo` — takes effect after logging out
  # and back in (group membership is read at login).
  users.users.${username}.extraGroups = [ "docker" ];

  # --- Rancher server (GUI) ---
  # Rancher's actual GUI is this web dashboard, not a separate desktop app
  # ("Rancher Desktop" is a different, unpackaged thing). Running it as a
  # container is the standard way to get it locally — it bundles its own
  # embedded k3s cluster to host its management components, which is why
  # the standalone `services.k3s` that used to be here is gone: no point
  # running two local clusters at once. Manage everything (create/import
  # clusters, deploy workloads, ...) through this GUI or the `rancher`
  # CLI below instead of raw kubectl against a second cluster.
  # --privileged is required for Rancher's embedded k3s to work inside the
  # container. Data (users, imported clusters, embedded cluster state)
  # persists across restarts in the "rancher-data" volume. Non-standard
  # host ports (8080/8443) so this doesn't fight with anything else that
  # might want 80/443 on this machine.
  #
  # autoStart = false: doesn't start at boot or whenever dockerd happens
  # to start — only runs when explicitly started by hand:
  #   systemctl start docker-rancher
  # and stopped the same way:
  #   systemctl stop docker-rancher
  virtualisation.oci-containers.backend = "docker";
  virtualisation.oci-containers.containers.rancher = {
    image = "rancher/rancher:latest";
    ports = [ "8080:80" "8443:443" ];
    volumes = [ "rancher-data:/var/lib/rancher" ];
    extraOptions = [ "--privileged" ];
    autoStart = false;
  };

  environment.systemPackages = with pkgs; [
    docker-compose   # multi-container compose files (docker-compose.yml)
    docker-buildx    # buildx plugin, for multi-arch/advanced image builds

    kubectl          # talks to any Kubernetes cluster's API (Rancher's or remote)
    kubernetes-helm  # package manager for Kubernetes (charts)
    rancher          # CLI for logging into and managing Rancher-managed clusters,
                      # local or remote — talks to the Rancher server above

    # Cypress (E2E testing). Nixpkgs' package bundles the patched Electron
    # binary and every shared lib it needs (Xvfb, GTK, NSS, ...), so
    # `cypress open`/`cypress run` just work without extra setup.
    cypress

    beekeeper-studio  # GUI DB client (Postgres/MySQL/SQLite/...)
    insomnia          # GUI API client (REST/GraphQL/gRPC)
  ];
}
