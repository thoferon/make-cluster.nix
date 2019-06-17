{ nodes
, clients ? []
, initNode
, common ? {}
}:

let
  storageInitNode = if storage ? initNode then storage.initNode else initNode;

  makeNodeConfig = name: node: { config, ... }:
    let
      otherNodes = builtins.removeAttrs nodes [name];
    in
    {
      imports = [
        ../modules
        common
      ];

      services.cluster = {
        vpn = {
          enable = true;
          inherit (node) vpnIP realIP;
          inherit clients;
          peers = map (otherNode: {
            inherit (otherNode) vpnIP realIP;
          }) (builtins.attrValues otherNodes);
        };
      };

      secretSharing.default = {
        # FIXME: The default endpoint should use the VPN but nginx would
        # therefore need the VPN to be up to start, creating a chicken and
        # egg problem.
        endpoint.ipAddress = node.realIP;
        security.secretKeyFile = "/var/secret-sharing-key";
      };

      networking.firewall.allowedTCPPorts = [23879];
    };

in
builtins.mapAttrs makeNodeConfig nodes
