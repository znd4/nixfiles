import asyncio
import functools
import getpass
import json
import os
import platform
import shutil
import site
import subprocess as sp
import sys
import tempfile
from contextlib import asynccontextmanager
from functools import lru_cache
from pathlib import Path
from typing import Callable, Iterator

from pyinfra.operations import apt, brew

# ~/.local/lib/pythonX.Y/site-packages might not exist when script starts
# So we need to manually add it to sys.path
site.addsitedir(site.getusersitepackages())

GLOBAL_CRATES = ["lolcate-rs"]


CARGO_PACKAGES = [
    "skim",
]

NIX_ENV_PACKAGES = ["myPackages"]
INSTALL_TEXLIVE = os.getenv("INSTALL_TEXLIVE", "true").lower() == "true"

HEADLESS = os.getenv("HEADLESS", "false").lower() == "true"
INSTALL_KMONAD = (not HEADLESS) and os.getenv(
    "INSTALL_KMONAD", "true"
).lower() == "true"

LOCAL_BIN = Path.home() / ".local" / "bin"
HEADLESS = os.getenv("HEADLESS", "false").lower() == "true"
UBUNTU_PACKAGES = [
    "python3-pip",
    # for pyenv
    "libedit-dev",
    "build-essential",
    "libssl-dev",
    "zlib1g-dev",
    "libbz2-dev",
    "libreadline-dev",
    "libsqlite3-dev",
    "curl",
    "man-db",
    "libncursesw5-dev",
    "xz-utils",
    "tk-dev",
    "libxml2-dev",
    "libxmlsec1-dev",
    "libffi-dev",
    "liblzma-dev",
    "zsh",
]
if not HEADLESS:
    UBUNTU_PACKAGES.extend(
        [
            "fonts-firacode",
            "libgmp-dev",
        ]
    )
APT_OR_BREW = [
    "podman",
    "shfmt",
]
BREW_PACKAGES = [
    "asdf",
    "argocd",
    "aws-shell",
    "bat",
    "black",
    "clipboard",
    "cookiecutter",
    "copier",
    "devcontainer",
    "glab",
    "git-delta",
    "fd",
    "fnm",
    "fzf",
    "gh",
    "git-lfs",
    "go",
    "gum",
    "hatch",
    "helm",
    "httpie",
    "isort",
    "just",
    "jq",
    "kubectl",
    "lazygit",
    "neovim",
    # "node",
    "pdm",
    "pipx",
    "pipenv",
    "python-launcher",
    "pre-commit",
    "ripgrep",
    "starship",
    "stylua",
    "thefuck",
    "tmux",
    "yq",
    "zellij",
    "zoxide",
    "zsh",
]
BREW_TAPS = []

if not HEADLESS:
    BREW_TAPS.append("homebrew/linux-fonts")
    BREW_PACKAGES.extend(
        [
            "texlive",
            "font-symbols-only-nerd-font",
            "font-victor-mono",
        ]
    )


async def main():
    apt_pkgs, brew_pkgs = process_apt_or_brew(
        APT_OR_BREW, UBUNTU_PACKAGES, BREW_PACKAGES
    )
    if shutil.which("apt-get"):
        apt.packages(packages=apt_pkgs, _sudo=True)
    for tap in BREW_TAPS:
        brew.tap(tap)
    brew.packages(packages=brew_pkgs)

    async_jobs = map(
        asyncio.create_task,
        [
            install_tpm("tmux-plugins/tpm", "tmux-plugins/tmux-sensible"),
            asdf_install(),
            cargo_setup(cargo_packages=CARGO_PACKAGES),
            krew_install("ctx"),
            krew_install("ns"),
            bin_install("https://github.com/k3d-io/k3d", LOCAL_BIN / "k3d"),
            run(["brew", "install", "--build-from-source", "fish"]),
        ],
    )
    await add_to_fpath_dir()

    install_docker_compose()
    install_pyenv()
    async_jobs = [*async_jobs, asyncio.create_task(pipx_stuff())]

    # gather all async_jobs
    await gather(*async_jobs)

    sp.check_call([Path.home() / ".cargo" / "bin" / "rustup", "default", "stable"])
    sp.check_call([Path.home() / ".cargo" / "bin" / "cargo", "install", *GLOBAL_CRATES])

    kmonad()

    symlink_fonts()


def is_executable(p: os.PathLike) -> bool:
    return os.access(p, os.X_OK)


async def bin_install(repo: str, dest: Path = None):
    if dest and dest.is_file() and is_executable(dest):
        return
    await install_bin()
    cmd = ["bin", "install", repo]
    if dest:
        cmd.append(str(dest))
    await run(cmd, stdin=sys.stdin)


