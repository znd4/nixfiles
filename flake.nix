{
  inputs.nixos-06cb-009a-fingerprint-sensor = {
    url = "github:ahbnr/nixos-06cb-009a-fingerprint-sensor";
    inputs.nixpkgs.follows = "nixpkgs";
  };
  outputs = { 
    self,
    nixpkgs,
    nixos-06cb-009a-fingerprint-sensor,
  }: {
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [ 
      	./configuration.nix
	nixos-06cb-009a-fingerprint-sensor.nixosModules.open-fprintd
      	nixos-06cb-009a-fingerprint-sensor.nixosModules.python-validity
	({pkgs, ...}: {
	  # fingerprint scanning for authentication
          # (this makes it so that it prompts for a password first. If none is entered or an incorrect one is entered, it will ask for a fingerprint instead)
          security.pam.services.sudo.text = ''
          # Account management.
          account required pam_unix.so
          
          # Authentication management.
          auth sufficient pam_unix.so   likeauth try_first_pass nullok
          auth sufficient ${nixos-06cb-009a-fingerprint-sensor.localPackages.fprintd-clients}/lib/security/pam_fprintd.so
          auth required pam_deny.so
          
          # Password management.
          password sufficient pam_unix.so nullok sha512
          
          # Session management.
          session required pam_env.so conffile=/etc/pam/environment readenv=0
          session required pam_unix.so
        '';
        })
      ];
    };
  };
}
