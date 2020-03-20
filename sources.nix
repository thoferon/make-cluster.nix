{}:
rec {
  nixpkgs = builtins.fetchGit {
    url = "https://github.com/thoferon/nixpkgs.git";
    rev = "ec552a73a076197a87eaf55ebec479b99a56e1ef";
    ref = "wireguard-publickeyfile";
  };
}
