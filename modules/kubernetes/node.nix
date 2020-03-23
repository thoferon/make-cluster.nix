{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.cluster.kubernetes.node;

  caFile = config.services.cfssl.ca;

  certs = import ./certs.nix {
    nodeName = cfg.name;
    ipAddress = cfg.ipAddress;
  };

  inherit (certs) mkCertPath mkCert;

  certificates = builtins.listToAttrs [
    (mkCert {
      name = "kubelet";
      service = "kubelet";
      owner = "kubernetes";
      group = "kubernetes";
      CN = "system:node:${cfg.name}";
      O = "system:nodes";
    })

    (mkCert {
      name = "kube-proxy";
      service = "kube-proxy";
      owner = "kubernetes";
      group = "kubernetes";
      CN = "system:master:${cfg.name}";
      O = "system:masters";
    })
  ];

in
{
  options.services.cluster.kubernetes.node = {
    enable = mkEnableOption "Kubernetes node";

    name = mkOption {
      type = types.str;
      example = "hydrogen";
      description = "Name of this node.";
    };

    ipAddress = mkOption {
      type = types.str;
      example = "10.128.0.1";
      description = "IP address of this address in the VPN.";
    };

    podCidr = mkOption {
      type = types.str;
      example = "10.1.0.0/24";
      description = "CIDR of IPs used by the pods running on this node.";
    };

    masterIPAddress = mkOption {
      type = types.str;
      example = "10.128.0.1";
      description = "IP Address of one of the API servers.";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [pkgs.kubectl];

    services.kubernetes = {
      roles = ["node"];
      easyCerts = false;
      inherit caFile;

      kubeconfig = {
        inherit caFile;
        certFile = mkCertPath "kubelet";
        keyFile = mkCertPath "kubelet-key";
        server = "https://${cfg.masterIPAddress}:4443";
      };

      apiserverAddress = "https://${cfg.masterIPAddress}:4443";

      kubelet = {
        address = cfg.ipAddress;
        clientCaFile = caFile;
        hostname = cfg.name;
        nodeIp = cfg.ipAddress;
        tlsCertFile = mkCertPath "kubelet";
        tlsKeyFile = mkCertPath "kubelet-key";

        extraOpts = "--pod-cidr ${cfg.podCidr}";

        networkPlugin = "cni";
        cni.config = [{
          cniVersion = "0.3.1";
          name = "kube";
          type = "bridge";
          bridge = "kube0";
          isDefaultGateway = true;
          forceAddress = false;
          ipMasq = true;
          hairpinMode = true;
          ipam = {
            type = "host-local";
            subnet = cfg.podCidr;
          };
        }];

        kubeconfig = {
          inherit caFile;
          certFile = mkCertPath "kubelet";
          keyFile = mkCertPath "kubelet-key";
          server = "https://${cfg.masterIPAddress}:4443";
        };
      };

      proxy  = {
        enable = true;
        bindAddress = cfg.ipAddress;

        kubeconfig = {
          inherit caFile;
          certFile = mkCertPath "kube-proxy";
          keyFile = mkCertPath "kube-proxy-key";
          server = "https://${cfg.masterIPAddress}:4443";
        };
      };
    };

    networking.firewall.interfaces.${config.services.cluster.vpn.interface} = {
      allowedTCPPorts = [
        10250 # kubelet
      ];
    };

    services.certmgr = {
      enable = true;
      specs = certificates;
    };
  };
}
