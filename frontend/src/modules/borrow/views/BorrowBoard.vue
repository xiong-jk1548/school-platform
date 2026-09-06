<script setup lang="ts">
import { ref, onMounted, computed, watch } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { Plus, Edit, Delete, Search, Goods } from '@element-plus/icons-vue'
import { supabase } from '@/api/supabase'
import { useUserStore } from '@/stores/user'

const userStore = useUserStore()

interface ItemRow {
  id: string
  item_name: string
  type: string
  total_quantity: number
  available_quantity: number
  location?: string
  description?: string
  school_id?: string
  class_id?: string
}

interface ClassOpt {
  id: string
  class_name: string
}

interface StudentOpt {
  id: string
  student_name: string
  class_id?: string
}

interface RecordRow {
  id: string
  item_id: string
  student_id: string
  borrow_date: string
  return_time?: string
  status: 'borrowed' | 'returned' | 'overdue'
  qty: number
  remark?: string
  borrower_name?: string
}

interface BorrowForm {
  id?: string
  item_name: string
  type: string
  total_quantity: number
  location: string
  description: string
}

const items = ref<ItemRow[]>([])
const loading = ref(false)
const schoolClasses = ref<ClassOpt[]>([])
const filterClassId = ref<string>('')
const searchKey = ref('')

const borrowDialogVisible = ref(false)
const borrowForm = ref({
  item_id: '',
  item_name: '',
  qty: 1,
  student_id: '',
  remark: '',
} as { item_id: string; item_name: string; qty: number; student_id: string; remark: string })

const recordDialogVisible = ref(false)
const currentRecords = ref<RecordRow[]>([])
const recordsLoading = ref(false)
const currentItem = ref<ItemRow | null>(null)

const itemDialogVisible = ref(false)
const editingItem = ref<ItemRow | null>(null)
const itemForm = ref<BorrowForm>({
  item_name: '',
  type: '体育器材',
  total_quantity: 1,
  location: '',
  description: '',
})

const recentBorrowerMap = ref<Record<string, string>>({})

const students = ref<StudentOpt[]>([])

const filteredItems = computed(() => {
  const kw = searchKey.value.trim().toLowerCase()
  if (!kw) return items.value
  return items.value.filter((it) => it.item_name.toLowerCase().includes(kw))
})

async function loadSchoolClasses() {
  try {
    if (userStore.role === 'teacher' && userStore.classId) {
      schoolClasses.value = [{ id: userStore.classId, class_name: userStore.className || '我的班级' }]
      filterClassId.value = userStore.classId
    } else if (userStore.role === 'school_admin' && userStore.schoolId) {
      const { data, error } = await supabase
        .from('classes')
        .select('id, class_name')
        .eq('school_id', userStore.schoolId)
      if (error) throw error
      schoolClasses.value = (data ?? []) as ClassOpt[]
      filterClassId.value = ''
    }
  } catch (err: any) {
    ElMessage.error(err.message || '加载班级失败')
  }
}

async function loadStudents() {
  try {
    let query = supabase
      .from('students')
      .select('id, student_name, class_id')
      .order('student_name', { ascending: true })
    if (filterClassId.value) {
      query = query.eq('class_id', filterClassId.value)
    } else if (userStore.schoolId) {
      query = query.eq('school_id', userStore.schoolId)
    } else {
      students.value = []
      return
    }
    const { data, error } = await query
    if (error) throw error
    students.value = (data ?? []) as StudentOpt[]
  } catch (err: any) {
    ElMessage.error(err.message || '加载学生列表失败')
  }
}

async function loadItems() {
  if (!userStore.schoolId) return
  loading.value = true
  try {
    let query = supabase
      .from('borrow_items')
      .select('*')
      .order('item_name', { ascending: true })
    if (filterClassId.value) {
      query = query.eq('class_id', filterClassId.value)
    } else {
      query = query.eq('school_id', userStore.schoolId)
    }
    const { data, error } = await query
    if (error) throw error
    items.value = (data ?? []) as ItemRow[]
    await loadRecentBorrowers()
  } catch (err: any) {
    ElMessage.error(err.message || '加载物品列表失败')
  } finally {
    loading.value = false
  }
}

