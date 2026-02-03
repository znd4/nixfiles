$env.config = {
    edit_mode: vi
}

# Use nvr inside neovim terminals
if ($env | get -i NVIM | is-not-empty) {
    $env.EDITOR = "nvr -cc split --remote-wait"
}
