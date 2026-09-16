import { Node } from '@tiptap/core'
import type { Editor } from '@tiptap/core'
import { collectHeadings } from './headings'

/** Блок, содержимое которого зависит не от самого узла, а от документа и данных приложения. */
interface LiveBlock {
  /** Слепок данных: пока он прежний, DOM не трогаем. */
  key: (editor: Editor) => string
  fill: (dom: HTMLElement, editor: Editor) => void
}

function blockPattern(name: string): RegExp {
  return new RegExp(`^\\[${name}\\][ \\t]*(?:\\n|$)`)
}

function createLink(text: string, onClick: (event: MouseEvent) => void): HTMLAnchorElement {
  const link = document.createElement('a')
  link.href = '#'
  link.textContent = text
  link.addEventListener('click', onClick)
  return link
}

function blockTitle(text: string): HTMLElement {
  const title = document.createElement('div')
  title.className = 'page-block-title'
  title.textContent = text
  return title
}

function blockEmpty(text: string): HTMLElement {
  const empty = document.createElement('div')
  empty.className = 'page-block-empty'
  empty.textContent = text
  return empty
}

/**
 * Вид, который сам следит за содержимым.
 *
 * Новая страница приходит через `setContent` без события `update`, а узел при этом
 * переиспользуется, поэтому слушаем транзакции и перерисовываем, когда данные и правда
 * изменились.
 */
function liveNodeView(editor: Editor, type: string, className: string, block: LiveBlock) {
  const dom = document.createElement('nav')
  dom.className = className
  dom.dataset.type = type
  dom.contentEditable = 'false'

  let lastKey: string | null = null
  let frame = 0

  const refresh = (): void => {
    const key = block.key(editor)
    if (key === lastKey) return
    lastKey = key
    block.fill(dom, editor)
  }
  const schedule = (): void => {
    if (frame) return
    frame = requestAnimationFrame(() => {
      frame = 0
      refresh()
    })
  }

  // Вид создаётся до того, как новый документ попадёт в состояние, поэтому ждём микрозадачу.
  queueMicrotask(refresh)
  editor.on('transaction', schedule)

  return {
    dom,
    ignoreMutation: () => true,
    destroy: () => {
      editor.off('transaction', schedule)
      if (frame) cancelAnimationFrame(frame)
    },
  }
}

const tableOfContents: LiveBlock = {
  key: (editor) =>
    collectHeadings(editor.state.doc)
      .map((heading) => `${heading.level} ${heading.text}`)
      .join('\n'),

  fill: (dom, editor) => {
    const headings = collectHeadings(editor.state.doc)
    const title = blockTitle('Содержание')
    if (headings.length === 0) {
      dom.replaceChildren(title, blockEmpty('На странице нет заголовков'))
      return
    }

    const list = document.createElement('ul')
    headings.forEach((heading, index) => {
      const item = document.createElement('li')
      item.dataset.level = String(heading.level)
      item.append(
        createLink(heading.text, (event) => {
          event.preventDefault()
          event.stopPropagation()
          // Позицию берём заново: пока страницу правят, заголовки съезжают.
          const current = collectHeadings(editor.state.doc)[index]
          if (!current) return
          const target = editor.view.nodeDOM(current.pos)
          if (target instanceof HTMLElement) target.scrollIntoView({ block: 'start' })
        }),
      )
      list.append(item)
    })
    dom.replaceChildren(title, list)
  },
}

const childPages: LiveBlock = {
  key: (editor) => editor.storage.folioContext.children.map((child) => child.title).join('\n'),

  fill: (dom, editor) => {
    const title = blockTitle('Дочерние страницы')
    const children = editor.storage.folioContext.children
    if (children.length === 0) {
      dom.replaceChildren(title, blockEmpty('Дочерних страниц нет'))
      return
    }

    const list = document.createElement('ul')
    for (const child of children) {
      const link = document.createElement('a')
      link.className = 'wiki-link'
      link.href = '#'
      link.dataset.space = ''
      link.dataset.title = child.title
      link.textContent = child.title
      const item = document.createElement('li')
      item.append(link)
      list.append(item)
    }
    dom.replaceChildren(title, list)
  },
}

/** `[toc]` — оглавление страницы, строится по заголовкам. */
export const TableOfContents = Node.create({
  name: 'tableOfContents',
  group: 'block',
  atom: true,
  selectable: true,

  parseHTML() {
    return [{ tag: 'nav[data-type="toc"]' }]
  },

  renderHTML() {
    return ['nav', { 'data-type': 'toc', class: 'page-block toc' }]
  },

  addNodeView() {
    return ({ editor }) => liveNodeView(editor, 'toc', 'page-block toc', tableOfContents)
  },

  markdownTokenizer: {
    name: 'tableOfContents',
    level: 'block',
    start: (src) => src.search(/^\[toc\]/m),
    tokenize: (src) => {
      const match = blockPattern('toc').exec(src)
      return match ? { type: 'tableOfContents', raw: match[0] } : undefined
    },
  },

  parseMarkdown: (_token, helpers) => helpers.createNode('tableOfContents'),
  renderMarkdown: () => '[toc]',
})

/** `[children]` — список дочерних страниц; данные приходят из приложения. */
export const ChildPages = Node.create({
  name: 'childPages',
  group: 'block',
  atom: true,
  selectable: true,

  parseHTML() {
    return [{ tag: 'nav[data-type="children"]' }]
  },

  renderHTML() {
    return ['nav', { 'data-type': 'children', class: 'page-block children' }]
  },

  addNodeView() {
    return ({ editor }) => liveNodeView(editor, 'children', 'page-block children', childPages)
  },

  markdownTokenizer: {
    name: 'childPages',
    level: 'block',
    start: (src) => src.search(/^\[children\]/m),
    tokenize: (src) => {
      const match = blockPattern('children').exec(src)
      return match ? { type: 'childPages', raw: match[0] } : undefined
    },
  },

  parseMarkdown: (_token, helpers) => helpers.createNode('childPages'),
  renderMarkdown: () => '[children]',
})
