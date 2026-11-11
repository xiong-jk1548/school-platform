<script setup lang="ts">
import { ref, onMounted, computed } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { Plus, Edit, Delete, Download, Upload } from '@element-plus/icons-vue'
import * as XLSX from 'xlsx'
import { supabase } from '@/api/supabase'
import { useUserStore } from '@/stores/user'
import { exportToExcel } from '@/utils/excel'

const userStore = useUserStore()

const isTeacher = computed(() => userStore.role === 'teacher')

interface ClassRow {
  id: string
  name: string
  class_name?: string
  grade?: string
  school_id: string
  student_count?: number
  homeroom_teacher_id?: string | null
  homeroom_teacher_name?: string
}

interface TeacherOpt {
  id: string
  real_name?: string
  phone?: string
  role?: string
}

const classes = ref<ClassRow[]>([])
const loading = ref(false)
const gradeOptions = ref<string[]>([])
const teachers = ref<TeacherOpt[]>([])

/**
 * 加载本校可选年级列表，作为「新增/编辑班级」弹窗年级下拉的数据源。
 * 年级取自 schools.grade_range；教育局端新建学校时若未选择学段，该字段会是空数组，
 * 此时回退为默认小学六学年，避免年级下拉框空白。
 * @returns 无返回值，结果写入响应式变量 gradeOptions
 */
async function loadGradeOptions() {
  if (!userStore.schoolId) return
  const { data: schoolRows } = await supabase.from('schools').select('grade_range').eq('id', userStore.schoolId)
  const school = (schoolRows ?? [])[0] as any
  // 坑（现象：学校端新建班级时年级下拉为空）：空数组同样视为未配置学段，需回退默认值
  if (school?.grade_range && Array.isArray(school.grade_range) && school.grade_range.length > 0) {
    gradeOptions.value = school.grade_range
  } else {
    gradeOptions.value = ['一年级', '二年级', '三年级', '四年级', '五年级', '六年级']
  }
}

/**
 * 加载本校可担任班主任的教师列表。
 * 班主任候选人范围：教师 + 学校管理员（管理员可兼任班主任）。
 * @returns 无返回值，结果写入响应式变量 teachers
 */
async function loadTeachers() {
  if (!userStore.schoolId) return
  try {
    const { data: teacherRows, error } = await supabase
      .from('profiles')
      .select('id, real_name, phone, role')
      .eq('school_id', userStore.schoolId)
      .in('role', ['teacher', 'school_admin'])
      .order('real_name', { ascending: true })
    if (error) throw error
    teachers.value = (teacherRows ?? []) as TeacherOpt[]
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '加载教师列表失败')
  }
}

const dialogVisible = ref(false)
const isEdit = ref(false)
const formRef = ref()
const form = ref<ClassRow>({
  id: '',
  name: '',
  class_name: '',
  grade: '',
  school_id: '',
  homeroom_teacher_id: null,
})

/**
 * 加载班级列表。
 * 教师只看自己担任班主任的班级，学校管理员看本校全部班级；
 * 随后为每个班级统计学生数，并补全班主任姓名。
 * @returns 无返回值，结果写入响应式变量 classes
 */
async function loadClasses() {
  loading.value = true
  try {
    let query = supabase.from('classes').select('*')
    if (isTeacher.value) {
      if (!userStore.classId) {
        loading.value = false
        return
      }
      query = query.eq('id', userStore.classId)
    } else {
      if (!userStore.schoolId) {
        loading.value = false
        return
      }
      query = query.eq('school_id', userStore.schoolId)
    }
    const { data: classData, error } = await query.order('name', { ascending: true })
    if (error) throw error

    const classRows = (classData ?? []) as ClassRow[]
    classRows.forEach((cls) => {
      if (!cls.name && cls.class_name) cls.name = cls.class_name
    })
    for (const cls of classRows) {
      const { count, error: countErr } = await supabase
        .from('students')
        .select('*', { count: 'exact', head: true })
        .eq('class_id', cls.id)
      if (countErr) throw countErr
      cls.student_count = count ?? 0
    }
    const teacherIds = Array.from(
      new Set(classRows.map((cls) => cls.homeroom_teacher_id).filter(Boolean)),
    ) as string[]
    if (teacherIds.length > 0) {
      const { data: teacherProfiles, error: profErr } = await supabase
        .from('profiles')
        .select('id, real_name')
        .in('id', teacherIds)
      if (profErr) throw profErr
      const teacherNameMap: Record<string, string> = {}
      ;(teacherProfiles ?? []).forEach((teacherProfile: any) => { teacherNameMap[teacherProfile.id] = teacherProfile.real_name })
      classRows.forEach((cls) => {
        if (cls.homeroom_teacher_id) {
          cls.homeroom_teacher_name = teacherNameMap[cls.homeroom_teacher_id] ?? undefined
        }
      })
    }
    classes.value = classRows
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '加载班级列表失败')
  } finally {
    loading.value = false
  }
}

