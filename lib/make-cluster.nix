{ nodes }:

let
  makeNodeConfig = name: node: { config, ... }:
    let
      otherNodes = builtins.removeAttrs nodes [name];
    in
    {
      imports = [../modules];

      services.cluster = {
        vpn = {
          enable = true;
          inherit (node) vpnIP realIP;
          peers = map (otherNode: {
            inherit (otherNode) vpnIP realIP;
          }) (builtins.attrValues otherNodes);
        };
      };
    };

in
builtins.mapAttrs makeNodeConfig nodes
