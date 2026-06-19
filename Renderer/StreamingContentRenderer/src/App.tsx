import { BrainCircuit, ChevronDown, ToolCase } from 'lucide-react'
import {
  useCallback,
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
  type RefObject,
  type ReactNode,
} from 'react'
import { useTranslation } from 'react-i18next'
import { attachStreamingRendererController, detachStreamingRendererController } from './renderer/bridge'
import {
  applyRendererConfiguration,
  enhanceRenderedMarkdown,
  renderMarkdownHTML,
  type StreamingRendererController,
  type Translate,
} from './renderer/streamingRenderer'
import './styles/renderer.css'

type ThoughtTimelineItem = AssistantTimelineReasoningItem | AssistantTimelineToolItem

interface TimelineState {
  isStreaming: boolean
  items: AssistantTimelineItem[]
}

interface ThoughtSegment {
  id: string
  isActive: boolean
  items: ThoughtTimelineItem[]
  kind: 'thought'
}

interface RawTextSegment {
  id: string
  item: AssistantTimelineRawTextItem
  kind: 'rawText'
}

type TimelineSegment = ThoughtSegment | RawTextSegment

const emptyTimelineState: TimelineState = {
  isStreaming: false,
  items: [],
}

function App() {
  const contentRef = useRef<HTMLDivElement>(null)
  const requestHeightUpdateRef = useRef<() => void>(() => {})
  const [timelineState, setTimelineState] = useState(emptyTimelineState)
  const { i18n, t } = useTranslation()

  const translate = useCallback<Translate>(
    (key, defaultValue) => t(key, { defaultValue }),
    [t],
  )

  const requestHeightUpdate = useCallback(() => {
    requestHeightUpdateRef.current()
  }, [])

  useEffect(() => {
    document.documentElement.lang = i18n.resolvedLanguage || i18n.language || 'en'
  }, [i18n.language, i18n.resolvedLanguage])

  useLayoutEffect(() => {
    const contentElement = contentRef.current
    if (!contentElement) {
      return
    }

    let heightAnimationFrame = 0
    let isDisposed = false
    const postHeight = () => {
      heightAnimationFrame = 0
      const height = Math.ceil(contentElement.getBoundingClientRect().height)
      window.webkit?.messageHandlers?.heightUpdate?.postMessage(height)
    }

    const scheduleHeightUpdate = () => {
      if (heightAnimationFrame || isDisposed) {
        return
      }

      heightAnimationFrame = requestAnimationFrame(postHeight)
    }

    requestHeightUpdateRef.current = scheduleHeightUpdate

    const resizeObserver = typeof ResizeObserver === 'undefined'
      ? null
      : new ResizeObserver(scheduleHeightUpdate)
    resizeObserver?.observe(contentElement)
    window.addEventListener('resize', scheduleHeightUpdate)
    document.fonts?.ready.then(scheduleHeightUpdate).catch(() => {})

    const controller: StreamingRendererController = {
      api: {
        configure(configuration) {
          applyRendererConfiguration(configuration)
          scheduleHeightUpdate()
        },
        setTimeline(items, options) {
          setTimelineState({
            items: Array.isArray(items) ? items : [],
            isStreaming: options?.isStreaming === true,
          })
        },
        requestHeightUpdate: scheduleHeightUpdate,
      },
    }

    attachStreamingRendererController(controller)
    scheduleHeightUpdate()

    return () => {
      isDisposed = true
      detachStreamingRendererController(controller)
      if (heightAnimationFrame) {
        cancelAnimationFrame(heightAnimationFrame)
      }
      resizeObserver?.disconnect()
      window.removeEventListener('resize', scheduleHeightUpdate)
      requestHeightUpdateRef.current = () => {}
    }
  }, [])

  useLayoutEffect(() => {
    requestHeightUpdate()
  }, [timelineState, requestHeightUpdate])

  return (
    <div id="content" ref={contentRef}>
      <AssistantTimeline
        isStreaming={timelineState.isStreaming}
        items={timelineState.items}
        requestHeightUpdate={requestHeightUpdate}
        t={t}
        translate={translate}
      />
    </div>
  )
}

