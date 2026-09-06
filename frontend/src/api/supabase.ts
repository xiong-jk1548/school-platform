import { createClient } from '@supabase/supabase-js'
import { mockSupabase } from '@/mock/index'

// Mock 模式：开发环境默认启用，不需要真实 Supabase
// 切换方式：浏览器控制台 localStorage.setItem('USE_MOCK', 'false') 后刷新
const USE_MOCK = (() => {
  if (import.meta.env.PROD) return localStorage.getItem('USE_MOCK') === 'true'
  if (import.meta.env.VITE_USE_REAL_SUPABASE === 'true') return false
  return localStorage.getItem('USE_MOCK') !== 'false'
})()

const supabase = ((): any => {
  if (USE_MOCK) {
    console.info('[mock] 使用本地 Mock 数据后端')
    return mockSupabase
  }
  const url = import.meta.env.VITE_SUPABASE_URL
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
