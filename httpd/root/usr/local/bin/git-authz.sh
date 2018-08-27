#!/usr/bin/env bash
set +x
read -n1024 USER
read -n1024 PASSWORD

## Remap urls to be constent
URI=$(echo $URI | sed 's/\/push//')
URI=$(echo $URI | sed 's/\/pull//')

# Set by docker
MILLICORE_HOST=$@
# Set by apache AuthExternalContext
ACTION=${CONTEXT}
# Fetch required data from URI
REPOSITORY=`echo $URI | sed 's/\/\(.*\)\.git.*/\1/'`
DOMAIN=`echo $URI | awk -F'/' '{print $2}'`

LOGIN=`curl --silent -H "Content-Type: application/json" --data-binary '{"domain":"'"$DOMAIN"'","user":"'"$USER"'","token":"'"$PASSWORD"'"}' "http://$MILLICORE_HOST/box/api/gitlab/authenticate" 2>&1`
LOGIN=`echo $LOGIN | grep '"status":"ok"'`

if [ "$LOGIN" = "" ]; then
   exit 1
fi

PERMISSION=`curl -f --silent -X POST -F "key_id=$USER" -F "project=$REPOSITORY" -F "action=$ACTION" "http://$MILLICORE_HOST/box/api/gls/api/v3/internal/allowed" 2>&1`
if [ "$PERMISSION" = "true" ]; then
   exit 0
fi
exit 1

