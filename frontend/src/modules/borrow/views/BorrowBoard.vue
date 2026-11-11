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

const borrowItemList = ref<ItemRow[]>([])
const itemsLoading = ref(false)
const schoolClasses = ref<ClassOpt[]>([])
const filterClassId = ref<string>('')
const itemSearchKeyword = ref('')

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

// 常用物品类型预设（可下拉选择，也可直接输入自定义类型）
const PRESET_ITEM_TYPES = [
  '体育器材', '文具教具', '图书绘本', '实验器材',
  '清洁工具', '电子产品', '艺术用品', '生活用品',
]

/** 物品类型下拉选项：预设类型 + 台账中已存在的自定义类型 */
const itemTypeOptions = computed(() => {
  const existingTypes = new Set(
    borrowItemList.value.map((borrowItem) => borrowItem.type).filter((typeName): typeName is string => !!typeName),
  )
  const presetOptions = PRESET_ITEM_TYPES.map((typeName) => ({
    value: typeName,
    label: existingTypes.has(typeName) ? typeName : typeName,
  }))
  const customTypeOptions = Array.from(existingTypes)
    .filter((typeName) => !PRESET_ITEM_TYPES.includes(typeName))
    .map((typeName) => ({ value: typeName, label: typeName }))
  return [...presetOptions, ...customTypeOptions]
})

const studentOptions = ref<StudentOpt[]>([])

/** 按搜索关键词过滤后的物品列表，用于表格展示 */
const filteredItems = computed(() => {
  const itemKeyword = itemSearchKeyword.value.trim().toLowerCase()
  if (!itemKeyword) return borrowItemList.value
  return borrowItemList.value.filter((borrowItem) => borrowItem.item_name.toLowerCase().includes(itemKeyword))
})

/**
 * 加载班级下拉数据。
 * 借阅是**校内公开**的数据（RLS 已按 school_id 放行），教师与学生管理员一样
 * 可以浏览全校物品，因此这里统一加载本校全部班级，默认不筛选（全部班级）。
 * @returns 无返回值（副作用：写入 schoolClasses；filterClassId 保持为空＝全部）
 */
async function loadSchoolClasses() {
  if (!userStore.schoolId) return
  try {
    const { data: classRows, error } = await supabase
      .from('classes')
      .select('id, class_name')
      .eq('school_id', userStore.schoolId)
    if (error) throw error
    schoolClasses.value = (classRows ?? []) as ClassOpt[]
    filterClassId.value = ''
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '加载班级失败')
  }
}

/**
 * 加载借出学生下拉数据。
 * 已选班级时按班级过滤；学校管理员未选班级时按学校范围过滤。
 * @returns 无返回值（副作用：写入 studentOptions）
 */
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
      studentOptions.value = []
      return
    }
    const { data: studentRows, error } = await query
    if (error) throw error
    studentOptions.value = (studentRows ?? []) as StudentOpt[]
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '加载学生列表失败')
  }
}

/**
 * 加载物品台账列表，并在列表就绪后刷新「最近借出人」展示。
 * 已选班级时按班级查询，否则按所属学校查询。
 * @returns 无返回值（副作用：写入 borrowItemList，并触发 loadRecentBorrowers）
 */
async function loadItems() {
  if (!userStore.schoolId) return
  itemsLoading.value = true
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
    const { data: itemRows, error } = await query
    if (error) throw error
    borrowItemList.value = (itemRows ?? []) as ItemRow[]
    await loadRecentBorrowers()
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '加载物品列表失败')
  } finally {
    itemsLoading.value = false
  }
}

/**
 * 统计每件物品最近一次「借出中」记录对应的学生姓名，用于列表展示。
 * 先按物品 ID 批量取出未归还的借阅记录，再一次性换取学生姓名，避免逐条查询。
 * @returns 无返回值（副作用：写入 recentBorrowerMap）
 */
