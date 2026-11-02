# sharding-repl-cache

MongoDB с шардированием и репликацией: конфиг-сервер, два шарда по три реплики и роутер `mongos`, к которому подключено приложение `pymongo_api`. Ответы эндпоинта `/<collection_name>/users` кешируются в Redis на 60 секунд.

| Сервис | Роль | Порт |
|---|---|---|
| `configSrv` | конфиг-сервер (replica set `config_server`) | 27019 |
| `shard1-1`, `shard1-2`, `shard1-3` | шард 1 (replica set `shard1`) | 27018 |
| `shard2-1`, `shard2-2`, `shard2-3` | шард 2 (replica set `shard2`) | 27018 |
| `mongos_router` | роутер запросов | 27017 |
| `redis` | кеш приложения | 6379 |
| `pymongo_api` | приложение (`REDIS_URL=redis://redis:6379`) | 8080 |

## Как запустить

Все команды выполняются из директории `sharding-repl-cache`.

```shell
docker compose up -d
```

## Инициализация шардирования и репликации

```shell
./scripts/mongo-init.sh
```

Скрипт выполняет следующие шаги.

1. Инициализирует replica set конфиг-сервера:

```shell
docker compose exec -T configSrv mongosh --port 27019 --quiet <<EOF
rs.initiate({
  _id: "config_server",
  configsvr: true,
  members: [{ _id: 0, host: "configSrv:27019" }]
})
EOF
```

2. Инициализирует replica set из трёх реплик для каждого шарда:

```shell
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard1",
  members: [
    { _id: 0, host: "shard1-1:27018" },
    { _id: 1, host: "shard1-2:27018" },
    { _id: 2, host: "shard1-3:27018" }
  ]
})
EOF

docker compose exec -T shard2-1 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard2",
  members: [
    { _id: 0, host: "shard2-1:27018" },
    { _id: 1, host: "shard2-2:27018" },
    { _id: 2, host: "shard2-3:27018" }
  ]
})
EOF
```

3. Добавляет шарды в кластер через роутер, включает шардирование коллекции `somedb.helloDoc` по хешу поля `name` и заполняет её 1000 документами:

```shell
docker compose exec -T mongos_router mongosh --port 27017 --quiet <<EOF
sh.addShard("shard1/shard1-1:27018,shard1-2:27018,shard1-3:27018")
sh.addShard("shard2/shard2-1:27018,shard2-2:27018,shard2-3:27018")
sh.enableSharding("somedb")
sh.shardCollection("somedb.helloDoc", { name: "hashed" })
use somedb
for (var i = 0; i < 1000; i++) db.helloDoc.insertOne({ age: i, name: "ly" + i })
EOF
```

## Как проверить

Общее количество документов и список шардов с репликами — http://localhost:8080

Количество документов и реплик в каждом шарде:

```shell
docker compose exec -T shard1-1 mongosh --quiet \
  "mongodb://shard1-1:27018,shard1-2:27018,shard1-3:27018/somedb?replicaSet=shard1" <<EOF
print("documents: " + db.helloDoc.countDocuments() + ", replicas: " + rs.status().members.length)
EOF

docker compose exec -T shard2-1 mongosh --quiet \
  "mongodb://shard2-1:27018,shard2-2:27018,shard2-3:27018/somedb?replicaSet=shard2" <<EOF
print("documents: " + db.helloDoc.countDocuments() + ", replicas: " + rs.status().members.length)
EOF
```

Роли реплик шарда (PRIMARY / SECONDARY):

```shell
docker compose exec -T shard1-1 mongosh --port 27018 --quiet --eval 'rs.status().members.forEach(m => print(m.name, m.stateStr))'
```

Кеширование: в ответе http://localhost:8080 поле `"cache_enabled": true`. Первый вызов `/helloDoc/users` выполняется около 1 секунды, повторные — быстрее 100 мс:

```shell
for i in 1 2 3; do curl -s -o /dev/null -w "%{time_total}s\n" http://localhost:8080/helloDoc/users; done
```

Документация API — http://localhost:8080/docs
