import { Node, mergeAttributes } from '@tiptap/core'
import type { DOMOutputSpec } from '@tiptap/pm/model'
import { findDirectiveStart, serializeDirectiveAttributes, tokenizeDirective } from './directive'

export const PANEL_TYPES = ['info', 'note', 'success', 'warning', 'error'] as const
export type PanelType = (typeof PANEL_TYPES)[number]

const PANEL_LABELS: Record<PanelType, string> = {
  info: 'Информация',
  note: 'Заметка',
  success: 'Успех',
  warning: 'Предупреждение',
  error: 'Ошибка',
}

export function isPanelType(value: unknown): value is PanelType {
  return typeof value === 'string' && (PANEL_TYPES as readonly string[]).includes(value)
}

/** Цветная панель Confluence: `:::warning {title="Внимание"}` … `:::`. */
export const Panel = Node.create({
  name: 'panel',
  group: 'block',
  content: 'block+',
  defining: true,

  addAttributes() {
    return {
      type: {
        default: 'info',
        parseHTML: (element) => {
          const value = element.getAttribute('data-panel')
          return isPanelType(value) ? value : 'info'
        },
        renderHTML: () => ({}),
      },
      title: {
        default: '',
        parseHTML: (element) => element.getAttribute('data-title') ?? '',
        renderHTML: () => ({}),
      },
    }
  },

  parseHTML() {
    return [{ tag: 'div[data-type="panel"]', contentElement: '.panel-content' }]
  },

  renderHTML({ node, HTMLAttributes }) {
    const type = isPanelType(node.attrs.type) ? node.attrs.type : 'info'
    const title = String(node.attrs.title ?? '')
    const header: DOMOutputSpec[] = title ? [['div', { class: 'panel-title' }, title]] : []
    return [
      'div',
      mergeAttributes(HTMLAttributes, {
        'data-type': 'panel',
        'data-panel': type,
        'data-title': title,
        class: `panel panel-${type}`,
        role: 'note',
        'aria-label': PANEL_LABELS[type],
      }),
      ['span', { class: 'panel-icon', 'aria-hidden': 'true', contenteditable: 'false' }],
      ['div', { class: 'panel-body' }, ...header, ['div', { class: 'panel-content' }, 0]],
    ] as DOMOutputSpec
  },

  markdownTokenizer: {
    name: 'panel',
    level: 'block',
    start: (src) => findDirectiveStart(src, PANEL_TYPES),
    tokenize: (src, _tokens, lexer) => tokenizeDirective(src, PANEL_TYPES, 'panel', lexer),
  },

  parseMarkdown: (token, helpers) => {
    const content = helpers.parseChildren(token.tokens ?? [])
    return helpers.createNode(
      'panel',
      { type: token.name, title: token.attributes?.title ?? '' },
      content.length > 0 ? content : [{ type: 'paragraph' }],
    )
  },

  renderMarkdown: (node, helpers) => {
    const type = isPanelType(node.attrs?.type) ? node.attrs.type : 'info'
    const opening = `:::${type}${serializeDirectiveAttributes({ title: node.attrs?.title })}`
    const body = helpers.renderChildren(node.content ?? [], '\n\n')
    return body.trim() ? `${opening}\n\n${body}\n\n:::` : `${opening}\n\n:::`
  },
})
