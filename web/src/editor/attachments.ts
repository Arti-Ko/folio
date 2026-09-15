import { Extension } from '@tiptap/core'
import { Plugin, PluginKey } from '@tiptap/pm/state'
import { insertAttachments, type AttachmentItem } from './commands'

/** Сохраняет файл рядом со страницей и возвращает относительный путь; реализует приложение. */
export interface AttachmentUploader {
  save: (file: File) => Promise<AttachmentItem | null>
}

function filesOf(transfer: DataTransfer | null): File[] {
  return transfer ? Array.from(transfer.files) : []
}

/** Вставка картинок и файлов из буфера и перетаскиванием. */
export const Attachments = Extension.create<{ uploader: AttachmentUploader | null }>({
  name: 'attachments',

  addOptions() {
    return { uploader: null }
  },

  addProseMirrorPlugins() {
    const { editor } = this
    const { uploader } = this.options
    if (!uploader) return []

    const upload = async (files: File[], position: number) => {
      const saved = await Promise.all(files.map((file) => uploader.save(file)))
      insertAttachments(
        editor,
        saved.filter((item): item is AttachmentItem => item !== null),
        position,
      )
    }

    return [
      new Plugin({
        key: new PluginKey('attachments'),
        props: {
          handlePaste: (view, event) => {
            const files = filesOf(event.clipboardData)
            if (files.length === 0 || !editor.isEditable) return false
            void upload(files, view.state.selection.from)
            return true
          },
          handleDrop: (view, event) => {
            const files = filesOf(event.dataTransfer)
            if (files.length === 0 || !editor.isEditable) return false
            const position = view.posAtCoords({ left: event.clientX, top: event.clientY })?.pos ?? view.state.selection.from
            void upload(files, position)
            return true
          },
        },
      }),
    ]
  },
})