function AssistantTimeline({
  isStreaming,
  items,
  requestHeightUpdate,
  t,
  translate,
}: {
  isStreaming: boolean
  items: AssistantTimelineItem[]
  requestHeightUpdate: () => void
  t: ReturnType<typeof useTranslation>['t']
  translate: Translate
}) {
  const segments = useMemo(() => groupTimelineItems(items, isStreaming), [items, isStreaming])

  if (!segments.length) {
    return null
  }

  return (
    <div className="assistant-timeline">
      {segments.map((segment) => {
        if (segment.kind === 'rawText') {
          return (
            <MarkdownContent
              className="assistant-raw-text"
              content={segment.item.text}
              key={segment.id}
              requestHeightUpdate={requestHeightUpdate}
              translate={translate}
            />
          )
        }

        return (
          <ThoughtSection
            key={segment.id}
            requestHeightUpdate={requestHeightUpdate}
            segment={segment}
            t={t}
            translate={translate}
          />
        )
      })}
    </div>
  )
}

function ThoughtSection({
  requestHeightUpdate,
  segment,
  t,
  translate,
}: {
  requestHeightUpdate: () => void
  segment: ThoughtSegment
  t: ReturnType<typeof useTranslation>['t']
  translate: Translate
}) {
  const [isManuallyExpanded, setIsManuallyExpanded] = useState(false)
  const summary = thoughtSummary(segment.items, t)
  const title = segment.isActive
    ? t('timeline.processing', { defaultValue: 'Processing' })
    : summary
  const isExpanded = segment.isActive || isManuallyExpanded
  const toggleExpansion = () => {
    if (!segment.isActive) {
      setIsManuallyExpanded((expanded) => !expanded)
    }
  }

  useLayoutEffect(() => {
    requestHeightUpdate()
  }, [isExpanded, requestHeightUpdate])

  if (!segment.isActive && !summary) {
    return null
  }

  return (
    <section className={segment.isActive ? 'thought-section is-active' : 'thought-section'}>
      <button
        aria-expanded={isExpanded}
        className="thought-toggle"
        onClick={toggleExpansion}
        type="button"
      >
        <ChevronDown aria-hidden="true" className="collapse-chevron" />
        <span className={segment.isActive ? 'thought-title is-shimmering' : 'thought-title'}>
          {title}
        </span>
      </button>
      {isExpanded ? (
        <div className="thought-body">
          {segment.items.map((item) => (
            <TimelineRow
              item={item}
              key={item.id}
              requestHeightUpdate={requestHeightUpdate}
              t={t}
              translate={translate}
            />
          ))}
        </div>
      ) : null}
    </section>
  )
}

function TimelineRow({
  item,
  requestHeightUpdate,
  t,
  translate,
}: {
  item: ThoughtTimelineItem
  requestHeightUpdate: () => void
  t: ReturnType<typeof useTranslation>['t']
  translate: Translate
}) {
  const rowRef = useTimelineIconAlignment(requestHeightUpdate, item)

  if (item.kind === 'tool') {
    return (
      <ToolTimelineRow item={item} requestHeightUpdate={requestHeightUpdate} rowRef={rowRef} t={t} />
    )
  }

  return (
    <div className="timeline-row reasoning-row" ref={rowRef}>
      <TimelineIcon>
        <BrainCircuit aria-hidden="true" />
      </TimelineIcon>
      <MarkdownContent
        className="timeline-reasoning timeline-align-target"
        content={item.text}
        requestHeightUpdate={requestHeightUpdate}
        translate={translate}
      />
    </div>
  )
}