def is_macos():
    return platform.system().lower() == "darwin"


async def run(
    cmd: list[str],
    check=True,
    timeout=60 * 5,
    stdout=None,
    stdin=None,
) -> asyncio.subprocess.Process:
    stderr = asyncio.subprocess.PIPE if check else None

    if not shutil.which(cmd[0]):
        raise RuntimeError(f"{cmd[0]} not found")

    try:
        proc = await asyncio.create_subprocess_exec(
            *cmd, stderr=stderr, stdout=stdout, stdin=stdin
        )
    except Exception as e:
        print(f"Failed to start {cmd}")
        raise e

    try:
        # Wait for the subprocess to finish, with a timeout
        await asyncio.wait_for(proc.wait(), timeout)
    except asyncio.TimeoutError:
        # If the process doesn't finish before the timeout, kill it
        print(f"Process timed out: {cmd}")
        proc.kill()
        await proc.wait()
        raise
    except Exception as e:
        print(f"got another error, Failed to wait for {cmd}")
        raise e

    if not check:
        return proc
    if proc.returncode == 0:
        return proc

    raise RuntimeError(
        (await proc.stderr.read()).decode()
        if proc.stderr
        else f"Unknown error, {proc.returncode=}"
    )


async def pipx_stuff():
    pylsp = pipx_install("python-lsp-server[rope]")

    rest = pipx_install("pre-commit", "black", "isort", "ruff", "nox")
    await pylsp

    await gather(
        run(
            pipx_cmd(
                "inject",
                "python-lsp-server",
                "pylsp-rope",
                "python-lsp-ruff",
                "pyls-isort",
                "python-lsp-black",
            ),
            check=True,
        ),
        rest,
    )


def process_apt_or_brew(
    apt_or_brew: list[str], apt: list[str], brew: list[str]
) -> tuple[list[str], list[str]]:
    if shutil.which("apt-get"):
        apt = [*apt, *apt_or_brew]
    elif shutil.which("brew"):
        brew = [*brew, *apt_or_brew]
    else:
        raise RuntimeError("No apt or brew found")
    return apt, brew


async def gather(*tasks: asyncio.Task):
    results = await asyncio.gather(*tasks, return_exceptions=True)
    exceptions = [r for r in results if isinstance(r, Exception)]
    if not exceptions:
        return
    raise ExceptionGroup("errors: ", exceptions)


COMPLETIONS = [
    (["pdm", "completion", "zsh"], "_pdm"),
    (["ruff", "generate-shell-completion", "zsh"], "_ruff"),
    (["podman", "completion", "zsh"], "_podman"),
    (["k3d", "completion", "zsh"], "_k3d"),
    (["register-python-argcomplete", "pipx"], "_pipx"),
    (["zellij", "setup", "--generate-completion", "zsh"], "_zellij"),
]


async def add_to_fpath_dir():
    local_fpath = Path.home() / ".zfunc"
    local_fpath.mkdir(exist_ok=True)
    await pip_install("atomicwrites")

    import atomicwrites

    # pipe pdm completion zsh to local_fpath / _pdm
    async def pipe(cmd: list[str], fp: Path):
        if not shutil.which(cmd[0]):
            print(f"{cmd[0]} not installed, not generating completions")
            return
        with atomicwrites.atomic_write(fp, overwrite=True) as f:
            await run(cmd, stdout=f, check=True)

    await gather(*(pipe(cmd, local_fpath / fname) for cmd, fname in COMPLETIONS))


def skip_if(cond: bool | Callable[[], bool]):
    def decorator(func):
        @functools.wraps(func)
        def wrapper(*args, **kwargs):
            if cond is True:
                return

            if callable(cond) and cond():
                return

            return func(*args, **kwargs)

        return wrapper

    return decorator


async def install_rustup():
    if shutil.which("rustup"):
        return

    async with download_script("https://sh.rustup.rs") as installer:
        await run(["sh", installer], check=True, stdin=sys.stdin)

    os.environ["PATH"] = f"{os.environ['PATH']}:{Path.home() / '.cargo' / 'bin'}"


async def cargo_setup(cargo_packages: list[str]):
    await install_rustup()
    installed = {
        line.strip().split()[0]
        for line in sp.check_output(
            ["cargo", "install", "--list"], text=True
        ).splitlines()
    }

    for package in set(cargo_packages) - installed:
        await run(["cargo", "install", package], check=True, stdin=sys.stdin)


