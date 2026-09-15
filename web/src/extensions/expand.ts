import { Node, mergeAttributes } from '@tiptap/core'
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
    return ({ node }) => {
      const dom = document.createElement('div')
      dom.className = 'expand'
      dom.dataset.type = 'expand'

      const summary = document.createElement('button')
      summary.type = 'button'
      summary.className = 'expand-summary'
      summary.contentEditable = 'false'
      summary.setAttribute('aria-expanded', 'false')

      const content = document.createElement('div')
      content.className = 'expand-content'

      const applyTitle = (title: unknown) => {
        summary.textContent = typeof title === 'string' && title ? title : DEFAULT_TITLE
      }
      applyTitle(node.attrs.title)

      summary.addEventListener('click', (event) => {
        event.preventDefault()
        const isOpen = dom.classList.toggle('is-open')
        summary.setAttribute('aria-expanded', String(isOpen))
      })

      dom.append(summary, content)
      return {
        dom,
        contentDOM: content,
        update: (next) => {
          if (next.type.name !== 'expand') return false
          applyTitle(next.attrs.title)
          return true
        },
        ignoreMutation: (mutation) =>
          mutation.type !== 'selection' && (mutation.target === dom || summary.contains(mutation.target)),
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