async function loadRecentBorrowers() {
  if (items.value.length === 0) {
    recentBorrowerMap.value = {}
    return
  }
  const itemIds = items.value.map((it) => it.id)
  try {
    const { data: records, error: rErr } = await supabase
      .from('borrow_records')
      .select('id, item_id, student_id, status, borrow_date')
      .eq('status', 'borrowed')
      .in('item_id', itemIds)
      .order('borrow_date', { ascending: false })
    if (rErr) throw rErr

    const stMap: Record<string, string> = {}
    const uniqueIds = Array.from(new Set((records ?? []).map((r: any) => r.student_id)))
    if (uniqueIds.length > 0) {
      const { data: sts, error: sErr } = await supabase
        .from('students')
        .select('id, student_name')
        .in('id', uniqueIds)
      if (sErr) throw sErr
      for (const s of (sts ?? []) as StudentOpt[]) {
        stMap[s.id] = s.student_name
      }
    }

    const map: Record<string, string> = {}
    for (const r of (records ?? []) as any[]) {
      if (!map[r.item_id]) {
        map[r.item_id] = stMap[r.student_id] || r.student_id
      }
    }
    recentBorrowerMap.value = map
  } catch (err: any) {
    ElMessage.error(err.message || '加载最近借出人失败')
  }
}

function openBorrowDialog(row: ItemRow) {
  if (row.available_quantity <= 0) {
    ElMessage.warning('该物品暂无可用数量')
    return
  }
  borrowForm.value = {
    item_id: row.id,
    item_name: row.item_name,
    qty: Math.min(1, row.available_quantity),
    student_id: '',
    remark: '',
  }
  borrowDialogVisible.value = true
}

async function submitBorrow() {
  const f = borrowForm.value
  if (!f.student_id) {
    ElMessage.warning('请选择借出学生')
    return
  }
  if (f.qty <= 0) {
    ElMessage.warning('借出数量必须大于 0')
    return
  }
  const item = items.value.find((it) => it.id === f.item_id)
  if (!item) return
  if (f.qty > item.available_quantity) {
    ElMessage.warning(`借出数量超过可用数量 ${item.available_quantity}`)
    return
  }
  try {
    const { data: st } = await supabase
      .from('students')
      .select('student_name')
      .eq('id', f.student_id)
      .maybeSingle()
    const studentName = (st as any)?.student_name || ''

    const borrowDate = new Date().toISOString()
    const expectedReturn = new Date(Date.now() + 7 * 86400000).toISOString()

    const studentClassId = students.value.find((s) => s.id === f.student_id)?.class_id || filterClassId.value || undefined

    const { error } = await supabase
      .from('borrow_records')
      .insert({
        item_id: f.item_id,
        student_id: f.student_id,
        borrower_name: studentName,
        borrow_date: borrowDate,
        expected_return_date: expectedReturn,
        status: 'borrowed',
        qty: f.qty,
        school_id: userStore.schoolId,
        class_id: studentClassId,
        operator_user_id: userStore.id,
        remark: f.remark || null,
      })
      .select()
    if (error) throw error
    ElMessage.success('借出登记成功')
    borrowDialogVisible.value = false
    await loadItems()
  } catch (err: any) {
    ElMessage.error(err.message || '借出登记失败')
  }
}

