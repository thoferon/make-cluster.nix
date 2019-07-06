fetch() {
  local ipAddr="$1"
  local port="$2"
  local identifier="$3"
  local secretKeyFile="$4"
  local path="$5"
  local owner="$6"
  local mode="$7"

  touch "$path"
  chown "$owner" "$path"
  chmod "$mode" "$path"

  # If the file is empty.
  if [ ! -s "$path" ]; then
    # We don't want to loop if the file stays empty. It might be legitimate.
    while true; do
      # This is inside the loop in case it is created or modified later on.
      secretKey="$(cat $secretKeyFile)"

      output="$(curl --fail "http://$ipAddr:$port/$identifier")"
      if [ $? == 0 ]; then
        temppath="$(mktemp)"
        chmod 600 "$temppath"
        IFS="#" read iv encrypted <<<"$output"
        openssl enc -d -aes-256-cbc -base64 -A -K "$secretKey" -iv "$iv" \
          <<<"$encrypted" > "$temppath"
        if [ $? == 0 ]; then
          cp "$temppath" "$path" && rm "$temppath" && exit 0
        else
          sleep 15
        fi
      else
        sleep 15
      fi
    done
  fi
}

fetch "$@"
