import vue from '@vitejs/plugin-vue'
import { defineConfig } from 'vite'
import path from 'node:path'
import AutoImport from 'unplugin-auto-import/vite'
import Components from 'unplugin-vue-components/vite'
import { ElementPlusResolver } from 'unplugin-vue-components/resolvers'

/**
 * Vite 构建配置：
 * - AutoImport：自动引入 vue / vue-router / pinia 的组合式 API（ref、computed、
 *   onMounted 等）以及 Element Plus 的 ElMessage 一类函数式 API，声明文件落到
 *   src/auto-imports.d.ts；
 * - Components：自动按需注册模板里用到的 Element Plus 组件，声明文件落到
 *   src/components.d.ts。这两个 dts 由插件生成，不要手改。
 * - resolve.alias：'@' 映射到 src，全项目统一用 '@/xxx' 引用，避免相对路径过深。
 */
export default defineConfig({
  plugins: [
    vue(),
    AutoImport({
      resolvers: [ElementPlusResolver()],
      imports: ['vue', 'vue-router', 'pinia'],
      dts: 'src/auto-imports.d.ts',
    }),
    Components({
      resolvers: [ElementPlusResolver()],
      dts: 'src/components.d.ts',
    }),
  ],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, 'src'),
    },
  },
})
