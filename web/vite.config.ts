import { defineConfig } from 'vite'

// Сборка грузится из бандла приложения по схеме folio://app/, поэтому пути относительные.
export default defineConfig({
  base: './',
  build: {
    outDir: 'dist',
    emptyOutDir: true,
    assetsInlineLimit: 0,
    chunkSizeWarningLimit: 2000,
  },
})