/**
 * 打开「新增班级」弹窗，并重置表单（学校 id 取当前登录用户所在学校）。
 * @returns 无返回值，直接控制弹窗与表单状态
 */
function openAdd() {
  isEdit.value = false
  form.value = {
    id: '',
    name: '',
    class_name: '',
    grade: '',
    school_id: userStore.schoolId!,
    homeroom_teacher_id: null,
  }
  dialogVisible.value = true
}

/**
 * 打开「编辑班级」弹窗，用选中班级的数据回填表单。
 * @param classRow 被编辑的班级行
 * @returns 无返回值，直接控制弹窗与表单状态
 */
function openEdit(classRow: ClassRow) {
  isEdit.value = true
  form.value = { ...classRow }
  if (form.value.homeroom_teacher_id === undefined) form.value.homeroom_teacher_id = null
  dialogVisible.value = true
}

/**
 * 提交班级新增/编辑。
 * 除写入 classes 表外，还会同步班主任的 profiles.class_id / class_name：
 * 原班主任被换掉时清空其归属，新班主任绑定到本班并解除其在其他班的班主任关系。
 * @returns 无返回值，成功后关闭弹窗并刷新班级列表
 */
async function handleSubmit() {
  try {
    await formRef.value?.validate()
  } catch {
    // 表单校验未通过（Element Plus 已给出提示），直接中断提交
    return
  }
  try {
    const prevHomeroomId = isEdit.value
      ? classes.value.find((cls) => cls.id === form.value.id)?.homeroom_teacher_id ?? null
      : null
    if (isEdit.value) {
      const { error } = await supabase
        .from('classes')
        .update({
          name: form.value.name,
          class_name: form.value.name,
          grade: form.value.grade,
          homeroom_teacher_id: form.value.homeroom_teacher_id || null,
        })
        .eq('id', form.value.id)
      if (error) throw error
    } else {
      const { data: inserted, error } = await supabase.from('classes').insert({
        name: form.value.name,
        class_name: form.value.name,
        grade: form.value.grade,
        school_id: userStore.schoolId!,
        homeroom_teacher_id: form.value.homeroom_teacher_id || null,
      }).select('id')
      if (error) throw error
      if (inserted && inserted.length > 0) {
        form.value.id = (inserted[0] as any).id
      }
    }
    const newHomeroomId = form.value.homeroom_teacher_id || null
    const classId = form.value.id
    const className = form.value.name
    if (prevHomeroomId && prevHomeroomId !== newHomeroomId) {
      await supabase
        .from('profiles')
        .update({ class_id: null, class_name: null })
        .eq('id', prevHomeroomId)
    }
    if (newHomeroomId && newHomeroomId !== prevHomeroomId) {
      await supabase
        .from('profiles')
        .update({ class_id: classId, class_name: className })
        .eq('id', newHomeroomId)
      await supabase
        .from('profiles')
        .update({ class_id: null, class_name: null })
        .eq('school_id', userStore.schoolId!)
        .in('role', ['teacher', 'school_admin'])
        .neq('id', newHomeroomId)
        .eq('class_id', classId)
    }
    ElMessage.success(isEdit.value ? '更新成功' : '新增成功')
    dialogVisible.value = false
    await loadClasses()
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '保存失败')
  }
}

/**
 * 删除班级：先二次确认，再解除班主任归属并删除班级记录。
 * @param classRow 被删除的班级行
 * @returns 无返回值，成功后刷新班级列表
 */
