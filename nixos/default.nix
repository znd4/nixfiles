# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).
{
  lib,
  inputs,
  pkgs,
  username,
  hostname,
  outputs,
  stateVersion,
  ...
}@args:
let
  machineConfigMap = {
    "t470" = ./machines/t470.nix;
    "desktop" = ./machines/desktop.nix;
  };
  hardwareConfig = machineConfigMap.${hostname};
in
{
  imports = [
    # Include the results of the hardware scan.
    hardwareConfig
    ./modules
  ];

  nix.settings = {
    trusted-users = [
      username
      "root"
    ];
    experimental-features = [
      "nix-command"
      "flakes"
    ];
  };

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
      # domain = true;
      # hinfo = true;
      # userServices = true;
    };
  };
  programs.ssh = {
    knownHostsFiles = (
      lib.attrsets.mapAttrsToList (name: value: (pkgs.writeText name value)) outputs.knownHosts
    );
  };

  # need for building raspberry pi images
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # font
  fonts.packages = with pkgs; [
    nerd-fonts.fira-code
    nerd-fonts.victor-mono
    nerd-fonts.symbols-only
  ];

  networking.hostName = hostname; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;
  programs.nm-applet.enable = true;
  # networking.networkmanager.wifi.backend = "iwd";
  # networking.wireless.iwd.enable = true;
  networking.wireless.iwd.settings = {
    Settings = {
      AutoConnect = true;
    };
  };

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
  services.displayManager = {
    sddm.enable = true;
  };
  services.xserver = {
    enable = true;
    xkb = {
      layout = "us";
      variant = "";
    };
    # displayManager.startx.enable = true;
  };

  virtualisation.podman = {
    enable = true;

    # Create a `docker` alias for podman, to use it as a drop-in replacement
    dockerCompat = true;

    # Required for containers under podman-compose to be able to talk to each other.
    defaultNetwork.settings.dns_enabled = true;
  };

  # bluetooth
  hardware.bluetooth.enable = true; # enables support for Bluetooth
  hardware.bluetooth.powerOnBoot = true; # powers up the default Bluetooth controller on boot

  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber.enable = true;
    # If you want to use JACK applications, uncomment this
    jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.${username} = {
    isNormalUser = true;
    description = "Zane Dufour";
    shell = pkgs.fish;
    extraGroups = [
      "networkmanager"
      "wheel"
      "input"
      "uinput"
    ];
    packages = with pkgs; [
      clipboard-jh
      firefox
      wezterm
      discord
      #  thunderbird
    ];
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.allowUnfreePredicate = _: true;

  nixpkgs.overlays = import ./overlays args;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    usbutils
    victor-mono
    xclip

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
  programs.fish.enable = lib.mkForce true;

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
