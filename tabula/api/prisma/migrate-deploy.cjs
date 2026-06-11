/**
 * Copyright (c) 2026 VitruvianSoftware
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

/**
 * Hermetic `prisma migrate deploy`: the one Prisma 6 command that executes a
 * native schema-engine binary. The engine is vendored via http_file (pinned
 * to the @prisma/engines-version hash) and its runfiles path arrives in
 * PRISMA_SCHEMA_ENGINE_BINARY, resolved here to an absolute path because the
 * Prisma CLI resolves that env var against its own cwd.
 */
const { spawnSync } = require('child_process');
const path = require('path');

const schemaArgIdx = process.argv.indexOf('--schema');
const schema =
  schemaArgIdx > 0 ? process.argv[schemaArgIdx + 1] : 'tabula/api/prisma/schema.prisma';

const env = { ...process.env, PRISMA_HIDE_UPDATE_MESSAGE: '1' };
if (env.PRISMA_SCHEMA_ENGINE_BINARY) {
  env.PRISMA_SCHEMA_ENGINE_BINARY = path.resolve(env.PRISMA_SCHEMA_ENGINE_BINARY);
}
// The query engine is only existence-checked by `migrate deploy` (never
// executed); a placeholder defeats the CLI's downloader. prisma/prisma#28083.
if (env.PRISMA_QUERY_ENGINE_LIBRARY) {
  env.PRISMA_QUERY_ENGINE_LIBRARY = path.resolve(env.PRISMA_QUERY_ENGINE_LIBRARY);
}

const prismaCli = require.resolve('prisma/build/index.js');
const res = spawnSync(process.execPath, [prismaCli, 'migrate', 'deploy', `--schema=${schema}`], {
  stdio: 'inherit',
  env,
});
process.exit(res.status === null ? 1 : res.status);
