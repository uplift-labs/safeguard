'use strict'

const childProcess = require('node:child_process')
const fs = require('node:fs')
const path = require('node:path')
const bridge = require('./bridge.js')

const SERVICE = 'safeguard-opencode'
const DEFAULT_CORE_TIMEOUT_MS = 10_000
const DEFAULT_ASK_TIMEOUT_MS = 60_000

const warnings = new Map()

function numberEnv(name, fallback) {
  const parsed = Number(process.env[name])
  if (!Number.isFinite(parsed) || parsed <= 0) return fallback
  return parsed
}

function disabled() {
  return process.env.CI === 'true' || process.env.SAFEGUARD_DISABLED === '1'
}

function findRoot() {
  if (process.env.SAFEGUARD_OPENCODE_ROOT) return process.env.SAFEGUARD_OPENCODE_ROOT

  const candidates = [
    path.resolve(__dirname, '../..'),
    path.resolve(__dirname, '../../..'),
    process.cwd(),
  ]

  for (const candidate of candidates) {
    if (fs.existsSync(path.join(candidate, 'core', 'cmd', 'safeguard-run.sh'))) return candidate
  }
  return path.resolve(__dirname, '../..')
}

function coreScript(root) {
  return path.join(root, 'core', 'cmd', 'safeguard-run.sh')
}

function toolName(tool) {
  const names = {
    bash: 'Bash',
    read: 'Read',
    edit: 'Edit',
    write: 'Write',
    apply_patch: 'Write',
  }
  return names[tool] || tool
}

function groupFor(tool) {
  if (tool === 'bash') return 'pre-bash'
  if (tool === 'read') return 'pre-read'
  if (tool === 'edit' || tool === 'write' || tool === 'apply_patch') return 'pre-edit'
}

function callKey(input) {
  return `${input.sessionID || 'default'}:${input.callID || 'unknown'}`
}

function addWarning(input, warning) {
  const key = callKey(input)
  const list = warnings.get(key) || []
  list.push(warning)
  warnings.set(key, list)
  bridge.showWarning({ sessionID: input.sessionID, callID: input.callID, message: warning })
}

function takeWarnings(input) {
  const key = callKey(input)
  const list = warnings.get(key) || []
  warnings.delete(key)
  return list
}

function parseDecision(raw) {
  const text = String(raw || '')
  for (const tag of ['BLOCK', 'ASK', 'WARN']) {
    const prefix = `${tag}:`
    if (text.startsWith(prefix)) return { tag, message: text.slice(prefix.length) }
  }
  return { tag: 'PASS', message: '' }
}

function firstString(...values) {
  for (const value of values) {
    if (typeof value === 'string' && value.length > 0) return value
  }
  return ''
}

function buildPayload(input, args, ctx) {
  const cwd = firstString(args.workdir, args.cwd, ctx.directory)
  const payload = {
    tool_name: toolName(input.tool),
    session_id: input.sessionID,
    call_id: input.callID,
    cwd,
    tool_input: args,
  }

  if (input.tool === 'bash') {
    payload.command = firstString(args.command)
  }

  if (input.tool === 'read') {
    payload.file_path = firstString(args.filePath, args.file_path, args.path)
  }

  if (input.tool === 'edit') {
    payload.file_path = firstString(args.filePath, args.file_path, args.path)
    payload.new_string = firstString(args.newString, args.new_string)
  }

  if (input.tool === 'write') {
    payload.file_path = firstString(args.filePath, args.file_path, args.path)
    payload.content = firstString(args.content)
  }

  return payload
}

function flushPatchEntry(entries, current) {
  if (!current || !current.filePath) return
  entries.push({ filePath: current.filePath, content: current.added.join('\n') })
}

function parseApplyPatch(patchText) {
  const entries = []
  let current
  const lines = String(patchText || '').replace(/\r\n/g, '\n').replace(/\r/g, '\n').split('\n')

  for (const line of lines) {
    let match = line.match(/^\*\*\* (Add|Update|Delete) File: (.+)$/)
    if (match) {
      flushPatchEntry(entries, current)
      current = { filePath: match[2], added: [] }
      continue
    }

    match = line.match(/^\*\*\* Move to: (.+)$/)
    if (match && current) {
      current.filePath = match[1]
      continue
    }

    if (line === '*** End Patch') {
      flushPatchEntry(entries, current)
      current = undefined
      continue
    }

    if (current && line.startsWith('+')) {
      current.added.push(line.slice(1))
    }
  }

  flushPatchEntry(entries, current)
  return entries
}

function applyPatchPayloads(input, args, ctx) {
  const patchText = firstString(args.patchText, args.patch, args.command)
  return parseApplyPatch(patchText).map((entry) => ({
    tool_name: 'Write',
    session_id: input.sessionID,
    call_id: input.callID,
    cwd: firstString(args.workdir, args.cwd, ctx.directory),
    file_path: entry.filePath,
    content: entry.content,
    tool_input: args,
  }))
}

