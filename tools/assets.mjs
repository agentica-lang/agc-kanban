// `make assets` (`pnpm build`): builds the Vue app and its stylesheet with Vite, names each file by the first 16 hex
// digits of the SHA-256 of its bytes (application-DIGEST.css and .js), writes them to public/assets/, removes the
// files of earlier builds, and writes src/kanban_web/asset_names.agc, the one file that holds the two names. The same
// sources give the same bytes. The build runs in memory so that Vite's own file names never reach the folder.

import { createHash } from "node:crypto";
import { mkdirSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import vue from "@vitejs/plugin-vue";
import { build } from "vite";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const out = join(root, "public/assets");
const names = join(root, "src/kanban_web/asset_names.agc");

const result = await build({
  root,
  configFile: false,
  logLevel: "warn",
  plugins: [vue()],
  define: { __VUE_OPTIONS_API__: false, __VUE_PROD_DEVTOOLS__: false, __VUE_PROD_HYDRATION_MISMATCH_DETAILS__: false },
  build: {
    write: false,
    cssCodeSplit: false,
    target: "es2020",
    rollupOptions: {
      input: join(root, "app/javascript/application.js"),
      output: { format: "iife" },
    },
  },
});

const files = (Array.isArray(result) ? result : [result]).flatMap((one) => one.output);
const script = files.find((file) => file.type === "chunk");
const sheet = files.find((file) => file.type === "asset" && file.fileName.endsWith(".css"));
const built = { css: Buffer.from(sheet.source), js: Buffer.from(script.code) };

mkdirSync(out, { recursive: true });

for (const old of readdirSync(out)) {
  if (/^application-[0-9a-f]{16}\.(css|js)$/.test(old)) {
    rmSync(join(out, old));
  }
}

const paths = {};
for (const [kind, bytes] of Object.entries(built)) {
  const digest = createHash("sha256").update(bytes).digest("hex").slice(0, 16);
  const file = `application-${digest}.${kind}`;
  writeFileSync(join(out, file), bytes);
  paths[kind] = `/assets/${file}`;
}

writeFileSync(
  names,
  `## The names of the built stylesheet and script, written by \`make assets\` (tools/assets.mjs). Do not edit it: build
## again. The name has the first 16 hex digits of the SHA-256 of the file.

STYLESHEET = "${paths.css}"
SCRIPT = "${paths.js}"
`,
);

console.log(`${paths.css} ${built.css.length} bytes`);
console.log(`${paths.js} ${built.js.length} bytes`);
