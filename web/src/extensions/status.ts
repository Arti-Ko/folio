import { Node } from '@tiptap/core'

export const STATUS_COLORS = ['grey', 'blue', 'green', 'yellow', 'red', 'purple'] as const
export type StatusColor = (typeof STATUS_COLORS)[number]

const STATUS_PATTERN = /^\[status(?:\s+color="([a-z]+)")?\]([^[\]\n]*)\[\/status\]/

export function normalizeStatusColor(value: unknown): StatusColor {
  return typeof value === 'string' && (STATUS_COLORS as readonly string[]).includes(value)
    ? (value as StatusColor)
    : 'grey'
}

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