async function handleDelete(classRow: ClassRow) {
  try {
    await ElMessageBox.confirm(
      `确定删除班级「${classRow.name}」吗？删除后该班级下的学生将失去关联。`,
      '提示',
      { type: 'warning' },
    )
  } catch {
    // 用户在确认框点了取消，不执行删除
    return
  }
  try {
    if (classRow.homeroom_teacher_id) {
      await supabase
        .from('profiles')
        .update({ class_id: null, class_name: null })
        .eq('id', classRow.homeroom_teacher_id)
    }
    const { error } = await supabase.from('classes').delete().eq('id', classRow.id)
    if (error) throw error
    ElMessage.success('删除成功')
    await loadClasses()
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '删除失败')
  }
}

const dialogTitle = computed(() => (isEdit.value ? '编辑班级' : '新增班级'))
const cardTitle = computed(() => (isTeacher.value ? '我的班级' : '班级管理'))

// ============ Excel 批量导入班级 ============
const importLoading = ref(false)
const fileInputRef = ref<HTMLInputElement | null>(null)

/**
 * 下载班级批量导入模板（班级名/年级/班主任三列）。
 * @returns 无返回值，直接触发浏览器下载
 */
function handleDownloadTemplate() {
  const header = ['班级名', '年级', '班主任']
  const sample = ['一年级一班', '一年级', '13800000003']
  exportToExcel([header, sample], '班级导入模板.xlsx')
}

/** 触发隐藏的 file input，打开文件选择框 */
function triggerFileImport() {
  fileInputRef.value?.click()
}

/**
 * 把 Excel 表头（中文）归一化为内部字段名，便于后续按字段取值。
 * 未登记的列名原样返回。
 * @param key Excel 原始表头
 * @returns 内部字段名（如 class_name / grade / homeroom）
 */
function normalizeHeader(key: string): string {
  const rawHeader = String(key).trim()
  const headerAliasMap: Record<string, string> = {
    班级名: 'class_name', 班级: 'class_name', 名称: 'class_name',
    年级: 'grade',
    班主任: 'homeroom', 班主任手机: 'homeroom', 班主任姓名: 'homeroom', 班主任手机号: 'homeroom',
  }
  return headerAliasMap[rawHeader] ?? rawHeader
}

/**
 * 按手机号精确查找本校教师。
 * @param phone 教师手机号
 * @returns 命中的教师；未命中返回 undefined
 */
function findTeacherByPhone(phone: string) {
  return teachers.value.find((teacher) => (teacher.phone ?? '').trim() === phone)
}

/**
 * 按姓名精确查找本校教师，仅在全校同名唯一时才视为命中。
 * @param name 教师姓名
 * @returns 唯一命中的教师；无命中或重名时返回 null
 */
function findTeacherByName(name: string) {
  const matches = teachers.value.filter((teacher) => (teacher.real_name ?? '').trim() === name)
  return matches.length === 1 ? matches[0] : null
}

/**
 * 同步「班主任」关系：先解除该教师原先担任班主任的班级，再绑定到新班级。
 * 教师的班级归属（profiles.class_id / class_name）由调用方按需写入。
 * @param teacherId 教师 profile id
 * @param newClassId 新的班主任班级 id，null 表示不绑定
 * @param newClassName 新的班主任班级名（由调用方维护，本函数不写库）
 * @returns Promise，写入 classes.homeroom_teacher_id
 */
async function syncClassHomeroomTeacher(
  teacherId: string,
  newClassId: string | null,
  newClassName: string | null,
) {
  if (!userStore.schoolId) return
  const { data: allClasses, error } = await supabase
    .from('classes')
    .select('id, homeroom_teacher_id')
    .eq('school_id', userStore.schoolId)
  if (error) throw error
  const allClassRows = (allClasses ?? []) as { id: string; homeroom_teacher_id: string | null }[]
  const previousHomeroomClass = allClassRows.find((cls) => cls.homeroom_teacher_id === teacherId)
  if (previousHomeroomClass && previousHomeroomClass.id !== newClassId) {
    await supabase.from('classes').update({ homeroom_teacher_id: null }).eq('id', previousHomeroomClass.id)
  }
  if (newClassId) {
    await supabase.from('classes').update({ homeroom_teacher_id: teacherId }).eq('id', newClassId)
  }
  await supabase
    .from('profiles')
    .update({ class_id: newClassId, class_name: newClassName })
    .eq('id', teacherId)
}

