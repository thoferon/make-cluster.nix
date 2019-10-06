subtest "VPN", sub {
  my $hydrogen_ip = "10.128.0.1";
  my $helium_ip = "10.128.0.2";
  my $lithium_ip = "10.128.0.3";

  subtest "servers have been assigned the correct IP", sub {
    sub check_ip {
      my ($server, $ip) = @_;
      my ($status, $out) = $server->execute("ip address show dev wg0");
      $out =~ /$ip/ or die;
    };
    check_ip($vmhydrogen, $hydrogen_ip);
    check_ip($vmhelium, $helium_ip);
    check_ip($vmlithium, $lithium_ip);
  };

  subtest "servers can ping each other", sub {
    $vmhydrogen->succeed("ping -c 1 $helium_ip");
    $vmhelium->succeed("ping -c 1 $lithium_ip");
    $vmlithium->succeed("ping -c 1 $hydrogen_ip");
  };

  subtest "clients can connect to the VPN", sub {
    $alice->start;
    $bob->start;

    $alice->waitForUnit("default.target");
    $bob->waitForUnit("default.target");

    # Alice and Bob connects to hydrogen.
    $alice->succeed("ping -c 1 $lithium_ip");
    $bob->succeed("ping -c 1 $lithium_ip");

    # At the moment, it's only possible if they both connect to the same node.
    my $bob_ip = "10.128.128.2";
    $alice->succeed("ping -c 1 $bob_ip");

    $alice->shutdown;
    $bob->shutdown;
  };
};
