{
  # Disable if you don't want unfree packages
  allowUnfree = true;
  # Workaround for https://github.com/nix-community/home-manager/issues/2942
  allowUnfreePredicate = _: true;
}
