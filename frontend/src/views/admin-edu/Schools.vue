<script setup lang="ts">
import { ElMessage, ElMessageBox } from 'element-plus'
import type { FormInstance, FormRules } from 'element-plus'
import { ref, reactive, computed, onMounted } from 'vue'
import { supabase } from '@/api/supabase'
import { Plus, Edit, Delete, Check, Close, Search, Download, Upload } from '@element-plus/icons-vue'
import * as XLSX from 'xlsx'
import { exportToExcel } from '@/utils/excel'

interface SchoolRow {
  id: string
  name: string
  code: string
  address?: string
  contact_phone?: string
  status: 'active' | 'disabled'
  grade_range?: string[] | null
  created_at?: string
}

interface SchoolForm {
  id?: string
  name: string
  code: string
  address: string
  contact_phone: string
  status: 'active' | 'disabled'
  stage: GradeStage
}

type GradeStage = 'primary' | 'junior' | 'senior' | 'complete'

// 坑：新建学校时如果没写入 grade_range，学校端「新建班级」的年级下拉会是空白，
// 所以这里按学段预置完整年级列表，新增/编辑学校时一并写库（见“新建学校 grade_range 为空数组”）
const GRADE_PRESETS: Record<GradeStage, { label: string; grades: string[] }> = {
  primary: { label: '小学', grades: ['一年级', '二年级', '三年级', '四年级', '五年级', '六年级'] },
  junior: { label: '初中', grades: ['初一', '初二', '初三'] },
  senior: { label: '高中', grades: ['高一', '高二', '高三'] },
  complete: {
    label: '完全中学（初高中）',
    grades: ['初一', '初二', '初三', '高一', '高二', '高三'],
  },
}

/**
 * 由已有年级列表反推学校所属学段，匹配不上任何预置学段时回退为小学。
 * @param grades 学校已有的年级数组（可能为空）
 * @returns 命中的学段标识
 */
function stageFromGrades(grades?: string[] | null): GradeStage {
  if (!grades || !grades.length) return 'primary'
  const gradesSignature = JSON.stringify([...grades].sort())
  for (const stageKey of Object.keys(GRADE_PRESETS) as GradeStage[]) {
    if (JSON.stringify([...GRADE_PRESETS[stageKey].grades].sort()) === gradesSignature) {
      return stageKey
    }
  }
  return 'primary'
}

const loading = ref(false)
const tableData = ref<SchoolRow[]>([])
const searchKw = ref('')

const dialogVisible = ref(false)
const dialogTitle = ref('新增学校')
const formRef = ref<FormInstance>()
const formLoading = ref(false)
const isEdit = ref(false)

const form = reactive<SchoolForm>({
  name: '',
  code: '',
  address: '',
  contact_phone: '',
  status: 'active',
  stage: 'primary',
})

const rules = reactive<FormRules<SchoolForm>>({
  name: [{ required: true, message: '请输入学校名称', trigger: 'blur' }],
  code: [{ required: true, message: '请输入学校代码', trigger: 'blur' }],
})

const filteredData = computed(() => {
  const kw = searchKw.value.trim().toLowerCase()
  if (!kw) return tableData.value
  return tableData.value.filter(
    (school) =>
      school.name.toLowerCase().includes(kw) ||
      school.code.toLowerCase().includes(kw),
  )
})

/**
 * 加载学校列表（按创建时间倒序）。
 * @returns 无返回值，列表写入 tableData
 */
async function loadData() {
  loading.value = true
  try {
    const { data: schoolRows, error } = await supabase
      .from('schools')
      .select('*')
      .order('created_at', { ascending: false })
    if (error) throw error
    tableData.value = (schoolRows ?? []) as SchoolRow[]
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error ? err.message : '加载学校列表失败')
  } finally {
    loading.value = false
  }
}

/**
 * 打开「新增学校」弹窗，并把表单重置为默认状态（启用 / 小学）。
 * @returns 无返回值，仅切换弹窗状态
 */
function openAdd() {
  isEdit.value = false
  dialogTitle.value = '新增学校'
  Object.assign(form, {
    name: '',
    code: '',
    address: '',
    contact_phone: '',
    status: 'active' as const,
    stage: 'primary' as GradeStage,
  })
  dialogVisible.value = true
}

/**
 * 打开「编辑学校」弹窗，用选中学校回填表单，并把已有年级反推成学段。
 * @param school 表格中选中的学校记录
 * @returns 无返回值，仅切换弹窗状态
 */
