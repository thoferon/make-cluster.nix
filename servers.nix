{}:

let
  nodes = import ./nodes.nix;
  configs = import ./lib/make-cluster.nix {
    inherit nodes;
  };

  mkServer = name: config:
    let
      sources = (import ./sources.nix {}).${name};
      nixos = import (sources.nixpkgs + /nixos) {
        system = "x86_64-linux";
        configuration = config;
      };
    in
    nixos.system;

in
builtins.mapAttrs mkServer nodes
