{
  pkgs ? import <nixpkgs> {}
}:

let
  inherit (pkgs) fetchFromGitHub;

  version = {
    owner = "NixOS";
    repo = "nixpkgs";
    rev = "f6ccdfcd2ac4f2e259d20e378737dcbd0ca7debe";
    sha256 = "1d2lk7a0l166pvgy0xfdlhxgja986hgn39szn9d1fqamyhxzvbaz";
  };
  nixpin = fetchFromGitHub version;
  pinnedPkgs = import nixpin {};

  tools = with pinnedPkgs; {
    inherit kubectl fluxcd;
  };

in pinnedPkgs.mkShell {
  buildInputs = builtins.attrValues tools;
}
