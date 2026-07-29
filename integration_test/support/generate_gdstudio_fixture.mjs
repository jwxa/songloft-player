import { readFileSync, writeFileSync } from 'node:fs'
import { join, resolve } from 'node:path'

const root = resolve(process.argv[2] || '')
const output = resolve(process.argv[3] || '')
const serverSource = readFileSync(new URL('./gdstudio_acceptance_server.mjs', import.meta.url), 'utf8')
const bootstrapMatch = serverSource.match(/function createBootstrap\(\) \{\s*return `([\s\S]*?)`\s*\}/)
if (!bootstrapMatch) throw new Error('acceptance bootstrap not found')

const indexPath = join(root, 'static', 'index.html')
let html = readFileSync(indexPath, 'utf8')
const stylesheetMatch = html.match(/<link[^>]+href="([^"]+\.css)"[^>]*>/)
const scriptMatch = html.match(/<script src="([^"]+\.js)"><\/script>/)
if (!stylesheetMatch || !scriptMatch) throw new Error('plugin assets not found')

const stylesheet = readFileSync(join(root, stylesheetMatch[1]), 'utf8')
const script = readFileSync(join(root, scriptMatch[1]), 'utf8')
html = html
  .replace(stylesheetMatch[0], `<style>${stylesheet}</style>`)
  .replace(scriptMatch[0], `<script>${bootstrapMatch[1]}</script><script>${script}</script>`)

const encoded = Buffer.from(html).toString('base64')
writeFileSync(output, `import 'dart:convert';\n\nconst _fixtureBase64 = '${encoded}';\n\nString get gdstudioFixtureHTML => utf8.decode(base64Decode(_fixtureBase64));\n`)
