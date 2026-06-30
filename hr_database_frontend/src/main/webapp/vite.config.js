import { defineConfig, loadEnv } from 'vite'
import react from '@vitejs/plugin-react'

// https://vitejs.dev/config/
export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '')
  return {
    plugins: [react()],
    // In dev mode, proxy /api to the Quarkus backend so CORS is never needed
    server: {
      port: 3000,
      proxy: {
        '/api': {
          target: env.VITE_HR_API_URL || 'http://localhost:8088',
          changeOrigin: true,
        },
      },
    },
    // Production build: output to dist/ — Maven copies this to META-INF/resources
    build: {
      outDir: 'dist',
      emptyOutDir: true,
    },
    define: {
      // Expose the HR API base URL to the app at build time
      __HR_API_URL__: JSON.stringify(env.VITE_HR_API_URL || '/api'),
    },
  }
})
