<script setup lang="ts">
import { ref, onMounted, computed, watch } from 'vue'
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
  return awards.value.filter((award) => award.level === filterLevel.value)
})

const groupedByLevel = computed(() => {
  const groupsByLevel: Record<string, AwardRow[]> = {}
  filteredAwards.value.forEach((award) => {
    const awardLevel = award.level || '其他'
    if (!groupsByLevel[awardLevel]) groupsByLevel[awardLevel] = []
    groupsByLevel[awardLevel].push(award)
  })
  return groupsByLevel
})

/**
 * 加载本班获奖记录并按学生 id 批量补齐 student_name
 * ⚠️ 必须显式按 class_id 收窄：`student_awards` 的教师读取策略是**按学校**放行的
 *（09 脚本给 teacher 的是 school_id 粒度，与 student_scores 的 class_id 粒度不同），
 * 漏掉过滤就会把全校获奖记录倒进本页 —— 即 DEPLOY-LESSONS 第 19 条「荣誉墙数据串了」。
 * 该条当时只补了注释、查询没真正加过滤，故本次重犯；同款问题在 AwardRegister.vue 一并修掉。
 * @returns 无返回值（副作用：写入 awards，并在 finally 中复位 loading）
 */
async function loadAwards() {
  if (!userStore.classId) return
  loading.value = true
  try {
    const { data: awardRows, error } = await supabase
      .from('student_awards')
      .select('*')
      .eq('class_id', userStore.classId)
      .order('award_date', { ascending: false })
    if (error) throw error

    const awardRecords = (awardRows ?? []) as AwardRow[]
    // 补齐 student_name（mock 里已有，真实后端可能没有）
    const studentIds = Array.from(new Set(awardRecords.map((award) => award.student_id)))
    if (studentIds.length > 0) {
      const { data: studentRows } = await supabase
        .from('students')
        .select('id, student_name')
        .in('id', studentIds)
      const stuMap: Record<string, string> = {}
      ;((studentRows ?? []) as any[]).forEach((student) => { stuMap[student.id] = student.student_name })
      awardRecords.forEach((award) => { if (!award.student_name) award.student_name = stuMap[award.student_id] })
    }
    awards.value = awardRecords
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '加载荣誉墙失败')
  } finally {
    loading.value = false
  }
}

/**
 * 顶栏班级下拉切换后跟随重载，避免标题显示新班级、卡片仍是旧班级的获奖记录。
 * @param classId 当前选中班级 id
 * @returns 无返回值
 */
watch(() => userStore.classId, async (classId, previousClassId) => {
  if (classId === previousClassId) return
  awards.value = []
  await loadAwards()
})

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

    <div v-for="(levelAwards, level) in groupedByLevel" :key="level" class="award-group">
      <div class="group-title">{{ level }}</div>
      <el-row :gutter="16">
        <el-col
          v-for="award in levelAwards"
          :key="award.id"
          :xs="24"
          :sm="12"
          :md="8"
          :lg="6"
          class="award-col"
        >
          <div class="award-card">
            <div class="award-title">{{ award.title }}</div>
            <div class="award-meta">
              <el-tag type="primary" effect="plain" size="small">{{ award.level }}</el-tag>
              <span class="award-date">{{ new Date(award.award_date).toLocaleDateString('zh-CN') }}</span>
            </div>
            <div class="award-student">获奖者：{{ award.student_name || '-' }}</div>
            <div v-if="award.description" class="award-desc">{{ award.description }}</div>
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
