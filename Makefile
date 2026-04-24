SHELL := /bin/bash

up:
	docker compose up -d

down:
	docker compose down

restart:
	docker compose restart nginx

logs:
	docker compose logs -f nginx

ps:
	docker compose ps

check:
	./scripts/check-nginx.sh

reload:
	./scripts/reload-nginx.sh

init-network:
	./scripts/init-edge-network.sh

deploy:
	./scripts/deploy-infra.sh
