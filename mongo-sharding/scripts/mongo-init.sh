#!/usr/bin/env bash
set -euo pipefail

DOCKER_BIN="$(command -v docker || true)"
if [[ -z "$DOCKER_BIN" && -x "$HOME/.docker/bin/docker" ]]; then
  DOCKER_BIN="$HOME/.docker/bin/docker"
fi
if [[ -z "$DOCKER_BIN" ]]; then
  echo "Docker CLI is not in PATH and was not found in ~/.docker/bin." >&2
  exit 1
fi

wait_for() {
  local service="$1"
  until "$DOCKER_BIN" compose exec -T "$service" mongosh --quiet --eval 'db.adminCommand({ping:1}).ok' 2>/dev/null | grep -q 1; do
    echo "Ожидаю MongoDB: $service"
    sleep 2
  done
}

init_replica() {
  local service="$1" config="$2"
  "$DOCKER_BIN" compose exec -T "$service" mongosh --quiet --eval "try { rs.status().ok } catch (e) { rs.initiate($config) }" >/dev/null
}

wait_for_primary() {
  local service="$1"
  until "$DOCKER_BIN" compose exec -T "$service" mongosh --quiet --eval 'try { rs.status().myState === 1 } catch (e) { false }' 2>/dev/null | grep -q true; do
    echo "Ожидаю PRIMARY: $service"
    sleep 2
  done
}

wait_for configSrv1
init_replica configSrv1 '{_id:"configRS",configsvr:true,members:[{_id:0,host:"configSrv1:27017"},{_id:1,host:"configSrv2:27017"},{_id:2,host:"configSrv3:27017"}]}'
wait_for_primary configSrv1
wait_for shard1
init_replica shard1 '{_id:"shard1RS",members:[{_id:0,host:"shard1:27017"}]}'
wait_for_primary shard1
wait_for shard2
init_replica shard2 '{_id:"shard2RS",members:[{_id:0,host:"shard2:27017"}]}'
wait_for_primary shard2
wait_for mongos

"$DOCKER_BIN" compose exec -T mongos mongosh --quiet --file /dev/stdin <<'EOF'
const admin = db.getSiblingDB("admin");
sh.stopBalancer();
let shardIds = [];
try { shardIds = admin.runCommand({listShards: 1}).shards.map(s => s._id); } catch (e) {}
if (!shardIds.includes("shard1RS")) sh.addShard("shard1RS/shard1:27017");
if (!shardIds.includes("shard2RS")) sh.addShard("shard2RS/shard2:27017");
sh.enableSharding("somedb");
const config = db.getSiblingDB("config");
if (!config.collections.findOne({_id: "somedb.helloDoc"})) {
  sh.shardCollection("somedb.helloDoc", {age: 1});
  sh.splitAt("somedb.helloDoc", {age: 500});
}
sh.moveChunk("somedb.helloDoc", {age: 100}, "shard1RS");
sh.moveChunk("somedb.helloDoc", {age: 750}, "shard2RS");
const collection = db.getSiblingDB("somedb").helloDoc;
if (collection.countDocuments({}) === 0) {
  collection.insertMany(Array.from({length: 1000}, (_, age) => ({age, name: `ly${age}`})));
}
sh.startBalancer();
EOF

echo "Готово: sharding настроен, helloDoc содержит 1000 документов."
