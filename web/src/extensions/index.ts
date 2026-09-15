import type { AnyExtension } from '@tiptap/core'
import { BubbleMenu } from '@tiptap/extension-bubble-menu'
import { TableKit } from '@tiptap/extension-table'
import { TaskItem, TaskList } from '@tiptap/extension-list'
import { Placeholder } from '@tiptap/extensions'
import { Markdown } from '@tiptap/markdown'
import { TextSelection } from '@tiptap/pm/state'
import StarterKit from '@tiptap/starter-kit'
import { Attachments, type AttachmentUploader } from '../editor/attachments'
import { PageLinkSuggestion } from '../editor/pageLinkMenu'
import { EditorShortcuts } from '../editor/shortcuts'
import { SlashCommands } from '../editor/slashMenu'
import { Expand } from './expand'
import { FolioContext } from './folioContext'
import { FolioImage } from './folioImage'
import { ChildPages, TableOfContents } from './pageBlocks'
import { Panel } from './panel'
import { Status } from './status'
import { WikiLink } from './wikiLink'

export interface ExtensionOptions {
  /** Элемент плавающей панели форматирования; без него панели нет (например, в тестах). */
  bubbleMenu?: HTMLElement
  uploader?: AttachmentUploader
}

const PLACEHOLDER = 'Начните писать или введите «/», чтобы вставить элемент'

export function createExtensions(options: ExtensionOptions = {}): AnyExtension[] {
  const bubbleMenu = options.bubbleMenu
    ? [
        BubbleMenu.configure({
          element: options.bubbleMenu,
          shouldShow: ({ editor, state, from, to }) =>
            editor.isEditable && from !== to && state.selection instanceof TextSelection && !editor.isActive('codeBlock'),
          options: { placement: 'top', offset: 8 },
        }),
      ]
    : []

  return [
    // Подчёркивания нет в Markdown GitHub — не даём его поставить, чтобы файлы оставались переносимыми.
    StarterKit.configure({
      link: { openOnClick: false, autolink: true, defaultProtocol: 'https' },
      underline: false,
    }),
    TableKit.configure({ table: { resizable: false } }),
    TaskList,
    TaskItem.configure({ nested: true }),
    Placeholder.configure({ placeholder: PLACEHOLDER, showOnlyCurrent: true }),
    FolioContext,
    FolioImage,
    Panel,
    Expand,
    Status,
    WikiLink,
    TableOfContents,
    ChildPages,
    SlashCommands,
    PageLinkSuggestion,
    EditorShortcuts,
    Attachments.configure({ uploader: options.uploader ?? null }),
    ...bubbleMenu,
    Markdown,
  ]
}
