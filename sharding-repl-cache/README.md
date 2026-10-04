# Шардирование, репликация и Redis

Итоговый проверочный стенд состоит из двух шардов по три узла, config replica set из трёх узлов, `mongos`, Redis и API. API-контейнер собирается из исходного приложения и получает требуемый тег `kazhem/pymongo_api:1.0.0`.

## Запуск

```sh
export PATH="$HOME/.docker/bin:$PATH"
docker compose up -d
./scripts/mongo-init.sh
```

Скрипт инициализирует replica set-ы и шардирование, затем заполняет `somedb.helloDoc` 1000 документами. Он безопасен для повторного запуска.

## Проверка

- Откройте `http://localhost:8080/`. JSON должен показывать MongoDB topology `Sharded`, два шарда, по три узла в каждом шарде, 1000 документов, число документов на каждом шарде и включённый кеш.
- Откройте `http://localhost:8080/docs` для документации API.
- Выполните два запроса и сравните время: `curl -s -o /dev/null -w '%{time_total}\n' http://localhost:8080/helloDoc/users`. Второй запрос должен занимать менее 0,1 секунды.
- Проверьте контейнеры: `docker compose ps`.

Данные MongoDB и Redis сохраняются в именованных Docker volumes. Чтобы начать с чистого состояния, остановите проект и удалите его volumes командой `docker compose down -v`.
