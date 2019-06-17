{}:
rec {
  nixpkgs = builtins.fetchGit {
    url = "https://github.com/thoferon/nixpkgs.git";
    rev = "e491b042887371f221eaafbfb810cecb47143d8e";
    ref = "wireguard-publickeyfile";
  };
}
