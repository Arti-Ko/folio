import { Node } from '@tiptap/core'
import type { Editor } from '@tiptap/core'
import { collectHeadings } from './headings'

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

function renderToc(dom: HTMLElement, editor: Editor): void {
  const headings = collectHeadings(editor.state.doc)
  const title = document.createElement('div')
  title.className = 'page-block-title'
  title.textContent = 'Содержание'

  if (headings.length === 0) {
    const empty = document.createElement('div')
    empty.className = 'page-block-empty'
    empty.textContent = 'На странице нет заголовков'
    dom.replaceChildren(title, empty)
    return
  }

  const list = document.createElement('ul')
  for (const heading of headings) {
    const item = document.createElement('li')
    item.dataset.level = String(heading.level)
    item.append(
      createLink(heading.text, (event) => {
        event.preventDefault()
        event.stopPropagation()
        const target = editor.view.nodeDOM(heading.pos)
        if (target instanceof HTMLElement) target.scrollIntoView({ block: 'start' })
      }),
    )
    list.append(item)
  }
  dom.replaceChildren(title, list)
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
    return ({ editor }) => {
      const dom = document.createElement('nav')
      dom.className = 'page-block toc'
      dom.dataset.type = 'toc'
      dom.contentEditable = 'false'
      // Вид создаётся до того, как новый документ попадёт в состояние, поэтому ждём микрозадачу.
      const render = () => renderToc(dom, editor)
      queueMicrotask(render)
      editor.on('update', render)
      return { dom, ignoreMutation: () => true, destroy: () => editor.off('update', render) }
    }
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
    return ({ editor }) => {
      const dom = document.createElement('nav')
      dom.className = 'page-block children'
      dom.dataset.type = 'children'
      dom.contentEditable = 'false'

      const title = document.createElement('div')
      title.className = 'page-block-title'
      title.textContent = 'Дочерние страницы'

      const children = editor.storage.folioContext.children
      if (children.length === 0) {
        const empty = document.createElement('div')
        empty.className = 'page-block-empty'
        empty.textContent = 'Дочерних страниц нет'
        dom.replaceChildren(title, empty)
      } else {
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
      }
      return { dom, ignoreMutation: () => true }
    }
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
