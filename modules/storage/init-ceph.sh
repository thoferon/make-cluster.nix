set -x

keyring_has_key() {
  local keyringFile="$1"
  local keyFile="$2"
  local keyName="$3"

  local key="$(ceph-authtool --print-key "$keyFile" -n "$keyName")"
  ceph-authtool --list "$keyringFile" | grep "key = $key" > /dev/null
}

cluster_has_key() {
  local name="$1"

  ceph auth get "$name" > /dev/null
}

init_mon() {
  local fsid="$1"
  local name="$2"
  local ipAddress="$3"
  local initMemberName="$4"
  local initMemberIPAddress="$5"

  mkdir -p "/var/lib/ceph/mon/ceph-$name"
  mkdir -p /etc/ceph

  if [ "$name" == "$initMemberName" ]; then
    init_initial_mon "$fsid" "$name" "$ipAddress"
  else
    init_other_mon "$fsid" "$name" "$ipAddress" "$initMemberIPAddress"
  fi

  chown -R ceph:ceph /var/lib/ceph/mon
}

init_initial_mon() {
  local fsid="$1"
  local name="$2"
  local ipAddress="$3"

  [ -f /var/lib/ceph/ceph.mon.keyring ] ||
    ceph-authtool --create-keyring /var/lib/ceph/ceph.mon.keyring \
      --gen-key -n mon. --cap mon 'allow *'

  [ -f /etc/ceph/ceph.client.admin.keyring ] ||
    ceph-authtool --create-keyring /etc/ceph/ceph.client.admin.keyring \
      --gen-key -n client.admin --cap mon 'allow *' --cap osd 'allow *' \
      --cap mds 'allow *' --cap mgr 'allow *' --cap rgw 'allow *'

  keyring_has_key /var/lib/ceph/ceph.mon.keyring \
      /etc/ceph/ceph.client.admin.keyring client.admin ||
    ceph-authtool /var/lib/ceph/ceph.mon.keyring \
      --import-keyring /etc/ceph/ceph.client.admin.keyring

  [ -f /var/lib/ceph/monmap ] ||
    monmaptool --create --fsid "$fsid" \
      --add "$name" "$ipAddress"

  chown ceph:ceph /var/lib/ceph /var/lib/ceph/ceph.mon.keyring

  [ -f "/var/lib/ceph/mon/ceph-$name/keyring" ] ||
    sudo -u ceph ceph-mon --mkfs -i "$name" \
      --monmap /var/lib/ceph/monmap --keyring /var/lib/ceph/ceph.mon.keyring
}

init_other_mon() {
  local fsid="$1"
  local name="$2"
  local ipAddress="$3"
  local initMemberIPAddress="$6"

}

init_mgr() {
  local name="$1"

  mkdir -p "/var/lib/ceph/mgr/ceph-$name"

  touch "/var/lib/ceph/mgr/ceph-$name/keyring"
  chmod 600 "/var/lib/ceph/mgr/ceph-$name/keyring"

  [ -s "/var/lib/ceph/mgr/ceph-$name/keyring" ] ||
    ceph auth get-or-create "mgr.$name" \
      mon 'allow profile mgr' osd 'allow *' mds 'allow *' \
      -o "/var/lib/ceph/mgr/ceph-$name/keyring"

  chown -R ceph:ceph /var/lib/ceph/mgr
}

init_osd() {
  local id="$1"
  local device="$2"

  chown ceph:ceph "$device"

  if [ ! -d "/var/lib/ceph/osd/ceph-$id" ]; then
    mkdir -p "/var/lib/ceph/osd/ceph-$id"

    local uuid="$(uuidgen)"
    local osdSecret="$(ceph-authtool --gen-print-key)"

    ln -sf "$device" "/var/lib/ceph/osd/ceph-$id/block"
    chown ceph:ceph "/var/lib/ceph/osd/ceph-$id/block"
    #ln -sf "$device" "/var/lib/ceph/osd/ceph-$id/superblock"
    #chown ceph:ceph "$device" "/var/lib/ceph/osd/ceph-$id/superblock"

    ceph-authtool --create-keyring "/var/lib/ceph/osd/ceph-$id/keyring" \
      --name "osd.$id" --add-key "$osdSecret"

    chown -R ceph:ceph "/var/lib/ceph/osd/ceph-$id"
    chown ceph:ceph /var/lib/ceph/osd

    ceph osd new "$uuid" "osd.$id" -i - -n client.admin \
      -k /etc/ceph/ceph.client.admin.keyring \
      <<<"{\"cephx_secret\":\"$osdSecret\"}"

    ceph-osd -i "$id" --osd-objectstore bluestore --mkfs --osd-uuid "$uuid"

    ceph-bluestore-tool prime-osd-dir --dev "$device" \
      --path "/var/lib/ceph/osd/ceph-$id"

    chown -R ceph:ceph "/var/lib/ceph/osd/ceph-$id"
  fi
}

init_mds() {
  local name="$1"

  mkdir -p "/var/lib/ceph/mds/ceph-$name"

  [ -f "/var/lib/ceph/mds/ceph-$name/keyring" ] ||
    ceph-authtool --create-keyring "/var/lib/ceph/mds/ceph-$name/keyring" \
      --gen-key -n "mds.$name"

  cluster_has_key "mds.$name" ||
    ceph auth add "mds.$name" osd "allow rwx" mds "allow" mon "allow profile mds" \
      -i "/var/lib/ceph/mds/ceph-$name/keyring"

  chown -R ceph:ceph "/var/lib/ceph/mds/ceph-$name"
}

case "$1" in
  mon)
    init_mon "$2" "$3" "$4" "$5" "$6"
    ;;

  mgr)
    init_mgr "$2"
    ;;

  osd)
    init_osd "$2" "$3"
    ;;

  mds)
    init_mds "$2"
    ;;

  *)
    error Incorrect first argument >&2
    ;;
esac
