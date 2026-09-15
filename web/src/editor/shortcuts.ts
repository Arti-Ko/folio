import { Extension } from '@tiptap/core'
import { runCommand } from './commands'
import { openLinkPopover } from './popover'

/** Сочетания, которых нет в TipTap из коробки. */
export const EditorShortcuts = Extension.create({
  name: 'editorShortcuts',

  addKeyboardShortcuts() {
    return {
      'Mod-k': () => {
        if (!this.editor.isEditable) return false
        openLinkPopover(this.editor)
        return true
      },
      'Alt-Shift-ArrowUp': () => runCommand(this.editor, 'moveBlockUp'),
      'Alt-Shift-ArrowDown': () => runCommand(this.editor, 'moveBlockDown'),
    }
  },
})
