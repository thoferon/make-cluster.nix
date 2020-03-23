args@{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.cluster.kubernetes.master;

  caFile = config.services.cfssl.ca;
  caKeyFile = config.services.cfssl.caKey;

  certs = import ./certs.nix {
    nodeName = cfg.name;
    ipAddress = cfg.ipAddress;
  };

  inherit (certs) mkCertPath mkCert;

  certificates =
    let
      serviceAccount = mkCert {
        service = "kube-apiserver";
        name = "kube-service-account";
        owner = "kubernetes";
        group = "kubernetes";
      };

      kubeAdmin = mkCert {
        name = "kube-admin";
        service = "kube-apiserver";
        action = "reload"; # Just because it needs to do something
        CN = "cluster-admin";
        O = "system:masters";
      };

      etcd = mkCert {
        name = "etcd";
        service = "etcd";
        owner = "etcd";
        group = "root";
      };

      kubeAPIServer = mkCert {
        name = "kube-apiserver";
        service = "kube-apiserver";
        owner = "kubernetes";
        group = "kubernetes";
        CN = "system:master:${cfg.name}";
        O = "system:masters";
      };

      kubeScheduler = mkCert {
        name = "kube-scheduler";
        service = "kube-scheduler";
        owner = "kubernetes";
        group = "kubernetes";
        CN = "system:master:${cfg.name}";
        O = "system:masters";
      };

      kubeControllerManager = mkCert {
        name = "kube-controller-manager";
        service = "kube-controller-manager";
        owner = "kubernetes";
        group = "kubernetes";
        CN = "system:master:${cfg.name}";
        O = "system:masters";
      };

      kubeAddonManager = mkCert {
        name = "kube-addon-manager";
        service = "kube-addon-manager";
        owner = "kubernetes";
        group = "kubernetes";
        CN = "system:master:${cfg.name}";
        O = "system:masters";
      };

      commonCerts = [
        etcd
        kubeAPIServer
        kubeScheduler
        kubeControllerManager
        kubeAddonManager
      ];

    in
    builtins.listToAttrs
      (if cfg.isInitNode
        then commonCerts ++ [serviceAccount kubeAdmin]
        else commonCerts);

  etcdCommonConfig = {
    inherit (cfg) name;
    advertiseClientUrls = ["https://${cfg.ipAddress}:2379"];
    certFile = mkCertPath "etcd";
    clientCertAuth = true;
    initialAdvertisePeerUrls = ["https://${cfg.ipAddress}:2380"];
    keyFile = mkCertPath "etcd-key";
    listenClientUrls = ["https://${cfg.ipAddress}:2379"];
    listenPeerUrls = ["https://${cfg.ipAddress}:2380"];
    peerCertFile = mkCertPath "etcd";
    peerClientCertAuth = true;
    peerKeyFile = mkCertPath "etcd-key";
    peerTrustedCaFile = caFile;
    trustedCaFile = caFile;
  };

  etcdInitConfig = {
    initialClusterState = "new";
    initialCluster = [
      "${cfg.initNode.name}=https://${cfg.initNode.ipAddress}:2380"
    ];
  };

  etcdOtherConfig = {
    initialClusterState = "existing";
    initialCluster =
      let
        takeUntil = pred: list:
          (pkgs.lib.lists.foldr
            (x: { acc, found }:
              let
                found' = found || pred x;
              in
              if found'
                then { acc = [x] ++ acc; found = found'; }
                else { inherit acc found; }
            ) { acc = []; found = false; } list).acc;
      in
      ["${cfg.initNode.name}=https://${cfg.initNode.ipAddress}:2380"]
      ++ builtins.map
          ({ name, ipAddress }: "${name}=https://${ipAddress}:2380")
          (builtins.filter
            ({ name, ... }: name != cfg.initNode.name)
            (takeUntil ({ name, ...}: name == cfg.name)
              cfg.masterIPAddresses));
  };

  etcdConfig =
    etcdCommonConfig //
    (if cfg.isInitNode then etcdInitConfig else etcdOtherConfig);

in
{
  options.services.cluster.kubernetes.master = {
    enable = mkEnableOption "Kubernetes master";

    name = mkOption {
      type = types.str;
      example = "hydrogen";
      description = "Name of this node.";
    };

    ipAddress = mkOption {
      type = types.str;
      example = "10.1.0.1";
      description = "IP address of this node in the VPN.";
    };

    masterIPAddresses = mkOption {
      type = with types; listOf (submodule {
        options = {
          name = mkOption {
            type = str;
            description = "Name of the node";
          };

          ipAddress = mkOption {
            type = str;
            description = "IP address of the node";
          };
        };
      });

      example = [{ name = "hydrogen"; ipAddress = "10.1.0.2"; }];

      description = ''
        IP addresses of the master nodes.

        Add new nodes *at the end* of the list. The order in the list determines
        the order in which they are added to the etcd member list.
      '';
    };

    initNode = {
      name = mkOption {
        type = types.str;
        example = "hydrogen";
        description = "Initialisation node's name.";
      };

      ipAddress = mkOption {
        type = types.str;
        example = "10.1.0.1";
        description = "Initialisation node's IP address.";
      };

      # FIXME: This should go away when the issue with secretSharing not being
      # able to use the VPN is fixed.
      sharedFileIPAddress = mkOption {
        type = types.str;
        example = "1.2.3.4";
        description = "IP address on which secretSharing is listening.";
      };
    };

    isInitNode = mkOption {
      type = types.bool;
      default = false;
      description = "Whether this node is the initialisation node.";
    };
  };

  config = mkIf cfg.enable {
    services.kubernetes = {
      roles = ["master"];
      easyCerts = false;
      inherit caFile;

      apiserver = {
        advertiseAddress = cfg.ipAddress;
        bindAddress = cfg.ipAddress;
        securePort = 4443;
        clientCaFile = caFile;
        kubeletClientCaFile = caFile;
        kubeletClientCertFile = mkCertPath "kube-apiserver";
        kubeletClientKeyFile = mkCertPath "kube-apiserver-key";
        proxyClientCertFile = mkCertPath "kube-apiserver";
        proxyClientKeyFile = mkCertPath "kube-apiserver-key";
        tlsCertFile = mkCertPath "kube-apiserver";
        tlsKeyFile = mkCertPath "kube-apiserver-key";
        serviceAccountKeyFile = mkCertPath "kube-service-account-key";

        etcd = {
          inherit caFile;
          servers = ["https://${cfg.ipAddress}:2379"];
          certFile = mkCertPath "kube-apiserver";
          keyFile = mkCertPath "kube-apiserver-key";
        };
      };

      scheduler = {
        enable = true;
        address = cfg.ipAddress;

        kubeconfig = {
          inherit caFile;
          certFile = mkCertPath "kube-scheduler";
          keyFile = mkCertPath "kube-scheduler-key";
          server = "https://${cfg.ipAddress}:4443";
        };
      };

      controllerManager = {
        enable = true;
        bindAddress = cfg.ipAddress;
        rootCaFile = caFile;
        serviceAccountKeyFile = mkCertPath "kube-service-account-key";
        tlsCertFile = mkCertPath "kube-controller-manager";
        tlsKeyFile = mkCertPath "kube-controller-manager-key";

        kubeconfig = {
          inherit caFile;
          certFile = mkCertPath "kube-controller-manager";
          keyFile = mkCertPath "kube-controller-manager-key";
          server = "https://${cfg.ipAddress}:4443";
        };
      };

      addons = {
        dashboard = {
          enable = true;
          rbac = {
            enable = true;
            clusterAdmin = true;
          };
        };

        dns = {
          enable = true;
          replicas = 3;
        };
      };

      addonManager.enable = true;
    };

    # Ideally, this should be fixed upstream but I don't have time now.
    systemd.services.kube-addon-manager.environment.KUBECTL_OPTS =
      builtins.concatStringsSep " " [
        "--server https://${cfg.ipAddress}:4443"
        "--certificate-authority ${caFile}"
        "--client-certificate ${mkCertPath "kube-addon-manager"}"
        "--client-key ${mkCertPath "kube-addon-manager-key"}"
      ];

    services.certmgr = {
      enable = true;
      specs = certificates;
    };

    services.etcd = etcdConfig;

    # Etcd might fail because the VPN is not up, we don't have the certs or
    # because the init node hasn't added this node as a member yet.
    # This unit should restart until it works.
    systemd.services.etcd = {
      serviceConfig = {
        RestartSec = "10";
        Restart = "always";
        # Never trigger the start limit.
        StartLimitIntervalSec = "1";
        StartLimitBurst = "5";
      };

      # FIXME: This should be fixed in NixOS/nixpkgs.
      environment = {
        ETCD_PEER_CLIENT_CERT_AUTH = "1";
      };
    };

    systemd.services.etcd-init = mkIf cfg.isInitNode {
      enable = true;

      reloadIfChanged = true;
      wantedBy = ["multi-user.target"];
      requires = ["network.target"];
      serviceConfig = {
        RestartSec = "5";
        Restart = "on-failure";
        # Never trigger the start limit.
        StartLimitIntervalSec = "1";
        StartLimitBurst = "5";
      };

      path = with pkgs; [etcd gnugrep];

      script = ''
        ctl() {
          etcdctl \
            --endpoints https://${cfg.initNode.ipAddress}:2379 \
            --ca-file ${caFile} \
            --cert-file ${mkCertPath "etcd"} \
            --key-file ${mkCertPath "etcd-key"} \
            "$@"
        }

        add_member() {
          local name="$1"
          local addr="$2"

          (ctl member list | grep "$name") || \
            ctl member add "$name" "https://$addr:2380"
          while true; do
            (ctl member list | grep "$name") && break || sleep 5
          done
        }

        ${builtins.concatStringsSep "\n" (builtins.map
          ({ name, ipAddress }: "add_member ${name} ${ipAddress}")
          cfg.masterIPAddresses)}
      '';
    };

    networking.firewall.interfaces.${config.services.cluster.vpn.interface} = {
      allowedTCPPorts = [
        2379 2380 # etcd
        4443 # apiserver
      ];
    };

    secretSharing.sharedFiles."kube-service-account-key" = mkIf cfg.isInitNode {
      path = "/var/lib/secrets/kube-service-account-key.pem";
    };

    secretSharing.remoteFiles = mkIf (!cfg.isInitNode) [{
      path = "/var/lib/secrets/kube-service-account-key.pem";
      identifier = "kube-service-account-key";
      owner = "kubernetes:kubernetes";
      mode = "0600";
      endpoint.ipAddress = cfg.initNode.sharedFileIPAddress;
      wantedBy = ["kube-apiserver.service"];
    }];
  };
}
