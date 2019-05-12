set -e

iv="$(echo "$SALT$IDENTIFIER" | md5sum | cut -d' ' -f1)"
secretKey="$(cat $SECRET_KEY_FILE)"
encrypted="$(openssl enc -aes-256-cbc -base64 -in "$SHARED_PATH" -K "$secretKey" -iv "$iv")"

echo "HTTP/1.1 200 OK"
echo "Content-type: text/plain"
echo
echo "$iv#$encrypted"
