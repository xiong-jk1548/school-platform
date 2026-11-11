import { createApp } from 'vue'
import { createPinia } from 'pinia'
import piniaPluginPersistedstate from 'pinia-plugin-persistedstate'
import ElementPlus from 'element-plus'
import 'element-plus/dist/index.css'
import * as ElementPlusIconsVue from '@element-plus/icons-vue'
import App from './App.vue'
import router from './router'
import './style.css'

/**
 * 应用入口：装配 Pinia（含持久化插件）→ 全局注册 Element Plus 图标 → 挂载 UI 库与路由。
 * @returns 无（副作用：把应用挂载到 #app）
 */
const app = createApp(App)

// 用户态（登录信息、当前班级、角色切换标记）需要跨刷新保留，所以必须挂持久化插件
const pinia = createPinia()
pinia.use(piniaPluginPersistedstate)
app.use(pinia)

// 图标按名字注册为全局组件，页面模板里可直接 <component :is="menu.icon" />
for (const [iconName, iconComponent] of Object.entries(ElementPlusIconsVue)) {
  app.component(iconName, iconComponent)
}

app.use(ElementPlus)
app.use(router)

app.mount('#app')