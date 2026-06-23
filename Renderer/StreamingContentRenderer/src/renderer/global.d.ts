export {}

declare global {
  interface Window {
    streamingRenderer?: StreamingRendererAPI
    webkit?: {
      messageHandlers?: {
        heightUpdate?: {
          postMessage: (height: number) => void
        }
      }
    }
  }

  interface StreamingRendererAPI {
    configure: (configuration: StreamingRendererConfiguration) => void
    requestHeightUpdate: () => void
    setTimeline: (items: AssistantTimelineItem[], options?: AssistantTimelineOptions) => void
  }

  interface StreamingRendererConfiguration {
    color?: string
    colorScheme?: 'dark' | 'light' | string
    fontSize?: number
    language?: string
    linkColor?: string
    secondaryColor?: string
    separatorColor?: string
    successColor?: string
    tertiaryColor?: string
    errorColor?: string
  }

  interface AssistantTimelineOptions {
    isStreaming?: boolean
  }

  type AssistantTimelineItem = AssistantTimelineReasoningItem
    | AssistantTimelineRawTextItem
    | AssistantTimelineToolItem

  interface AssistantTimelineReasoningItem {
    id: string
    kind: 'reasoning'
    text: string
  }

  interface AssistantTimelineRawTextItem {
    id: string
    kind: 'rawText'
    text: string
  }

  interface AssistantTimelineToolItem {
    id: string
    kind: 'tool'
    callID: string
    displayName: string
    state: 'running' | 'completed' | 'failed'
    detail?: string
  }
}
