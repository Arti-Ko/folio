import { Node } from '@tiptap/core'
import { openStatusPopover } from '../editor/popover'
import { normalizeStatusColor } from './statusColors'

export { STATUS_COLORS, normalizeStatusColor, type StatusColor } from './statusColors'

const STATUS_PATTERN = /^\[status(?:\s+color="([a-z]+)")?\]([^[\]\n]*)\[\/status\]/

/** Статус Confluence внутри текста: `[status color="green"]Готово[/status]`. */
export const Status = Node.create({
  name: 'status',
  group: 'inline',
  inline: true,
  atom: true,
  selectable: true,

  addAttributes() {
    return {
      label: { default: '' },
      color: { default: 'grey' },
    }
  },

  parseHTML() {
    return [
      {
        tag: 'span[data-type="status"]',
        getAttrs: (element) => ({
          label: element.textContent ?? '',
          color: normalizeStatusColor(element.getAttribute('data-color')),
        }),
      },
    ]
  },

  renderHTML({ node }) {
    const color = normalizeStatusColor(node.attrs.color)
    return ['span', { 'data-type': 'status', 'data-color': color, class: `status status-${color}` }, String(node.attrs.label)]
  },

  renderText({ node }) {
    return String(node.attrs.label)
  },

  addNodeView() {
    return ({ node, editor, getPos }) => {
      const dom = document.createElement('span')
      const apply = (label: unknown, colorValue: unknown) => {
        const color = normalizeStatusColor(colorValue)
        dom.className = `status status-${color}`
        dom.dataset.type = 'status'
        dom.dataset.color = color
        dom.textContent = String(label ?? '')
      }
      apply(node.attrs.label, node.attrs.color)

      dom.addEventListener('click', (event) => {
        const position = getPos()
        if (!editor.isEditable || typeof position !== 'number') return
        event.preventDefault()
        openStatusPopover(editor, position, dom.getBoundingClientRect())
      })

      return {
        dom,
        update: (next) => {
          if (next.type.name !== 'status') return false
          apply(next.attrs.label, next.attrs.color)
          return true
        },
      }
    }
  },

  markdownTokenizer: {
    name: 'status',
    level: 'inline',
    start: (src) => src.indexOf('[status'),
    tokenize: (src) => {
      const match = STATUS_PATTERN.exec(src)
      if (!match) return undefined
      return { type: 'status', raw: match[0], color: normalizeStatusColor(match[1]), label: match[2].trim() }
    },
  },

  parseMarkdown: (token, helpers) =>
    helpers.createNode('status', { label: token.label ?? '', color: normalizeStatusColor(token.color) }),

  renderMarkdown: (node) => {
    const color = normalizeStatusColor(node.attrs?.color)
    const label = String(node.attrs?.label ?? '').replace(/[[\]\n]/g, '')
    return color === 'grey' ? `[status]${label}[/status]` : `[status color="${color}"]${label}[/status]`
  },
})