async function openRecordsDialog(row: ItemRow) {
  currentItem.value = row
  recordDialogVisible.value = true
  recordsLoading.value = true
  try {
    const { data, error } = await supabase
      .from('borrow_records')
      .select('*')
      .eq('item_id', row.id)
      .order('borrow_date', { ascending: false })
    if (error) throw error
    const records = (data ?? []) as any[]

    const uniqueStIds = Array.from(new Set(records.map((r) => r.student_id)))
    const stMap: Record<string, string> = {}
    if (uniqueStIds.length > 0) {
      const { data: sts } = await supabase
        .from('students')
        .select('id, student_name')
        .in('id', uniqueStIds)
      for (const s of (sts ?? []) as StudentOpt[]) {
        stMap[s.id] = s.student_name
      }
    }

    currentRecords.value = records.map((r) => ({
      id: r.id,
      item_id: r.item_id,
      student_id: r.student_id,
      borrow_date: r.borrow_date,
      return_time: r.return_time || r.actual_return_date,
      status: r.status,
      qty: r.qty ?? 1,
      remark: r.remark,
      borrower_name: r.borrower_name || stMap[r.student_id] || r.student_id,
    }))
  } catch (err: any) {
    ElMessage.error(err.message || '加载归还记录失败')
  } finally {
    recordsLoading.value = false
  }
}

async function confirmReturn(rec: RecordRow) {
  try {
    await ElMessageBox.confirm(
      `确认将「${currentItem.value?.item_name}」的 ${rec.borrower_name} ${rec.qty} 件登记为已归还？`,
      '确认归还',
      { type: 'warning' },
    )
  } catch {
    return
  }
  try {
    const now = new Date().toISOString()
    const { error } = await supabase
      .from('borrow_records')
      .update({
        status: 'returned',
        return_time: now,
        actual_return_date: now,
      })
      .eq('id', rec.id)
    if (error) throw error
    ElMessage.success('归还成功')
    await openRecordsDialog(currentItem.value!)
    await loadItems()
  } catch (err: any) {
    ElMessage.error(err.message || '归还操作失败')
  }
}

function openAddItemDialog() {
  editingItem.value = null
  itemForm.value = {
    item_name: '',
    type: '体育器材',
    total_quantity: 1,
    location: '',
    description: '',
  }
  itemDialogVisible.value = true
}

function openEditItemDialog(row: ItemRow) {
  editingItem.value = row
  itemForm.value = {
    item_name: row.item_name,
    type: row.type,
    total_quantity: row.total_quantity,
    location: row.location || '',
    description: row.description || '',
  }
  itemDialogVisible.value = true
}

async function submitItem() {
  const f = itemForm.value
  if (!f.item_name.trim()) {
    ElMessage.warning('请填写物品名称')
    return
  }
  if (f.total_quantity <= 0) {
    ElMessage.warning('总数必须大于 0')
    return
  }
  try {
    if (editingItem.value) {
      const availableDelta = f.total_quantity - editingItem.value.total_quantity
      const newAvailable = Math.max(0, editingItem.value.available_quantity + availableDelta)
      const { error } = await supabase
        .from('borrow_items')
        .update({
          item_name: f.item_name,
          type: f.type,
          total_quantity: f.total_quantity,
          location: f.location || null,
          description: f.description || null,
          available_quantity: newAvailable,
        })
        .eq('id', editingItem.value.id)
      if (error) throw error
      ElMessage.success('更新物品成功')
    } else {
      const { error } = await supabase.from('borrow_items').insert({
        item_name: f.item_name,
        type: f.type,
        total_quantity: f.total_quantity,
        available_quantity: f.total_quantity,
        location: f.location || null,
        description: f.description || null,
        school_id: userStore.schoolId,
        class_id: filterClassId.value || undefined,
      })
      if (error) throw error
      ElMessage.success('新增物品成功')
    }
    itemDialogVisible.value = false
    await loadItems()
  } catch (err: any) {
    ElMessage.error(err.message || '保存物品失败')
  }
}

async function deleteItem(row: ItemRow) {
  try {
    await ElMessageBox.confirm(`确定删除物品「${row.item_name}」吗？`, '删除确认', { type: 'warning' })
  } catch {
    return
  }
  try {
    const { data: borrowedRecords } = await supabase
      .from('borrow_records')
      .select('id')
      .eq('item_id', row.id)
      .eq('status', 'borrowed')
    if ((borrowedRecords ?? []).length > 0) {
      ElMessage.warning('该物品尚有未归还记录，无法删除')
      return
    }
    const { error } = await supabase.from('borrow_items').delete().eq('id', row.id)
    if (error) throw error
    ElMessage.success('删除成功')
    await loadItems()
  } catch (err: any) {
    ElMessage.error(err.message || '删除物品失败')
  }
}

