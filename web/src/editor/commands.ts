import type { Editor, JSONContent } from '@tiptap/core'
import { TextSelection } from '@tiptap/pm/state'
import { isPanelType } from '../extensions/panel'
import { normalizeStatusColor } from '../extensions/statusColors'
import { openLinkPopover, openStatusPopover } from './popover'

export type CommandArgs = Record<string, unknown>
type CommandHandler = (editor: Editor, args: CommandArgs) => boolean

export interface AttachmentItem {
  path: string
  name: string
  isImage: boolean
}

/** Просьба к приложению: системный выбор файла веб-часть открыть не может. */
export const NATIVE_REQUEST_EVENT = 'folio:native-request'

const DEFAULT_STATUS_LABEL = 'Статус'
const TABLE_SIZE = 3

function focused(editor: Editor) {
  return editor.chain().focus()
}

const COMMANDS: Record<string, CommandHandler> = {
  undo: (editor) => focused(editor).undo().run(),
  redo: (editor) => focused(editor).redo().run(),

  paragraph: (editor) => focused(editor).setParagraph().run(),
  heading1: (editor) => focused(editor).toggleHeading({ level: 1 }).run(),
  heading2: (editor) => focused(editor).toggleHeading({ level: 2 }).run(),
  heading3: (editor) => focused(editor).toggleHeading({ level: 3 }).run(),
  blockquote: (editor) => focused(editor).toggleBlockquote().run(),
  codeBlock: (editor) => focused(editor).toggleCodeBlock().run(),
  horizontalRule: (editor) => focused(editor).setHorizontalRule().run(),

  bold: (editor) => focused(editor).toggleBold().run(),
  italic: (editor) => focused(editor).toggleItalic().run(),
  strike: (editor) => focused(editor).toggleStrike().run(),
  code: (editor) => focused(editor).toggleCode().run(),
  link: (editor) => {
    openLinkPopover(editor)
    return true
  },
  clearFormatting: (editor) => focused(editor).unsetAllMarks().clearNodes().run(),

  bulletList: (editor) => focused(editor).toggleBulletList().run(),
  orderedList: (editor) => focused(editor).toggleOrderedList().run(),
  taskList: (editor) => focused(editor).toggleTaskList().run(),

  insertTable: (editor) => focused(editor).insertTable({ rows: TABLE_SIZE, cols: TABLE_SIZE, withHeaderRow: true }).run(),
  addRowBefore: (editor) => focused(editor).addRowBefore().run(),
  addRowAfter: (editor) => focused(editor).addRowAfter().run(),
  addColumnBefore: (editor) => focused(editor).addColumnBefore().run(),
  addColumnAfter: (editor) => focused(editor).addColumnAfter().run(),
  deleteRow: (editor) => focused(editor).deleteRow().run(),
  deleteColumn: (editor) => focused(editor).deleteColumn().run(),
  toggleHeaderRow: (editor) => focused(editor).toggleHeaderRow().run(),
  deleteTable: (editor) => focused(editor).deleteTable().run(),

  insertPanel: (editor, args) => insertPanel(editor, args.type),
  insertExpand: (editor) => focused(editor).insertContent(wrapper('expand', { title: '' })).run(),
  insertStatus: (editor, args) => insertStatus(editor, args),
  insertToc: (editor) => focused(editor).insertContent({ type: 'tableOfContents' }).run(),
  insertChildren: (editor) => focused(editor).insertContent({ type: 'childPages' }).run(),
  insertPageLink: (editor, args) => insertPageLink(editor, args),
  insertAttachments: (editor, args) => insertAttachments(editor, parseAttachments(args.items)),
  requestAttachment: () => {
    window.dispatchEvent(new CustomEvent(NATIVE_REQUEST_EVENT, { detail: { type: 'pickAttachment' } }))
    return true
  },

  moveBlockUp: (editor) => moveBlock(editor, -1),
  moveBlockDown: (editor) => moveBlock(editor, 1),
}

export function runCommand(editor: Editor, name: string, args: CommandArgs = {}): boolean {
  const handler = COMMANDS[name]
  if (!handler || !editor.isEditable) return false
  return handler(editor, args)
}

