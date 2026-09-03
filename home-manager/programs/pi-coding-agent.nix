{ inputs, ... }:
# Pi, a terminal coding agent from https://pi.dev (earendil-works/pi).
# The module comes from the lukasl-dev/pi.nix flake, which is pinned to a
# reviewed revision — see the input comment in flake.nix for why.
{
  imports = [ inputs.pi-coding-agent.homeModules.default ];

  programs.pi.coding-agent.enable = true;
}
