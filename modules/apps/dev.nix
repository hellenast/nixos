{ pkgs, username, ... }:

# Development tooling: Docker, a local Rancher server, Kubernetes CLIs, and
# JS/TS + testing/API/DB tools. Nothing here runs until it's used.
{
  # --- Docker ---
  virtualisation.docker.enable = true;
  # dockerd isn't started at boot. docker.socket starts it on demand the
  # first time any `docker` command runs, so it costs nothing while idle.
  virtualisation.docker.enableOnBoot = false;
  # Run `docker` without sudo (applies after logging out and back in).
  users.users.${username}.extraGroups = [ "docker" ];

  # --- Rancher server (web GUI) ---
  # Rancher's GUI is this web dashboard, run as a container (Rancher Desktop
  # is a different, unpackaged app). It bundles its own k3s cluster for its
  # management components, so there's no separate `services.k3s` — clusters
  # are created/imported and managed from here or the `rancher` CLI.
  #
  # --privileged is required for the embedded k3s. State (users, clusters)
  # persists in the "rancher-data" volume. Host ports 8080/8443 leave 80/443
  # free. Only runs when started by hand:
  #   systemctl start docker-rancher   # https://localhost:8443
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

    # JS/TS frontend work (React, Next.js). Databases (Postgres) run per
    # project from docker-compose, so there's no `services.postgresql`.
    nodejs           # node runtime + npm
    bun              # JS runtime/bundler/package manager
    pnpm             # pnpm package manager

    kubectl          # Kubernetes API client (Rancher's clusters or remote ones)
    kubernetes-helm  # Kubernetes package manager (charts)
    rancher          # CLI for the Rancher server above, or remote ones

    # nixpkgs' Cypress bundles its patched Electron and every library it
    # needs, so `cypress open`/`cypress run` work with no extra setup.
    cypress  # E2E testing framework

    beekeeper-studio  # GUI DB client (Postgres/MySQL/SQLite/...)
    insomnia          # GUI API client (REST/GraphQL/gRPC)
  ];
}
