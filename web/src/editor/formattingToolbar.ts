import type { Editor } from '@tiptap/core'
import { runCommand } from './commands'
import { element, strokeIcon } from './dom'
import { openLinkPopover } from './popover'

interface ToolbarSpec {
  command: string
  label: string
  glyph: string | string[]
  className?: string
}

const SPECS: ToolbarSpec[] = [
  { command: 'bold', label: 'Жирный', glyph: 'B', className: 'is-bold' },
  { command: 'italic', label: 'Курсив', glyph: 'I', className: 'is-italic' },
  { command: 'strike', label: 'Зачёркнутый', glyph: 'S', className: 'is-strike' },
  { command: 'code', label: 'Код', glyph: ['M5.5 4.5 2 8l3.5 3.5', 'M10.5 4.5 14 8l-3.5 3.5'] },
  {
    command: 'link',
    label: 'Ссылка',
    glyph: ['M6.5 9.5l3-3', 'M7 4.5l1-1a2.5 2.5 0 0 1 3.5 3.5l-1 1', 'M9 11.5l-1 1a2.5 2.5 0 0 1-3.5-3.5l1-1'],
  },
]

export interface FormattingToolbar {
  element: HTMLElement
  bind: (editor: Editor) => void
}

/** Плавающая панель над выделенным текстом. */
export function createFormattingToolbar(): FormattingToolbar {
  const toolbar = element('div', 'folio-toolbar')
  toolbar.setAttribute('role', 'toolbar')
  toolbar.setAttribute('aria-label', 'Форматирование')
  let editor: Editor | null = null

  const buttons = SPECS.map((spec) => {
    const button = element('button', `folio-toolbar-button ${spec.className ?? ''}`.trim())
    button.type = 'button'
    button.title = spec.label
    button.setAttribute('aria-label', spec.label)
    if (typeof spec.glyph === 'string') {
      button.textContent = spec.glyph
    } else {
      button.append(strokeIcon(spec.glyph))
    }
    button.addEventListener('mousedown', (event) => event.preventDefault())
    button.addEventListener('click', () => {
      if (!editor) return
      if (spec.command === 'link') {
        openLinkPopover(editor)
      } else {
        runCommand(editor, spec.command)
      }
    })
    toolbar.append(button)
    return { spec, button }
  })

  const refresh = () => {
    if (!editor) return
    for (const { spec, button } of buttons) {
      button.setAttribute('aria-pressed', String(editor.isActive(spec.command)))
    }
  }

  return {
    element: toolbar,
    bind: (next) => {
      editor = next
      next.on('transaction', refresh)
    },
  }
}
