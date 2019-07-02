{ nodeName, ipAddress }:

rec {
  mkCertPath = name: "/var/lib/secrets/${name}.pem";

  mkCert =
    { service
    , action ? "restart"
    , name
    , CN ? "cluster.local"
    , O ? "cluster"
    , owner ? "root"
    , group ? owner
    , mode ? "0600"
    , otherHosts ? []
    }:
    let
      value = {
        inherit service action;
        authority = {
          remote = "http://127.0.0.1:8888";
        };
        certificate = {
          path = mkCertPath name;
        };
        private_key = {
          path = mkCertPath "${name}-key";
          inherit owner group mode;
        };
        request = {
          inherit CN;
          hosts = [
            nodeName
            ipAddress
            "10.0.0.1"
            "kubernetes"
            "kubernetes.default"
            "kubernetes.default.svc"
            "kubernetes.default.svc.cluster"
            "kubernetes.default.svc.cluster.local"
          ];
          key = {
            algo = "rsa";
            size = 2048;
          };
          names = [{
            inherit O;
            L = "Internet";
          }];
        };
      };
    in
    { inherit name value; };
}
