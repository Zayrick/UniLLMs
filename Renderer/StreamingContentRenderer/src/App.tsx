import { useEffect, useLayoutEffect, useRef } from 'react'
import { useTranslation } from 'react-i18next'
import { attachStreamingRendererController, detachStreamingRendererController } from './renderer/bridge'
import { createStreamingRenderer, type StreamingRendererController } from './renderer/streamingRenderer'
import './styles/renderer.css'

function App() {
  const contentRef = useRef<HTMLDivElement>(null)
  const controllerRef = useRef<StreamingRendererController | null>(null)
  const translateRef = useRef((_key: string, defaultValue: string) => defaultValue)
  const { i18n, t } = useTranslation()

  useEffect(() => {
    document.documentElement.lang = i18n.resolvedLanguage || i18n.language || 'en'
  }, [i18n.language, i18n.resolvedLanguage])

  useEffect(() => {
    translateRef.current = (key: string, defaultValue: string) => t(key, { defaultValue })
    controllerRef.current?.refreshTranslations()
  }, [t])

  useLayoutEffect(() => {
    const contentElement = contentRef.current
    if (!contentElement) {
      return
    }

    const controller = createStreamingRenderer(contentElement, {
      translate: (key, defaultValue) => translateRef.current(key, defaultValue),
    })

    controllerRef.current = controller
    attachStreamingRendererController(controller)

    return () => {
      detachStreamingRendererController(controller)
      controller.dispose()
      controllerRef.current = null
    }
  }, [])

  return <div id="content" ref={contentRef} />
}

export default App
