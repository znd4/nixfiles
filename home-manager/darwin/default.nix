{
  inputs,
  username,
  config,
  keys,
  system,
  pkgs,
  lib,
  ...
}:
if !(lib.strings.hasSuffix "darwin" system) then
  { }
else
  {
    imports = (
      builtins.map (f: (import (./. + "/${f}"))) (
        builtins.filter (f: f != "default.nix") (builtins.attrNames (builtins.readDir ./.))
      )

    );

    home.sessionVariables.SSH_AUTH_SOCK = "/Users/${username}/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock";
    home.homeDirectory = "/Users/${username}";
    home.sessionPath = [ "${config.home.homeDirectory}/homebrew/bin" ];
    home.packages = with pkgs; [ python311Packages.supervisor ];
    # programs.git.includes = [{
    #   condition = "gitdir:${config.home.homeDirectory}/Work";
    #   contents = {
    #     user = {
    #       name = "Zane Dufour";
    #       email = "extern.zane.dufour@vw.com";
    #       signingKey = keys."git.company.com";
    #     };
    #   };
    # }];
    # programs.ssh.matchBlocks = let
    #   vw_config = {
    #     identitiesOnly = true;
    #     identityFile =
    #       "${pkgs.writeText "vw_id_rsa.pub" keys."git.company.com"}";
    #   };
    # in {
    #   "git2.company.com" = vw_config;
    #   "git.company.com" = vw_config;
    # };
  }