function ToolTimelineRow({
  item,
  requestHeightUpdate,
  rowRef,
  t,
}: {
  item: AssistantTimelineToolItem
  requestHeightUpdate: () => void
  rowRef: RefObject<HTMLDivElement | null>
  t: ReturnType<typeof useTranslation>['t']
}) {
  const [isExpanded, setIsExpanded] = useState(false)
  const detail = item.detail ?? ''
  const hasDetail = detail.trim().length > 0
  const titleClassName = item.state === 'running'
    ? 'tool-title timeline-align-target is-shimmering'
    : 'tool-title timeline-align-target'
  const title = (
    <span className={titleClassName}>
      {toolTitle(item, t)}
    </span>
  )
  const isDetailExpanded = hasDetail && isExpanded

  useLayoutEffect(() => {
    requestHeightUpdate()
  }, [isDetailExpanded, requestHeightUpdate])

  return (
    <div className={`timeline-row tool-row is-${item.state}`} ref={rowRef}>
      <TimelineIcon>
        <ToolCase aria-hidden="true" />
      </TimelineIcon>
      <div className="tool-content">
        {hasDetail ? (
          <button
            aria-expanded={isDetailExpanded}
            className="tool-toggle has-detail"
            onClick={() => setIsExpanded((expanded) => !expanded)}
            type="button"
          >
            {title}
            <ChevronDown aria-hidden="true" className="collapse-chevron" />
          </button>
        ) : (
          <div className="tool-toggle">
            {title}
          </div>
        )}
        {isDetailExpanded ? (
          <pre className="tool-detail">{detail}</pre>
        ) : null}
      </div>
    </div>
  )
}

function TimelineIcon({ children }: { children: ReactNode }) {
  return <span className="timeline-icon">{children}</span>
}

function useTimelineIconAlignment(
  requestHeightUpdate: () => void,
  refreshKey: unknown,
) {
  const rowRef = useRef<HTMLDivElement>(null)

  useLayoutEffect(() => {
    const rowElement = rowRef.current
    if (!rowElement) {
      return
    }

    let animationFrame = 0
    const alignIcon = () => {
      animationFrame = 0
      const iconElement = rowElement.querySelector<HTMLElement>('.timeline-icon')
      const targetElement = timelineAlignmentTarget(rowElement)
      if (!iconElement || !targetElement) {
        return
      }

      const rowRect = rowElement.getBoundingClientRect()
      const targetRect = targetElement.getBoundingClientRect()
      const iconHeight = iconElement.getBoundingClientRect().height || 16
      const lineHeight = resolvedLineHeight(targetElement)
      const offset = Math.max(0, targetRect.top - rowRect.top + (lineHeight - iconHeight) / 2)
      const nextValue = `${Math.round(offset * 100) / 100}px`

      if (rowElement.style.getPropertyValue('--timeline-icon-offset') === nextValue) {
        return
      }

      rowElement.style.setProperty('--timeline-icon-offset', nextValue)
      requestHeightUpdate()
    }

    const scheduleAlignment = () => {
      if (animationFrame) {
        return
      }

      animationFrame = requestAnimationFrame(alignIcon)
    }

    scheduleAlignment()

    const resizeObserver = typeof ResizeObserver === 'undefined'
      ? null
      : new ResizeObserver(scheduleAlignment)
    resizeObserver?.observe(rowElement)
    const targetRoot = rowElement.querySelector<HTMLElement>('.timeline-align-target')
    if (targetRoot) {
      resizeObserver?.observe(targetRoot)
    }
    document.fonts?.ready.then(scheduleAlignment).catch(() => {})

    return () => {
      if (animationFrame) {
        cancelAnimationFrame(animationFrame)
      }
      resizeObserver?.disconnect()
    }
  }, [refreshKey, requestHeightUpdate])

  return rowRef
}

function timelineAlignmentTarget(rowElement: HTMLElement) {
  const targetElement = rowElement.querySelector<HTMLElement>('.timeline-align-target')
  if (!targetElement) {
    return null
  }

  if (!targetElement.classList.contains('markdown-content')) {
    return targetElement
  }

  return targetElement.querySelector<HTMLElement>(
    'p, ul, ol, blockquote, pre, div.code-block, div.math-block, table, h1, h2, h3, h4, h5, h6',
  ) ?? targetElement
}

