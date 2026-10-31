# pymongo-api: шардирование, репликация и кеширование

Проектная работа 4 спринта: онлайн-магазин «Мобильный мир».

## Структура репозитория

| Путь | Что внутри |
|---|---|
| `architecture.drawio` | схемы архитектуры; итоговая — страница «5. CDN (итоговая схема)» |
| `mongo-sharding/` | задание 2: MongoDB с двумя шардами |
| `mongo-sharding-repl/` | задание 3: два шарда по три реплики |
| `sharding-repl-cache/` | задание 4: шардирование, репликация и кеширование в Redis — **финальная реализация** |

## Как запустить финальную реализацию

Требования: Docker с Docker Compose, минимум 2 CPU и 4 ГБ ОЗУ.

```shell
cd sharding-repl-cache
docker compose up -d
./scripts/mongo-init.sh
```

`docker compose up -d` поднимает 10 сервисов:

| Сервис | Роль |
|---|---|
| `configSrv` | конфиг-сервер (replica set `config_server`) |
| `shard1-1`, `shard1-2`, `shard1-3` | шард 1 (replica set `shard1`) |
| `shard2-1`, `shard2-2`, `shard2-3` | шард 2 (replica set `shard2`) |
| `mongos_router` | роутер запросов, к нему подключено приложение |
| `redis` | кеш приложения |
| `pymongo_api` | приложение `kazhem/pymongo_api:1.0.0`, порт 8080 |

`./scripts/mongo-init.sh` инициализирует replica set конфиг-сервера и шардов, добавляет шарды в кластер, включает шардирование коллекции `somedb.helloDoc` по хешу поля `name`, записывает 1000 документов и выводит количество документов и реплик в каждом шарде. Подробное описание шагов — в [sharding-repl-cache/README.md](sharding-repl-cache/README.md).

## Как проверить

Статус сервисов:

```shell
docker compose ps
```

Информация о MongoDB и кеше — http://localhost:8080. В ответе:

- `"mongo_topology_type": "Sharded"`;
- `"collections": {"helloDoc": {"documents_count": 1000}}`;
- `"shards"` — два шарда, у каждого по три реплики;
- `"cache_enabled": true`.

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

Кеширование: первый вызов `/helloDoc/users` выполняется около 1 секунды, повторные — быстрее 100 мс:

```shell
for i in 1 2 3; do curl -s -o /dev/null -w "%{time_total}s\n" http://localhost:8080/helloDoc/users; done
```

Документация API — http://localhost:8080/docs

## Как остановить

```shell
docker compose down -v
```
