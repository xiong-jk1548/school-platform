<script setup lang="ts">
import { ref, onMounted, computed } from 'vue'
import { ElMessage } from 'element-plus'
import { Trophy } from '@element-plus/icons-vue'
import { supabase } from '@/api/supabase'
import { useUserStore } from '@/stores/user'

const userStore = useUserStore()

interface StudentRow {
  id: string
  student_name: string
  name?: string
  total_score: number
}

const students = ref<StudentRow[]>([])
const loading = ref(false)
const topN = ref(10)

/**
 * 按总积分倒序加载本班学生（最多 50 条），并兼容 name 字段补齐 student_name
 * @returns 无返回值（副作用：写入 students，并在 finally 中复位 loading）
 */
async function loadStudents() {
  if (!userStore.classId) return
  loading.value = true
  try {
    const { data: studentRows, error } = await supabase
      .from('students')
      .select('id, student_name, total_score')
      .eq('class_id', userStore.classId)
      .order('total_score', { ascending: false })
      .limit(50)
    if (error) throw error
    const rankedStudents = (studentRows ?? []) as StudentRow[]
    rankedStudents.forEach((student: any) => { if (!student.student_name && student.name) student.student_name = student.name })
    students.value = rankedStudents
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '加载排行榜失败')
  } finally {
    loading.value = false
  }
}

const topList = computed(() => students.value.slice(0, topN.value))
const rankBgColors = ['#ffd700', '#c0c0c0', '#cd7f32']

onMounted(loadStudents)
</script>

<template>
  <el-card>
    <template #header>
      <div class="card-header">
        <div class="header-left">
          <Trophy class="header-icon" />
          <span class="header-title">{{ userStore.className || '本班' }} 积分排行榜</span>
        </div>
        <el-select v-model="topN" style="width: 100px">
          <el-option :value="5" label="前 5 名" />
          <el-option :value="10" label="前 10 名" />
          <el-option :value="20" label="前 20 名" />
        </el-select>
      </div>
    </template>

    <el-table :data="topList" v-loading="loading" stripe style="width: 100%">
      <el-table-column label="排名" width="100" align="center">
        <template #default="{ $index }">
          <span
            v-if="$index < 3"
            class="rank-medal"
            :style="{ background: rankBgColors[$index] }"
          >{{ $index + 1 }}</span>
          <span v-else class="rank-num">{{ $index + 1 }}</span>
        </template>
      </el-table-column>
      <el-table-column prop="student_name" label="姓名" min-width="140">
        <template #default="{ row: studentRow }">{{ studentRow.student_name || studentRow.name }}</template>
      </el-table-column>
      <el-table-column label="总积分" min-width="120" align="center">
        <template #default="{ row: studentRow }">
          <el-tag :type="(studentRow.total_score ?? 0) >= 0 ? 'success' : 'danger'" size="large" effect="dark">
            {{ studentRow.total_score ?? 0 }}
          </el-tag>
        </template>
      </el-table-column>
    </el-table>
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
.rank-medal {
  display: inline-block;
  width: 32px;
  height: 32px;
  line-height: 32px;
  border-radius: 50%;
  color: #fff;
  font-weight: 700;
  font-size: 14px;
}
.rank-num {
  display: inline-block;
  width: 32px;
  height: 32px;
  line-height: 32px;
  border-radius: 50%;
  background: #f0f0f0;
  color: #606266;
  font-weight: 600;
  font-size: 14px;
}
</style>
