# End-to-end check of the disko LUKS layout plus initrd SSH unlock:
#
# 1. `installer` formats an empty disk with nixos/disko/luks-btrfs.nix,
#    generates the initrd host key on the target (as a real install would), and
#    installs `installedSystem` onto it.
# 2. The disk is booted as a second VM with the initrd's sshd forwarded to the
#    test driver. The driver SSHes in, checking the host key it just saw
#    generated. A wrong passphrase must be rejected and asked for again; the
#    right one is then accepted.
# 3. The system must then finish booting with / on the unlocked LUKS volume,
#    and a file written to it during the install must be there.
#
# The passphrase doubles as a canary: it must not show up on the unencrypted
# ESP, nor anywhere in the installed system's store closure.
{
  pkgs,
  lib,
  nixosSystem,
  disko,
}:
let
  # Only ever written to /tmp/disk.key inside the installer VM.
  canary = "luks-canary-0b7e4d91f2a6c835";
  sshPort = 2222;

  # Throwaway client keypair that nixpkgs ships for its own initrd-ssh tests.
  # A source path, so reading the .pub is not import-from-derivation.
  clientKey = "${pkgs.path}/nixos/tests/initrd-network-ssh/id_ed25519";

  layout = import ../disko/luks-btrfs.nix {
    # The installer's own root is /dev/vda. disko mounts by partition label,
    # so the booted VM finds the partitions although the disk is /dev/vda there.
    device = "/dev/vdb";
    espSize = "256M";
  };

  installedSystem = nixosSystem {
    system = pkgs.stdenv.hostPlatform.system;
    modules = [
      disko.nixosModules.disko
      layout
      ../modules/initrd-ssh-unlock.nix
      (
        { modulesPath, ... }:
        {
          imports = [
            (modulesPath + "/testing/test-instrumentation.nix")
            (modulesPath + "/profiles/qemu-guest.nix")
          ];

          znd4.initrdSshUnlock = {
            enable = true;
            port = sshPort;
            authorizedKeys = [ (builtins.readFile "${clientKey}.pub") ];
          };

          boot.loader.systemd-boot.enable = true;
          # The booted VM's EFI variables are read-only; OVMF falls back to
          # \EFI\BOOT\BOOTX64.EFI.
          boot.loader.systemd-boot.graceful = true;
          boot.consoleLogLevel = lib.mkForce 100;

          # Share the host store instead of copying the closure onto the disk.
          fileSystems."/nix/store" = lib.mkForce {
            device = "nix-store";
            fsType = "9p";
            neededForBoot = true;
            options = [
              "trans=virtio"
              "version=9p2000.L"
              "cache=loose"
            ];
          };

          documentation.enable = false;
          networking.hostName = "luks-ssh-unlock";
          system.stateVersion = "25.11";
        }
      )
    ];
  };

  toplevel = installedSystem.config.system.build.toplevel;

  qemu-common = import "${pkgs.path}/nixos/lib/qemu-common.nix" { inherit lib pkgs; };