/**
 * 批量导入班级：逐行解析 Excel，按「班级名」查重后新增或更新，并同步班主任关系。
 * 每行独立处理，单行失败只记录到 errorRows 并计入跳过数，不中断整体导入。
 * @param event 文件选择框的 change 事件
 * @returns 无返回值，结束后提示新增/更新/跳过统计并刷新班级列表
 */
async function handleFileChange(event: Event) {
  const input = event.target as HTMLInputElement
  const file = input.files?.[0]
  if (!file) return
  input.value = ''

  importLoading.value = true
  let createdCount = 0
  let updatedCount = 0
  let skippedCount = 0
  const errorRows: string[] = []
  try {
    const buf = await file.arrayBuffer()
    const wb = XLSX.read(buf, { type: 'array' })
    const ws = wb.Sheets[wb.SheetNames[0]]
    const sheetRows = XLSX.utils.sheet_to_json<any>(ws, { defval: '' })

    // 确保教师列表已加载（页面 onMounted 已加载，此处保险再拉一次）
    if (teachers.value.length === 0) await loadTeachers()

    // 文件内同名班级去重：保留首次出现
    const seenNames = new Set<string>()

    for (const excelRow of sheetRows) {
      const normalizedRow: Record<string, any> = {}
      for (const [excelHeader, excelValue] of Object.entries(excelRow)) {
        normalizedRow[normalizeHeader(excelHeader)] = excelValue
      }
      const className = String(normalizedRow.class_name ?? '').trim()
      const grade = String(normalizedRow.grade ?? '').trim()
      const homeroomRaw = String(normalizedRow.homeroom ?? '').trim()

      if (!className || !grade) {
        errorRows.push(`班级名或年级为空：${className || '(空)'}`)
        skippedCount++
        continue
      }
      if (seenNames.has(className)) {
        errorRows.push(`重复班级名「${className}」，已跳过`)
        skippedCount++
        continue
      }
      seenNames.add(className)

      // 解析班主任：手机号优先；否则按姓名（仅本校内唯一匹配）
      let homeroomTeacherId: string | null = null
      if (homeroomRaw) {
        const byPhone = findTeacherByPhone(homeroomRaw)
        if (byPhone) {
          homeroomTeacherId = byPhone.id
        } else {
          const byName = findTeacherByName(homeroomRaw)
          if (byName) {
            homeroomTeacherId = byName.id
          } else {
            const sameNameCount = teachers.value.filter(
              (teacher) => (teacher.real_name ?? '').trim() === homeroomRaw,
            ).length
            if (sameNameCount > 1) {
              errorRows.push(`${className}：班主任「${homeroomRaw}」姓名在本校存在 ${sameNameCount} 人，请使用手机号`)
            } else {
              errorRows.push(`${className}：班主任「${homeroomRaw}」在本校未找到`)
            }
            skippedCount++
            continue
          }
        }
      }

      // 查重：按 (school_id, class_name) 找已有班级
      const { data: existing } = await supabase
        .from('classes')
        .select('id, name, class_name, grade, homeroom_teacher_id')
        .eq('school_id', userStore.schoolId)
        .or(`class_name.eq.${className},name.eq.${className}`)
        .maybeSingle()

      let classId: string | null = null
      if (existing?.id) {
        // 更新：年级必更；班主任按 Excel 给的值（空则不动）
        const updatePayload: Record<string, any> = { name: className, class_name: className, grade }
        // 注意：班主任列若为空，不主动清空已有班主任；若填写则覆盖
        if (homeroomRaw) updatePayload.homeroom_teacher_id = homeroomTeacherId
        const { error } = await supabase.from('classes').update(updatePayload).eq('id', existing.id)
        if (error) {
          errorRows.push(`${className}：${error.message}`)
          skippedCount++
          continue
        }
        classId = existing.id
        updatedCount++
      } else {
        // 新增
        const { data: inserted, error: insertErr } = await supabase
          .from('classes')
          .insert({
            name: className,
            class_name: className,
            school_id: userStore.schoolId,
            grade,
            homeroom_teacher_id: homeroomTeacherId,
          })
          .select('id')
        if (insertErr || !inserted || inserted.length === 0) {
          errorRows.push(`${className}：${insertErr?.message ?? '新增失败'}`)
          skippedCount++
          continue
        }
        classId = (inserted[0] as any).id as string
        createdCount++
      }

      // 同步班主任（新建/更新均处理；若班主任列为空，不动 profiles.class_id）
      if (homeroomRaw && homeroomTeacherId && classId) {
        await syncClassHomeroomTeacher(homeroomTeacherId, classId, className)
      }
    }
    let msg = `批量导入完成：新增 ${createdCount} 个，更新 ${updatedCount} 个，跳过 ${skippedCount} 行`
    if (errorRows.length) msg += `\n${errorRows.slice(0, 5).join('\n')}`
    ElMessage({
      type: createdCount || updatedCount ? 'success' : 'warning',
      message: msg,
      duration: 6000,
    })
    await loadClasses()
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '批量导入失败')
  } finally {
    importLoading.value = false
  }
}

