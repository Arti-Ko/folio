import { Editor } from '@tiptap/core'
import { createExtensions } from './extensions'
import type { ChildPageSummary } from './extensions/folioContext'
import { collectHeadings } from './extensions/headings'
import { normalizeStatusColor } from './extensions/status'
import './styles.css'

interface StatusPayload {
  label: string
  color: string
}

/** Всё, что приложение присылает для показа страницы (`PagePayload` в Swift). */
interface PagePayload {
  markdown: string
  title: string
  status: StatusPayload | null
  labels: string[]
  meta: string
  assetBase: string
  links: Record<string, boolean>
  children: ChildPageSummary[]
  banner: string | null
  resetScroll: boolean
}

type NativeMessage =
  | { type: 'ready' }
  | { type: 'openPage'; space: string | null; title: string }
  | { type: 'openURL'; href: string }
  | { type: 'outline'; items: { level: number; text: string; index: number }[] }
  | { type: 'renderError'; message: string }

declare global {
  interface Window {
    webkit?: { messageHandlers?: { folio?: { postMessage: (message: NativeMessage) => void } } }
    folio: {
      render: (payload: PagePayload) => void
      scrollToHeading: (index: number) => void
    }
  }
}

function post(message: NativeMessage): void {
  window.webkit?.messageHandlers?.folio?.postMessage(message)
}

function requireElement<T extends HTMLElement>(id: string): T {
  const element = document.getElementById(id)
  if (!element) throw new Error(`В разметке нет элемента #${id}`)
  return element as T
}

const page = requireElement<HTMLElement>('page')
const banner = requireElement<HTMLElement>('page-banner')
const titleElement = requireElement<HTMLHeadingElement>('page-title')
const metaElement = requireElement<HTMLElement>('page-meta')
const editorElement = requireElement<HTMLElement>('editor')

const editor = new Editor({
  element: editorElement,
  extensions: createExtensions(),
  editable: false,
  content: '',
})

function renderHeader(payload: PagePayload): void {
  titleElement.textContent = payload.title
  banner.textContent = payload.banner ?? ''
  banner.hidden = !payload.banner

  const parts: HTMLElement[] = []
  if (payload.status?.label) {
    const color = normalizeStatusColor(payload.status.color)
    const status = document.createElement('span')
    status.className = `status status-${color}`
    status.textContent = payload.status.label
    parts.push(status)
  }
  for (const label of payload.labels) {
    const chip = document.createElement('span')
    chip.className = 'label'
    chip.textContent = label
    parts.push(chip)
  }
  if (payload.meta) {
    const meta = document.createElement('span')
    meta.className = 'page-meta-text'
    meta.textContent = payload.meta
    parts.push(meta)
  }
  metaElement.replaceChildren(...parts)
  metaElement.hidden = parts.length === 0
}

function postOutline(): void {
  const items = collectHeadings(editor.state.doc).map((heading, index) => ({
    level: heading.level,
    text: heading.text,
    index,
  }))
  post({ type: 'outline', items })
}

function renderFallback(markdown: string): void {
  const pre = document.createElement('pre')
  pre.className = 'render-fallback'
  pre.textContent = markdown
  editorElement.replaceChildren(pre)
}

function render(payload: PagePayload): void {
  renderHeader(payload)
  Object.assign(editor.storage.folioContext, {
    links: payload.links,
    children: payload.children,
    assetBase: payload.assetBase,
  })

  try {
    editor.commands.setContent(payload.markdown, { contentType: 'markdown', emitUpdate: true })
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    post({ type: 'renderError', message })
    renderFallback(payload.markdown)
  }

  editorElement.dataset.empty = String(payload.markdown.trim() === '')
  page.hidden = false
  if (payload.resetScroll) window.scrollTo({ top: 0 })
  queueMicrotask(postOutline)
}

function scrollToHeading(index: number): void {
  const heading = collectHeadings(editor.state.doc)[index]
  if (!heading) return
  const target = editor.view.nodeDOM(heading.pos)
  if (target instanceof HTMLElement) target.scrollIntoView({ block: 'start' })
}

page.addEventListener('click', (event) => {
  const target = event.target instanceof Element ? event.target : null
  if (!target) return

  const wikiLink = target.closest<HTMLElement>('a.wiki-link')
  if (wikiLink) {
    event.preventDefault()
    post({ type: 'openPage', space: wikiLink.dataset.space || null, title: wikiLink.dataset.title ?? '' })
    return
  }

  const anchor = target.closest<HTMLAnchorElement>('a[href]')
  if (anchor && !anchor.closest('.page-block')) {
    event.preventDefault()
    post({ type: 'openURL', href: anchor.getAttribute('href') ?? '' })
  }
})

window.folio = { render, scrollToHeading }
post({ type: 'ready' })
