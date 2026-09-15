export const STATUS_COLORS = ['grey', 'blue', 'green', 'yellow', 'red', 'purple'] as const
export type StatusColor = (typeof STATUS_COLORS)[number]

export const STATUS_COLOR_NAMES: Record<StatusColor, string> = {
  grey: 'Серый',
  blue: 'Синий',
  green: 'Зелёный',
  yellow: 'Жёлтый',
  red: 'Красный',
  purple: 'Фиолетовый',
}

export function normalizeStatusColor(value: unknown): StatusColor {
  return typeof value === 'string' && (STATUS_COLORS as readonly string[]).includes(value)
    ? (value as StatusColor)
    : 'grey'
}
