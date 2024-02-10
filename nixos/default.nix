# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ lib, inputs, pkgs, username, machineName, stateVersion, ... }:

let
  machineConfigMap = { "t470" = ./machines/t470.nix; };
  hardwareConfig = machineConfigMap.${machineName};
in {
  imports = [
    # Include the results of the hardware scan.
    hardwareConfig
    "${inputs.kmonad}/nix/nixos-module.nix"
  ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.luks.devices."luks-ccee3b9d-e376-4681-9cff-ac1bbcfb6840".device =
    "/dev/disk/by-uuid/ccee3b9d-e376-4681-9cff-ac1bbcfb6840";
  networking.hostName = "nixos"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "America/Detroit";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  services.kmonad = let
    keyboardMap = {
      "t470" = "/dev/input/by-path/platform-i8042-serio-0-event-kbd";
    };
  in {
    enable = true;
    keyboards = {
      "kmonad-keeb" = {
        device = keyboardMap.${machineName} or throw
          "No keyboard map defined for ${machineName}";
        config = builtins.readFile
          "${inputs.dotfiles}/xdg-config/.config/kmonad/config.kbd";
      };
    };
    # Modify the following line if you copied nixos-module.nix elsewhere or if you want to use the derivation described above
    # package = import /pack/to/kmonad.nix;
  };
  services.xserver.layout = "us";
  services.xserver.xkbOptions = "compose:ralt";

  # Enable the KDE Plasma Desktop Environment.
  services.xserver.displayManager.sddm.enable = true;
  services.xserver.desktopManager.plasma5.enable = true;

  virtualisation.podman = {

    enable = true;

    # Create a `docker` alias for podman, to use it as a drop-in replacement
    dockerCompat = true;

    # Required for containers under podman-compose to be able to talk to each other.
    defaultNetwork.settings.dns_enabled = true;
  };

  # Configure keymap in X11
  services.xserver = {
    xkb.layout = "us";
    xkb.variant = "";
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  sound.enable = true;
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # for kmonad
  users.groups.uinput = { };
  services.udev.extraRules = ''
    # KMonad user access to /dev/uinput
    KERNEL=="uinput", MODE="0660", GROUP="uinput", OPTIONS+="static_node=uinput"
  '';

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.${username} = {
    isNormalUser = true;
    description = "Zane Dufour";
    shell = pkgs.fish;
    extraGroups = [ "networkmanager" "wheel" "input" "uinput" ];
    packages = with pkgs; [
      clipboard-jh
      firefox
      kate
      wezterm
      discord
      #  thunderbird
    ];
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # logseq
  nixpkgs.config.permittedInsecurePackages = [ "electron-20.3.12" ];
  nixpkgs.overlays = import ./overlays;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    _1password
    #appimageTools
    logseq
    usbutils
    victor-mono
    xclip

    kmonad

    (vivaldi.override {
      proprietaryCodecs = true;
      enableWidevine = false;
    })
    vivaldi-ffmpeg-codecs
    widevine-cdm
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };
  programs._1password.enable = true;
  programs._1password-gui = {
    enable = true;
    # Certain features, including CLI integration and system authentication support,
    # require enabling PolKit integration on some desktop environments (e.g. Plasma).
    polkitPolicyOwners = [ "znd4" ];
  };
  programs.fish.enable = lib.mkForce true;
  programs.neovim.enable = lib.mkForce true;

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = stateVersion; # Did you read the comment?

}
