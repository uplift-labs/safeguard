'use strict'

const KEY = '__SAFEGUARD_OPENCODE_BRIDGE__'

function state() {
  if (!globalThis[KEY]) {
    globalThis[KEY] = {
      tui: undefined,
      queue: Promise.resolve(),
    }
  }
  return globalThis[KEY]
}

function timeoutMs(value, fallback) {
  const parsed = Number(value)
  if (!Number.isFinite(parsed) || parsed <= 0) return fallback
  return parsed
}

function registerTui(handler) {
  const current = state()
  current.tui = handler
  return () => {
    if (current.tui === handler) current.tui = undefined
  }
}

function fail(status, reason) {
  return { status, reason }
}

async function runApproval(handler, request, ms) {
  const ctrl = new AbortController()
  let timer

  try {
    return await new Promise((resolve) => {
      timer = setTimeout(() => {
        ctrl.abort()
        resolve(fail('timeout', 'Safeguard approval timed out.'))
      }, ms)

      Promise.resolve(handler.requestApproval({ ...request, signal: ctrl.signal }))
        .then((allowed) => {
          resolve(allowed === true ? { status: 'allow' } : fail('block', 'Safeguard approval was not granted.'))
        })
        .catch((error) => {
          resolve(fail('block', error instanceof Error ? error.message : String(error)))
        })
    })
  } finally {
    if (timer) clearTimeout(timer)
  }
}

function requestApproval(request, ms) {
  const current = state()
  const handler = current.tui
  if (!handler || typeof handler.requestApproval !== 'function') {
    return Promise.resolve(fail('unavailable', 'Safeguard approval UI is unavailable.'))
  }

  const wait = timeoutMs(ms, 60_000)
  const run = () => runApproval(handler, request, wait)
  const next = current.queue.catch(() => undefined).then(run)
  current.queue = next.catch(() => undefined)
  return next
}

function showWarning(warning) {
  const handler = state().tui
  if (!handler || typeof handler.showWarning !== 'function') return
  Promise.resolve(handler.showWarning(warning)).catch(() => undefined)
}

function resetForTests() {
  delete globalThis[KEY]
}

module.exports = {
  registerTui,
  requestApproval,
  showWarning,
  resetForTests,
}
