import type { Node as ProseMirrorNode } from '@tiptap/pm/model'

export interface HeadingSummary {
  level: number
  text: string
  pos: number
}

const MAX_OUTLINE_LEVEL = 3

export function collectHeadings(doc: ProseMirrorNode): HeadingSummary[] {
  const headings: HeadingSummary[] = []
  doc.descendants((node, pos) => {
    if (node.type.name !== 'heading') return true
    const level = Number(node.attrs.level)
    const text = node.textContent.trim()
    if (level <= MAX_OUTLINE_LEVEL && text) headings.push({ level, text, pos })
    return false
  })
  return headings
}
