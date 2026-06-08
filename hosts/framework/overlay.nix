final: prev: {
  linux_zen_7_0 = prev.linux_zen.override {
    argsOverride = rec {
      version = "7.0.9";
      suffix = "zen1";
      modDirVersion = final.lib.versions.pad 3 "${version}-${suffix}";
      structuredExtraConfig = builtins.removeAttrs prev.linux_zen.structuredExtraConfig [
        "PREEMPT_VOLUNTARY"
      ];
      src = final.fetchFromGitHub {
        owner = "zen-kernel";
        repo = "zen-kernel";
        rev = "v${version}-${suffix}";
        sha256 = "1fm1v1ghhls6kvfn6mdzcsq8rmng428ws329xb6ry1j3ax3apvmy";
      };
    };
  };
  linuxPackages_zen_7_0 = final.linuxPackagesFor final.linux_zen_7_0;
}
