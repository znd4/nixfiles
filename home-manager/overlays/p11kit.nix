{...}:
(self: super: {
        p11-kit = super.p11-kit.overrideAttrs (old: { 
                doCheck = false; 
                doInstallCheck = false; 
        });
})