in
{
  test = pkgs.testers.runNixOSTest {
    name = "luks-ssh-unlock";

    nodes.installer = {
      virtualisation.emptyDiskImages = [ 4096 ];
      virtualisation.memorySize = 2048;
      boot.supportedFilesystems = [
        "btrfs"
        "vfat"
      ];
      environment.systemPackages = [
        pkgs.cryptsetup
        pkgs.openssh
      ];
      documentation.enable = false;
      nix.settings.substituters = lib.mkForce [ ];
    };

    # The driver predefines a Python variable per node (`installer`) and helpers
    # such as `subtest`, `create_machine`, `driver` and `retry`:
    # https://nixos.org/manual/nixos/stable/#sec-nixos-tests
    testScript = ''
      import os
      import select
      import shlex
      import shutil
      import subprocess
      import tempfile
      import time

      PASSPHRASE = "${canary}"
      WRONG_PASSPHRASE = "not-the-passphrase"
      MARKER = "written-during-install"
      HOST_KEY = "/mnt/etc/secrets/initrd/ssh_host_ed25519_key"

      with subtest("format the disk and install"):
          installer.start()
          installer.succeed(f"printf %s {PASSPHRASE} > /tmp/disk.key")
          installer.succeed(
              "${lib.getExe installedSystem.config.system.build.destroyFormatMount} --yes-wipe-all-disks"
          )
          installer.succeed("rm /tmp/disk.key")
          installer.succeed("cryptsetup isLuks /dev/vdb2")

          # Generated on the target at install time; only the public half
          # leaves it, to be pinned by the client.
          installer.succeed(f"install -d -m 700 {os.path.dirname(HOST_KEY)}")
          installer.succeed(f"ssh-keygen -q -t ed25519 -N ''' -C initrd -f {HOST_KEY}")
          host_pub = installer.succeed(f"cut -d' ' -f1,2 {HOST_KEY}.pub").strip()

          installer.succeed("mkdir -p /mnt/nix/store && mount --bind /nix/store /mnt/nix/store")
          installer.succeed(
              "nix-store --load-db < ${pkgs.closureInfo { rootPaths = [ toplevel ]; }}/registration"
          )
          installer.succeed("mkdir -p /mnt/etc && touch /mnt/etc/NIXOS")
          installer.succeed("mkdir -p /mnt/nix/var/nix/profiles")
          installer.succeed("nix-env -p /mnt/nix/var/nix/profiles/system --set ${toplevel}")
          installer.succeed(
              "NIXOS_INSTALL_BOOTLOADER=1 nixos-enter --root /mnt -- ${toplevel}/bin/switch-to-configuration boot"
          )
          # On the encrypted root; only readable after a real unlock.
          installer.succeed(f"echo {MARKER} > /mnt/etc/luks-test-marker")

      with subtest("no secrets on the unencrypted ESP"):
          installer.fail(f"grep -rqaF {PASSPHRASE} /mnt/boot")
          # The initrd host key is meant to be there (appended to the initrd);
          # the main system's host keys must not be.
          installer.fail("ls /mnt/boot | grep -q ssh_host")

      installer.succeed("sync")
      installer.shutdown()

      start_command = shlex.split("${qemu-common.qemuBinary pkgs.qemu_test}") + [
          # LUKS2's argon2id cost was benchmarked on the 2 GiB installer; less RAM
          # here and cryptsetup is OOM-killed while deriving the key.
          "-m", "2048",
          "-virtfs", "local,path=/nix/store,security_model=none,mount_tag=nix-store",
          "-drive", f"file={installer.state_dir}/empty0.qcow2,id=drive1,if=none,index=1,werror=report",
          "-device", "virtio-blk-pci,drive=drive1",
          "-drive", "if=pflash,format=raw,unit=0,readonly=on,file=${pkgs.OVMF.firmware}",
          "-drive", "if=pflash,format=raw,unit=1,readonly=on,file=${pkgs.OVMF.variables}",
          "-nic", "user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:${toString sshPort}-:${toString sshPort}",
      ]
      booted = create_machine(start_command=" ".join(start_command), name="booted")
      driver.machines.append(booted)

      def answer_over_ssh(tmp: str, passphrase: str) -> bool:
          """One attempt. False if sshd is not up yet or nothing is asking."""
          cmd = [
              "${pkgs.openssh}/bin/ssh", "-F", "/dev/null", "-tt",
              "-p", "${toString sshPort}", "-i", f"{tmp}/id_ed25519",
              "-o", f"UserKnownHostsFile={tmp}/known_hosts",
              "-o", "StrictHostKeyChecking=yes",
              "-o", "IdentitiesOnly=yes",
              "-o", "ConnectTimeout=5",
              "root@127.0.0.1",
          ]
          proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
          assert proc.stdin is not None and proc.stdout is not None
          stdin, stdout = proc.stdin, proc.stdout
          output = b""
          deadline = time.monotonic() + 30
          while b"assphrase" not in output:
              remaining = deadline - time.monotonic()
              ready, _, _ = select.select([stdout], [], [], max(remaining, 0))
              chunk = os.read(stdout.fileno(), 4096) if ready else b""
              if not chunk:
                  proc.kill()
                  proc.wait()
                  booted.log(f"ssh attempt ended without a prompt: {output!r}")
                  # A host key mismatch must fail the test, not be retried.
                  assert b"Host key verification failed" not in output, output
                  return False
              output += chunk
          stdin.write(passphrase.encode() + b"\n")
          stdin.close()
          proc.wait(timeout=60)
          return True

      def answer_prompt(tmp: str, passphrase: str) -> None:
          for _ in range(60):
              if answer_over_ssh(tmp, passphrase):
                  return
              time.sleep(3)
          raise AssertionError("never got a passphrase prompt over SSH")

      tmp = tempfile.mkdtemp()
      shutil.copy("${clientKey}", f"{tmp}/id_ed25519")
      os.chmod(f"{tmp}/id_ed25519", 0o600)
      with open(f"{tmp}/known_hosts", "w") as f:
          f.write(f"[127.0.0.1]:${toString sshPort} {host_pub}\n")

      booted.start()

      with subtest("a wrong passphrase is rejected and asked for again"):
          answer_prompt(tmp, WRONG_PASSPHRASE)
          # Not wait_for_console_text: it takes one queued line per second,
          # and the boot log ahead of this message is longer than the timeout.
          retry(lambda _: "(Passphrase incorrect?)" in booted.get_console_log(), timeout=60)

      with subtest("the right passphrase over SSH unlocks the disk"):
          answer_prompt(tmp, PASSPHRASE)

      with subtest("system boots from the unlocked volume"):
          booted.wait_for_unit("multi-user.target")
          booted.succeed("findmnt -no SOURCE / | grep -q '^/dev/mapper/cryptroot'")
          booted.succeed("cryptsetup status cryptroot | grep -q 'is active'")
          booted.succeed(f"grep -qx {MARKER} /etc/luks-test-marker")
          booted.fail(f"grep -rqaF {PASSPHRASE} /boot")
    '';
  };

  # Fails if the passphrase canary is anywhere in the installed system's
  # closure, i.e. if some option was handed the secret's contents or a path
  # literal instead of a runtime path string.
  secretsNotInStore =
    pkgs.runCommand "luks-ssh-unlock-secrets-not-in-store"
      { closure = pkgs.closureInfo { rootPaths = [ toplevel ]; }; }
      ''
        if xargs grep -rlaF ${lib.escapeShellArg canary} < $closure/store-paths; then
          echo "canary found in the store paths above" >&2
          exit 1
        fi
        touch $out
      '';
}
