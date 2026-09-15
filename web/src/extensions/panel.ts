import { Node, mergeAttributes } from '@tiptap/core'
import type { DOMOutputSpec, Node as ProseMirrorNode } from '@tiptap/pm/model'
import { actionButton, element } from '../editor/dom'
import { findDirectiveStart, serializeDirectiveAttributes, tokenizeDirective } from './directive'

export const PANEL_TYPES = ['info', 'note', 'success', 'warning', 'error'] as const
export type PanelType = (typeof PANEL_TYPES)[number]

export const PANEL_LABELS: Record<PanelType, string> = {
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

  addNodeView() {
    return ({ node, editor, getPos }) => {
      let current: ProseMirrorNode = node
      const dom = element('div')
      const icon = element('span', 'panel-icon')
      icon.setAttribute('aria-hidden', 'true')
      icon.contentEditable = 'false'
      const body = element('div', 'panel-body')
      const titleView = element('div', 'panel-title')
      titleView.contentEditable = 'false'
      const controls = element('div', 'panel-controls')
      controls.contentEditable = 'false'
      const content = element('div', 'panel-content')

      const setAttributes = (attributes: Record<string, unknown>) => {
        const position = getPos()
        if (typeof position !== 'number') return
        editor.view.dispatch(editor.state.tr.setNodeMarkup(position, undefined, { ...current.attrs, ...attributes }))
      }

      const swatches = PANEL_TYPES.map((type) => {
        const swatch = actionButton('', `panel-swatch panel-swatch-${type}`, () => setAttributes({ type }))
        swatch.title = PANEL_LABELS[type]
        swatch.setAttribute('aria-label', `Тип панели: ${PANEL_LABELS[type]}`)
        return swatch
      })
      const titleInput = element('input', 'panel-title-input')
      titleInput.type = 'text'
      titleInput.placeholder = 'Заголовок панели'
      titleInput.addEventListener('input', () => setAttributes({ title: titleInput.value }))
      const remove = actionButton('×', 'panel-remove', () => {
        const position = getPos()
        if (typeof position !== 'number') return
        editor.chain().focus().deleteRange({ from: position, to: position + current.nodeSize }).run()
      })
      remove.title = 'Удалить панель'
      remove.setAttribute('aria-label', 'Удалить панель')
      controls.append(...swatches, titleInput, remove)

      body.append(titleView, controls, content)
      dom.append(icon, body)

      const apply = (next: ProseMirrorNode) => {
        current = next
        const type = isPanelType(next.attrs.type) ? next.attrs.type : 'info'
        const title = String(next.attrs.title ?? '')
        dom.className = `panel panel-${type}`
        dom.dataset.type = 'panel'
        dom.dataset.panel = type
        dom.setAttribute('role', 'note')
        dom.setAttribute('aria-label', PANEL_LABELS[type])
        titleView.textContent = title
        titleView.hidden = !title
        if (document.activeElement !== titleInput) titleInput.value = title
        swatches.forEach((swatch, index) => swatch.setAttribute('aria-pressed', String(PANEL_TYPES[index] === type)))
      }
      apply(node)

      return {
        dom,
        contentDOM: content,
        update: (next) => {
          if (next.type.name !== 'panel') return false
          apply(next)
          return true
        },
        stopEvent: (event) => controls.contains(event.target as globalThis.Node),
        ignoreMutation: (mutation) => mutation.type !== 'selection' && !content.contains(mutation.target),
      }
    }
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
