import type { Editor } from '@tiptap/core'
import { STATUS_COLORS, STATUS_COLOR_NAMES, normalizeStatusColor } from '../extensions/statusColors'
import { actionButton, element, labeledInput } from './dom'

const POPOVER_GAP = 8
const VIEWPORT_MARGIN = 8
const DEFAULT_STATUS_LABEL = 'Статус'

let closeCurrent: (() => void) | null = null

/** Небольшое окошко у выделения: закрывается по Escape и щелчку мимо. */
export function showPopover(anchor: DOMRect, build: (container: HTMLElement, close: () => void) => void): void {
  closeCurrent?.()
  const container = element('div', 'folio-popover')
  container.setAttribute('role', 'dialog')

  const onKeyDown = (event: KeyboardEvent) => {
    if (event.key !== 'Escape') return
    event.preventDefault()
    event.stopPropagation()
    close()
  }
  const onPointerDown = (event: MouseEvent) => {
    if (!container.contains(event.target as Node)) close()
  }
  const close = () => {
    container.remove()
    document.removeEventListener('keydown', onKeyDown, true)
    document.removeEventListener('mousedown', onPointerDown, true)
    if (closeCurrent === close) closeCurrent = null
  }

  build(container, close)
  document.body.append(container)
  const height = container.offsetHeight
  const below = anchor.bottom + POPOVER_GAP
  const top = below + height > window.innerHeight ? anchor.top - POPOVER_GAP - height : below
  const left = Math.min(anchor.left, window.innerWidth - container.offsetWidth - VIEWPORT_MARGIN)
  container.style.top = `${Math.max(VIEWPORT_MARGIN, top)}px`
  container.style.left = `${Math.max(VIEWPORT_MARGIN, left)}px`

  document.addEventListener('keydown', onKeyDown, true)
  document.addEventListener('mousedown', onPointerDown, true)
  closeCurrent = close
  container.querySelector<HTMLInputElement>('input')?.focus()
}

export function selectionRect(editor: Editor): DOMRect {
  const { from, to } = editor.state.selection
  const start = editor.view.coordsAtPos(from)
  const end = editor.view.coordsAtPos(to)
  const top = Math.min(start.top, end.top)
  return new DOMRect(start.left, top, Math.max(end.right - start.left, 1), Math.max(start.bottom, end.bottom) - top)
}

/** Адрес без протокола вроде `example.com` дополняется `https://`; пути к файлам остаются как есть. */
export function normalizeHref(value: string): string {
  const trimmed = value.trim()
  if (!trimmed) return ''
  if (/^[a-z][a-z0-9+.-]*:/i.test(trimmed) || trimmed.startsWith('#')) return trimmed
  const looksLikeDomain = /^[^\s/]+\.[a-zа-я]{2,}(\/|$)/i.test(trimmed)
  const looksLikeFile = /\.(md|png|jpe?g|gif|webp|svg|pdf|docx?|xlsx?|pptx?|txt|csv|zip)$/i.test(trimmed)
  return looksLikeDomain && !looksLikeFile ? `https://${trimmed}` : trimmed
}

export function openLinkPopover(editor: Editor): void {
  if (!editor.isEditable) return
  const currentHref = String(editor.getAttributes('link').href ?? '')

  showPopover(selectionRect(editor), (container, close) => {
    const form = element('form', 'folio-popover-form')
    const input = labeledInput('Адрес ссылки', currentHref, 'https://… или файл рядом со страницей')
    const actions = element('div', 'folio-popover-actions')
    if (currentHref) {
      actions.append(
        actionButton('Убрать ссылку', 'folio-button folio-button-danger', () => {
          editor.chain().focus().extendMarkRange('link').unsetLink().run()
          close()
        }),
      )
    }
    const submit = element('button', 'folio-button folio-button-primary', 'Готово')
    submit.type = 'submit'
    actions.append(submit)
    form.append(input.label, actions)
    form.addEventListener('submit', (event) => {
      event.preventDefault()
      applyLink(editor, input.field.value)
      close()
    })
    container.append(form)
  })
}

function applyLink(editor: Editor, value: string): void {
  const href = normalizeHref(value)
  if (!href) {
    editor.chain().focus().extendMarkRange('link').unsetLink().run()
    return
  }
  if (editor.state.selection.empty && !editor.isActive('link')) {
    editor.chain().focus().insertContent({ type: 'text', text: href, marks: [{ type: 'link', attrs: { href } }] }).run()
    return
  }
  editor.chain().focus().extendMarkRange('link').setLink({ href }).run()
}

export function openStatusPopover(editor: Editor, position: number, anchor: DOMRect): void {
  const node = editor.state.doc.nodeAt(position)
  if (!editor.isEditable || !node || node.type.name !== 'status') return

  showPopover(anchor, (container, close) => {
    let color = normalizeStatusColor(node.attrs.color)
    const form = element('form', 'folio-popover-form')
    const input = labeledInput('Текст статуса', String(node.attrs.label ?? ''), 'Например, В работе')
    const swatches = element('div', 'folio-swatches')

    const update = () => {
      const current = editor.state.doc.nodeAt(position)
      if (!current || current.type.name !== 'status') return
      const label = input.field.value.replace(/[[\]\n]/g, '').trim() || DEFAULT_STATUS_LABEL
      editor.view.dispatch(editor.state.tr.setNodeMarkup(position, undefined, { ...current.attrs, label, color }))
    }

    const buttons = STATUS_COLORS.map((option) => {
      const swatch = actionButton(STATUS_COLOR_NAMES[option], `folio-swatch status status-${option}`, () => {
        color = option
        buttons.forEach((button, index) => button.setAttribute('aria-pressed', String(STATUS_COLORS[index] === color)))
        update()
      })
      swatch.setAttribute('aria-pressed', String(option === color))
      return swatch
    })
    swatches.append(...buttons)
    input.field.addEventListener('input', update)

    const actions = element('div', 'folio-popover-actions')
    actions.append(
      actionButton('Удалить', 'folio-button folio-button-danger', () => {
        const current = editor.state.doc.nodeAt(position)
        if (current?.type.name === 'status') {
          editor.view.dispatch(editor.state.tr.delete(position, position + current.nodeSize))
        }
        close()
        editor.commands.focus()
      }),
    )
    const submit = element('button', 'folio-button folio-button-primary', 'Готово')
    submit.type = 'submit'
    actions.append(submit)

    form.append(input.label, swatches, actions)
    form.addEventListener('submit', (event) => {
      event.preventDefault()
      update()
      close()
      editor.commands.focus()
    })
    container.append(form)
  })
}
