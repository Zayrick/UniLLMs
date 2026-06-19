import type { StreamingRendererController } from './streamingRenderer'

type StreamingRendererAPI = NonNullable<Window['streamingRenderer']>

let activeController: StreamingRendererController | null = null
let pendingConfiguration: Parameters<StreamingRendererAPI['configure']>[0] | null = null
let pendingTimeline: AssistantTimelineItem[] = []
let pendingTimelineOptions: AssistantTimelineOptions = {}
let hasPendingTimeline = false
let hasPendingHeightRequest = false

const bridgeAPI: StreamingRendererAPI = {
  configure(configuration) {
    pendingConfiguration = configuration
    activeController?.api.configure(configuration)
  },

  setTimeline(items, options) {
    pendingTimeline = Array.isArray(items) ? items : []
    pendingTimelineOptions = options || {}
    hasPendingTimeline = true
    activeController?.api.setTimeline(pendingTimeline, pendingTimelineOptions)
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

  if (hasPendingTimeline) {
    controller.api.setTimeline(pendingTimeline, pendingTimelineOptions)
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
