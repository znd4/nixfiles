{
  inputs,
  ...
}:
{
  imports = [
    inputs.flake-parts.flakeModules.easyOverlay
  ];
  perSystem =
    {
      config,
      pkgs,
      ...
    }:
    {
      overlayAttrs = {
        inherit (config.packages) telescope-filter;
      };
      packages.telescope-filter = (
        pkgs.writeShellApplication (
          let
            nvim_temp = inputs.nixvim.legacyPackages.${pkgs.system}.makeNixvim {
              plugins = {
                web-devicons.enable = true;
                telescope = {
                  enable = true;
                  settings = {
                    defaults = {
                      mappings =
                        let
                          new_enter = {
                            __raw = ''
                              function(prompt_bufnr)
                                local entry = require('telescope.actions.state').get_selected_entry()
                                vim.print({"selected_entry", entry})
                                vim.fn.writefile({ entry.value }, vim.g.search_output_file )
                                require("telescope.actions").close(prompt_bufnr)
                                vim.cmd.quit()
                              end
                            '';
                          };
                        in
                        {
                          i = {
                            "<cr>" = new_enter;
                          };
                          n = {
                            "<cr>" = new_enter;
                            "<esc>" = {
                              __raw = ''
                                function(prompt_bufnr)
                                  require("telescope.actions").close(prompt_bufnr)
                                  vim.cmd.quit()
                                end
                              '';
                            };
                          };
                        };
                      layout_config = {
                        horizontal = {
                          height = 0.99;
                          width = 0.99;
                        };
                        vertical = {
                          height = 0.99;
                          width = 0.99;
                        };
                      };
                    };
                  };
                };
              };
            };
            script = pkgs.writeText "lua-script" (
              builtins.readFile "${inputs.self}/scripts/telescope-filter.lua"
            );
          in
          {
            name = "telescope-filter";
            runtimeInputs = [
              nvim_temp
              script
            ];
            text = ''
              #!/usr/bin/env bash
              set -euo pipefail
              # set -x
              input=$(mktemp)
              cat - > "$input"
              output=$(mktemp)
              if [ ! -t 0 ]; then
                ${nvim_temp}/bin/nvim \
                  -c "let g:search_output_file='$output'" \
                  -c "let g:search_input_file='$input'" \
                  -c "lua assert(loadfile('${script}'))()" \
                  < /dev/tty > /dev/tty
              fi

              cat "$output"
            '';
          }
        )
      );

    };
}
