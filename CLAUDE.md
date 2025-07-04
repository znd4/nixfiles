# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

### Build and Switch Configurations
```shell
# NixOS (Linux systems)
just nixos                              # Build and switch NixOS config
sudo nixos-rebuild switch --flake .    # Direct command

# macOS (nix-darwin)
just darwin                             # Build and switch macOS config
nix run nix-darwin -- switch --flake ".#work"  # Direct command

# Home Manager (user environment)
just home-manager                       # Build and switch home-manager config
nix run .#home-manager-switch .        # Direct command for current user@hostname
```

### Target System Hostnames
- **NixOS**: `desktop`, `t470` (Linux machines)
- **macOS**: `work`, `mac-mini` (Apple Silicon)
- **Users**: `znd4` (primary user)

### Package Development
```shell
# Custom Go packages in /pkgs/
cd pkgs/hy-auth && nix develop          # Enter dev environment
cd pkgs/sesh-new-project && nix build  # Build package
```

## Architecture

This is a **Nix flakes-based system configuration repository** managing multiple machines and environments:

### Core Structure
- **flake.nix**: Main configuration defining all system outputs and dependencies
- **home-manager/**: User environment configuration (dotfiles, programs, packages)
- **nixos/**: Linux system configuration with machine-specific modules
- **darwin/**: macOS system configuration using nix-darwin
- **pkgs/**: Custom Go packages and tools
- **xdg-config/**: XDG configuration files (Neovim, Fish, Alacritty, etc.)

### Multi-Platform Support
The configuration supports:
- **NixOS systems**: Full system configuration with modules
- **macOS systems**: System-level configuration via nix-darwin
- **Home Manager**: Cross-platform user environment management

### Key Components
- **Neovim**: Comprehensive LSP setup in `xdg-config/nvim/` (Lua configuration)
- **Shell**: Fish shell with extensive customization
- **Development Tools**: Complete language server setup for multiple languages
- **Custom Packages**: Go CLI tools for project management and authentication

### Package Management
- **Primary**: Nix flakes with locked dependencies (flake.lock)
- **Multiple nixpkgs versions**: Stable (25.05), unstable, and trunk branches
- **Custom overlays**: Personal package modifications
- **Flake inputs**: External dependencies (nixvim, ghostty, etc.)

### Configuration Pattern
All configurations use the **module system** with:
- Reusable modules in respective directories
- Machine-specific configurations in `machines/` subdirectories
- Shared configuration through imports and overlays
- Per-platform customization while maintaining consistency

The repository follows modern Nix practices with flakes, Home Manager, and declarative system management across multiple platforms.