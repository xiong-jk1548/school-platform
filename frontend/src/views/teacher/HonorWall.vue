<script setup lang="ts">
import { ref, onMounted, computed } from 'vue'
import { ElMessage } from 'element-plus'
import { Medal } from '@element-plus/icons-vue'
import { supabase } from '@/api/supabase'
import { useUserStore } from '@/stores/user'

const userStore = useUserStore()

interface AwardRow {
  id: string
  student_id: string
  student_name?: string
  title: string
  level: string
  award_type: string
  award_date: string
  description?: string
}

const awards = ref<AwardRow[]>([])
const loading = ref(false)
const filterLevel = ref('')

const levelOptions = ['校级', '区级', '市级', '省级', '国家级', '其他']

const filteredAwards = computed(() => {
  if (!filterLevel.value) return awards.value
  return awards.value.filter((a) => a.level === filterLevel.value)
})

const groupedByLevel = computed(() => {
  const groups: Record<string, AwardRow[]> = {}
  filteredAwards.value.forEach((a) => {
    const lvl = a.level || '其他'
    if (!groups[lvl]) groups[lvl] = []
    groups[lvl].push(a)
  })
  return groups
})

async function loadAwards() {
  if (!userStore.classId) return
  loading.value = true
  try {
    const { data, error } = await supabase
      .from('student_awards')
      .select('*')
      .order('award_date', { ascending: false })
    if (error) throw error

    const rows = (data ?? []) as AwardRow[]
    // 补齐 student_name（mock 里已有，真实后端可能没有）
    const studentIds = Array.from(new Set(rows.map((r) => r.student_id)))
    if (studentIds.length > 0) {
      const { data: stuRes } = await supabase
        .from('students')
        .select('id, student_name')
        .in('id', studentIds)
      const stuMap: Record<string, string> = {}
      ;((stuRes ?? []) as any[]).forEach((s) => { stuMap[s.id] = s.student_name })
      rows.forEach((r) => { if (!r.student_name) r.student_name = stuMap[r.student_id] })
    }
    awards.value = rows
  } catch (err: any) {
    ElMessage.error(err.message || '加载荣誉墙失败')
  } finally {
    loading.value = false
  }
}

onMounted(loadAwards)
</script>

<template>
  <el-card>
    <template #header>
      <div class="card-header">
        <div class="header-left">
          <Medal class="header-icon" />
          <span class="header-title">{{ userStore.className || '本班' }} 荣誉墙</span>
        </div>
        <el-select v-model="filterLevel" placeholder="全部级别" clearable style="width: 140px">
          <el-option v-for="lvl in levelOptions" :key="lvl" :label="lvl" :value="lvl" />
        </el-select>
      </div>
    </template>

    <div v-if="filteredAwards.length === 0 && !loading" class="empty-hint">
      暂无荣誉记录，前往「获奖登记」添加吧 ✨
    </div>

    <div v-for="(list, level) in groupedByLevel" :key="level" class="award-group">
      <div class="group-title">{{ level }}</div>
      <el-row :gutter="16">
        <el-col
          v-for="item in list"
          :key="item.id"
          :xs="24"
          :sm="12"
          :md="8"
          :lg="6"
          class="award-col"
        >
          <div class="award-card">
            <div class="award-title">{{ item.title }}</div>
            <div class="award-meta">
              <el-tag type="primary" effect="plain" size="small">{{ item.level }}</el-tag>
              <span class="award-date">{{ new Date(item.award_date).toLocaleDateString('zh-CN') }}</span>
            </div>
            <div class="award-student">获奖者：{{ item.student_name || '-' }}</div>
            <div v-if="item.description" class="award-desc">{{ item.description }}</div>
          </div>
        </el-col>
      </el-row>
    </div>
  </el-card>
</template>

<style scoped>
.card-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
}
.header-left {
  display: flex;
  align-items: center;
  gap: 8px;
}
.header-icon {
  font-size: 20px;
  color: #e6a23c;
}
.header-title {
  font-size: 16px;
  font-weight: 600;
}
.empty-hint {
  text-align: center;
  color: #909399;
  padding: 40px 0;
}
.award-group {
  margin-bottom: 24px;
}
.group-title {
  font-size: 14px;
  font-weight: 600;
  color: #303133;
  margin-bottom: 12px;
  padding-left: 8px;
  border-left: 3px solid #e6a23c;
}
.award-col {
  margin-bottom: 16px;
}
.award-card {
  background: linear-gradient(135deg, #fffbe6 0%, #fff 100%);
  border: 1px solid #ffe58f;
  border-radius: 8px;
  padding: 14px;
  transition: box-shadow 0.2s;
}
.award-card:hover {
  box-shadow: 0 4px 12px rgba(230, 162, 60, 0.2);
}
.award-title {
  font-size: 15px;
  font-weight: 600;
  color: #303133;
  margin-bottom: 8px;
}
.award-meta {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 6px;
}
.award-date {
  font-size: 12px;
  color: #909399;
}
.award-student {
  font-size: 13px;
  color: #606266;
}
.award-desc {
  font-size: 12px;
  color: #909399;
  margin-top: 6px;
}
</style>