async function loadRecentBorrowers() {
  if (borrowItemList.value.length === 0) {
    recentBorrowerMap.value = {}
    return
  }
  const borrowedItemIds = borrowItemList.value.map((borrowItem) => borrowItem.id)
  try {
    const { data: borrowRecords, error: recordsError } = await supabase
      .from('borrow_records')
      .select('id, item_id, student_id, status, borrow_date')
      .eq('status', 'borrowed')
      .in('item_id', borrowedItemIds)
      .order('borrow_date', { ascending: false })
    if (recordsError) throw recordsError

    const studentNameMap: Record<string, string> = {}
    const studentIdList = Array.from(new Set((borrowRecords ?? []).map((recordRow: any) => recordRow.student_id)))
    if (studentIdList.length > 0) {
      const { data: studentRows, error: studentsError } = await supabase
        .from('students')
        .select('id, student_name')
        .in('id', studentIdList)
      if (studentsError) throw studentsError
      for (const studentRow of (studentRows ?? []) as StudentOpt[]) {
        studentNameMap[studentRow.id] = studentRow.student_name
      }
    }

    const latestBorrowerMap: Record<string, string> = {}
    for (const recordRow of (borrowRecords ?? []) as any[]) {
      if (!latestBorrowerMap[recordRow.item_id]) {
        latestBorrowerMap[recordRow.item_id] = studentNameMap[recordRow.student_id] || recordRow.student_id
      }
    }
    recentBorrowerMap.value = latestBorrowerMap
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '加载最近借出人失败')
  }
}

/**
 * 打开借出登记弹窗，并带出被借物品的基础信息。
 * @param itemRow 被借出的物品行
 * @returns 无返回值；物品无可用数量时仅提示，不打开弹窗
 */
function openBorrowDialog(itemRow: ItemRow) {
  if (itemRow.available_quantity <= 0) {
    ElMessage.warning('该物品暂无可用数量')
    return
  }
  borrowForm.value = {
    item_id: itemRow.id,
    item_name: itemRow.item_name,
    qty: Math.min(1, itemRow.available_quantity),
    student_id: '',
    remark: '',
  }
  borrowDialogVisible.value = true
}

/**
 * 提交借出登记：校验借出数量后写入一条 borrow_records 记录（默认 7 天后归还）。
 * @returns 无返回值；成功后关闭弹窗并刷新物品列表
 */
async function submitBorrow() {
  const borrowDraft = borrowForm.value
  if (!borrowDraft.student_id) {
    ElMessage.warning('请选择借出学生')
    return
  }
  if (borrowDraft.qty <= 0) {
    ElMessage.warning('借出数量必须大于 0')
    return
  }
  const targetItem = borrowItemList.value.find((borrowItem) => borrowItem.id === borrowDraft.item_id)
  if (!targetItem) return
  if (borrowDraft.qty > targetItem.available_quantity) {
    ElMessage.warning(`借出数量超过可用数量 ${targetItem.available_quantity}`)
    return
  }
  try {
    const { data: studentRow } = await supabase
      .from('students')
      .select('student_name')
      .eq('id', borrowDraft.student_id)
      .maybeSingle()
    const studentName = (studentRow as any)?.student_name || ''

    const borrowDate = new Date().toISOString()
    const expectedReturn = new Date(Date.now() + 7 * 86400000).toISOString()

    const studentClassId = studentOptions.value.find((studentOption) => studentOption.id === borrowDraft.student_id)?.class_id || filterClassId.value || userStore.classId || undefined

    const { error } = await supabase
      .from('borrow_records')
      .insert({
        item_id: borrowDraft.item_id,
        student_id: borrowDraft.student_id,
        borrower_name: studentName,
        borrow_date: borrowDate,
        expected_return_date: expectedReturn,
        status: 'borrowed',
        qty: borrowDraft.qty,
        school_id: userStore.schoolId,
        class_id: studentClassId,
        operator_user_id: userStore.id,
        remark: borrowDraft.remark || null,
      })
      .select()
    if (error) throw error
    ElMessage.success('借出登记成功')
    borrowDialogVisible.value = false
    await loadItems()
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '借出登记失败')
  }
}

