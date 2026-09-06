<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useUserStore } from '@/stores/user'
import { supabase } from '@/api/supabase'
import {
  School,
  User,
  Reading,
  TrendCharts,
  DataAnalysis,
  UserFilled,
  OfficeBuilding,
} from '@element-plus/icons-vue'

const router = useRouter()
const userStore = useUserStore()

const summary = ref({
  schoolCount: 0,
  schoolAdminCount: 0,
  teacherCount: 0,
  studentCount: 0,
})

const quickLinks = [
  { path: '/admin-edu/schools', title: '学校管理', desc: '维护区域内学校信息', icon: School, color: '#1E6FD9' },
  { path: '/admin-edu/points-config', title: '管理员账号', desc: '创建学校管理员账号', icon: UserFilled, color: '#722ed1' },
  { path: '/admin-edu/reports', title: '统计报表', desc: '查看全区积分统计', icon: DataAnalysis, color: '#fa8c16' },
]

async function loadData() {
  try {
    const [
      { count: sc },
      { count: sac },
      { count: tc },
      { count: stc },
    ] = await Promise.all([
      supabase.from('schools').select('*', { count: 'exact', head: true }),
      supabase
        .from('profiles')
        .select('*', { count: 'exact', head: true })
        .eq('role', 'school_admin'),
      supabase
        .from('profiles')
        .select('*', { count: 'exact', head: true })
        .eq('role', 'teacher'),
      supabase.from('students').select('*', { count: 'exact', head: true }),
    ])
    summary.value = {
      schoolCount: sc ?? 0,
      schoolAdminCount: sac ?? 0,
      teacherCount: tc ?? 0,
      studentCount: stc ?? 0,
    }
  } catch {
    /* 静默失败 */
  }
}

function goTo(path: string) {
  router.push(path)
}

onMounted(loadData)
</script>

<template>
  <div class="page">
    <el-card shadow="never" class="welcome-card">
      <div class="welcome-inner">
        <div class="welcome-left">
          <div class="welcome-greeting">
            您好，{{ userStore.name ?? userStore.email ?? '教育局管理员' }}
          </div>
          <div class="welcome-sub">欢迎回到多校学生积分管理平台</div>
        </div>
        <div class="welcome-right">
          <el-icon :size="48" color="#1E6FD9"><OfficeBuilding /></el-icon>
        </div>
      </div>
    </el-card>

    <div class="stat-row">
      <div class="stat-item">
        <div class="stat-icon" style="background: #eaf3ff; color: #1E6FD9">
          <el-icon :size="24"><School /></el-icon>
        </div>
        <div class="stat-detail">
          <div class="stat-num">{{ summary.schoolCount }}</div>
          <div class="stat-label">学校数</div>
        </div>
      </div>
      <div class="stat-item">
        <div class="stat-icon" style="background: #f3e8ff; color: #722ed1">
          <el-icon :size="24"><User /></el-icon>
        </div>
        <div class="stat-detail">
          <div class="stat-num">{{ summary.schoolAdminCount }}</div>
          <div class="stat-label">学校管理员</div>
        </div>
      </div>
      <div class="stat-item">
        <div class="stat-icon" style="background: #e6fffb; color: #13c2c2">
          <el-icon :size="24"><Reading /></el-icon>
        </div>
        <div class="stat-detail">
          <div class="stat-num">{{ summary.teacherCount }}</div>
          <div class="stat-label">教师数</div>
        </div>
      </div>
      <div class="stat-item">
        <div class="stat-icon" style="background: #fff7e6; color: #fa8c16">
          <el-icon :size="24"><TrendCharts /></el-icon>
        </div>
        <div class="stat-detail">
          <div class="stat-num">{{ summary.studentCount }}</div>
          <div class="stat-label">学生数</div>
        </div>
      </div>
    </div>

    <el-card shadow="never">
      <template #header>
        <span>快捷操作</span>
      </template>
      <div class="link-grid">
        <div
          v-for="link in quickLinks"
          :key="link.path"
          class="link-card"
          @click="goTo(link.path)"
        >
          <div
            class="link-icon"
            :style="{ background: link.color + '1a', color: link.color }"
          >
            <el-icon :size="28"><component :is="link.icon" /></el-icon>
          </div>
          <div class="link-info">
            <div class="link-title">{{ link.title }}</div>
            <div class="link-desc">{{ link.desc }}</div>
          </div>
          <el-icon class="link-arrow"><component :is="link.icon" /></el-icon>
        </div>
      </div>
    </el-card>
  </div>
</template>

<style scoped>
.page {
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.welcome-card {
  background: linear-gradient(135deg, #1E6FD9 0%, #4A90E2 100%);
  border: none;
  color: #fff;
}

.welcome-card :deep(.el-card__body) {
  padding: 28px 32px;
}

.welcome-inner {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.welcome-greeting {
  font-size: 22px;
  font-weight: 600;
}

.welcome-sub {
  margin-top: 8px;
  font-size: 14px;
  opacity: 0.9;
}

.stat-row {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 16px;
}

.stat-item {
  background: #fff;
  padding: 20px;
  border-radius: 8px;
  display: flex;
  align-items: center;
  gap: 16px;
  box-shadow: 0 1px 4px rgba(0, 21, 41, 0.05);
}

.stat-icon {
  width: 48px;
  height: 48px;
  border-radius: 10px;
  display: flex;
  align-items: center;
  justify-content: center;
}

.stat-num {
  font-size: 24px;
  font-weight: 700;
  color: #303133;
}

.stat-label {
  font-size: 13px;
  color: #909399;
  margin-top: 2px;
}

.link-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 16px;
}

.link-card {
  display: flex;
  align-items: center;
  gap: 14px;
  padding: 18px 20px;
  border: 1px solid #ebeef5;
  border-radius: 8px;
  cursor: pointer;
  transition: all 0.2s;
}

.link-card:hover {
  border-color: #1E6FD9;
  box-shadow: 0 4px 12px rgba(30, 111, 217, 0.15);
  transform: translateY(-2px);
}

.link-icon {
  width: 48px;
  height: 48px;
  border-radius: 10px;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}

.link-info {
  flex: 1;
  min-width: 0;
}

.link-title {
  font-size: 15px;
  font-weight: 600;
  color: #303133;
}

.link-desc {
  font-size: 12px;
  color: #909399;
  margin-top: 4px;
}

.link-arrow {
  color: #c0c4cc;
}
</style>