function openEdit(school: SchoolRow) {
  isEdit.value = true
  dialogTitle.value = '编辑学校'
  Object.assign(form, {
    id: school.id,
    name: school.name,
    code: school.code,
    address: school.address ?? '',
    contact_phone: school.contact_phone ?? '',
    status: school.status,
    stage: stageFromGrades(school.grade_range),
  })
  dialogVisible.value = true
}

/**
 * 保存学校表单：编辑态更新已有学校，新增态插入一条学校记录；
 * 两个分支都会把「学段」映射成 grade_range 一并写库。
 * @returns 无返回值，成功后关闭弹窗并刷新列表
 */
async function handleSubmit() {
  const valid = await formRef.value?.validate().catch(() => false)
  if (!valid) return
  formLoading.value = true
  try {
    if (isEdit.value && form.id) {
      const { error } = await supabase
        .from('schools')
        .update({
          name: form.name,
          code: form.code,
          address: form.address || null,
          contact_phone: form.contact_phone || null,
          status: form.status,
          grade_range: GRADE_PRESETS[form.stage].grades,
        })
        .eq('id', form.id)
      if (error) throw error
      ElMessage.success('更新成功')
    } else {
      // 坑：schools 表早期没有 name/code 列，前端提交这两个字段会直接 400，
      // 后来库里补了同名兼容列并由 trigger 双向同步（见“新增学校 400”那次排查）
      const { error } = await supabase.from('schools').insert({
        name: form.name,
        code: form.code,
        address: form.address || null,
        contact_phone: form.contact_phone || null,
        status: form.status,
        grade_range: GRADE_PRESETS[form.stage].grades,
      })
      if (error) throw error
      ElMessage.success('新增成功')
    }
    dialogVisible.value = false
    await loadData()
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error ? err.message : '保存失败')
  } finally {
    formLoading.value = false
  }
}

/**
 * 启用 / 禁用学校：先二次确认，再更新 schools.status。
 * @param school 表格中选中的学校记录
 * @returns 无返回值，用户取消确认时不做任何提示
 */
async function toggleStatus(school: SchoolRow) {
  const next = school.status === 'active' ? 'disabled' : 'active'
  const label = next === 'active' ? '启用' : '禁用'
  try {
    await ElMessageBox.confirm(`确定要${label}学校「${school.name}」吗？`, '提示', {
      type: 'warning',
    })
    const { error } = await supabase
      .from('schools')
      .update({ status: next })
      .eq('id', school.id)
    if (error) throw error
    ElMessage.success(`${label}成功`)
    await loadData()
  } catch (err: unknown) {
    if (err !== 'cancel') {
      ElMessage.error(err instanceof Error ? err.message : '操作失败')
    }
  }
}

/**
 * 删除学校：先二次确认（提示不可恢复），再删除该学校记录。
 * @param school 表格中选中的学校记录
 * @returns 无返回值，用户取消确认时不做任何提示
 */
async function handleDelete(school: SchoolRow) {
  try {
    await ElMessageBox.confirm(
      `确定要删除学校「${school.name}」吗？此操作不可恢复。`,
      '危险操作',
      { type: 'error', confirmButtonText: '删除', confirmButtonClass: 'el-button--danger' },
    )
    const { error } = await supabase.from('schools').delete().eq('id', school.id)
    if (error) throw error
    ElMessage.success('删除成功')
    await loadData()
  } catch (err: unknown) {
    if (err !== 'cancel') {
      ElMessage.error(err instanceof Error ? err.message : '删除失败')
    }
  }
}

onMounted(loadData)

// ============ Excel 批量导入学校 ============
const importLoading = ref(false)
const fileInputRef = ref<HTMLInputElement | null>(null)

// 学段中文 → key
const STAGE_MAP: Record<string, GradeStage> = {
  '小学': 'primary',
  '初中': 'junior',
  '高中': 'senior',
  '完全中学': 'complete',
  '初高中': 'complete',
  '完全中学（初高中）': 'complete',
}

/**
 * 下载批量导入所需的 Excel 模板（含一行示例数据）。
 * @returns 无返回值，直接触发浏览器下载
 */
function handleDownloadTemplate() {
  const header = ['学校名称', '学校代码', '地址', '联系电话', '学段']
  const sample = ['阳光小学', 'SCH001', '某某市某某区某某路 1 号', '0571-88888888', '小学']
  exportToExcel([header, sample], '学校导入模板.xlsx')
}

