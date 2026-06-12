#!/usr/bin/env node
/**
 * GitHub webhook listener — rebuilds and restarts claude-telegram
 * when a push lands on the main branch.
 *
 * Setup:
 *   1. Copy this file to /opt/claude-telegram/auto-update/webhook.js
 *   2. Set GITHUB_WEBHOOK_SECRET in /opt/claude-telegram/auto-update/.env
 *   3. Enable the systemd service: sudo systemctl enable --now claude-telegram-updater
 *   4. In GitHub repo → Settings → Webhooks → add:
 *        Payload URL: http://<server-ip>:9876/webhook
 *        Content type: application/json
 *        Secret: same as GITHUB_WEBHOOK_SECRET
 *        Events: Just the push event
 */

const http = require('http')
const crypto = require('crypto')
const { execSync } = require('child_process')
const fs = require('fs')
const path = require('path')

const ENV_FILE = path.join(__dirname, '.env')
if (fs.existsSync(ENV_FILE)) {
  for (const line of fs.readFileSync(ENV_FILE, 'utf8').split('\n')) {
    const m = line.match(/^(\w+)=(.*)$/)
    if (m && process.env[m[1]] === undefined) process.env[m[1]] = m[2]
  }
}

const SECRET = process.env.GITHUB_WEBHOOK_SECRET
const PORT = Number(process.env.WEBHOOK_PORT ?? 9876)
const REPO_DIR = process.env.REPO_DIR ?? '/opt/claude-telegram'
const SERVICE = process.env.SERVICE_NAME ?? 'claude-telegram'

if (!SECRET) {
  console.error('GITHUB_WEBHOOK_SECRET not set in auto-update/.env')
  process.exit(1)
}

function verify(body, sig) {
  const expected = 'sha256=' + crypto.createHmac('sha256', SECRET).update(body).digest('hex')
  try { return crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(expected)) } catch { return false }
}

function run(cmd) {
  console.log('$', cmd)
  execSync(cmd, { stdio: 'inherit', cwd: REPO_DIR })
}

const server = http.createServer((req, res) => {
  if (req.method !== 'POST' || req.url !== '/webhook') {
    res.writeHead(404).end()
    return
  }

  const chunks = []
  req.on('data', c => chunks.push(c))
  req.on('end', () => {
    const body = Buffer.concat(chunks)
    const sig = req.headers['x-hub-signature-256'] ?? ''

    if (!verify(body, sig)) {
      console.warn('invalid signature')
      res.writeHead(403).end('Forbidden')
      return
    }

    let payload
    try { payload = JSON.parse(body.toString()) } catch {
      res.writeHead(400).end('Bad JSON')
      return
    }

    const branch = (payload.ref ?? '').replace('refs/heads/', '')
    if (branch !== 'main') {
      res.writeHead(200).end('ignored')
      return
    }

    res.writeHead(200).end('rebuilding')
    console.log(`push to main by ${payload.pusher?.name} — rebuilding`)

    setImmediate(() => {
      try {
        run(`git -C ${REPO_DIR} pull origin main`)
        run(`docker build -t claude-telegram-claude-telegram:latest ${REPO_DIR}`)
        run(`systemctl restart ${SERVICE}`)
        console.log('rebuild + restart done')
      } catch (err) {
        console.error('rebuild failed:', err.message)
      }
    })
  })
})

server.listen(PORT, () => console.log(`webhook listening on :${PORT}`))
