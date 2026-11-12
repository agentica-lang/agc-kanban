AGENTICA ?= agentica
JOBS ?= 1

.PHONY: install run cli check fmt-check test assets assets-check
install:
	$(AGENTICA) install
run:
	$(AGENTICA) server.agc
cli:
	mkdir -p dist
	$(AGENTICA) compile cli.agc -o dist/kanban.agcb
check:
	$(AGENTICA) check
fmt-check:
	$(AGENTICA) fmt --check server.agc cli.agc src specs
test:
	$(AGENTICA) test --jobs $(JOBS)
assets:
	@true
assets-check:
	@true