@asynccontextmanager
async def download_script(url: str) -> Iterator[Path]:
    await pip_install("httpx")
    import httpx

    async with httpx.AsyncClient() as client:
        resp = await client.get(url)

    resp.raise_for_status()

    with tempfile.TemporaryDirectory() as td:
        target = Path(td) / "installer"
        target.write_text(resp.text)

        yield target


def gui_only(func):
    @functools.wraps(func)
    def wrapper(*args, **kwargs):
        if HEADLESS:
            print("Skipping GUI-only command")
            return
        return func(*args, **kwargs)

    return wrapper


def haskell_stack():
    if shutil.which("stack"):
        print("Stack already installed, skipping")
        return
    sp.check_call(
        "curl -sSL https://get.haskellstack.org/ | sh", shell=True, stdin=sys.stdin
    )


def env_patch(key: str, val: str) -> Callable[[Callable], Callable]:
    def decorator(func: Callable):
        @functools.wraps(func)
        def wrapped(*args, **kwargs):
            original = os.environ.get(key, None)
            os.environ[key] = val
            try:
                func(*args, **kwargs)
            finally:
                if original is None:
                    os.environ.pop(key)
                    return
                os.environ[key] = original

        return wrapped

    return decorator


async def brew_tap(*taps: str):
    for tap in taps:
        await run([brew_path("brew"), "tap", tap], check=True)


@functools.lru_cache
async def install_bin():
    if shutil.which("bin"):
        return
    os, arch = get_platform()
    with tempfile.TemporaryDirectory() as td:
        bin = Path(td) / "bin"
        sp.check_call(
            [
                "gh",
                "release",
                "download",
                "--repo=marcosnils/bin",
                f"--pattern=*{os}_{arch}*",
                f"--output={bin}",
            ],
            stdin=sys.stdin,
        )
        sp.check_call(["chmod", "+x", bin])
        await run([bin, "install", "github.com/marcosnils/bin", LOCAL_BIN / "bin"])


def get_platform():
    is_macos = platform.system() == "Darwin"
    if is_macos:
        return ("darwin", "arm64")
    is_windows = platform.system() == "Windows"
    if is_windows:
        return ("windows", "amd64")
    return ("linux", "amd64")


@skip_if(lambda: HEADLESS)
def install_nerd_font_symbols():
    if "nerd" in sp.check_output(["fc-list"], text=True).lower():
        return

    proc = sp.Popen(
        [
            "gh",
            "release",
            "download",
            "--repo=ryanoasis/nerd-fonts",
            "--pattern=*SymbolsOnly.tar.xz",
            "--output=-",
        ],
        stdout=sp.PIPE,
    )

    # Define the fonts directory
    fonts_dir = Path.home() / ".local" / "share" / "fonts"

    # Create the fonts directory if it doesn't exist
    fonts_dir.mkdir(parents=True, exist_ok=True)

    # Extract all files into the fonts directory
    sp.check_call(["tar", "--xz", "-xf", "-", "-C", str(fonts_dir)], stdin=proc.stdout)

    sp.check_call(["fc-cache", "-f", "-v"], stdin=sys.stdin)


@env_patch("LD_LIBRARY_PATH", "/usr/lib/x86_64-linux-gnu")
@env_patch("LIBRARY_PATH", "/usr/lib/x86_64-linux-gnu")
@skip_if(HEADLESS or is_macos())
def kmonad():
    if not INSTALL_KMONAD:
        print("Skipping kmonad setup")
        return
    print(f"{os.environ['LD_LIBRARY_PATH']=}")

    print("running kmonad setup")
    haskell_stack()
    # create uinput group if it doesn't already exist
    sp.check_call(sudo(["groupadd", "uinput", "--force"]), stdin=sys.stdin)
    # add current user to uinput group and input group
    for group in ["uinput", "input"]:
        sp.check_call(
            sudo(
                [
                    "usermod",
                    "-aG",
                    group,
                    getpass.getuser(),
                ]
            ),
            stdin=sys.stdin,
        )

    # add to udev rules
    # copy ~/.config/kmonad/udev.rules to /etc/udev/rules.d/99-kmonad.rules
    # then reload udev rules
    sp.check_call(sudo(["mkdir", "-p", "/etc/udev/rules.d/"]), stdin=sys.stdin)
    sp.check_call(
        sudo(
            [
                "cp",
                Path.home() / ".config/kmonad/udev.rules",
                "/etc/udev/rules.d/99-kmonad.rules",
            ]
        ),
        stdin=sys.stdin,
    )
    sp.check_call(sudo(["udevadm", "control", "--reload-rules"]), stdin=sys.stdin)

    # clone https://github.com/kmonad/kmonad into temporary directory
    with tempfile.TemporaryDirectory() as tmpdir:
        build_and_install_kmonad(Path(tmpdir))

    sp.check_call(["systemctl", "--user", "enable", "kmonad.service"], stdin=sys.stdin)
    sp.check_call(["systemctl", "--user", "restart", "kmonad.service"], stdin=sys.stdin)


def sudo(cmd: list[str]) -> list[str]:
    if getpass.getuser() == "root":
        return cmd
    return ["sudo", *cmd]


async def build_and_install_kmonad(dir_: Path):
    if shutil.which("kmonad"):
        print("kmonad already installed, skipping")
        return

    sp.check_call(
        [
            "git",
            "clone",
            "https://github.com/kmonad/kmonad",
            str(dir_),
        ],
        stdin=sys.stdin,
    )

    # here because it won't be installed when we first start the script
    await pip_install("ruamel.yaml")
    from ruamel.yaml import YAML

    stack_yaml_path = dir_ / "stack.yaml"
    yaml = YAML()
    stack_config = {}

    # Check if stack.yaml already exists and load its content
    if stack_yaml_path.is_file():
        with open(stack_yaml_path, "r") as stack_yaml:
            stack_config = yaml.load(stack_yaml)

    extra_lib_dirs = "extra-lib-dirs"

    stack_config[extra_lib_dirs] = [
        *stack_config.get(extra_lib_dirs, []),
        "/usr/lib/x86_64-linux-gnu",
    ]

    # Save the modified stack.yaml file
    with open(stack_yaml_path, "w") as stack_yaml:
        yaml.dump(stack_config, stack_yaml)

    def check_call(args):
        return sp.check_call(args, stdin=sys.stdin, cwd=dir_)

    check_call(["stack", "setup"])
    check_call(["stack", "build"])
    check_call(["stack", "install"])


@lru_cache
def install_pip():
    print(f"{sys.executable=}")
    try:
        sp.check_call([sys.executable, "-m", "pip", "--version"])
    except Exception:
        pass
    else:
        return

    try:
        import ensurepip

        ensurepip.bootstrap(user=True)
    except Exception:
        raise Exception("failed to get pip")


@functools.lru_cache()
async def pip_install(*packages: str):
    install_pip()
    print(f"pip installing {', '.join(packages)}")
    if platform.system().lower() == "linux" and sys.executable.startswith(
        "/usr/bin/python3"
    ):
        sp.check_call(
            sudo(
                [
                    "apt-get",
                    "install",
                    "-y",
                    *(f"python3-{package}" for package in packages),
                ]
            )
        )
        return

    await run(
        [
            sys.executable,
            "-m",
            "pip",
            "install",
            # "--user",
            *packages,
        ]
    )


def install_tpm_packages():
    sp.check_call(["tmux", "new", "-d", "-s", "tmp"])
    tmux_session = "tmp"
    try:
        # send prefix + I to install plugins
        sp.check_call(["tmux", "send-keys", "-t", tmux_session, "C-a", "I"])
    finally:
        # kill the session
        sp.check_call(["tmux", "kill-session", "-t", tmux_session])


async def install_tpm(*plugins: str):
    plugins_dir = Path.home() / ".config" / "tmux" / "plugins"
    plugins_dir.mkdir(parents=True, exist_ok=True)

    for plugin in plugins:
        target_dir = plugins_dir / plugin.split("/")[-1]

        if target_dir.exists() and not sp.call(
            ["git", "rev-parse", "--is-inside-work-tree"], cwd=target_dir
        ):
            print(f"{plugin} already installed, skipping")
            continue

        if target_dir.exists():
            shutil.rmtree(target_dir)

        await pip_install("furl")
        import furl

        sp.check_call(
            [
                "git",
                "clone",
                (furl.furl("https://github.com") / plugin).url,
                str(target_dir),
            ]
        )
    install_tpm_packages()


def gh_auth_login():
    if not os.system("gh auth status"):
        return
    sp.check_call(["gh", "auth", "login"])


@functools.lru_cache()
def install_gh_install():
    gh_auth_login()
    sp.check_call(
        [
            "gh",
            "extension",
            "install",
            # "--force",
            "--pin=patch-1",
            "znd4/gh-install",
        ],
        stdin=sys.stdin,
    )


linux_only = skip_if(lambda: platform.system() != "Linux")


DOCKER_PLUGINS_DIR = Path.home() / ".docker" / "cli-plugins"


