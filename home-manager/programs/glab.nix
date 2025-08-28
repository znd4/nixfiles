{
  pkgs,
  config,
  lib,
  ...
}:
let
  inherit (lib) mkIf mkOption types;
  cfg = config.programs.glab;

  # Define host configuration type
  hostType = types.submodule {
    options = {
      apiProtocol = mkOption {
        type = types.enum [
          "http"
          "https"
        ];
        default = "https";
        description = "What protocol to use to access the API endpoint";
      };

      apiHost = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Configure host for API endpoint. Defaults to the host itself";
      };

      token = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Your GitLab access token";
      };

      gitProtocol = mkOption {
        type = types.nullOr (
          types.enum [
            "ssh"
            "https"
          ]
        );
        default = null;
        description = "What protocol to use when performing Git operations for this host";
      };

      user = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Username for this GitLab instance";
      };

      containerRegistryDomains = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "The domains of associated container registries";
      };
    };
  };

  # Build the configuration
  glabConfig = {
    git_protocol = cfg.gitProtocol;
    editor = if cfg.editor != null then cfg.editor else "";
    browser = if cfg.browser != null then cfg.browser else "";
    glamour_style = cfg.glamourStyle;
    check_update = false; # we're managing this with nix, glab, can't autoupdate
    display_hyperlinks = cfg.displayHyperlinks;
    host = cfg.host;
    no_prompt = cfg.noPrompt;
    telemetry = cfg.telemetry;
    hosts = lib.mapAttrs (
      name: hostCfg:
      {
        api_protocol = hostCfg.apiProtocol;
        api_host = if hostCfg.apiHost != null then hostCfg.apiHost else name;
      }
      // lib.optionalAttrs (hostCfg.token != null) {
        token = hostCfg.token;
      }
      // lib.optionalAttrs (hostCfg.gitProtocol != null) {
        git_protocol = hostCfg.gitProtocol;
      }
      // lib.optionalAttrs (hostCfg.user != null) {
        user = hostCfg.user;
      }
      // lib.optionalAttrs (hostCfg.containerRegistryDomains != [ ]) {
        container_registry_domains = hostCfg.containerRegistryDomains;
      }
    ) cfg.hosts;
  };
in
{
  options.programs.glab = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to enable glab GitLab CLI";
    };

    package = mkOption {
      type = types.package;
      default = pkgs.glab;
      description = "The glab package to use";
    };

    gitProtocol = mkOption {
      type = types.enum [
        "ssh"
        "https"
      ];
      default = "ssh";
      description = "What protocol to use when performing Git operations";
    };

    editor = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "What editor glab should run when creating issues, merge requests, etc";
    };

    browser = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "What browser glab should run when opening links";
    };

    glamourStyle = mkOption {
      type = types.enum [
        "dark"
        "light"
        "notty"
      ];
      default = "dark";
      description = "Set your desired Markdown renderer style";
    };

    displayHyperlinks = mkOption {
      type = types.bool;
      default = false;
      description = "Whether or not to display hyperlink escape characters when listing items";
    };

    host = mkOption {
      type = types.str;
      default = "gitlab.com";
      description = "Default GitLab hostname to use";
    };

    noPrompt = mkOption {
      type = types.bool;
      default = false;
      description = "Set to true to disable prompts, or false to enable them";
    };

    telemetry = mkOption {
      type = types.bool;
      default = false;
      description = "Set to false to disable sending usage data to your GitLab instance or true to enable";
    };

    hosts = mkOption {
      type = types.attrsOf hostType;
      default = { };
      description = "Configuration specific for GitLab instances";
      example = {
        "gitlab.com" = {
          apiProtocol = "https";
          # apiHost defaults to "gitlab.com" (the host name)
          containerRegistryDomains = [
            "gitlab.com"
            "gitlab.com:443"
            "registry.gitlab.com"
          ];
        };
      };
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ cfg.package ];

    xdg.configFile."glab-cli/config.yml" = {
      source = (pkgs.formats.yaml { }).generate "glab-config.yml" glabConfig;
      mode = "0600";
    };
  };
}
