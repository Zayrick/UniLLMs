import DOMPurify, { type Config } from 'dompurify'
import hljs from 'highlight.js/lib/common'
import katex from 'katex'
import 'katex/contrib/mhchem'
import { Marked, type RendererObject, type TokenizerAndRendererExtension, type Tokens } from 'marked'
import morphdom from 'morphdom'

type Translate = (key: string, defaultValue: string) => string

interface StreamingRendererDependencies {
  translate: Translate
}

export interface StreamingRendererController {
  api: Window['streamingRenderer'] & {}
  dispose: () => void
  refreshTranslations: () => void
}

interface MathToken extends Tokens.Generic {
  text: string
}

const sanitizeOptions: Config = {
  USE_PROFILES: { html: true },
  ADD_TAGS: ['details', 'summary', 'kbd'],
  FORBID_TAGS: ['style'],
  FORBID_ATTR: ['style'],
  ALLOW_DATA_ATTR: false,
  ALLOWED_URI_REGEXP: /^(?:(?:https?|mailto|tel):)/i,
  RETURN_DOM_FRAGMENT: true,
}

const renderInterval = 1000 / 8

export function createStreamingRenderer(
  contentElement: HTMLElement,
  dependencies: StreamingRendererDependencies,
): StreamingRendererController {
  let pendingContent = ''
  let renderScheduled = false
  let heightScheduled = false
  let lastRenderTime = 0
  let lastRenderedContent: string | null = null
  let lastRenderUsedMarkdown = false
  let mathTokenIndex = 0

  const markdown = createMarkdownRenderer(dependencies.translate, () => {
    mathTokenIndex += 1
    return mathTokenIndex
  })

  function postHeight() {
    heightScheduled = false
    const height = Math.ceil(contentElement.getBoundingClientRect().height)
    window.webkit?.messageHandlers?.heightUpdate?.postMessage(height)
  }

  function requestHeightUpdate() {
    if (heightScheduled) {
      return
    }

    heightScheduled = true
    requestAnimationFrame(postHeight)
  }

  function renderPlainText(content: string) {
    contentElement.classList.add('plain-text')
    if (contentElement.textContent !== content || contentElement.childNodes.length !== 1) {
      contentElement.textContent = content
    }
  }

  function highlightCodeBlocks() {
    contentElement.querySelectorAll('pre code').forEach((codeElement) => {
      try {
        hljs.highlightElement(codeElement as HTMLElement)
      } catch {
        // Keep rendering content even if a language grammar throws.
      }
    })
  }

  function renderMathElements() {
    const mathElements = Array.from(contentElement.querySelectorAll<HTMLElement>('.math-pending'))
    mathElements.forEach((element) => {
      const source = element.textContent || ''
      const displayMode = element.classList.contains('math-block')

      try {
        katex.render(source, element, {
          displayMode,
          throwOnError: false,
          strict: false,
          trust: false,
        })
        element.classList.remove('math-pending')
        element.classList.add('math-rendered')
      } catch {
        element.textContent = source
      }
    })

    if (mathElements.length) {
      requestHeightUpdate()
    }
  }

  function renderMarkdown(content: string) {
    try {
      mathTokenIndex = 0
      const dirtyHTML = markdown.parse(content)
      const cleanFragment = DOMPurify.sanitize(String(dirtyHTML), sanitizeOptions) as unknown as DocumentFragment
      const targetElement = document.createElement('div')
      targetElement.append(cleanFragment)

      contentElement.classList.remove('plain-text')
      morphdom(contentElement, targetElement, {
        childrenOnly: true,
        onBeforeElUpdated(fromElement, toElement) {
          if (isSameMathElement(fromElement, toElement)) {
            return false
          }

          if (fromElement.tagName === 'DETAILS') {
            const sourceDetails = fromElement as HTMLDetailsElement
            const targetDetails = toElement as HTMLDetailsElement
            targetDetails.open = sourceDetails.open
          }

          return !fromElement.isEqualNode(toElement)
        },
      })

      highlightCodeBlocks()
      renderMathElements()
    } catch {
      renderPlainText(content)
    }
  }

  function isMathElement(element: Element) {
    return element.classList.contains('math-block')
      || element.classList.contains('math-inline')
  }

  function isSameMathElement(fromElement: Element, toElement: Element) {
    return isMathElement(fromElement)
      && isMathElement(toElement)
      && fromElement.id === toElement.id
      && fromElement.id.length > 0
  }

  function scheduleRender() {
    if (renderScheduled) {
      return
    }

    renderScheduled = true
    requestAnimationFrame(renderContent)
  }

  function renderContent(timestamp: DOMHighResTimeStamp) {
    if (lastRenderTime > 0 && timestamp - lastRenderTime < renderInterval) {
      requestAnimationFrame(renderContent)
      return
    }

    renderScheduled = false
    lastRenderTime = timestamp
    const shouldUseMarkdown = true
    const contentChanged = lastRenderedContent !== pendingContent || lastRenderUsedMarkdown !== shouldUseMarkdown

    if (contentChanged) {
      renderMarkdown(pendingContent)
      lastRenderedContent = pendingContent
      lastRenderUsedMarkdown = shouldUseMarkdown
    }
    requestHeightUpdate()
  }

  function handleResize() {
    requestHeightUpdate()
  }

  window.addEventListener('resize', handleResize)
  document.fonts?.ready.then(() => {
    requestHeightUpdate()
  }).catch(() => {})
  requestHeightUpdate()

  const api = {
    configure(configuration) {
      const colorScheme = configuration.colorScheme === 'dark' ? 'dark' : 'light'
      document.documentElement.style.colorScheme = colorScheme
      if (configuration.color) {
        document.documentElement.style.setProperty('--streaming-text-color', configuration.color)
      }
      if (configuration.linkColor) {
        document.documentElement.style.setProperty('--streaming-link-color', configuration.linkColor)
      }
      if (typeof configuration.fontSize === 'number') {
        document.documentElement.style.setProperty('--streaming-font-size', `${configuration.fontSize}px`)
      }
      requestHeightUpdate()
    },

    setContent(nextContent) {
      pendingContent = nextContent || ''
      scheduleRender()
    },

    requestHeightUpdate,
  } satisfies Window['streamingRenderer'] & {}

  return {
    api,
    dispose() {
      window.removeEventListener('resize', handleResize)
    },
    refreshTranslations() {
      lastRenderedContent = null
      scheduleRender()
    },
  }
}

