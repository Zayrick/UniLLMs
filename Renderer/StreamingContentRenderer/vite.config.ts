import { defineConfig } from 'vite'
import react, { reactCompilerPreset } from '@vitejs/plugin-react'
import babel from '@rolldown/plugin-babel'
import { fileURLToPath } from 'node:url'

function webViewFileScriptPlugin() {
  return {
    name: 'webview-file-script',
    apply: 'build' as const,
    enforce: 'post' as const,
    transformIndexHtml(html: string) {
      return html
        .replace(/<script type="module" crossorigin src=/g, '<script defer src=')
        .replace(/<script type="module" src=/g, '<script defer src=')
        .replace(/\s+crossorigin(?=[\s>])/g, '')
    },
  }
}

// https://vite.dev/config/
export default defineConfig({
  base: './',
  plugins: [
    react(),
    babel({ presets: [reactCompilerPreset()] }),
    webViewFileScriptPlugin(),
  ],
  build: {
    outDir: fileURLToPath(new URL('../../UniLLMs/Resources/StreamingContentRenderer', import.meta.url)),
    emptyOutDir: true,
    modulePreload: false,
    assetsDir: 'StreamingContentRendererAssets.bundle',
  },
})