/**
 * 触发隐藏的文件选择框，供「批量导入」按钮调用。
 * @returns 无返回值
 */
function triggerFileImport() {
  fileInputRef.value?.click()
}

/**
 * 把 Excel 表头（中文别名或原始字段名）归一化成表单字段名。
 * @param header 表格中的原始表头文字
 * @returns 归一化后的字段名，未命中别名时原样返回
 */
function normalizeHeader(header: string): string {
  const headerKey = String(header).trim()
  const headerAliasMap: Record<string, string> = {
    学校名称: 'name', 名称: 'name',
    学校代码: 'code', 代码: 'code',
    地址: 'address',
    联系电话: 'contact_phone', 电话: 'contact_phone', 联系方式: 'contact_phone',
    学段: 'stage', 学段类型: 'stage',
  }
  return headerAliasMap[headerKey] ?? headerKey
}

/**
 * 处理「批量导入」选中的 Excel 文件：逐行解析学校信息，按名称或代码查重，
 * 已存在则更新、不存在则新增，最后汇总新增/更新/跳过的行数。
 * @param changeEvent 文件输入框的 change 事件
 * @returns 无返回值，完成后提示导入结果并刷新列表
 */
async function handleFileChange(changeEvent: Event) {
  const input = changeEvent.target as HTMLInputElement
  const file = input.files?.[0]
  if (!file) return
  input.value = ''

  importLoading.value = true
  let createdCount = 0
  let updatedCount = 0
  let skippedCount = 0
  const errorRows: string[] = []
  try {
    const fileBuffer = await file.arrayBuffer()
    const workbook = XLSX.read(fileBuffer, { type: 'array' })
    const worksheet = workbook.Sheets[workbook.SheetNames[0]]
    const sheetRows = XLSX.utils.sheet_to_json<any>(worksheet, { defval: '' })

    for (const rawRow of sheetRows) {
      const mappedRow: Record<string, any> = {}
      for (const [rawHeader, cellValue] of Object.entries(rawRow)) {
        mappedRow[normalizeHeader(rawHeader)] = cellValue
      }
      const name = String(mappedRow.name ?? '').trim()
      const code = String(mappedRow.code ?? '').trim()
      const address = String(mappedRow.address ?? '').trim() || null
      const contact_phone = String(mappedRow.contact_phone ?? '').trim() || null
      const stageRaw = String(mappedRow.stage ?? '').trim()
      const stage = STAGE_MAP[stageRaw] ?? 'primary'

      if (!name || !code) {
        skippedCount++
        continue
      }

      // 按名称或代码查重
      const { data: existing } = await supabase
        .from('schools')
        .select('id')
        .or(`name.eq.${name},code.eq.${code}`)
        .maybeSingle()

      if (existing?.id) {
        const { error } = await supabase
          .from('schools')
          .update({
            name,
            code,
            address,
            contact_phone,
            grade_range: GRADE_PRESETS[stage].grades,
          })
          .eq('id', existing.id)
        if (error) {
          errorRows.push(`${name}：${error.message}`)
          skippedCount++
        } else {
          updatedCount++
        }
      } else {
        const { error } = await supabase.from('schools').insert({
          name,
          code,
          address,
          contact_phone,
          status: 'active',
          grade_range: GRADE_PRESETS[stage].grades,
        })
        if (error) {
          errorRows.push(`${name}：${error.message}`)
          skippedCount++
        } else {
          createdCount++
        }
      }
    }
    let msg = `批量导入完成：新增 ${createdCount} 所，更新 ${updatedCount} 所，跳过 ${skippedCount} 行`
    if (errorRows.length) msg += `\n${errorRows.slice(0, 5).join('\n')}`
    ElMessage({ type: createdCount || updatedCount ? 'success' : 'warning', message: msg, duration: 6000 })
    await loadData()
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error ? err.message : '批量导入失败')
  } finally {
    importLoading.value = false
  }
}
</script>