/**
 * 打开某件物品的归还记录弹窗，并加载它的全部借阅流水（含借出学生姓名）。
 * @param itemRow 目标物品行
 * @returns 无返回值（副作用：写入 currentItem 与 currentRecords）
 */
async function openRecordsDialog(itemRow: ItemRow) {
  currentItem.value = itemRow
  recordDialogVisible.value = true
  recordsLoading.value = true
  try {
    const { data: recordRows, error } = await supabase
      .from('borrow_records')
      .select('*')
      .eq('item_id', itemRow.id)
      .order('borrow_date', { ascending: false })
    if (error) throw error
    const borrowRecordRows = (recordRows ?? []) as any[]

    const studentIdList = Array.from(new Set(borrowRecordRows.map((recordRow) => recordRow.student_id)))
    const studentNameMap: Record<string, string> = {}
    if (studentIdList.length > 0) {
      const { data: studentRows } = await supabase
        .from('students')
        .select('id, student_name')
        .in('id', studentIdList)
      for (const studentRow of (studentRows ?? []) as StudentOpt[]) {
        studentNameMap[studentRow.id] = studentRow.student_name
      }
    }

    currentRecords.value = borrowRecordRows.map((recordRow) => ({
      id: recordRow.id,
      item_id: recordRow.item_id,
      student_id: recordRow.student_id,
      borrow_date: recordRow.borrow_date,
      return_time: recordRow.return_time || recordRow.actual_return_date,
      status: recordRow.status,
      qty: recordRow.qty ?? 1,
      remark: recordRow.remark,
      borrower_name: recordRow.borrower_name || studentNameMap[recordRow.student_id] || recordRow.student_id,
    }))
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '加载归还记录失败')
  } finally {
    recordsLoading.value = false
  }
}

/**
 * 确认归还：把指定借阅记录的状态改为已归还，并记录归还时间。
 * @param recordRow 待归还的借阅记录
 * @returns 无返回值；成功后刷新记录弹窗与物品列表
 */
async function confirmReturn(recordRow: RecordRow) {
  try {
    await ElMessageBox.confirm(
      `确认将「${currentItem.value?.item_name}」的 ${recordRow.borrower_name} ${recordRow.qty} 件登记为已归还？`,
      '确认归还',
      { type: 'warning' },
    )
  } catch {
    // 用户在确认框中取消操作，此处直接结束，无需额外处理
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
      .eq('id', recordRow.id)
    if (error) throw error
    ElMessage.success('归还成功')
    await openRecordsDialog(currentItem.value!)
    await loadItems()
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '归还操作失败')
  }
}

/** 打开「新增物品」弹窗，并把表单重置为默认值 */
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

/**
 * 打开「编辑物品」弹窗，并把选中物品的字段回填到表单。
 * @param itemRow 待编辑的物品行
 * @returns 无返回值
 */
function openEditItemDialog(itemRow: ItemRow) {
  editingItem.value = itemRow
  itemForm.value = {
    item_name: itemRow.item_name,
    type: itemRow.type,
    total_quantity: itemRow.total_quantity,
    location: itemRow.location || '',
    description: itemRow.description || '',
  }
  itemDialogVisible.value = true
}

/**
 * 保存物品表单：编辑时按总数差额同步可用数量，新增时可用数量等于总数。
 * @returns 无返回值；成功后关闭弹窗并刷新物品列表
 */
