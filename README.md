# Black Friday: архитектура MongoDB-кластера

В репозитории подготовлены три последовательных варианта Docker Compose:

1. `mongo-sharding` — два шарда MongoDB.
2. `mongo-sharding-repl` — по три реплики в каждом шарде.
3. `sharding-repl-cache` — итоговый стенд с MongoDB, репликацией, шардированием, Redis и API.

Итоговую схему откройте в draw.io из файла [`architecture.drawio`](architecture.drawio). В нём пять страниц: исходная схема и варианты после заданий 1, 3, 5 и 6.

## Запуск стенда для проверки

Требуется Docker Desktop и не менее 2 CPU и 4 ГБ памяти. Перейдите в итоговую директорию:

```sh
cd sharding-repl-cache
export PATH="$HOME/.docker/bin:$PATH"
docker compose up -d
./scripts/mongo-init.sh
docker compose ps
```

Приложение доступно на `http://localhost:8080/`, Swagger — на `http://localhost:8080/docs`. На главной странице API показаны топология MongoDB, шарды, количество документов по коллекциям и по шардам, а также статус кеша.

Для проверки кеша выполните дважды:

```sh
curl -s -o /dev/null -w '%{time_total}\n' http://localhost:8080/helloDoc/users
```

Повторный запрос должен укладываться в 100 мс. Данные сохраняются в Docker volumes. Для полной очистки стенда выполните из `sharding-repl-cache`: `docker compose down -v`.
