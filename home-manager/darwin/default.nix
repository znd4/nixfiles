{
  inputs,
  username,
  config,
  stateVersion,
  keys,
  pkgs,
  ...}:
{
  imports = (
    builtins.map (f: (import (./. + "/${f}"))) (
      builtins.filter (f: f != "default.nix") (builtins.attrNames (builtins.readDir ./.))
    )

  );

# You can import other home-manager modules here
_module.args = {
  inherit inputs;
  inherit keys;
  inherit username;
# inherit pkgs;
};
home.sessionVariables.SSH_AUTH_SOCK = "/Users/${username}/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock";
home.homeDirectory = "/Users/${username}";
home.sessionPath = [ "${config.home.homeDirectory}/homebrew/bin" ];
home.packages = with pkgs; [ python311Packages.supervisor ];
home.stateVersion = stateVersion;
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

