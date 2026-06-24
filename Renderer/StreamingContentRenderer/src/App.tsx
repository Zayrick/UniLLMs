import * as Collapsible from '@radix-ui/react-collapsible'
import { cjk } from '@streamdown/cjk'
import { code } from '@streamdown/code'
import { createMathPlugin } from '@streamdown/math'
import { mermaid } from '@streamdown/mermaid'
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
import {
  Streamdown,
  type ControlsConfig,
  type LinkSafetyConfig,
  type PluginConfig,
  type StreamdownTranslations,
} from 'streamdown'
import { attachStreamingRendererController, detachStreamingRendererController } from './renderer/bridge'
import {
  applyRendererConfiguration,
  type StreamingRendererController,
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
  isActive: boolean
  item: AssistantTimelineRawTextItem
  kind: 'rawText'
}

type TimelineSegment = ThoughtSegment | RawTextSegment

const streamdownPlugins: PluginConfig = {
  cjk,
  code,
  math: createMathPlugin({
    errorColor: 'var(--streaming-secondary-color)',
    singleDollarTextMath: true,
  }),
  mermaid,
}

const streamdownLinkSafety: LinkSafetyConfig = {
  enabled: false,
}

const streamdownControls: ControlsConfig = {
  code: {
    copy: true,
    download: false,
  },
  mermaid: {
    copy: true,
    download: false,
    fullscreen: false,
    panZoom: false,
  },
  table: {
    copy: false,
    download: false,
    fullscreen: false,
  },
}

const emptyTimelineState: TimelineState = {
  isStreaming: false,
  items: [],
}

function App() {
  const contentRef = useRef<HTMLDivElement>(null)
  const requestHeightUpdateRef = useRef<() => void>(() => {})
  const [timelineState, setTimelineState] = useState(emptyTimelineState)
  const { i18n, t } = useTranslation()

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
          syncRendererLanguage(configuration.language, i18n, scheduleHeightUpdate)
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
  }, [i18n])

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
      />
    </div>
  )
}

function AssistantTimeline({
  isStreaming,
  items,
  requestHeightUpdate,
  t,
}: {
  isStreaming: boolean
  items: AssistantTimelineItem[]
  requestHeightUpdate: () => void
  t: ReturnType<typeof useTranslation>['t']
}) {
  const segments = useMemo(() => groupTimelineItems(items, isStreaming), [items, isStreaming])
  const translations = useMemo(() => streamdownTranslations(t), [t])

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
              isStreaming={segment.isActive}
              key={segment.id}
              requestHeightUpdate={requestHeightUpdate}
              translations={translations}
            />
          )
        }

        return (
          <ThoughtSection
            key={segment.id}
            requestHeightUpdate={requestHeightUpdate}
            segment={segment}
            t={t}
            translations={translations}
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
  translations,
}: {
  requestHeightUpdate: () => void
  segment: ThoughtSegment
  t: ReturnType<typeof useTranslation>['t']
  translations: Partial<StreamdownTranslations>
}) {
  const [isManuallyExpanded, setIsManuallyExpanded] = useState(false)
  const summary = thoughtSummary(segment.items, t)
  const title = segment.isActive
    ? t('timeline.processing', { defaultValue: 'Processing' })
    : summary
  const isExpanded = segment.isActive || isManuallyExpanded
  const setExpanded = (expanded: boolean) => {
    if (!segment.isActive) {
      setIsManuallyExpanded(expanded)
    }
  }

  useLayoutEffect(() => {
    requestHeightUpdate()
  }, [isExpanded, requestHeightUpdate])

  if (!segment.isActive && !summary) {
    return null
  }

  return (
    <Collapsible.Root
      className={segment.isActive ? 'thought-section is-active' : 'thought-section'}
      onOpenChange={setExpanded}
      open={isExpanded}
    >
      <Collapsible.Trigger asChild disabled={segment.isActive}>
        <button className="thought-toggle" type="button">
          <ChevronDown aria-hidden="true" className="collapse-chevron" />
          <span className={segment.isActive ? 'thought-title is-shimmering' : 'thought-title'}>
            {title}
          </span>
        </button>
      </Collapsible.Trigger>
      <Collapsible.Content className="collapsible-content">
        <div className="thought-body">
          {segment.items.map((item) => (
            <TimelineRow
              item={item}
              isStreaming={segment.isActive}
              key={item.id}
              requestHeightUpdate={requestHeightUpdate}
              t={t}
              translations={translations}
            />
          ))}
        </div>
      </Collapsible.Content>
    </Collapsible.Root>
  )
}

