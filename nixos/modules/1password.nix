{ username, pkgs, ... }:
{

  environment.systemPackages = with pkgs; [ _1password-cli ];
  programs._1password-gui = {
    enable = true;
    # Certain features, including CLI integration and system authentication support,
    # require enabling PolKit integration on some desktop environments (e.g. Plasma).
    polkitPolicyOwners = [ username ];
  };

}
