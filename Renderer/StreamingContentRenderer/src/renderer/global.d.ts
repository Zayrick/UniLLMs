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
}

interface StreamingRendererAPI {
  configure: (configuration: StreamingRendererConfiguration) => void
  requestHeightUpdate: () => void
  setContent: (nextContent: string) => void
}

interface StreamingRendererConfiguration {
  color?: string
  colorScheme?: 'dark' | 'light' | string
  fontSize?: number
  linkColor?: string
}

declare module 'katex/contrib/mhchem'