async function submitItem() {
  const itemDraft = itemForm.value
  if (!itemDraft.item_name.trim()) {
    ElMessage.warning('请填写物品名称')
    return
  }
  if (itemDraft.total_quantity <= 0) {
    ElMessage.warning('总数必须大于 0')
    return
  }
  try {
    if (editingItem.value) {
      const availableDelta = itemDraft.total_quantity - editingItem.value.total_quantity
      const newAvailable = Math.max(0, editingItem.value.available_quantity + availableDelta)
      const { error } = await supabase
        .from('borrow_items')
        .update({
          item_name: itemDraft.item_name,
          type: itemDraft.type,
          total_quantity: itemDraft.total_quantity,
          location: itemDraft.location || null,
          description: itemDraft.description || null,
          available_quantity: newAvailable,
        })
        .eq('id', editingItem.value.id)
      if (error) throw error
      ElMessage.success('更新物品成功')
    } else {
      // 物品的归属班级：优先跟随当前筛选的班级，未筛选时落到自己绑定的班。
      // 注：借阅已改为**全校粒度**（RLS 只校验 school_id = 本校），class_id 仅用于分类展示，
      // 不再有"必须挂本班否则 403"的限制；保留兜底是为了让物品有明确归属、便于按班筛选。
      const classId = filterClassId.value || userStore.classId || undefined
      if (userStore.role === 'teacher' && !classId) {
        ElMessage.warning('未获取到班级信息，请稍后重试')
        return
      }
      const { error } = await supabase.from('borrow_items').insert({
        item_name: itemDraft.item_name.trim(),
        type: itemDraft.type?.trim() || '其他',
        total_quantity: itemDraft.total_quantity,
        available_quantity: itemDraft.total_quantity,
        location: itemDraft.location || null,
        description: itemDraft.description || null,
        school_id: userStore.schoolId,
        class_id: classId,
      })
      if (error) throw error
      ElMessage.success('新增物品成功')
    }
    itemDialogVisible.value = false
    await loadItems()
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '保存物品失败')
  }
}

/**
 * 删除物品：存在「借出中」记录时禁止删除。
 * @param itemRow 待删除的物品行
 * @returns 无返回值；成功后刷新物品列表
 */
async function deleteItem(itemRow: ItemRow) {
  try {
    await ElMessageBox.confirm(`确定删除物品「${itemRow.item_name}」吗？`, '删除确认', { type: 'warning' })
  } catch {
    // 用户在确认框中取消删除，直接结束
    return
  }
  try {
    const { data: borrowedRecords } = await supabase
      .from('borrow_records')
      .select('id')
      .eq('item_id', itemRow.id)
      .eq('status', 'borrowed')
    if ((borrowedRecords ?? []).length > 0) {
      ElMessage.warning('该物品尚有未归还记录，无法删除')
      return
    }
    const { error } = await supabase.from('borrow_items').delete().eq('id', itemRow.id)
    if (error) throw error
    ElMessage.success('删除成功')
    await loadItems()
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '删除物品失败')
  }
}

watch(filterClassId, async () => {
  await loadStudents()
  await loadItems()
})