<template>
  <div class="page">
    <el-card shadow="never">
      <div class="toolbar">
        <div class="toolbar-left">
          <el-input
            v-model="searchKw"
            placeholder="搜索学校名称或代码"
            :prefix-icon="Search"
            clearable
            style="width: 260px"
          />
        </div>
        <div class="toolbar-right">
          <el-button :icon="Download" @click="handleDownloadTemplate">下载模板</el-button>
          <el-button :icon="Upload" :loading="importLoading" @click="triggerFileImport">批量导入</el-button>
          <input
            ref="fileInputRef"
            type="file"
            accept=".xlsx,.xls"
            style="display: none"
            @change="handleFileChange"
          />
          <el-button type="primary" :icon="Plus" @click="openAdd">新增学校</el-button>
        </div>
      </div>

      <el-table :data="filteredData" v-loading="loading" stripe>
        <el-table-column prop="name" label="学校名称" min-width="160" />
        <el-table-column prop="code" label="学校代码" width="140" />
        <el-table-column label="学段" width="120" align="center">
          <template #default="{ row: school }">
            {{ GRADE_PRESETS[stageFromGrades((school as SchoolRow).grade_range)].label }}
          </template>
        </el-table-column>
        <el-table-column prop="address" label="地址" min-width="180" show-overflow-tooltip />
        <el-table-column prop="contact_phone" label="联系电话" width="140" />
        <el-table-column label="状态" width="100" align="center">
          <template #default="{ row: school }">
            <el-tag v-if="school.status === 'active'" type="success" effect="light">
              启用
            </el-tag>
            <el-tag v-else type="info" effect="light">禁用</el-tag>
          </template>
        </el-table-column>
        <el-table-column prop="created_at" label="创建时间" width="180">
          <template #default="{ row: school }">
            {{ school.created_at ? new Date(school.created_at).toLocaleString() : '-' }}
          </template>
        </el-table-column>
        <el-table-column label="操作" width="260" fixed="right" align="center">
          <template #default="{ row: school }">
            <el-button link type="primary" :icon="Edit" @click="openEdit(school as SchoolRow)">
              编辑
            </el-button>
            <el-button
              link
              :type="school.status === 'active' ? 'warning' : 'success'"
              :icon="school.status === 'active' ? Close : Check"
              @click="toggleStatus(school as SchoolRow)"
            >
              {{ school.status === 'active' ? '禁用' : '启用' }}
            </el-button>
            <el-button
              link
              type="danger"
              :icon="Delete"
              @click="handleDelete(school as SchoolRow)"
            >
              删除
            </el-button>
          </template>
        </el-table-column>
      </el-table>

      <div class="footer-hint">共 {{ filteredData.length }} 条记录</div>
    </el-card>

    <el-dialog
      v-model="dialogVisible"
      :title="dialogTitle"
      width="520px"
      :close-on-click-modal="false"
    >
      <el-form
        ref="formRef"
        :model="form"
        :rules="rules"
        label-width="90px"
      >
        <el-form-item label="学校名称" prop="name">
          <el-input v-model="form.name" placeholder="请输入学校全称" />
        </el-form-item>
        <el-form-item label="学校代码" prop="code">
          <el-input v-model="form.code" placeholder="如：SCH001" />
        </el-form-item>
        <el-form-item label="地址">
          <el-input v-model="form.address" placeholder="请输入学校地址" />
        </el-form-item>
        <el-form-item label="联系电话">
          <el-input v-model="form.contact_phone" placeholder="请输入联系电话" />
        </el-form-item>
        <el-form-item label="学段">
          <el-radio-group v-model="form.stage">
            <el-radio-button v-for="(preset, stageKey) in GRADE_PRESETS" :key="stageKey" :value="stageKey">
              {{ preset.label }}
            </el-radio-button>
          </el-radio-group>
          <div class="stage-hint">学校端「新建班级」的年级下拉将使用该学段的年级列表</div>
        </el-form-item>
        <el-form-item label="状态">
          <el-radio-group v-model="form.status">
            <el-radio-button value="active">启用</el-radio-button>
            <el-radio-button value="disabled">禁用</el-radio-button>
          </el-radio-group>
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="dialogVisible = false">取消</el-button>
        <el-button type="primary" :loading="formLoading" @click="handleSubmit">
          确定
        </el-button>
      </template>
    </el-dialog>
  </div>
</template>

<style scoped>
.page {
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.toolbar {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 16px;
}

.toolbar-right {
  display: flex;
  gap: 8px;
  align-items: center;
}

.footer-hint {
  margin-top: 12px;
  font-size: 12px;
  color: #909399;
}

.stage-hint {
  width: 100%;
  margin-top: 4px;
  font-size: 12px;
  color: #909399;
  line-height: 1.4;
}
</style>
