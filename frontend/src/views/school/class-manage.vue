<script setup lang="ts">
import { ref, onMounted, computed } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { Plus, Edit, Delete } from '@element-plus/icons-vue'
import { supabase } from '@/api/supabase'
import { useUserStore } from '@/stores/user'

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
}

const classes = ref<ClassRow[]>([])
const loading = ref(false)
const gradeOptions = ref<string[]>([])
const teachers = ref<TeacherOpt[]>([])

async function loadGradeOptions() {
  if (!userStore.schoolId) return
  const { data } = await supabase.from('schools').select('grade_range').eq('id', userStore.schoolId)
  const s = (data ?? [])[0] as any
  if (s?.grade_range && Array.isArray(s.grade_range)) {
    gradeOptions.value = s.grade_range
  } else {
    gradeOptions.value = ['一年级', '二年级', '三年级', '四年级', '五年级', '六年级']
  }
}

async function loadTeachers() {
  if (!userStore.schoolId) return
  try {
    const { data, error } = await supabase
      .from('profiles')
      .select('id, real_name, phone')
      .eq('school_id', userStore.schoolId)
      .eq('role', 'teacher')
      .order('real_name', { ascending: true })
    if (error) throw error
    teachers.value = (data ?? []) as TeacherOpt[]
  } catch (err: any) {
    ElMessage.error(err.message || '加载教师列表失败')
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
    const { data, error } = await query.order('name', { ascending: true })
    if (error) throw error

    const rows = (data ?? []) as ClassRow[]
    rows.forEach((c) => {
      if (!c.name && c.class_name) c.name = c.class_name
    })
    for (const c of rows) {
      const { count, error: countErr } = await supabase
        .from('students')
        .select('*', { count: 'exact', head: true })
        .eq('class_id', c.id)
      if (countErr) throw countErr
      c.student_count = count ?? 0
    }
    const teacherIds = Array.from(
      new Set(rows.map((r) => r.homeroom_teacher_id).filter(Boolean)),
    ) as string[]
    if (teacherIds.length > 0) {
      const { data: profs, error: profErr } = await supabase
        .from('profiles')
        .select('id, real_name')
        .in('id', teacherIds)
      if (profErr) throw profErr
      const nameMap: Record<string, string> = {}
      ;(profs ?? []).forEach((p: any) => { nameMap[p.id] = p.real_name })
      rows.forEach((r) => {
        if (r.homeroom_teacher_id) {
          r.homeroom_teacher_name = nameMap[r.homeroom_teacher_id] ?? undefined
        }
      })
    }
    classes.value = rows
  } catch (err: any) {
    ElMessage.error(err.message || '加载班级列表失败')
  } finally {
    loading.value = false
  }
}

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

function openEdit(row: ClassRow) {
  isEdit.value = true
  form.value = { ...row }
  if (form.value.homeroom_teacher_id === undefined) form.value.homeroom_teacher_id = null
  dialogVisible.value = true
}

async function handleSubmit() {
  try {
    await formRef.value?.validate()
  } catch {
    return
  }
  try {
    const prevHomeroomId = isEdit.value
      ? classes.value.find((c) => c.id === form.value.id)?.homeroom_teacher_id ?? null
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
        .eq('role', 'teacher')
        .neq('id', newHomeroomId)
        .eq('class_id', classId)
    }
    ElMessage.success(isEdit.value ? '更新成功' : '新增成功')
    dialogVisible.value = false
    await loadClasses()
  } catch (err: any) {
    ElMessage.error(err.message || '保存失败')
  }
}

async function handleDelete(row: ClassRow) {
  try {
    await ElMessageBox.confirm(
      `确定删除班级「${row.name}」吗？删除后该班级下的学生将失去关联。`,
      '提示',
      { type: 'warning' },
    )
  } catch {
    return
  }
  try {
    if (row.homeroom_teacher_id) {
      await supabase
        .from('profiles')
        .update({ class_id: null, class_name: null })
        .eq('id', row.homeroom_teacher_id)
    }
    const { error } = await supabase.from('classes').delete().eq('id', row.id)
    if (error) throw error
    ElMessage.success('删除成功')
    await loadClasses()
  } catch (err: any) {
    ElMessage.error(err.message || '删除失败')
  }
}

const dialogTitle = computed(() => (isEdit.value ? '编辑班级' : '新增班级'))
const cardTitle = computed(() => (isTeacher.value ? '我的班级' : '班级管理'))

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
        <el-button v-if="!isTeacher" type="primary" :icon="Plus" @click="openAdd">新增班级</el-button>
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
              :label="t.real_name + (t.phone ? ` (${t.phone})` : '')"
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
</style>
