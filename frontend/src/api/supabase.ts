import { createClient } from '@supabase/supabase-js'
import { mockSupabase } from '@/mock/index'

// Mock 模式：开发环境默认启用，不需要真实 Supabase
// 切换方式：浏览器控制台 localStorage.setItem('USE_MOCK', 'false') 后刷新
/**
 * 计算当前是否走本地 Mock 后端。
 * 优先级：生产构建 < USE_MOCK 开关 < VITE_USE_REAL_SUPABASE。
 * @returns boolean true=用 Mock，false=连真实 Supabase
 */
const USE_MOCK = (() => {
  if (import.meta.env.PROD) return localStorage.getItem('USE_MOCK') === 'true'
  if (import.meta.env.VITE_USE_REAL_SUPABASE === 'true') return false
  return localStorage.getItem('USE_MOCK') !== 'false'
})()

/**
 * 全局唯一的 Supabase 客户端；Mock 模式下换成 mockSupabase，业务代码无需分支。
 *
 * 坑：离线包的前端镜像在 build 时就把 VITE_SUPABASE_URL 与 anon key 烧进了 JS 产物，
 * 而 anon key 是由 .env 的 JWT_SECRET 签发的——重新随机生成 .env 会让前后端密钥对不上，
 * 所有请求 401。离线场景必须沿用包内那份 .env（且不能带 BOM）。
 */
const supabase = ((): any => {
  if (USE_MOCK) {
    console.info('[mock] 使用本地 Mock 数据后端')
    return mockSupabase
  }
  // 生产环境：跟随浏览器地址栏自动指向同机 Kong(8000)，
  // 这样无论用 127.0.0.1 还是局域网 IP 访问都能正常调用 API
  const url = import.meta.env.PROD
    ? `${window.location.protocol}//${window.location.hostname}:8000`
    : import.meta.env.VITE_SUPABASE_URL
  const key = import.meta.env.VITE_SUPABASE_ANON_KEY
  if (!url || !key) {
    throw new Error(
      '请在 .env.local 中配置 VITE_SUPABASE_URL 和 VITE_SUPABASE_ANON_KEY',
    )
  }
  return createClient(url, key, {
    auth: { persistSession: true, autoRefreshToken: true },
  })
})()

export { supabase }
export default supabase