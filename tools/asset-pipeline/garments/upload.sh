#!/bin/zsh
# upload.sh <file> <put-url>: PUTs one PNG to a presigned upload URL and prints the HTTP status.
curl -sS -o /dev/null -w "%{http_code} $1\n" -X PUT -H "Content-Type: image/png" --data-binary @"$1" "$2"
