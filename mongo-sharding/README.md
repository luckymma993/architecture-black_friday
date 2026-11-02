# mongo-sharding

MongoDB с шардированием: конфиг-сервер, два шарда и роутер `mongos`, к которому подключено приложение `pymongo_api`.

| Сервис | Роль | Порт |
|---|---|---|
| `configSrv` | конфиг-сервер (replica set `config_server`) | 27019 |
| `shard1` | шард 1 (replica set `shard1`) | 27018 |
| `shard2` | шард 2 (replica set `shard2`) | 27018 |
| `mongos_router` | роутер запросов | 27017 |
| `pymongo_api` | приложение | 8080 |

## Как запустить

Все команды выполняются из директории `mongo-sharding`.

```shell
docker compose up -d
```

## Инициализация шардирования

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

2. Инициализирует replica set каждого шарда:

```shell
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
rs.initiate({ _id: "shard1", members: [{ _id: 0, host: "shard1:27018" }] })
EOF

docker compose exec -T shard2 mongosh --port 27018 --quiet <<EOF
rs.initiate({ _id: "shard2", members: [{ _id: 0, host: "shard2:27018" }] })
EOF
```

3. Добавляет шарды в кластер через роутер, включает шардирование коллекции `somedb.helloDoc` по хешу поля `name` и заполняет её 1000 документами:

```shell
docker compose exec -T mongos_router mongosh --port 27017 --quiet <<EOF
sh.addShard("shard1/shard1:27018")
sh.addShard("shard2/shard2:27018")
sh.enableSharding("somedb")
sh.shardCollection("somedb.helloDoc", { name: "hashed" })
use somedb
for (var i = 0; i < 1000; i++) db.helloDoc.insertOne({ age: i, name: "ly" + i })
EOF
```

## Как проверить

Общее количество документов и список шардов — http://localhost:8080

Количество документов в каждом шарде:

```shell
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF

docker compose exec -T shard2 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

Документация API — http://localhost:8080/docs
