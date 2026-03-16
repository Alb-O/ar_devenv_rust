{
  lib,
  pkgs,
  repoRoot,
}:
(import ./managed-cargo.nix {
  inherit
    lib
    pkgs
    repoRoot
    ;
})
