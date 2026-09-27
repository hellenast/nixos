{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    # Claude Code, Anthropic's CLI coding agent. The nixpkgs package disables
    # its self-updater (the store is read-only), so it updates with nixpkgs.
    #
    # Mainly here for `claude rc` (remote control): it runs a session on this
    # machine, with local files and tools, that can be driven from the Claude
    # phone app or claude.ai/code. Needs a claude.ai subscription login
    # (`claude` → `/login`), not an API key.
    claude-code
  ];
}