onMounted(() => {
  loadGradeOptions()
  if (!isTeacher.value) loadTeachers()
  loadClasses()
})
</script>

<template>
  <el-card>
    <template #header>
      <div class="card-header">
        <span>{{ cardTitle }}</span>
        <div v-if="!isTeacher" class="header-actions">
          <el-button :icon="Download" @click="handleDownloadTemplate">下载模板</el-button>
          <el-button :icon="Upload" :loading="importLoading" @click="triggerFileImport">批量导入</el-button>
          <input
            ref="fileInputRef"
            type="file"
            accept=".xlsx,.xls"
            style="display: none"
            @change="handleFileChange"
          />
          <el-button type="primary" :icon="Plus" @click="openAdd">新增班级</el-button>
        </div>
      </div>
    </template>

    <el-table :data="classes" v-loading="loading" stripe style="width: 100%">
      <el-table-column prop="name" label="班级名" min-width="140" />
      <el-table-column prop="grade" label="年级" min-width="100" />
      <el-table-column label="班主任" min-width="140">
        <template #default="{ row }">
          <el-tag
            v-if="row.homeroom_teacher_name"
            type="warning"
            effect="light"
          >{{ row.homeroom_teacher_name }}</el-tag>
          <el-tag v-else type="info" effect="light">未设置</el-tag>
        </template>
      </el-table-column>
      <el-table-column label="学生数" min-width="100">
        <template #default="{ row }">
          <el-tag type="info">{{ row.student_count ?? 0 }}</el-tag>
        </template>
      </el-table-column>
      <el-table-column label="操作" width="180" fixed="right">
        <template #default="{ row }">
          <el-button link type="primary" :icon="Edit" @click="openEdit(row as ClassRow)">编辑</el-button>
          <el-button
            v-if="!isTeacher"
            link
            type="danger"
            :icon="Delete"
            @click="handleDelete(row as ClassRow)"
          >
            删除
          </el-button>
        </template>
      </el-table-column>
    </el-table>

    <el-dialog v-model="dialogVisible" :title="dialogTitle" width="460px" destroy-on-close>
      <el-form ref="formRef" :model="form" label-width="80px">
        <el-form-item
          label="班级名"
          prop="name"
          :rules="[{ required: true, message: '请输入班级名', trigger: 'blur' }]"
        >
          <el-input v-model="form.name" placeholder="例如：一年级1班" />
        </el-form-item>
        <el-form-item
          label="年级"
          prop="grade"
          :rules="[{ required: true, message: '请输入年级', trigger: 'blur' }]"
        >
          <el-select v-model="form.grade" placeholder="请选择年级" style="width: 100%">
            <el-option
              v-for="g in gradeOptions"
              :key="g"
              :label="g"
              :value="g"
            />
          </el-select>
        </el-form-item>
        <el-form-item v-if="!isTeacher" label="班主任">
          <el-select
            v-model="form.homeroom_teacher_id"
            placeholder="未设置"
            clearable
            filterable
            style="width: 100%"
          >
            <el-option
              v-for="t in teachers"
              :key="t.id"
              :label="t.real_name + (t.role === 'school_admin' ? '（管理员）' : '') + (t.phone ? ` (${t.phone})` : '')"
              :value="t.id"
            />
          </el-select>
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="dialogVisible = false">取消</el-button>
        <el-button type="primary" @click="handleSubmit">确定</el-button>
      </template>
    </el-dialog>
  </el-card>
</template>

<style scoped>
.card-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
}
.header-actions {
  display: flex;
  gap: 8px;
  align-items: center;
}
</style>