function wrapper(type: string, attrs: Record<string, unknown>): JSONContent {
  return { type, attrs, content: [{ type: 'paragraph' }] }
}

function insertPanel(editor: Editor, type: unknown): boolean {
  const attrs = { type: isPanelType(type) ? type : 'info', title: '' }
  if (!editor.state.selection.empty) {
    return focused(editor).wrapIn('panel', attrs).run()
  }
  return focused(editor).insertContent(wrapper('panel', attrs)).run()
}

function insertStatus(editor: Editor, args: CommandArgs): boolean {
  const label = typeof args.label === 'string' && args.label.trim() ? args.label.trim() : DEFAULT_STATUS_LABEL
  const inserted = focused(editor)
    .insertContent({ type: 'status', attrs: { label, color: normalizeStatusColor(args.color) } })
    .run()
  if (!inserted || args.silent === true) return inserted

  // Сразу предлагаем подписать статус: он стоит прямо перед курсором.
  const position = editor.state.selection.from - 1
  requestAnimationFrame(() => {
    const dom = editor.view.nodeDOM(position)
    if (dom instanceof HTMLElement) openStatusPopover(editor, position, dom.getBoundingClientRect())
  })
  return true
}

function insertPageLink(editor: Editor, args: CommandArgs): boolean {
  if (typeof args.title === 'string' && args.title.trim()) {
    const space = typeof args.space === 'string' && args.space.trim() ? args.space.trim() : null
    return focused(editor)
      .insertContent([
        { type: 'wikiLink', attrs: { space, title: args.title.trim(), label: null } },
        { type: 'text', text: ' ' },
      ])
      .run()
  }
  // Без заголовка ставим «[[» — это открывает подсказку страниц.
  return focused(editor).insertContent({ type: 'text', text: '[[' }).run()
}

function parseAttachments(value: unknown): AttachmentItem[] {
  if (typeof value !== 'string') return []
  try {
    const parsed: unknown = JSON.parse(value)
    return Array.isArray(parsed) ? parsed.filter(isAttachmentItem) : []
  } catch {
    return []
  }
}

function isAttachmentItem(value: unknown): value is AttachmentItem {
  if (typeof value !== 'object' || value === null) return false
  const item = value as Record<string, unknown>
  return typeof item.path === 'string' && typeof item.name === 'string' && typeof item.isImage === 'boolean'
}

export function attachmentContent(item: AttachmentItem): JSONContent {
  if (item.isImage) {
    return { type: 'image', attrs: { src: item.path, alt: item.name.replace(/\.[^.]+$/, '') } }
  }
  return { type: 'text', text: item.name, marks: [{ type: 'link', attrs: { href: item.path } }] }
}

export function insertAttachments(editor: Editor, items: AttachmentItem[], position?: number): boolean {
  if (items.length === 0) return false
  const content = items.flatMap((item) => [attachmentContent(item), { type: 'text', text: ' ' }])
  if (position === undefined) return focused(editor).insertContent(content).run()
  const safePosition = Math.min(position, editor.state.doc.content.size)
  return focused(editor).insertContentAt(safePosition, content).run()
}

/** Меняет местами блок верхнего уровня под курсором и соседний. */
function moveBlock(editor: Editor, direction: -1 | 1): boolean {
  const { state } = editor
  const { $from } = state.selection
  if ($from.depth < 1) return false

  const index = $from.index(0)
  const targetIndex = index + direction
  if (targetIndex < 0 || targetIndex >= state.doc.childCount) return false

  const node = state.doc.child(index)
  const neighbour = state.doc.child(targetIndex)
  const start = $from.before(1)
  const offset = state.selection.from - start
  const insertAt = direction === -1 ? start - neighbour.nodeSize : start + neighbour.nodeSize

  const tr = state.tr.delete(start, start + node.nodeSize).insert(insertAt, node)
  tr.setSelection(TextSelection.near(tr.doc.resolve(Math.min(insertAt + offset, tr.doc.content.size))))
  editor.view.dispatch(tr.scrollIntoView())
  return true
}
