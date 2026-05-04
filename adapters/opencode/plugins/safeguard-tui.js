'use strict'

const bridge = require('./bridge.js')

function short(text, max) {
  const value = String(text || '').replace(/\s+/g, ' ').trim()
  if (value.length <= max) return value
  return `${value.slice(0, max - 3)}...`
}

function message(request) {
  const parts = [short(request.reason, 240)]
  const preview = short(request.preview, 240)
  if (preview) parts.push(`Target: ${preview}`)
  return parts.join('\n')
}

const plugin = {
  id: 'uplift.safeguard.tui',
  tui: async (api) => {
    const unregister = bridge.registerTui({
      requestApproval(request) {
        return new Promise((resolve) => {
          let done = false
          const finish = (allowed) => {
            if (done) return
            done = true
            request.signal?.removeEventListener?.('abort', onAbort)
            api.ui.dialog.clear()
            resolve(allowed)
          }
          const onAbort = () => finish(false)

          if (api.lifecycle.signal.aborted || request.signal?.aborted) {
            resolve(false)
            return
          }

          request.signal?.addEventListener?.('abort', onAbort, { once: true })
          api.ui.dialog.setSize('medium')
          api.ui.dialog.replace(
            () => api.ui.DialogSelect({
              title: 'Safeguard approval required',
              placeholder: message(request),
              skipFilter: true,
              options: [
                {
                  title: 'Allow once',
                  value: 'allow',
                  description: `Run this ${request.tool} action once.`,
                  category: 'Safeguard',
                },
                {
                  title: 'Block',
                  value: 'block',
                  description: 'Deny this action and ask OpenCode to choose a safer path.',
                  category: 'Safeguard',
                },
              ],
              onSelect(option) {
                finish(option.value === 'allow')
              },
            }),
            () => finish(false),
          )
        })
      },
      showWarning(warning) {
        api.ui.toast({
          title: 'Safeguard',
          message: short(warning.message, 300),
          variant: 'warning',
          duration: 5000,
        })
      },
    })

    api.lifecycle.onDispose(unregister)
    api.command.register(() => [
      {
        title: 'Safeguard status',
        value: 'safeguard.status',
        category: 'Safeguard',
        onSelect: () => api.ui.toast({ message: 'Safeguard OpenCode adapter is active.', variant: 'success' }),
      },
    ])
  },
}

module.exports = plugin
