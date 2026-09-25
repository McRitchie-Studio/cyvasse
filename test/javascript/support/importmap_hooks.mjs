// Resolve the bare `cyvasse/<module>` specifiers the way the browser does.
//
// In the browser, config/importmap.rb pins app/javascript/cyvasse under
// "cyvasse", so the engine modules import each other as "cyvasse/board". Node
// has no import map, so this hook maps the same prefix onto the same files.
// Nothing else is rewritten.
const ROOT = new URL("../../../app/javascript/cyvasse/", import.meta.url);

export async function resolve(specifier, context, nextResolve) {
  const match = /^cyvasse\/([\w/]+)$/.exec(specifier);
  if (match) {
    return nextResolve(new URL(`${match[1]}.js`, ROOT).href, context);
  }
  return nextResolve(specifier, context);
}
