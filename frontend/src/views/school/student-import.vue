<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { ElMessage } from 'element-plus'
import { Upload, Check, Download } from '@element-plus/icons-vue'
import * as XLSX from 'xlsx'
import { supabase } from '@/api/supabase'
import { useUserStore } from '@/stores/user'

const userStore = useUserStore()

interface ClassOpt {
  id: string
  name: string
}

interface ParsedStudent {
  name: string
  student_no: string
  status?: 'ok' | 'fail'
  reason?: string
}

interface ImportResult {
  success: number
  fail: number
  errors: { name: string; student_no: string; reason: string }[]
}

const classes = ref<ClassOpt[]>([])
const selectedClassId = ref('')
const uploading = ref(false)
const parsedRows = ref<ParsedStudent[]>([])
const importResult = ref<ImportResult | null>(null)

async function loadClasses() {
  if (!userStore.schoolId) return
  try {
    const { data, error } = await supabase
      .from('classes')
      .select('id, name')
      .eq('school_id', userStore.schoolId)
      .order('name', { ascending: true })
    if (error) throw error
    classes.value = (data ?? []) as ClassOpt[]
    if (classes.value.length > 0 && !selectedClassId.value) {
      selectedClassId.value = classes.value[0].id
    }
  } catch (err: any) {
    ElMessage.error(err.message || '加载班级列表失败')
  }
}

function downloadTemplate() {
  const wb = XLSX.utils.book_new()
  const data = [
    ['序号', '学生姓名', '学号', '备注'],
    ['1', '张三', '2024001', ''],
    ['2', '李四', '2024002', ''],
  ]
  XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet(data), '学生名单')
  XLSX.writeFile(wb, '学生导入模板.xlsx')
}

function beforeUpload(file: File) {
  const valid = file.name.endsWith('.xlsx') || file.name.endsWith('.xls')
  if (!valid) {
    ElMessage.error('请上传 Excel 文件（.xlsx / .xls）')
    return false
  }
  importResult.value = null
  file
    .arrayBuffer()
    .then((buf) => {
      const wb = XLSX.read(buf, { type: 'array' })
      const sheet = wb.Sheets[wb.SheetNames[0]]
      const rows: any[][] = XLSX.utils.sheet_to_json(sheet, { header: 1 })
      const parsed: ParsedStudent[] = []
      for (let i = 1; i < rows.length; i++) {
        const r = rows[i]
        if (!Array.isArray(r) || r.length === 0) continue
        const name = String(r[1] ?? '').trim()
        const student_no = String(r[2] ?? '').trim()
        if (!name) continue
        parsed.push({ name, student_no })
      }
      parsedRows.value = parsed
      ElMessage.success(`解析完成，共 ${parsedRows.value.length} 条记录`)
    })
    .catch((err) => {
      ElMessage.error('Excel 解析失败：' + (err as Error).message)
    })
  return false
}

async function handleImport() {
  if (parsedRows.value.length === 0) {
    ElMessage.warning('请先上传并解析 Excel 文件')
    return
  }
  if (!selectedClassId.value) {
    ElMessage.warning('请选择目标班级')
    return
  }
  uploading.value = true
  importResult.value = null
  try {
    const payload = parsedRows.value.map((r) => ({
      name: r.name,
      student_no: r.student_no || null,
      class_id: selectedClassId.value,
      school_id: userStore.schoolId,
    }))
    const { data, error } = await supabase.from('students').insert(payload).select('student_no')
    if (error) {
      if (error.code === '23505' || (error.details && String(error.details).includes('duplicate'))) {
        const existingNos = new Set(
          (data as any[])?.map((d: any) => d.student_no).filter(Boolean) ?? [],
        )
        const errors: ImportResult['errors'] = []
        for (const r of parsedRows.value) {
          if (r.student_no && existingNos.has(r.student_no)) {
            errors.push({ name: r.name, student_no: r.student_no, reason: '学号重复' })
          }
        }
        importResult.value = {
          success: 0,
          fail: parsedRows.value.length,
          errors,
        }
        ElMessage.error(`导入全部失败：检测到 ${errors.length} 条学号重复`)
      } else {
        throw error
      }
    } else {
      importResult.value = {
        success: parsedRows.value.length,
        fail: 0,
        errors: [],
      }
      ElMessage.success(`成功导入 ${parsedRows.value.length} 条学生记录`)
      parsedRows.value = []
    }
  } catch (err: any) {
    ElMessage.error(err.message || '导入失败')
  } finally {
    uploading.value = false
  }
}

onMounted(loadClasses)
</script>

<template>
  <el-card>
    <template #header>
      <div class="card-header">
        <span>Excel 批量导入学生</span>
        <el-button :icon="Download" @click="downloadTemplate">下载导入模板</el-button>
      </div>
    </template>

    <el-alert type="info" :closable="false" style="margin-bottom: 16px">
      请使用模板格式：A 列序号、B 列学生姓名、C 列学号、D 列备注。第一行为表头，从第二行开始填写数据。
    </el-alert>

    <el-form label-width="100px" style="margin-bottom: 16px">
      <el-form-item label="目标班级">
        <el-select v-model="selectedClassId" placeholder="请选择班级" style="width: 280px">
          <el-option v-for="c in classes" :key="c.id" :label="c.name" :value="c.id" />
        </el-select>
      </el-form-item>
      <el-form-item label="上传文件">
        <el-upload
          :show-file-list="false"
          :auto-upload="false"
          :before-upload="beforeUpload"
          accept=".xlsx,.xls"
        >
          <el-button :icon="Upload">选择 Excel 文件</el-button>
        </el-upload>
      </el-form-item>
    </el-form>

    <el-divider content-position="left">预览</el-divider>

    <el-table v-if="parsedRows.length > 0" :data="parsedRows" border stripe max-height="360">
      <el-table-column type="index" label="#" width="60" />
      <el-table-column prop="name" label="学生姓名" min-width="180" />
      <el-table-column prop="student_no" label="学号" min-width="160">
        <template #default="{ row }">{{ row.student_no || '-' }}</template>
      </el-table-column>
    </el-table>
    <el-empty v-else description="请上传 Excel 文件进行预览" />

    <div v-if="importResult" style="margin: 16px 0">
      <el-alert
        v-if="importResult.success > 0"
        type="success"
        :closable="false"
        :title="`成功导入 ${importResult.success} 条`"
        show-icon
      />
      <el-alert
        v-if="importResult.fail > 0"
        type="error"
        :closable="false"
        style="margin-top: 8px"
        :title="`失败 ${importResult.fail} 条`"
        show-icon
      >
        <ul v-if="importResult.errors.length" style="margin: 4px 0 0; padding-left: 18px">
          <li
            v-for="(e, i) in importResult.errors.slice(0, 10)"
            :key="i"
            style="font-size: 12px"
          >
            {{ e.name }}（{{ e.student_no || '无学号' }}）：{{ e.reason }}
          </li>
          <li v-if="importResult.errors.length > 10" style="font-size: 12px">
            ... 还有 {{ importResult.errors.length - 10 }} 条未展示
          </li>
        </ul>
      </el-alert>
    </div>

    <div style="margin-top: 16px; text-align: right">
      <el-button
        type="primary"
        :icon="Check"
        :loading="uploading"
        :disabled="parsedRows.length === 0"
        @click="handleImport"
      >
        确认导入（{{ parsedRows.length }} 条）
      </el-button>
    </div>
  </el-card>
</template>

<style scoped>
.card-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
}
</style>