function TimelineRow({
  isStreaming,
  item,
  requestHeightUpdate,
  t,
  translations,
}: {
  isStreaming: boolean
  item: ThoughtTimelineItem
  requestHeightUpdate: () => void
  t: ReturnType<typeof useTranslation>['t']
  translations: Partial<StreamdownTranslations>
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
        isStreaming={isStreaming}
        requestHeightUpdate={requestHeightUpdate}
        translations={translations}
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
      <Collapsible.Root
        className="tool-content"
        onOpenChange={setIsExpanded}
        open={isDetailExpanded}
      >
        {hasDetail ? (
          <Collapsible.Trigger asChild>
            <button className="tool-toggle has-detail" type="button">
              {title}
              <ChevronDown aria-hidden="true" className="collapse-chevron" />
            </button>
          </Collapsible.Trigger>
        ) : (
          <div className="tool-toggle">
            {title}
          </div>
        )}
        <Collapsible.Content className="collapsible-content">
          <pre className="tool-detail">{detail}</pre>
        </Collapsible.Content>
      </Collapsible.Root>
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
  return rowElement.querySelector<HTMLElement>('.timeline-align-target')
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
  isStreaming,
  requestHeightUpdate,
  translations,
}: {
  className?: string
  content: string
  isStreaming: boolean
  requestHeightUpdate: () => void
  translations: Partial<StreamdownTranslations>
}) {
  const contentRef = useRef<HTMLDivElement>(null)

  useLayoutEffect(() => {
    const contentElement = contentRef.current
    if (!contentElement) {
      return
    }

    requestHeightUpdate()
    const resizeObserver = typeof ResizeObserver === 'undefined'
      ? null
      : new ResizeObserver(requestHeightUpdate)
    resizeObserver?.observe(contentElement)
    document.fonts?.ready.then(requestHeightUpdate).catch(() => {})

    return () => {
      resizeObserver?.disconnect()
    }
  }, [content, requestHeightUpdate])

  return (
    <div
      className={className ? `streamdown-content ${className}` : 'streamdown-content'}
      ref={contentRef}
    >
      <Streamdown
        controls={streamdownControls}
        dir="auto"
        isAnimating={isStreaming}
        mode="streaming"
        normalizeHtmlIndentation
        linkSafety={streamdownLinkSafety}
        plugins={streamdownPlugins}
        translations={translations}
      >
        {content}
      </Streamdown>
    </div>
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
        isActive: false,
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
  return segments.map((segment) => ({
    ...segment,
    isActive: isStreaming && segment === lastSegment,
  }))
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

function streamdownTranslations(
  t: ReturnType<typeof useTranslation>['t'],
): Partial<StreamdownTranslations> {
  return {
    close: t('streamdown.close', { defaultValue: 'Close' }),
    copied: t('streamdown.copied', { defaultValue: 'Copied' }),
    copyCode: t('streamdown.copyCode', { defaultValue: 'Copy Code' }),
    copyLink: t('streamdown.copyLink', { defaultValue: 'Copy link' }),
    copyTable: t('streamdown.copyTable', { defaultValue: 'Copy table' }),
    copyTableAsCsv: t('streamdown.copyTableAsCsv', { defaultValue: 'Copy table as CSV' }),
    copyTableAsMarkdown: t('streamdown.copyTableAsMarkdown', { defaultValue: 'Copy table as Markdown' }),
    copyTableAsTsv: t('streamdown.copyTableAsTsv', { defaultValue: 'Copy table as TSV' }),
    downloadDiagram: t('streamdown.downloadDiagram', { defaultValue: 'Download diagram' }),
    downloadDiagramAsMmd: t('streamdown.downloadDiagramAsMmd', { defaultValue: 'Download diagram as MMD' }),
    downloadDiagramAsPng: t('streamdown.downloadDiagramAsPng', { defaultValue: 'Download diagram as PNG' }),
    downloadDiagramAsSvg: t('streamdown.downloadDiagramAsSvg', { defaultValue: 'Download diagram as SVG' }),
    downloadFile: t('streamdown.downloadFile', { defaultValue: 'Download file' }),
    downloadImage: t('streamdown.downloadImage', { defaultValue: 'Download image' }),
    downloadTable: t('streamdown.downloadTable', { defaultValue: 'Download table' }),
    downloadTableAsCsv: t('streamdown.downloadTableAsCsv', { defaultValue: 'Download table as CSV' }),
    downloadTableAsMarkdown: t('streamdown.downloadTableAsMarkdown', { defaultValue: 'Download table as Markdown' }),
    exitFullscreen: t('streamdown.exitFullscreen', { defaultValue: 'Exit fullscreen' }),
    externalLinkWarning: t('streamdown.externalLinkWarning', { defaultValue: "You're about to visit an external website." }),
    imageNotAvailable: t('streamdown.imageNotAvailable', { defaultValue: 'Image not available' }),
    mermaidFormatMmd: t('streamdown.mermaidFormatMmd', { defaultValue: 'MMD' }),
    mermaidFormatPng: t('streamdown.mermaidFormatPng', { defaultValue: 'PNG' }),
    mermaidFormatSvg: t('streamdown.mermaidFormatSvg', { defaultValue: 'SVG' }),
    openExternalLink: t('streamdown.openExternalLink', { defaultValue: 'Open external link?' }),
    openLink: t('streamdown.openLink', { defaultValue: 'Open link' }),
    tableFormatCsv: t('streamdown.tableFormatCsv', { defaultValue: 'CSV' }),
    tableFormatMarkdown: t('streamdown.tableFormatMarkdown', { defaultValue: 'Markdown' }),
    tableFormatTsv: t('streamdown.tableFormatTsv', { defaultValue: 'TSV' }),
    viewFullscreen: t('streamdown.viewFullscreen', { defaultValue: 'View fullscreen' }),
  }
}

export default App

function syncRendererLanguage(
  language: string | undefined,
  i18n: ReturnType<typeof useTranslation>['i18n'],
  requestHeightUpdate: () => void,
) {
  const nextLanguage = language?.trim()
  if (!nextLanguage || i18n.language === nextLanguage || i18n.resolvedLanguage === nextLanguage) {
    return
  }

  void i18n.changeLanguage(nextLanguage).then(requestHeightUpdate).catch(requestHeightUpdate)
}