function createMarkdownRenderer(translate: Translate, nextMathTokenIndex: () => number) {
  const markdown = new Marked({ gfm: true })
  const renderer: RendererObject<string, string> = {
    code(token) {
      const language = normalizedCodeLanguage(token.lang)
      const languageClass = language ? ` class="language-${escapeAttribute(language)}"` : ''
      const languageLabel = language || translate('codeBlock.defaultLanguage', 'text')
      const code = token.escaped ? token.text : escapeHTML(token.text)

      return `
<div class="code-block">
<div class="code-block-header"><span class="code-block-language">${escapeHTML(languageLabel)}</span></div>
<pre><code${languageClass}>${code}</code></pre>
</div>
`
    },

    listitem(item) {
      const className = item.task ? ' class="task-list-item"' : ''
      return `<li${className}>${this.parser.parse(item.tokens)}</li>\n`
    },

    checkbox({ checked }) {
      const marker = checked ? '\u2611' : '\u25A1'
      return `<span class="task-list-marker" aria-hidden="true">${marker}</span> `
    },
  }

  markdown.use({
    renderer,
    extensions: [
      createDisplayMathExtension(nextMathTokenIndex),
      createInlineMathExtension(nextMathTokenIndex),
    ],
  })

  return markdown
}

function createDisplayMathExtension(nextMathTokenIndex: () => number): TokenizerAndRendererExtension<string, string> {
  return {
    name: 'displayMath',
    level: 'block',
    start(src) {
      return firstIndexOfAny(src, ['$$', '\\['])
    },
    tokenizer(src) {
      const match = src.match(/^(?: {0,3})\$\$[ \t]*\n([\s\S]+?)\n(?: {0,3})\$\$[ \t]*(?:\n+|$)/)
        || src.match(/^(?: {0,3})\$\$([^\n]+?)\$\$[ \t]*(?:\n+|$)/)
        || src.match(/^(?: {0,3})\\\[[ \t]*\n([\s\S]+?)\n(?: {0,3})\\\][ \t]*(?:\n+|$)/)
        || src.match(/^(?: {0,3})\\\[([^\n]+?)\\\][ \t]*(?:\n+|$)/)
      return mathToken('displayMath', match)
    },
    renderer(token) {
      return mathElementHTML('div', 'math-block', (token as MathToken).text, nextMathTokenIndex)
    },
  }
}

function createInlineMathExtension(nextMathTokenIndex: () => number): TokenizerAndRendererExtension<string, string> {
  return {
    name: 'inlineMath',
    level: 'inline',
    start(src) {
      return firstIndexOfAny(src, ['$', '\\('])
    },
    tokenizer(src) {
      const match = src.match(/^\$(?!\$)((?:\\.|[^\n\\$])+?)\$(?!\$)/)
        || src.match(/^\\\(((?:\\.|[\s\S])+?)\\\)/)
      return mathToken('inlineMath', match)
    },
    renderer(token) {
      return mathElementHTML('span', 'math-inline', (token as MathToken).text, nextMathTokenIndex)
    },
  }
}

function normalizedCodeLanguage(language?: string) {
  const languageName = String(language || '').trim().split(/\s+/)[0] || ''
  return languageName.replace(/^language-/i, '')
}

const htmlEscapeMap: Record<string, string> = {
  '&': '&amp;',
  '<': '&lt;',
  '>': '&gt;',
  '"': '&quot;',
  "'": '&#39;',
}

function escapeHTML(value: string) {
  return String(value).replace(/[&<>"']/g, (char) => htmlEscapeMap[char])
}

function escapeAttribute(value: string) {
  return escapeHTML(value).replace(/[^A-Za-z0-9_+.#-]/g, '-')
}

function firstIndexOfAny(source: string, values: string[]) {
  const indexes = values
    .map((value) => source.indexOf(value))
    .filter((index) => index >= 0)
  return indexes.length ? Math.min(...indexes) : undefined
}

function mathToken(type: string, match: RegExpMatchArray | null): MathToken | undefined {
  if (!match) {
    return undefined
  }

  return {
    type,
    raw: match[0],
    text: match[1].trim(),
  }
}

function mathElementHTML(
  tagName: 'div' | 'span',
  className: string,
  source: string,
  nextMathTokenIndex: () => number,
) {
  const id = `math-${nextMathTokenIndex()}-${hashString(source)}`
  const escapedSource = escapeHTML(source)
  return `<${tagName} id="${id}" class="${className} math-pending">${escapedSource}</${tagName}>`
}

function hashString(value: string) {
  let hash = 5381
  const string = String(value)
  for (let index = 0; index < string.length; index += 1) {
    hash = ((hash << 5) + hash) ^ string.charCodeAt(index)
  }
  return (hash >>> 0).toString(36)
}
