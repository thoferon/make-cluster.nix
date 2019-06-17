subtest "Storage", sub {
  $hydrogen->execute("mkdir -p /var/lib/ceph/osd/ceph-0");
  $hydrogen->execute("chown -R ceph:ceph /var/lib/ceph");
  #$hydrogen->waitForUnit("");

  # FIXME:
  # Create file on hydrogen
  # Read file on helium
  # Check contents
};
