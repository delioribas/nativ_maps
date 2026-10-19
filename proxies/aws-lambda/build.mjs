// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.
//
// Bundles the Lambda adapter, the shared core (`../node/proxy.mjs`) and their
// dependencies into `dist/index.mjs`: one self-contained file, which is what
// gets deployed and what `local.mjs` runs.
//
//   npm install && npm run build

import { readFile, rm, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';

const here = fileURLToPath(new URL('.', import.meta.url));
const read = async (path) =>
  JSON.parse(await readFile(new URL(path, import.meta.url), 'utf8'));

// 1 · The core's dependencies are installed here, at the very versions the
//     core declares. If someone bumps them there and not here, the build
//     stops instead of shipping a different signer than the node proxy's.
const core = await read('../node/package.json');
const own = await read('./package.json');
const drift = Object.entries(core.dependencies).filter(
  ([name, version]) => own.devDependencies?.[name] !== version,
);
if (drift.length > 0) {
  for (const [name, version] of drift) {
    console.error(
      `${name}: the core wants ${version}, package.json has ` +
        `${own.devDependencies?.[name] ?? 'nothing'}.`,
    );
  }
  console.error('Copy the versions from ../node/package.json and npm install.');
  process.exit(1);
}

// 2 · Bare imports inside ../node/proxy.mjs resolve from THIS folder's
//     node_modules, not from ../node/node_modules: the bundle never depends
//     on whether the node proxy happens to be installed.
const coreFile = fileURLToPath(new URL('../node/proxy.mjs', import.meta.url));
const fromHere = {
  name: 'resolve-from-here',
  setup(b) {
    b.onResolve({ filter: /^[^./]/ }, (args) =>
      args.importer === coreFile && args.pluginData !== 'here'
        ? b.resolve(args.path, {
            kind: args.kind,
            resolveDir: here,
            pluginData: 'here',
          })
        : undefined,
    );
  },
};

await rm(new URL('./dist', import.meta.url), { recursive: true, force: true });
const result = await build({
  entryPoints: [fileURLToPath(new URL('./src/index.mjs', import.meta.url))],
  outfile: fileURLToPath(new URL('./dist/index.mjs', import.meta.url)),
  bundle: true,
  platform: 'node',
  target: 'node22',
  format: 'esm',
  // The ESM builds of the AWS SDK, so nothing needs `require` at runtime…
  mainFields: ['module', 'main'],
  // …and, for any CommonJS left in the tree, a real one.
  banner: {
    js: "import { createRequire as __createRequire } from 'node:module';\n" +
      'const require = __createRequire(import.meta.url);',
  },
  // Readable lines and names: a stack trace in CloudWatch points somewhere.
  // Full minification saves bytes, not cold-start time (both import in ~30 ms).
  minifySyntax: true,
  keepNames: true,
  legalComments: 'eof',
  plugins: [fromHere],
  metafile: true,
  logLevel: 'warning',
});

// `sam build` expects a package.json next to the code; with no dependencies
// it just copies the bundle.
await writeFile(
  new URL('./dist/package.json', import.meta.url),
  `${JSON.stringify(
    {
      name: own.name,
      version: own.version,
      private: true,
      type: 'module',
      main: 'index.mjs',
    },
    null,
    2,
  )}\n`,
);

const bytes = Object.values(result.metafile.outputs)[0].bytes;
const inputs = Object.keys(result.metafile.inputs);
console.log(
  `dist/index.mjs: ${(bytes / 1024).toFixed(0)} KiB, ${inputs.length} modules, ` +
    `core from ${inputs.find((p) => p.endsWith('node/proxy.mjs'))}`,
);
