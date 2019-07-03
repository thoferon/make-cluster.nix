{ nodes
, clients ? []
, initNode
, common ? {}
}:

let
  makeNodeConfig =
    name:
    {
      vpnIP,
      realIP,
      kubeMaster ? false
    }:
    { config, lib, ... }:
    let
      otherNodes = builtins.removeAttrs nodes [name];
      masterIPAddresses =
        builtins.mapAttrs
          (name: node: node.vpnIP)
          (lib.attrsets.filterAttrs
            (_: node: if node ? kubeMaster then node.kubeMaster else false)
            nodes);
      isInitNode = initNode == name;
      masterIPAddress = if kubeMaster then vpnIP else nodes.${initNode}.vpnIP;
    in
    {
      imports = [
        ../modules
        common
      ];

      services.cluster = {
        vpn = {
          enable = true;
          inherit name vpnIP realIP clients;
          peers = builtins.attrValues (builtins.mapAttrs (name: otherNode: {
            inherit name;
            inherit (otherNode) vpnIP realIP;
          }) otherNodes);
        };

        pki = {
          enable = true;
          initNodeIP = nodes.${initNode}.realIP;
          inherit isInitNode;
        };

        kubernetes = {
          master = {
            enable = kubeMaster;
            ipAddress = vpnIP;
            inherit name isInitNode masterIPAddresses;
            initNode = {
              name = initNode;
              ipAddress = nodes.${initNode}.vpnIP;
              sharedFileIPAddress = nodes.${initNode}.realIP;
            };
          };

          node = {
            enable = true;
            inherit name masterIPAddress;
            ipAddress = vpnIP;
          };
        };
      };

      secretSharing.default = {
        # FIXME: The default endpoint should use the VPN but nginx would
        # therefore need the VPN to be up to start, creating a chicken and
        # egg problem.
        endpoint.ipAddress = realIP;
        security.secretKeyFile = "/var/secret-sharing-key";
      };

      networking.firewall.allowedTCPPorts = [23879];
    };

in
builtins.mapAttrs makeNodeConfig nodes
