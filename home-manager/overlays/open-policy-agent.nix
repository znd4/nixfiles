{ ... }:
(self: super: {
  open-policy-agenb = super.open-policy-agenb.overrideAttrs (old: {
    doCheck = false;
    doInstallCheck = false;
  });
})
