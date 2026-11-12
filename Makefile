AGENTICA ?= agentica
JOBS ?= 1

.PHONY: install run cli install-cli check fmt-check test smoke smoke-docker up down assets FORCE
install:
	$(AGENTICA) install
	cd specs/fixtures/ws_client && $(AGENTICA) install
run: assets
	$(AGENTICA) server.agc
cli:
	mkdir -p dist
	$(AGENTICA) compile cli.agc -o dist/kanban.agcb
install-cli: cli
	mkdir -p "$(HOME)/.local/bin"
	ln -sf "$(CURDIR)/bin/kanban" "$(HOME)/.local/bin/kanban"
check: assets
	$(AGENTICA) check
fmt-check:
	$(AGENTICA) fmt --check server.agc cli.agc src specs test
test: assets
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
# The built files (public/assets/ and src/kanban_web/asset_names.agc) are not in git: run, check and test build them.
# The stamp makes the build run again only when its inputs change, when one is deleted (the sorted list of app/ files
# is rewritten only when it changes) or when the built files are gone.
ASSET_INPUTS = $(shell find app -type f) tools/assets.mjs pnpm-lock.yaml pnpm-workspace.yaml package.json
BUILT_JS = $(wildcard public/assets/application-*.js)
BUILT_NAMES = $(wildcard src/kanban_web/asset_names.agc)
assets: node_modules/.assets-stamp
node_modules/.assets-stamp: node_modules/.assets-list $(ASSET_INPUTS) $(if $(BUILT_JS),,FORCE) $(if $(BUILT_NAMES),,FORCE)
	corepack pnpm install --frozen-lockfile
	corepack pnpm build
	touch $@
node_modules/.assets-list: FORCE
	@mkdir -p node_modules
	@find app -type f | sort > $@.new
	@if cmp -s $@.new $@; then rm $@.new; else mv $@.new $@; fi
FORCE:
