// Loaded with `node --import` by bin/test-js. Installs studio-engine's shared
// importmap hook (lib/studio/node_tooling/node_test), so "cyvasse/<module>"
// resolves to app/javascript/cyvasse/<module>.js the way config/importmap.rb
// pins it in the browser. bin/test-js links node_modules/.studio-engine first.
// test/lib/node_tooling_test.rb holds the prefix to the importmap.
import { registerImportmapHooks } from "../../../node_modules/.studio-engine/node_test/register.mjs";

registerImportmapHooks({
  root: new URL("../../../", import.meta.url),
  prefixes: { cyvasse: "app/javascript/cyvasse/" },
});
