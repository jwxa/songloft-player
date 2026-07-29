import { createReadStream, readFileSync, statSync } from 'node:fs'
import { createServer } from 'node:http'
import { extname, join, normalize, resolve, sep } from 'node:path'

const root = resolve(process.argv[2] || '')
const port = Number(process.argv[3] || 58092)
const state = {
  audioRequests: 0,
  rangeRequests: 0,
  previewDeletes: 0,
  settings: { sources: { netease: true, kuwo: true, tencent: true } },
  downloadSettings: { path_template: 'downloads/{artist}-{album}/{title}', max_concurrency: 2 },
}
const indexPath = join(root, 'static', 'index.html')
const bootstrap = `<script>${createBootstrap()}</script>`
const indexHTML = readFileSync(indexPath, 'utf8').replace('<script src=', `${bootstrap}<script src=`)
const audio = createWave()

const server = createServer((request, response) => {
  const url = new URL(request.url || '/', `http://${request.headers.host}`)
  console.log(`${request.method} ${url.pathname}`)
  if (url.pathname === '/healthz') return json(response, 200, { ok: true })
  if (url.pathname === '/__state') return json(response, 200, state)
  if (url.pathname === '/__settings' && request.method === 'GET') return json(response, 200, state.settings)
  if (url.pathname === '/__settings' && request.method === 'PUT') {
    return readJSONBody(request).then(body => {
      state.settings = body
      json(response, 200, body)
    })
  }
  if (url.pathname === '/__download-settings' && request.method === 'GET') return json(response, 200, state.downloadSettings)
  if (url.pathname === '/__download-settings' && request.method === 'PUT') {
    return readJSONBody(request).then(body => {
      state.downloadSettings = body
      json(response, 200, body)
    })
  }
  if (url.pathname === '/__range-check') return serveAudio(request, response, false)
  if (url.pathname === '/audio.wav' && request.method === 'DELETE') {
    state.previewDeletes++
    response.writeHead(204).end()
    return
  }
  if (url.pathname === '/audio.wav') return serveAudio(request, response, true)
  if (url.pathname === '/api/v1/plugin-preview-sessions/gdstudio' && request.method === 'POST') {
    return readBody(request).then(() => json(response, 200, {
      stream_url: `http://${request.headers.host}/audio.wav`,
      audio: { format: 'wav', bitrate: 1411 },
    }))
  }
  if (url.pathname === '/api/v1/jsplugin/gdstudio/' || url.pathname === '/') {
    response.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' }).end(indexHTML)
    return
  }
  serveStatic(url.pathname, response)
})

server.listen(port, '0.0.0.0', () => {
  console.log(`GDStudio acceptance server listening on ${port}`)
})

