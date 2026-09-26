{ config, pkgs, lib, ... }:

{
  environment.systemPackages = with pkgs; [
    # Claude Code, Anthropic's CLI coding agent. Nixpkgs' package bundles
    # the native binary and turns off its self-updater (it can't write into
    # the read-only store anyway), so updates come from bumping nixpkgs
    # instead — `nix flake update` like everything else.
    #
    # I mainly want `claude rc` (short for `claude remote-control`) from
    # this: it starts a session on this machine that I can then drive from
    # the Claude app on my phone or claude.ai/code in a browser, while it
    # keeps running here with my local files and tools. It needs a claude.ai
    # subscription login (`claude` → `/login`), not an API key.
    claude-code
  ];
}
