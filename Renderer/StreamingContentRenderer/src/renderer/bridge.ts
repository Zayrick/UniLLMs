import type { StreamingRendererController } from './streamingRenderer'

type StreamingRendererAPI = NonNullable<Window['streamingRenderer']>

let activeController: StreamingRendererController | null = null
let pendingConfiguration: Parameters<StreamingRendererAPI['configure']>[0] | null = null
let pendingContent = ''
let hasPendingContent = false
let hasPendingHeightRequest = false

const bridgeAPI: StreamingRendererAPI = {
  configure(configuration) {
    pendingConfiguration = configuration
    activeController?.api.configure(configuration)
  },

  setContent(nextContent) {
    pendingContent = nextContent || ''
    hasPendingContent = true
    activeController?.api.setContent(pendingContent)
  },

  requestHeightUpdate() {
    if (activeController) {
      activeController.api.requestHeightUpdate()
      return
    }

    hasPendingHeightRequest = true
  },
}

export function installStreamingRendererBridge() {
  window.streamingRenderer = bridgeAPI
}

export function attachStreamingRendererController(controller: StreamingRendererController) {
  activeController = controller

  if (pendingConfiguration) {
    controller.api.configure(pendingConfiguration)
  }

  if (hasPendingContent) {
    controller.api.setContent(pendingContent)
  }

  if (hasPendingHeightRequest) {
    controller.api.requestHeightUpdate()
    hasPendingHeightRequest = false
  }
}

export function detachStreamingRendererController(controller: StreamingRendererController) {
  if (activeController === controller) {
    activeController = null
  }
}
