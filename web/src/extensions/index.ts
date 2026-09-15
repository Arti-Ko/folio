import type { AnyExtension } from '@tiptap/core'
import { TableKit } from '@tiptap/extension-table'
import { TaskItem, TaskList } from '@tiptap/extension-list'
import { Markdown } from '@tiptap/markdown'
import StarterKit from '@tiptap/starter-kit'
import { Expand } from './expand'
import { FolioContext } from './folioContext'
import { FolioImage } from './folioImage'
import { ChildPages, TableOfContents } from './pageBlocks'
import { Panel } from './panel'
import { Status } from './status'
import { WikiLink } from './wikiLink'

export function createExtensions(): AnyExtension[] {
  return [
    StarterKit.configure({
      link: { openOnClick: false, autolink: true },
    }),
    TableKit.configure({ table: { resizable: false } }),
    TaskList,
    TaskItem.configure({ nested: true }),
    FolioContext,
    FolioImage,
    Panel,
    Expand,
    Status,
    WikiLink,
    TableOfContents,
    ChildPages,
    Markdown,
  ]
}
