{
  nixpkgs-unstable,
  overlay,
}:

{
  unstablePkgsFor =
    system:
    import nixpkgs-unstable {
      inherit system;
      config = {
        allowUnfree = true;
        cudaSupport = true;
      };
      overlays = [ overlay ];
    };
}