function serveStatic(pathname, response) {
  const relativePath = normalize(pathname
    .replace(/^\/api\/v1\/jsplugin\/gdstudio\//, '')
    .replace(/^\/+/, ''))
  const filePath = resolve(root, relativePath)
  if (!filePath.startsWith(`${root}${sep}`) && filePath !== root) return json(response, 403, { error: 'forbidden' })
  try {
    if (!statSync(filePath).isFile()) throw new Error('not a file')
    response.writeHead(200, { 'Content-Type': contentType(filePath) })
    createReadStream(filePath).pipe(response)
  } catch {
    json(response, 404, { error: 'not found' })
  }
}

function serveAudio(request, response, countPreview) {
  if (countPreview) state.audioRequests++
  const range = request.headers.range
  if (!range) {
    response.writeHead(200, {
      'Accept-Ranges': 'bytes',
      'Content-Type': 'audio/wav',
      'Content-Length': audio.length,
    }).end(audio)
    return
  }
  const match = /^bytes=(\d+)-(\d*)$/.exec(range)
  if (!match) return response.writeHead(416).end()
  const start = Number(match[1])
  const end = Math.min(match[2] ? Number(match[2]) : audio.length - 1, audio.length - 1)
  if (start > end || start >= audio.length) return response.writeHead(416).end()
  state.rangeRequests++
  response.writeHead(206, {
    'Accept-Ranges': 'bytes',
    'Content-Type': 'audio/wav',
    'Content-Length': end - start + 1,
    'Content-Range': `bytes ${start}-${end}/${audio.length}`,
  }).end(audio.subarray(start, end + 1))
}

function json(response, status, body) {
  response.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' }).end(JSON.stringify(body))
}

function readBody(request) {
  return new Promise(resolvePromise => {
    request.resume()
    request.on('end', resolvePromise)
  })
}

async function readJSONBody(request) {
  const chunks = []
  for await (const chunk of request) chunks.push(chunk)
  return JSON.parse(Buffer.concat(chunks).toString('utf8'))
}

function contentType(filePath) {
  return {
    '.css': 'text/css; charset=utf-8',
    '.html': 'text/html; charset=utf-8',
    '.js': 'text/javascript; charset=utf-8',
    '.svg': 'image/svg+xml',
    '.txt': 'text/plain; charset=utf-8',
  }[extname(filePath)] || 'application/octet-stream'
}

function createWave() {
  const sampleRate = 8000
  const samples = sampleRate * 2
  const dataLength = samples * 2
  const buffer = Buffer.alloc(44 + dataLength)
  buffer.write('RIFF', 0)
  buffer.writeUInt32LE(36 + dataLength, 4)
  buffer.write('WAVEfmt ', 8)
  buffer.writeUInt32LE(16, 16)
  buffer.writeUInt16LE(1, 20)
  buffer.writeUInt16LE(1, 22)
  buffer.writeUInt32LE(sampleRate, 24)
  buffer.writeUInt32LE(sampleRate * 2, 28)
  buffer.writeUInt16LE(2, 32)
  buffer.writeUInt16LE(16, 34)
  buffer.write('data', 36)
  buffer.writeUInt32LE(dataLength, 40)
  for (let index = 0; index < samples; index++) {
    buffer.writeInt16LE(Math.round(Math.sin(index * 2 * Math.PI * 440 / sampleRate) * 2000), 44 + index * 2)
  }
  return buffer
}

function createBootstrap() {
  return `
    const tracks = [
      { id: 'track-1', source: 'netease', dedupe_key: 'gdstudio:netease:track-1', title: 'So Cynical (Badum)', artist: 'Acceptance Artist', album: 'Acceptance Album', duration: 185, cover_id: '', source_data: { root_source: 'netease', identifier: 'track-1', url_id: 'url-1' } },
      { id: 'track-2', source: 'netease', dedupe_key: 'gdstudio:netease:track-2', title: 'Second Track', artist: 'Acceptance Artist', album: 'Acceptance Album', duration: 201, cover_id: '', source_data: { root_source: 'netease', identifier: 'track-2', url_id: 'url-2' } }
    ];
    window.__acceptance = {
      previewRequests: 0,
      previewDeletes: 0,
      audioRequests: 0,
      openPlayerCount: 0,
      queue: [],
      downloadPolls: {},
      settings: { sources: { netease: true, kuwo: true, tencent: true } },
      downloadSettings: { path_template: 'downloads/{artist}-{album}/{title}', max_concurrency: 2 }
    };
    const originalFetch = window.fetch.bind(window);
    const audioURL = URL.createObjectURL(new Blob([new Uint8Array(4096)], { type: 'audio/wav' }));
    window.fetch = async (input, options = {}) => {
      const url = String(input);
      const method = options.method || 'GET';
      if (url.includes('/plugin-preview-sessions/gdstudio') && method === 'POST') {
        window.__acceptance.previewRequests++;
        window.__acceptance.audioRequests++;
        return new Response(JSON.stringify({ stream_url: audioURL, audio: { format: 'wav', bitrate: 1411 } }), { status: 200 });
      }
      if (url === audioURL && method === 'DELETE') {
        window.__acceptance.previewDeletes++;
        return new Response(null, { status: 204 });
      }
      if (url.includes('/__range-check')) return new Response(new Uint8Array(64), { status: 206 });
      return originalFetch(input, options);
    };
    window.SongloftPlugin = {
      getAuthToken: () => 'acceptance-token',
      apiGet: async path => {
        if (path === '/api/settings') return structuredClone(window.__acceptance.settings);
        if (path === '/api/download-settings') return structuredClone(window.__acceptance.downloadSettings);
        if (path === '/api/info') return { plugin_version: 'acceptance', musicdl_version: '2.13.4', protocol_version: 'v1' };
        if (path.startsWith('/api/download-status/')) {
          const id = path.split('/').pop();
          const poll = (window.__acceptance.downloadPolls[id] || 0) + 1;
          window.__acceptance.downloadPolls[id] = poll;
          if (poll === 1) return { id, status: 'running', phase: 'downloading', downloaded_bytes: 50, total_bytes: 100 };
          return { id, status: 'completed', phase: 'completed', downloaded_bytes: 100, total_bytes: 100, path: '/music/test.wav' };
        }
        throw new Error('unexpected GET ' + path);
      },
      apiPut: async (path, body) => {
        if (path === '/api/settings') window.__acceptance.settings = structuredClone(body);
        if (path === '/api/download-settings') window.__acceptance.downloadSettings = structuredClone(body);
        return structuredClone(body);
      },
      apiPost: async (path, body) => {
        if (path === '/api/search') return { keyword: body.keyword, page_size: 10, groups: [{ source: 'netease', label: '网易云', page: 1, has_more: false, items: tracks }] };
        if (path === '/api/library') return { song: { id: 101, type: 'remote', title: body.track.title, artist: body.track.artist, album: body.track.album }, metadata: { status: 'complete', missing: [], errors: [] } };
        if (path === '/api/library/batch') return { items: body.tracks.map((track, index) => ({ dedupe_key: track.dedupe_key, status: 'added', song: { id: 101 + index, type: 'remote', title: track.title, artist: track.artist, album: track.album }, metadata: { status: 'complete', missing: [], errors: [] } })) };
        if (path === '/api/download') return { status: 'queued', song: { id: 101, type: 'remote' }, metadata: { status: 'complete' }, task: { id: 'download-1', status: 'queued', phase: 'queued', downloaded_bytes: 0, total_bytes: 100 } };
        throw new Error('unexpected POST ' + path);
      },
      host: { isAvailable: () => true, openPlayer: async () => { window.__acceptance.openPlayerCount++; } },
      player: { setQueue: async ids => { window.__acceptance.queue = ids; } }
    };
  `
}
