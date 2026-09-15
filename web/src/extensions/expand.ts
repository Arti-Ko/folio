import { Node, mergeAttributes } from '@tiptap/core'
import type { Node as ProseMirrorNode } from '@tiptap/pm/model'
import { element } from '../editor/dom'
import { findDirectiveStart, serializeDirectiveAttributes, tokenizeDirective } from './directive'

const EXPAND_NAMES = ['expand'] as const
const DEFAULT_TITLE = 'Подробнее'

/** Раскрывающийся блок Confluence: `:::expand {title="Расшифровка"}` … `:::`. */
export const Expand = Node.create({
  name: 'expand',
  group: 'block',
  content: 'block+',
  defining: true,

  addAttributes() {
    return {
      title: {
        default: '',
        parseHTML: (element) => element.getAttribute('data-title') ?? '',
        renderHTML: () => ({}),
      },
    }
  },

  parseHTML() {
    return [{ tag: 'div[data-type="expand"]', contentElement: '.expand-content' }]
  },

  renderHTML({ node, HTMLAttributes }) {
    const title = String(node.attrs.title ?? '')
    return [
      'div',
      mergeAttributes(HTMLAttributes, { 'data-type': 'expand', 'data-title': title, class: 'expand' }),
      ['div', { class: 'expand-summary', contenteditable: 'false' }, title || DEFAULT_TITLE],
      ['div', { class: 'expand-content' }, 0],
    ]
  },

  addNodeView() {
    return ({ node, editor, getPos }) => {
      let current: ProseMirrorNode = node
      const dom = element('div', 'expand')
      dom.dataset.type = 'expand'

      const header = element('div', 'expand-header')
      header.contentEditable = 'false'
      const summary = element('button', 'expand-summary')
      summary.type = 'button'
      summary.setAttribute('aria-expanded', 'false')
      const titleInput = element('input', 'expand-title-input')
      titleInput.type = 'text'
      titleInput.placeholder = 'Заголовок блока'
      header.append(summary, titleInput)

      const content = element('div', 'expand-content')

      summary.addEventListener('click', (event) => {
        event.preventDefault()
        const isOpen = dom.classList.toggle('is-open')
        summary.setAttribute('aria-expanded', String(isOpen))
      })
      titleInput.addEventListener('input', () => {
        const position = getPos()
        if (typeof position !== 'number') return
        editor.view.dispatch(
          editor.state.tr.setNodeMarkup(position, undefined, { ...current.attrs, title: titleInput.value }),
        )
      })

      const apply = (next: ProseMirrorNode) => {
        current = next
        const title = String(next.attrs.title ?? '')
        summary.textContent = title || DEFAULT_TITLE
        if (document.activeElement !== titleInput) titleInput.value = title
      }
      apply(node)

      dom.append(header, content)
      return {
        dom,
        contentDOM: content,
        update: (next) => {
          if (next.type.name !== 'expand') return false
          apply(next)
          return true
        },
        stopEvent: (event) => header.contains(event.target as globalThis.Node),
        ignoreMutation: (mutation) => mutation.type !== 'selection' && !content.contains(mutation.target),
      }
    }
  },

  markdownTokenizer: {
    name: 'expand',
    level: 'block',
    start: (src) => findDirectiveStart(src, EXPAND_NAMES),
    tokenize: (src, _tokens, lexer) => tokenizeDirective(src, EXPAND_NAMES, 'expand', lexer),
  },

  parseMarkdown: (token, helpers) => {
    const content = helpers.parseChildren(token.tokens ?? [])
    return helpers.createNode(
      'expand',
      { title: token.attributes?.title ?? '' },
      content.length > 0 ? content : [{ type: 'paragraph' }],
    )
  },

  renderMarkdown: (node, helpers) => {
    const opening = `:::expand${serializeDirectiveAttributes({ title: node.attrs?.title })}`
    const body = helpers.renderChildren(node.content ?? [], '\n\n')
    return body.trim() ? `${opening}\n\n${body}\n\n:::` : `${opening}\n\n:::`
  },
})