watch(filterClassId, async () => {
  await loadStudents()
  await loadItems()
})

onMounted(async () => {
  await loadSchoolClasses()
  await loadStudents()
  await loadItems()
})
</script>

<template>
  <el-card>
    <template #header>
      <div class="toolbar">
        <div class="toolbar-left">
          <Goods class="header-icon" />
          <span class="header-title">班级公共物品借阅</span>
          <el-select
            v-if="userStore.role === 'school_admin'"
            v-model="filterClassId"
            clearable
            placeholder="按班级筛选"
            style="width: 180px; margin-left: 12px"
          >
            <el-option label="全部班级" value="" />
            <el-option
              v-for="c in schoolClasses"
              :key="c.id"
              :label="c.class_name"
              :value="c.id"
            />
          </el-select>
          <el-tag v-if="userStore.role === 'teacher' && userStore.className" type="info" style="margin-left: 12px">
            {{ userStore.className }}
          </el-tag>
        </div>
        <div class="toolbar-right">
          <el-input
            v-model="searchKey"
            placeholder="搜索物品名称"
            :prefix-icon="Search"
            clearable
            style="width: 220px"
          />
          <el-button type="primary" :icon="Plus" @click="openAddItemDialog">新增物品</el-button>
        </div>
      </div>
    </template>

    <el-table :data="filteredItems" v-loading="loading" stripe style="width: 100%">
      <el-table-column prop="item_name" label="物品名称" min-width="140" />
      <el-table-column prop="type" label="类型" min-width="110" />
      <el-table-column prop="total_quantity" label="总数" width="90" />
      <el-table-column label="可用数量" width="100">
        <template #default="{ row }">
          <el-tag :type="row.available_quantity > 0 ? 'success' : 'danger'">
            {{ row.available_quantity }}
          </el-tag>
        </template>
      </el-table-column>
      <el-table-column prop="location" label="存放位置" min-width="140">
        <template #default="{ row }">{{ row.location || '-' }}</template>
      </el-table-column>
      <el-table-column label="最近借出人" min-width="140">
        <template #default="{ row }">
          <span v-if="recentBorrowerMap[row.id]">{{ recentBorrowerMap[row.id] }}</span>
          <span v-else style="color: #909399">暂无借出</span>
        </template>
      </el-table-column>
      <el-table-column label="操作" width="260" fixed="right">
        <template #default="{ row }">
          <el-button link type="primary" :disabled="(row as ItemRow).available_quantity <= 0" @click="openBorrowDialog(row as ItemRow)">
            借出
          </el-button>
          <el-button link type="primary" @click="openRecordsDialog(row as ItemRow)">归还记录</el-button>
          <el-button link type="warning" :icon="Edit" @click="openEditItemDialog(row as ItemRow)" />
          <el-button link type="danger" :icon="Delete" @click="deleteItem(row as ItemRow)" />
        </template>
      </el-table-column>
    </el-table>

    <el-dialog v-model="borrowDialogVisible" title="物品借出登记" width="460px" destroy-on-close>
      <el-form label-width="90px">
        <el-form-item label="物品名称">
          <el-input :model-value="borrowForm.item_name" disabled />
        </el-form-item>
        <el-form-item label="借出数量" required>
          <el-input-number
            v-model="borrowForm.qty"
            :min="1"
            :max="items.find(i => i.id === borrowForm.item_id)?.available_quantity || 1"
            style="width: 100%"
          />
        </el-form-item>
        <el-form-item label="借出学生" required>
          <el-select
            v-model="borrowForm.student_id"
            placeholder="请选择学生"
            filterable
            style="width: 100%"
          >
            <el-option
              v-for="s in students"
              :key="s.id"
              :label="s.student_name"
              :value="s.id"
            />
          </el-select>
        </el-form-item>
        <el-form-item label="备注">
          <el-input
            v-model="borrowForm.remark"
            type="textarea"
            :rows="2"
            placeholder="选填"
          />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="borrowDialogVisible = false">取消</el-button>
        <el-button type="primary" @click="submitBorrow">确定借出</el-button>
      </template>
    </el-dialog>

    <el-dialog
      v-model="recordDialogVisible"
      :title="`归还记录 - ${currentItem?.item_name || ''}`"
      width="720px"
      destroy-on-close
    >
      <el-table :data="currentRecords" v-loading="recordsLoading" stripe size="small">
        <el-table-column label="状态" width="100">
          <template #default="{ row }">
            <el-tag v-if="row.status === 'borrowed'" type="danger">借出中</el-tag>
            <el-tag v-else-if="row.status === 'returned'" type="success">已归还</el-tag>
            <el-tag v-else type="warning">逾期</el-tag>
          </template>
        </el-table-column>
        <el-table-column label="学生" min-width="110">
          <template #default="{ row }">{{ row.borrower_name }}</template>
        </el-table-column>
        <el-table-column prop="qty" label="数量" width="70" />
        <el-table-column label="借出时间" min-width="170">
          <template #default="{ row }">{{ new Date(row.borrow_date).toLocaleString('zh-CN') }}</template>
        </el-table-column>
        <el-table-column label="归还时间" min-width="170">
          <template #default="{ row }">
            <span v-if="row.return_time">{{ new Date(row.return_time).toLocaleString('zh-CN') }}</span>
            <span v-else style="color: #909399">-</span>
          </template>
        </el-table-column>
        <el-table-column label="备注" min-width="120">
          <template #default="{ row }">{{ row.remark || '-' }}</template>
        </el-table-column>
        <el-table-column label="操作" width="110" fixed="right">
          <template #default="{ row }">
            <el-button
              v-if="row.status === 'borrowed'"
              link
              type="success"
              @click="confirmReturn(row as RecordRow)"
            >
              确认归还
            </el-button>
          </template>
        </el-table-column>
      </el-table>
      <template #footer>
        <el-button @click="recordDialogVisible = false">关闭</el-button>
      </template>
    </el-dialog>

    <el-dialog
      v-model="itemDialogVisible"
      :title="editingItem ? '编辑物品' : '新增物品'"
      width="460px"
      destroy-on-close
    >
      <el-form label-width="90px">
        <el-form-item label="物品名称" required>
          <el-input v-model="itemForm.item_name" placeholder="如：足球、跳绳" />
        </el-form-item>
        <el-form-item label="物品类型">
          <el-input v-model="itemForm.type" placeholder="如：体育器材、文具" />
        </el-form-item>
        <el-form-item label="总数" required>
          <el-input-number v-model="itemForm.total_quantity" :min="1" style="width: 100%" />
        </el-form-item>
        <el-form-item label="存放位置">
          <el-input v-model="itemForm.location" placeholder="如：器材室A架" />
        </el-form-item>
        <el-form-item label="备注">
          <el-input v-model="itemForm.description" type="textarea" :rows="2" placeholder="选填" />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="itemDialogVisible = false">取消</el-button>
        <el-button type="primary" @click="submitItem">保存</el-button>
      </template>
    </el-dialog>
  </el-card>
</template>

<style scoped>
.toolbar {
  display: flex;
  justify-content: space-between;
  align-items: center;
}
.toolbar-left {
  display: flex;
  align-items: center;
  gap: 8px;
}
.toolbar-right {
  display: flex;
  gap: 12px;
  align-items: center;
}
.header-icon {
  font-size: 18px;
  color: var(--el-color-primary);
}
.header-title {
  font-size: 16px;
  font-weight: 600;
}
</style>
