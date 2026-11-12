AGENTICA ?= agentica
JOBS ?= 1

.PHONY: install run cli install-cli check fmt-check test smoke smoke-docker up down assets assets-check
install:
	$(AGENTICA) install
run:
	$(AGENTICA) server.agc
cli:
	mkdir -p dist
	$(AGENTICA) compile cli.agc -o dist/kanban.agcb
install-cli: cli
	mkdir -p "$(HOME)/.local/bin"
	ln -sf "$(CURDIR)/bin/kanban" "$(HOME)/.local/bin/kanban"
check:
	$(AGENTICA) check
fmt-check:
	$(AGENTICA) fmt --check server.agc cli.agc src specs test
test:
	$(AGENTICA) test --jobs $(JOBS)
smoke:
	tools/smoke.sh
smoke-docker:
	docker compose down -v
	docker compose up -d --build --wait
	SMOKE_URL=http://172.28.0.10:4580 SMOKE_KEY="$$(sed -n 's/^KANBAN_API_KEY=//p' .env)" tools/smoke.sh
	docker compose restart --timeout 10
	@for i in $$(seq 1 60); do curl -sf http://172.28.0.10:4580/api/health >/dev/null && break; sleep 0.5; done
	@curl -sf -H "apikey: $$(sed -n 's/^KANBAN_API_KEY=//p' .env)" http://172.28.0.10:4580/api/boards/project | grep -Fq '"slug":"project"' && echo "PASS the board survives a container restart"
up:
	docker compose up -d --build --wait
down:
	docker compose down
assets:
	corepack pnpm install --frozen-lockfile
	node tools/assets.mjs
assets-check: assets
	@changed="$$(git status --porcelain -- public/assets src/kanban_web/asset_names.agc)"; \
	if [ -n "$$changed" ]; then echo "make assets changed the built files; commit them:" >&2; echo "$$changed" >&2; exit 1; fi
