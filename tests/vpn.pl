subtest "VPN", sub {
  my $hydrogen_ip = "10.128.0.1";
  my $helium_ip = "10.128.0.2";
  my $lithium_ip = "10.128.0.3";

  subtest "servers have been assigned the correct IP", sub {
    sub check_ip {
      my ($server,$ip) = @_;
      my ($status, $out) = $server->execute("ip address show dev wg0");
      $out =~ /$ip/ or die;
    };
    check_ip($hydrogen, $hydrogen_ip);
    check_ip($helium, $helium_ip);
    check_ip($lithium, $lithium_ip);
  };

  subtest "servers can ping each other", sub {
    $hydrogen->succeed("ping -c 1 $helium_ip");
    $helium->succeed("ping -c 1 $lithium_ip");
    $lithium->succeed("ping -c 1 $hydrogen_ip");
  };
};