// 说明：本页班级筛选（filterClassId）是页面自有状态，不再跟随顶栏班级下拉。
// 借阅数据按 school_id 全校共享，顶栏切班对本页无影响；学生的可借范围也由本页下拉决定。

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
          <span class="header-title">公共物品借阅</span>
          <el-select
            v-if="schoolClasses.length > 0"
            v-model="filterClassId"
            clearable
            placeholder="按班级筛选"
            style="width: 180px; margin-left: 12px"
          >
            <el-option label="全部班级" value="" />
            <el-option
              v-for="classOption in schoolClasses"
              :key="classOption.id"
              :label="classOption.class_name"
              :value="classOption.id"
            />
          </el-select>
          <el-tag type="info" style="margin-left: 12px">
            {{ filterClassId ? (schoolClasses.find((c) => c.id === filterClassId)?.class_name || '') : '全校' }}
          </el-tag>
        </div>
        <div class="toolbar-right">
          <el-input
            v-model="itemSearchKeyword"
            placeholder="搜索物品名称"
            :prefix-icon="Search"
            clearable
            style="width: 220px"
          />
          <el-button type="primary" :icon="Plus" @click="openAddItemDialog">新增物品</el-button>
        </div>
      </div>
    </template>

    <el-table :data="filteredItems" v-loading="itemsLoading" stripe style="width: 100%">
      <el-table-column prop="item_name" label="物品名称" min-width="140" />
      <el-table-column prop="type" label="类型" min-width="110" />
      <el-table-column prop="total_quantity" label="总数" width="90" />
      <el-table-column label="可用数量" width="100">
        <template #default="{ row: itemRow }">
          <el-tag :type="itemRow.available_quantity > 0 ? 'success' : 'danger'">
            {{ itemRow.available_quantity }}
          </el-tag>
        </template>
      </el-table-column>
      <el-table-column prop="location" label="存放位置" min-width="140">
        <template #default="{ row: itemRow }">{{ itemRow.location || '-' }}</template>
      </el-table-column>
      <el-table-column label="最近借出人" min-width="140">
        <template #default="{ row: itemRow }">
          <span v-if="recentBorrowerMap[itemRow.id]">{{ recentBorrowerMap[itemRow.id] }}</span>
          <span v-else style="color: #909399">暂无借出</span>
        </template>
      </el-table-column>
      <el-table-column label="操作" width="260" fixed="right">
        <template #default="{ row: itemRow }">
          <el-button link type="primary" :disabled="(itemRow as ItemRow).available_quantity <= 0" @click="openBorrowDialog(itemRow as ItemRow)">
            借出
          </el-button>
          <el-button link type="primary" @click="openRecordsDialog(itemRow as ItemRow)">归还记录</el-button>
          <el-button link type="warning" :icon="Edit" @click="openEditItemDialog(itemRow as ItemRow)" />
          <el-button link type="danger" :icon="Delete" @click="deleteItem(itemRow as ItemRow)" />
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
            :max="borrowItemList.find((borrowItem) => borrowItem.id === borrowForm.item_id)?.available_quantity || 1"
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
              v-for="studentOption in studentOptions"
              :key="studentOption.id"
              :label="studentOption.student_name"
              :value="studentOption.id"
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
          <template #default="{ row: recordRow }">
            <el-tag v-if="recordRow.status === 'borrowed'" type="danger">借出中</el-tag>
            <el-tag v-else-if="recordRow.status === 'returned'" type="success">已归还</el-tag>
            <el-tag v-else type="warning">逾期</el-tag>
          </template>
        </el-table-column>
        <el-table-column label="学生" min-width="110">
          <template #default="{ row: recordRow }">{{ recordRow.borrower_name }}</template>
        </el-table-column>
        <el-table-column prop="qty" label="数量" width="70" />
        <el-table-column label="借出时间" min-width="170">
          <template #default="{ row: recordRow }">{{ new Date(recordRow.borrow_date).toLocaleString('zh-CN') }}</template>
        </el-table-column>
        <el-table-column label="归还时间" min-width="170">
          <template #default="{ row: recordRow }">
            <span v-if="recordRow.return_time">{{ new Date(recordRow.return_time).toLocaleString('zh-CN') }}</span>
            <span v-else style="color: #909399">-</span>
          </template>
        </el-table-column>
        <el-table-column label="备注" min-width="120">
          <template #default="{ row: recordRow }">{{ recordRow.remark || '-' }}</template>
        </el-table-column>
        <el-table-column label="操作" width="110" fixed="right">
          <template #default="{ row: recordRow }">
            <el-button
              v-if="recordRow.status === 'borrowed'"
              link
              type="success"
              @click="confirmReturn(recordRow as RecordRow)"
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
          <el-select
            v-model="itemForm.type"
            filterable
            allow-create
            default-first-option
            placeholder="选择常用类型，或输入自定义类型"
            style="width: 100%"
          >
            <el-option
              v-for="itemOption in itemTypeOptions"
              :key="itemOption.value"
              :value="itemOption.value"
              :label="itemOption.label"
            />
          </el-select>
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