@linux_only
@env_patch("GH_BINPATH", str(DOCKER_PLUGINS_DIR))
def install_docker_compose():
    if (DOCKER_PLUGINS_DIR / "docker-compose").is_file():
        print("not installing docker compose")
        return

    print("installing docker compose")
    DOCKER_PLUGINS_DIR.mkdir(parents=True, exist_ok=True)
    gh_install("docker/compose")


@skip_if(not sys.stdout.isatty())
def gh_install(repo: str):
    install_gh_install()
    sp.check_call(["gh", "install", repo], stdin=sys.stdin)


def install_pyenv():
    pyenv_root = Path.home() / ".pyenv"
    if not pyenv_root.is_dir():
        sp.check_call(
            [
                "git",
                "clone",
                "https://github.com/pyenv/pyenv.git",
                pyenv_root,
            ]
        )
    pyenv = pyenv_root / "bin" / "pyenv"
    versions = ["3.10.11", "3.11.3"]
    globals = set(sp.check_output([pyenv, "global"], text=True).strip().split("\n"))
    print(f"{globals=}")
    print(f"{versions=}")
    installed = [
        line.lstrip("*").strip()
        for line in sp.check_output(
            [pyenv, "versions"],
            text=True,
        )
        .strip()
        .split("\n")
    ]
    print(f"{installed=}")

    for version in versions:
        if any(v.startswith(version) for v in installed):
            continue
        sp.check_call([pyenv, "install", version])

    sp.check_call([pyenv, "global", *versions])

    for version in versions:
        print(f"{version=}")
        sp.check_call(
            [
                pyenv,
                "exec",
                "pip",
                "install",
                "--upgrade",
                "pynvim",
            ],
            env={"PYENV_VERSION": version, **os.environ},
        )


def brew_bin() -> Path:
    brew = shutil.which("brew")
    if not brew:
        return Path.home() / "homebrew" / "bin"
    return Path(brew).resolve().parent


def brew_path(exe: str) -> Path:
    return brew_bin() / exe


def path_to_brew() -> Path:
    return brew_bin() / "brew"


async def brew_install(*pkgs: str):
    installed = set(sp.check_output([path_to_brew(), "list"], text=True).split())

    await pip_install("more-itertools")
    import more_itertools as mi

    pkgs = (pkg for pkg in pkgs if pkg not in installed)

    for chunk in mi.chunked(pkgs, 10):
        sp.check_call([path_to_brew(), "install", *chunk])


@skip_if(HEADLESS or is_macos())
def symlink_fonts():
    fonts_dir = Path.home() / ".local" / "share" / "fonts"
    if not fonts_dir.is_dir():
        os.symlink(
            str(brew_bin().parent / "share" / "fonts"),
            str(fonts_dir),
        )

    sp.check_call(["fc-cache", "-fv"])


def pipx_cmd(*args: str) -> list[str]:
    return [str(brew_path("pipx")), *args]


async def pipx_install(*packages):
    installed = set(
        json.loads(
            (
                await (
                    await run(
                        pipx_cmd("list", "--json"), stdout=asyncio.subprocess.PIPE
                    )
                ).stdout.read()
            ).decode()
        )["venvs"]
    )

    def to_install_cmd(package):
        if isinstance(package, str):
            return pipx_cmd("install", package)
        return pipx_cmd("install", *package)

    await gather(
        *(
            run(to_install_cmd(package))
            for package in packages
            if package.split("[")[0] not in installed
        )
    )


async def asdf_install():
    plugins = {
        "direnv",
    } - set(
        line.strip()
        for line in sp.run(
            ["asdf", "plugin-list"],
            text=True,
            capture_output=True,
        )
        .stdout.strip()
        .split("\n")
    )
    # direnv
    await gather(*(run(["asdf", "plugin-add", plugin]) for plugin in plugins))
    sp.check_call(["asdf", "install"])


async def krew_install(plugin: str):
    if plugin in krew_list():
        return
    await install_krew()
    await run(["kubectl", "krew", "install", plugin])


KREW_LIST = None


@lru_cache
def krew_list():
    return set(
        sp.check_output(["kubectl", "krew", "list"], text=True).strip().splitlines()
    )


INSTALLING_KREW = False


async def install_krew():
    # safe b.c. async, not separate threads
    global INSTALLING_KREW
    if INSTALLING_KREW or shutil.which("kubectl-krew"):
        return
    INSTALLING_KREW = True
    await bin_install(
        "github.com/kubernetes-sigs/krew",
        LOCAL_BIN / "kubectl-krew",
    ),


asyncio.run(main())
