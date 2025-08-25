{ ... }:
(
  final: prev:
  let
    # Create a wrapper that maps GITHUB_TOKEN to GITHUB_PERSONAL_ACCESS_TOKEN
    github-mcp-wrapper = final.writeShellApplication {
      name = "gh";
      runtimeInputs = [ prev.github-mcp-server ];
      text = ''
        # Map GITHUB_TOKEN (set by 1Password) to GITHUB_PERSONAL_ACCESS_TOKEN (expected by github-mcp-server)
        export GITHUB_PERSONAL_ACCESS_TOKEN="$GITHUB_TOKEN"
        exec github-mcp-server "$@"
      '';
    };
  in
  {
    github-mcp-server = final.writeShellApplication {
      name = "github-mcp-server";
      runtimeInputs = [
        final._1password-cli
        github-mcp-wrapper
      ];
      text = ''
        # Run op plugin with our wrapper gh in PATH
        exec op plugin run -- gh "$@"
      '';
    };
  }
)

