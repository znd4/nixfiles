{ inputs, username, stateVersion, keys }:
{ lib, config, pkgs, ... }: {
  # You can import other home-manager modules here
  _module.args = {
    inherit inputs;
    inherit keys;
    inherit stateVersion;
    inherit username;
    # inherit pkgs;
    system = "aarch64-darwin";
  };
  imports = [
    # If you want to use modules your own flake exports (from modules/home-manager):
    # outputs.homeManagerModules.example

    # Or modules exported from other flakes (such as nix-colors):
    # inputs.nix-colors.homeManagerModules.default

    # You can also split up your configuration and import pieces of it here:
    ./shared.nix
    ./programs/kmonad.nix
  ];
  home.sessionVariables.SSH_AUTH_SOCK =
    "/Users/${username}/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock";
  home.sessionPath = [ "/Users/${username}/homebrew/bin" ];
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
