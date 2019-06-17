{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.cluster.storage;

  isInitMember = cfg.name == cfg.initialMember.name;

  initCeph =
    with pkgs; runCommand "init-ceph" { buildInputs = [makeWrapper]; } ''
      makeWrapper ${./init-ceph.sh} "$out" \
        --suffix PATH : "${lib.makeBinPath [ceph sudo utillinux]}"
    '';

  osdOptions = {
    id = mkOption {
      type = types.str;
      example = "0";
      description = "OSD ID";
    };

    device = mkOption {
      type = types.str;
      example = "/dev/sda";
      description = "Disk used by the OSD's data.";
    };
  };

in
{
  options.services.cluster.storage = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Ceph cluster as persistent storage for the cluster.";
    };

    fsid = mkOption {
      type = types.str;
      example = "a0ffc974-222e-449a-a078-121bdfcb110b";
      description = "Filesystem ID (random UUID.)";
    };

    subnet = mkOption {
      type = types.str;
      example = "10.128.0.0/16";
      description = "Subnet of nodes in the cluster.";
    };

    name = mkOption {
      type = types.str;
      example = "hydrogen";
      description = "Name identifying this node in the cluster.";
    };

    ipAddress = mkOption {
      type = types.str;
      example = "10.128.0.1";
      description = "IP address of this node in the cluster.";
    };

    initialMember = mkOption {
      type = with types; submodule {
        options = {
          name = mkOption {
            type = str;
            description = "Name of the initial node.";
          };

          ipAddress = mkOption {
            type = str;
            description = "IP address of the initial node.";
          };
        };
      };
      example = { name = "hydrogen"; ipAddress = "10.128.0.1"; };
    };

    osds = mkOption {
      type = with types; listOf (submodule { options = osdOptions; });
      default = [];
      description = "List of OSDs running on this node.";
    };

    requiredUnits = mkOption {
      type = with types; listOf str;
      default = [];
      example = ["wireguard-wg0.service"];
      description = "Units that need to be started before Ceph.";
    };
  };

  imports = [
    {
      systemd.services = mkIf cfg.enable (listToAttrs
        (lists.concatLists (map ({ id, device, ... }: [
          {
            name = "ceph-osd-${id}";
            value = {
              wants = ["init-ceph-osd-${id}.service"];
              after = ["init-ceph-osd-${id}.service"];
              serviceConfig.PrivateDevices = mkForce "no";
            };
          }
          {
            name = "init-ceph-osd-${id}";
            value = {
              description = "Initialise Ceph's MGR daemon.";
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
              };
              wants = cfg.requiredUnits ++ ["init-ceph-mon.service"];
              after = cfg.requiredUnits ++ ["init-ceph-mon.service"];
              script = ''
                ${initCeph} ${pkgs.lib.strings.escapeShellArgs [
                  "osd"
                  id
                  device
                ]}
              '';
            };
          }
        ]) cfg.osds)));
    }
  ];

  config = mkIf cfg.enable {
    services.ceph = {
      enable = true;
      client.enable = true;

      global = {
        inherit (cfg) fsid;
        clusterNetwork = cfg.subnet;
        publicNetwork = cfg.subnet;
        monInitialMembers = cfg.initialMember.name;
        monHost = cfg.initialMember.ipAddress;
      };

      mgr = {
        enable = true;
        daemons = [cfg.name];
      };

      mon = {
        enable = true;
        daemons = [cfg.name];
      };

      osd = {
        enable = true;
        daemons = map ({ id, ...}: id) cfg.osds;
      };

      mds = {
        enable = true;
        daemons = [cfg.name];
      };

      rgw = {
        enable = true;
        daemons = [cfg.name];
      };
    };

    environment.systemPackages = [pkgs.ceph];

    systemd.services.init-ceph-mon = {
      description = "Initialise Ceph's MON daemon.";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      wants = cfg.requiredUnits;
      after = cfg.requiredUnits;
      before = ["ceph-mon-${cfg.name}.service"];
      wantedBy = ["ceph-mon-${cfg.name}.service"];
      script = ''
        ${initCeph} ${pkgs.lib.strings.escapeShellArgs (with cfg; [
          "mon"
          fsid
          name
          ipAddress
          initialMember.name
          initialMember.ipAddress
        ])}
      '';
    };

    systemd.services.init-ceph-mgr = {
      description = "Initialise Ceph's MGR daemon.";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      wants = cfg.requiredUnits ++ ["init-ceph-mon.service"];
      after = cfg.requiredUnits ++ ["init-ceph-mon.service"];
      before = ["ceph-mgr-${cfg.name}.service"];
      wantedBy = ["ceph-mgr-${cfg.name}.service"];
      script = ''
        ${initCeph} ${pkgs.lib.strings.escapeShellArgs (with cfg; [
          "mgr"
          name
        ])}
      '';
    };

    systemd.services.init-ceph-mds = {
      description = "Initialise Ceph's MDS daemon.";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      wants = cfg.requiredUnits ++ ["init-ceph-mds.service"];
      after = cfg.requiredUnits ++ ["init-ceph-mds.service"];
      before = ["ceph-mds-${cfg.name}.service"];
      wantedBy = ["ceph-mds-${cfg.name}.service"];
      script = ''
        ${initCeph} ${pkgs.lib.strings.escapeShellArgs (with cfg; [
          "mds"
          name
        ])}
      '';
    };

    # We can't use ceph.target directly as it is broken.
    systemd.targets.ceph-mon.wantedBy = ["multi-user.target"];
    systemd.targets.ceph-mgr.wantedBy = ["multi-user.target"];
    systemd.targets.ceph-mds.wantedBy = ["multi-user.target"];
    systemd.targets.ceph-osd.wantedBy = ["multi-user.target"];

    # To show errors.
    systemd.services."ceph-rgw-${cfg.name}".path = [pkgs.binutils];

    secretSharing = {
      sharedFiles = mkIf isInitMember {
        "ceph-mon-keyring" = {
          command = "${pkgs.ceph}/bin/ceph auth get mon.";
        };
      };
    };
  };
}
