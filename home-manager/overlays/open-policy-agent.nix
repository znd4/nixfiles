{ ... }:
(self: super: {
  open-policy-agent = super.open-policy-agent.overrideAttrs (old: {
    doCheck = false;
    doInstallCheck = false;
  });
})
