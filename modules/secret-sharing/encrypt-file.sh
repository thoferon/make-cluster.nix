set -e

iv="$(echo "$SALT$IDENTIFIER" | md5sum | cut -d' ' -f1)"
secretKey="$(cat $SECRET_KEY_FILE)"
pathExpr=""
if [ "$SHARED_TYPE" == "path" ]; then
  pathExpr="$SHARED_OBJECT"
else
  pathExpr="<(eval \"$SHARED_OBJECT\")"
fi
encrypted="$(eval openssl enc -aes-256-cbc -base64 -A -in $pathExpr -K "$secretKey" -iv "$iv")"

echo "HTTP/1.1 200 OK"
echo "Content-type: text/plain"
echo
echo "$iv#$encrypted"
