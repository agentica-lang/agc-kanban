# Development

Run `make install` once first. The tests need Node and corepack too, because they build the web assets.

```sh
make test
```

Before a PR:

- A fixture with its own `agentica.toml` is installed by `make install`; run the tests once from a clean checkout.
- A stamp-file rule in the Makefile depends on its inputs and its outputs.
- A web change checks older CSS rules of equal specificity on the elements it touches (the later file wins).

The API is in [api.md](api.md).
