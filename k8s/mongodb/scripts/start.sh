#!/bin/sh
set -eu
mongod --bind_ip_all --replSet rs0 --auth --keyFile /security/keyfile \
  --tlsMode requireTLS --tlsCertificateKeyFile /security/server_pem \
  --tlsCAFile /security/ca_pem --tlsAllowConnectionsWithoutCertificates \
  --wiredTigerCacheSizeGB 0.25 &
mongo_pid=$!
trap 'kill -TERM "$mongo_pid" 2>/dev/null || true; wait "$mongo_pid" || true' TERM INT
for attempt in $(seq 1 60); do
  kill -0 "$mongo_pid" || exit 1
  if mongosh --host localhost --tls --tlsCAFile /security/ca_pem --quiet \
    --eval 'quit(db.adminCommand({ping:1}).ok === 1 ? 0 : 1)' >/dev/null 2>&1; then break; fi
  sleep 2
done
if ! mongosh --nodb --quiet /scripts/bootstrap.js; then
  kill -TERM "$mongo_pid" 2>/dev/null || true
  wait "$mongo_pid" || true
  exit 1
fi
wait "$mongo_pid"