function runCore(group, payload, ctx) {
  const root = ctx.root || findRoot()
  const script = coreScript(root)
  const bash = process.env.SAFEGUARD_OPENCODE_BASH || 'bash'
  const timeout = numberEnv('SAFEGUARD_OPENCODE_CORE_TIMEOUT_MS', DEFAULT_CORE_TIMEOUT_MS)
  const body = JSON.stringify(payload)

  return new Promise((resolve) => {
    let stdout = ''
    let stderr = ''
    let settled = false
    const child = childProcess.spawn(bash, [script, group], {
      cwd: payload.cwd || ctx.directory || process.cwd(),
      env: process.env,
      stdio: ['pipe', 'pipe', 'pipe'],
    })

    const finish = (result) => {
      if (settled) return
      settled = true
      clearTimeout(timer)
      resolve(result)
    }

    const timer = setTimeout(() => {
      child.kill()
      finish({ ok: false, stdout, stderr, error: `core timeout after ${timeout}ms` })
    }, timeout)

    child.stdout.on('data', (chunk) => {
      stdout += chunk.toString()
    })
    child.stderr.on('data', (chunk) => {
      stderr += chunk.toString()
    })
    child.on('error', (error) => finish({ ok: false, stdout, stderr, error: error.message }))
    child.on('close', () => finish({ ok: true, stdout, stderr }))
    child.stdin.end(body)
  })
}

function preview(input, args) {
  if (input.tool === 'bash') return firstString(args.command).slice(0, 500)
  if (input.tool === 'read' || input.tool === 'edit' || input.tool === 'write') {
    return firstString(args.filePath, args.file_path, args.path).slice(0, 500)
  }
  if (input.tool === 'apply_patch') {
    return parseApplyPatch(firstString(args.patchText, args.patch, args.command))
      .map((entry) => entry.filePath)
      .join(', ')
      .slice(0, 500)
  }
  return input.tool
}

async function log(client, level, message, extra) {
  try {
    await client?.app?.log?.({ body: { service: SERVICE, level, message, extra } })
  } catch {}
}

async function handleDecision(decision, input, args, ctx) {
  if (decision.tag === 'PASS') return

  if (decision.tag === 'WARN') {
    addWarning(input, decision.message)
    return
  }

  if (decision.tag === 'BLOCK') {
    void log(ctx.client, 'warn', 'blocked tool call', { tool: input.tool, reason: decision.message })
    throw new Error(decision.message)
  }

  const timeout = numberEnv('SAFEGUARD_OPENCODE_ASK_TIMEOUT_MS', DEFAULT_ASK_TIMEOUT_MS)
  const answer = await bridge.requestApproval({
    reason: decision.message,
    tool: input.tool,
    sessionID: input.sessionID,
    callID: input.callID,
    preview: preview(input, args),
  }, timeout)

  if (answer.status === 'allow') return

  const reason = `${decision.message} (${answer.reason || answer.status})`
  void log(ctx.client, 'warn', 'approval denied', { tool: input.tool, reason })
  throw new Error(reason)
}

async function runPreHook(input, args, ctx) {
  if (disabled()) return
  const group = groupFor(input.tool)
  if (!group) return

  const payloads = input.tool === 'apply_patch' ? applyPatchPayloads(input, args, ctx) : [buildPayload(input, args, ctx)]
  for (const payload of payloads) {
    const result = await runCore(group, payload, ctx)
    if (!result.ok) {
      if (group === 'pre-bash' || group === 'pre-edit') {
        throw new Error(`[safeguard:opencode] Could not verify ${input.tool}: ${result.error || 'core failed'}`)
      }
      continue
    }
    await handleDecision(parseDecision(result.stdout), input, args, ctx)
  }
}

function appendWarnings(output, list) {
  if (!list.length || !output || typeof output !== 'object') return
  output.metadata = { ...(output.metadata || {}), safeguardWarnings: list }
  if (typeof output.output === 'string') {
    output.output += `\n\n${list.join('\n')}`
  }
}

async function runPostHook(input, output, ctx) {
  const list = takeWarnings(input)
  if (!disabled() && input.tool === 'bash') {
    const payload = buildPayload(input, input.args || {}, ctx)
    const result = await runCore('post-bash', payload, ctx)
    const decision = result.ok ? parseDecision(result.stdout) : { tag: 'PASS', message: '' }
    if (decision.tag === 'BLOCK') list.push(decision.message)
  }
  appendWarnings(output, list)
}

const plugin = {
  id: 'uplift.safeguard.server',
  server: async (ctx) => {
    const runtime = { ...ctx, root: findRoot() }
    void log(ctx.client, 'info', 'loaded', { directory: ctx.directory, root: runtime.root })

    return {
      'tool.execute.before': async (input, output) => {
        await runPreHook(input, output.args || {}, runtime)
      },
      'tool.execute.after': async (input, output) => {
        await runPostHook(input, output, runtime)
      },
      'tool.definition': async (input, output) => {
        if (!['bash', 'read', 'edit', 'write', 'apply_patch'].includes(input.toolID)) return
        output.description += '\nSafeguard is active: dangerous commands, secret writes, and unsafe suppressions may be blocked before execution.'
      },
    }
  },
  _test: {
    buildPayload,
    parseApplyPatch,
    parseDecision,
    runPreHook,
    runPostHook,
    warnings,
  },
}

module.exports = plugin