function resolvedLineHeight(element: HTMLElement) {
  const style = window.getComputedStyle(element)
  const parsedLineHeight = Number.parseFloat(style.lineHeight)
  if (Number.isFinite(parsedLineHeight)) {
    return parsedLineHeight
  }

  const parsedFontSize = Number.parseFloat(style.fontSize)
  return Number.isFinite(parsedFontSize) ? parsedFontSize * 1.2 : 16
}

function MarkdownContent({
  className,
  content,
  requestHeightUpdate,
  translate,
}: {
  className?: string
  content: string
  requestHeightUpdate: () => void
  translate: Translate
}) {
  const contentRef = useRef<HTMLDivElement>(null)
  const html = useMemo(() => renderMarkdownHTML(content, translate), [content, translate])

  useLayoutEffect(() => {
    const contentElement = contentRef.current
    if (!contentElement) {
      return
    }

    enhanceRenderedMarkdown(contentElement, requestHeightUpdate)
    requestHeightUpdate()
  }, [html, requestHeightUpdate])

  return (
    <div
      className={className ? `markdown-content ${className}` : 'markdown-content'}
      dangerouslySetInnerHTML={{ __html: html }}
      ref={contentRef}
    />
  )
}

function groupTimelineItems(items: AssistantTimelineItem[], isStreaming: boolean): TimelineSegment[] {
  const segments: TimelineSegment[] = []
  let currentThoughtSegment: ThoughtSegment | null = null

  items.forEach((item) => {
    if (item.kind === 'rawText') {
      currentThoughtSegment = null
      segments.push({
        id: item.id,
        item,
        kind: 'rawText',
      })
      return
    }

    if (!currentThoughtSegment) {
      currentThoughtSegment = {
        id: `thought-${item.id}`,
        isActive: false,
        items: [],
        kind: 'thought',
      }
      segments.push(currentThoughtSegment)
    }
    currentThoughtSegment.items.push(item)
  })

  const lastSegment = segments[segments.length - 1]
  return segments.map((segment) => {
    if (segment.kind !== 'thought') {
      return segment
    }

    return {
      ...segment,
      isActive: isStreaming && segment === lastSegment,
    }
  })
}

function thoughtSummary(
  items: ThoughtTimelineItem[],
  t: ReturnType<typeof useTranslation>['t'],
) {
  const reasoningCount = items.filter((item) => item.kind === 'reasoning').length
  const toolCount = new Set(
    items
      .filter((item): item is AssistantTimelineToolItem => item.kind === 'tool')
      .map((item) => item.callID),
  ).size
  const parts: string[] = []

  if (reasoningCount > 0) {
    parts.push(t(
      reasoningCount === 1 ? 'timeline.reasoningStepSingular' : 'timeline.reasoningStepPlural',
      {
        count: reasoningCount,
        defaultValue: reasoningCount === 1
          ? `${reasoningCount} reasoning step`
          : `${reasoningCount} reasoning steps`,
      },
    ))
  }
  if (toolCount > 0) {
    parts.push(t(
      toolCount === 1 ? 'timeline.toolCallSingular' : 'timeline.toolCallPlural',
      {
        count: toolCount,
        defaultValue: toolCount === 1
          ? `${toolCount} tool call`
          : `${toolCount} tool calls`,
      },
    ))
  }

  return parts.join(', ')
}

function toolTitle(
  item: AssistantTimelineToolItem,
  t: ReturnType<typeof useTranslation>['t'],
) {
  switch (item.state) {
  case 'running':
    return t('timeline.usingTool', {
      defaultValue: `Using ${item.displayName}`,
      name: item.displayName,
    })
  case 'failed':
    return t('timeline.toolFailed', {
      defaultValue: `Failed ${item.displayName}`,
      name: item.displayName,
    })
  case 'completed':
  default:
    return item.displayName
  }
}

export default App
