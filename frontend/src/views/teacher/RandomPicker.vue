<script setup lang="ts">
import { ref, onMounted, computed } from 'vue'
import { ElMessage } from 'element-plus'
import { supabase } from '@/api/supabase'
import { useUserStore } from '@/stores/user'

const userStore = useUserStore()

interface StudentRow {
  id: string
  student_name: string
}

const students = ref<StudentRow[]>([])
const spinning = ref(false)
const wheelAngle = ref(0)          // 转盘当前角度
const displayName = ref('准备点名')  // 底部显示的名字
const finalPicked = ref<string | null>(null)
const history = ref<string[]>([])
const excludePicked = ref(true)
const confettiPieces = ref<Array<{ id: number; left: number; delay: number; color: string }>>([])

let rafId: number | null = null

/**
 * 加载本班学生作为转盘扇区数据源，并兼容 name 字段补齐 student_name
 * @returns 无返回值，成功后写入 students 列表
 */
async function loadStudents() {
  if (!userStore.classId) return
  try {
    const { data: studentRows } = await supabase
      .from('students')
      .select('*')
      .eq('class_id', userStore.classId)
      .order('student_name', { ascending: true })
    const studentList = (studentRows ?? []) as StudentRow[]
    studentList.forEach((student: any) => {
      if (!student.student_name && student.name) student.student_name = student.name
    })
    students.value = studentList
  } catch (err: unknown) {
    ElMessage.error(err instanceof Error && err.message ? err.message : '加载失败')
  }
}

// 可参与本轮抽取的候选名单（开启「不重复抽」时剔除已抽过的学生）
const pool = computed(() => {
  if (!excludePicked.value) return students.value
  if (history.value.length === 0) return students.value
  return students.value.filter((student) => !history.value.includes(student.student_name))
})

// 每个扇形的角度
const sliceAngle = computed(() => {
  const studentTotal = students.value.length
  return studentTotal > 0 ? 360 / studentTotal : 0
})

// 转盘扇形颜色（交替）
const sliceColors = ['#2B5CE6', '#F59E0B', '#10B981', '#8B5CF6', '#EF4444', '#06B6D4', '#EC4899', '#84CC16']

// ==== 核心：RAF 转盘动画 ====
/**
 * 开始一次随机抽取：先随机确定中奖学生并计算目标角度，再用 requestAnimationFrame 逐帧播放减速动画
 * 动画结束后固定指针角度、写入点名历史并撒花提示
 * @returns 无返回值（副作用：驱动 wheelAngle/displayName/finalPicked 等响应式状态）
 */
function startPick() {
  if (spinning.value) return
  if (students.value.length === 0) {
    ElMessage.warning('本班暂无学生')
    return
  }
  if (pool.value.length === 0) {
    ElMessage.info('已全部抽过，点击"重置"重新开始')
    return
  }

  spinning.value = true
  finalPicked.value = null
  confettiPieces.value = []

  // 选最终目标
  const pickedStudent = pool.value[Math.floor(Math.random() * pool.value.length)]
  const finalName = pickedStudent.student_name
  const finalIdx = students.value.findIndex((student) => student.student_name === finalName)

  // 目标角度：当前角度 + 5-8 圈 + 指向目标扇形中心的偏移
  const angleModAtStart = ((wheelAngle.value % 360) + 360) % 360
  // 指针在顶部（0°），转盘顺时针转，所以角度增加时，对应的扇形索引 = floor(((360 - currentAngle + 360) % 360) / sliceAngle)
  // 让指针指向目标扇形中心：
  const targetOffset = 360 - (finalIdx * sliceAngle.value + sliceAngle.value / 2)
  const randomJitter = (Math.random() - 0.5) * (sliceAngle.value * 0.6) // 小抖动增加真实感
  const fullTurns = 6 + Math.floor(Math.random() * 3) // 6-8 圈
  const targetAngle = wheelAngle.value + (fullTurns * 360) + (targetOffset - angleModAtStart) + randomJitter

  // 动画参数
  const duration = 3000 // 3 秒
  const startAngle = wheelAngle.value
  const startTime = performance.now()

  // easing: easeOutQuart（强减速）
  function easeOutQuart(progress: number): number {
    return 1 - Math.pow(1 - progress, 4)
  }

  function frame(timestamp: number) {
    const elapsed = timestamp - startTime
    const progress = Math.min(1, elapsed / duration)
    const eased = easeOutQuart(progress)
    wheelAngle.value = startAngle + (targetAngle - startAngle) * eased

    // 实时更新底部显示的名字（根据当前角度反算指针指向的扇形）
    const angleModNow = ((wheelAngle.value % 360) + 360) % 360
    const pointerAngle = (360 - angleModNow + 360) % 360
    const pointerIdx = Math.floor(pointerAngle / sliceAngle.value) % students.value.length
    displayName.value = students.value[pointerIdx]?.student_name || '点名中…'

    if (progress < 1) {
      rafId = requestAnimationFrame(frame)
    } else {
      // 结束
      spinning.value = false
      wheelAngle.value = targetAngle
      displayName.value = finalName
      finalPicked.value = finalName
      history.value.unshift(finalName)
      burstConfetti()
      ElMessage.success(`🎉 抽到 ${finalName}！`)
      rafId = null
    }
  }

  rafId = requestAnimationFrame(frame)
}

/**
 * 生成 50 片随机位置/颜色/延迟的纸屑，用于抽中后的撒花动画（2.4 秒后自动清空）
 */
function burstConfetti() {
  const colors = ['#2B5CE6', '#F59E0B', '#10B981', '#EF4444', '#8B5CF6', '#EC4899']
  confettiPieces.value = Array.from({ length: 50 }).map((_, pieceIndex) => ({
    id: Date.now() + pieceIndex,
    left: Math.random() * 100,
    delay: Math.random() * 0.4,
    color: colors[Math.floor(Math.random() * colors.length)],
  }))
  setTimeout(() => { confettiPieces.value = [] }, 2400)
}

/**
 * 重置转盘：停掉进行中的动画帧，清空点名历史与抽中结果，角度归零
 */
function resetHistory() {
  if (rafId) { cancelAnimationFrame(rafId); rafId = null }
  spinning.value = false
  wheelAngle.value = 0
  history.value = []
  finalPicked.value = null
  displayName.value = '准备点名'
  ElMessage.success('已重置')
}

onMounted(loadStudents)
</script>

<template>
  <div class="picker-page">
    <div class="page-header">
      <div class="title-wrap">
        <span class="sparkle">✨</span>
        <h1 class="page-title">幸运点名转盘</h1>
        <span class="sparkle">✨</span>
      </div>
      <div class="subtitle">{{ userStore.className || '本班' }} · 共 {{ students.length }} 人 · 转啊转～</div>
    </div>

    <!-- 转盘 -->
    <div class="wheel-stage">
      <!-- 固定指针 -->
      <div class="pointer"></div>

      <!-- 转盘本体 -->
      <div class="wheel-wrap">
        <svg
          v-if="students.length > 0"
          class="wheel"
          :viewBox="`-200 -200 400 400`"
          :style="{ transform: `rotate(${wheelAngle}deg)` }"
        >
          <!-- 每个扇形 -->
          <g v-for="(student, i) in students" :key="student.id">
            <path
              :d="`M0,0 L ${ 200 * Math.cos(((i * sliceAngle - 90) * Math.PI) / 180) }, ${ 200 * Math.sin(((i * sliceAngle - 90) * Math.PI) / 180) } A 200 200 0 0 1 ${ 200 * Math.cos((((i + 1) * sliceAngle - 90) * Math.PI) / 180) }, ${ 200 * Math.sin((((i + 1) * sliceAngle - 90) * Math.PI) / 180) } Z`"
              :fill="sliceColors[i % sliceColors.length]"
              stroke="#fff"
              stroke-width="2"
              opacity="0.92"
            />
            <text
              :x="`${ 120 * Math.cos(((i * sliceAngle + sliceAngle / 2 - 90) * Math.PI) / 180) }`"
              :y="`${ 120 * Math.sin(((i * sliceAngle + sliceAngle / 2 - 90) * Math.PI) / 180) }`"
              text-anchor="middle"
              dominant-baseline="middle"
              fill="#fff"
              font-size="16"
              font-weight="600"
              :transform="`rotate(${ i * sliceAngle + sliceAngle / 2 }, ${ 120 * Math.cos(((i * sliceAngle + sliceAngle / 2 - 90) * Math.PI) / 180) }, ${ 120 * Math.sin(((i * sliceAngle + sliceAngle / 2 - 90) * Math.PI) / 180) })`"
            >{{ student.student_name }}</text>
          </g>
          <!-- 中心装饰圆 -->
          <circle cx="0" cy="0" r="30" fill="#fff" stroke="#2B5CE6" stroke-width="3" />
          <text x="0" y="4" text-anchor="middle" font-size="20">🎯</text>
        </svg>
      </div>

      <!-- 彩色纸屑 -->
      <div class="confetti">
        <span
          v-for="confetti in confettiPieces"
          :key="confetti.id"
          class="confetti-piece"
          :style="{ left: confetti.left + '%', background: confetti.color, animationDelay: confetti.delay + 's' }"
        ></span>
      </div>
    </div>

    <!-- 底部控制 -->
    <div class="controls">
      <div class="name-readout" :class="{ 'picked': !!finalPicked }">
        <span class="name-label" v-if="!finalPicked && !spinning">等待开始…</span>
        <span class="name-label" v-else-if="spinning">🎲 旋转中…</span>
        <span class="name-label" v-else>🎉 本轮幸运儿</span>
        <span class="name-big">{{ displayName }}</span>
      </div>

      <button class="pick-btn" :disabled="spinning" @click="startPick">
        <span v-if="spinning" class="btn-inner">旋转中…</span>
        <span v-else class="btn-inner">🎲 开始点名</span>
      </button>

      <div class="options">
        <el-switch
          v-model="excludePicked"
          active-text="不重复抽"
          inactive-text="可重复"
          style="--el-switch-on-color: #2B5CE6"
        />
        <el-button size="small" @click="resetHistory">🔄 重置转盘</el-button>
      </div>
    </div>

    <!-- 点名历史 -->
    <div v-if="history.length > 0" class="history-wrap">
      <div class="history-title">本次已抽（{{ history.length }}）</div>
      <div class="history-list">
        <span v-for="(name, historyIdx) in history" :key="name + historyIdx" class="history-chip" :class="{ crown: historyIdx === 0 }">
          {{ historyIdx === 0 ? '👑' : '' }} {{ name }}
        </span>
      </div>
    </div>
  </div>
</template>

<style scoped>
.picker-page {
  min-height: calc(100vh - 120px);
  background:
    radial-gradient(ellipse at top, #EBF1FE 0%, transparent 55%),
    radial-gradient(ellipse at bottom right, #FEF3C7 0%, transparent 50%),
    linear-gradient(135deg, #F8FAFF 0%, #EFF2FF 100%);
  border-radius: 16px;
  padding: 28px 24px;
  position: relative;
  overflow: hidden;
}

/* 标题 */
.page-header { text-align: center; margin-bottom: 16px; }
.title-wrap { display: inline-flex; align-items: center; gap: 10px; }
.page-title {
  font-size: 28px; font-weight: 800;
  background: linear-gradient(135deg, #2B5CE6 0%, #8B5CF6 100%);
  -webkit-background-clip: text; background-clip: text; color: transparent;
  margin: 0; letter-spacing: 3px;
}
.sparkle { font-size: 24px; animation: twinkle 1.5s ease-in-out infinite alternate; }
.sparkle:last-child { animation-delay: 0.3s; }
@keyframes twinkle {
  from { transform: scale(0.9) rotate(-8deg); opacity: 0.7; }
  to   { transform: scale(1.2) rotate(8deg);  opacity: 1; }
}
.subtitle { color: #6B7280; margin-top: 4px; font-size: 13px; }

/* 转盘舞台 */
.wheel-stage {
  position: relative;
  display: flex; justify-content: center; align-items: center;
  height: 460px;
  margin: 8px 0;
}

.pointer {
  position: absolute;
  top: -12px; left: 50%;
  transform: translateX(-50%);
  width: 0; height: 0;
  border-left: 20px solid transparent;
  border-right: 20px solid transparent;
  border-top: 40px solid #EF4444;
  filter: drop-shadow(0 4px 6px rgba(0,0,0,0.25));
  z-index: 10;
}
.pointer::after {
  content: '';
  position: absolute;
  top: -46px; left: -10px;
  width: 20px; height: 20px;
  background: #EF4444;
  border-radius: 50%;
  border: 3px solid #fff;
}

.wheel-wrap {
  width: 400px; height: 400px;
  filter: drop-shadow(0 10px 30px rgba(43, 92, 230, 0.3));
}
.wheel {
  width: 100%; height: 100%;
  transition: transform 0.02s linear; /* smooth but JS takes over via RAF */
}

/* 纸屑 */
.confetti { position: absolute; inset: 0; pointer-events: none; overflow: hidden; z-index: 20; }
.confetti-piece {
  position: absolute; top: 20%;
  width: 10px; height: 18px; border-radius: 2px;
  animation: fall 2s ease-in forwards;
  animation-fill-mode: both;
}
@keyframes fall {
  0%   { transform: translateY(0) rotate(0deg) scale(1); opacity: 1; }
  100% { transform: translateY(280px) rotate(720deg) scale(0.5); opacity: 0; }
}

/* 控制区 */
.controls {
  display: flex; flex-direction: column; align-items: center; gap: 14px;
}

.name-readout {
  text-align: center;
  padding: 10px 40px;
  background: rgba(255,255,255,0.7);
  backdrop-filter: blur(6px);
  border-radius: 14px;
  border: 1px solid rgba(43,92,230,0.15);
  min-width: 280px;
  transition: all 0.3s;
}
.name-readout.picked {
  background: linear-gradient(135deg, rgba(43,92,230,0.1), rgba(139,92,246,0.1));
  border-color: #2B5CE6;
  box-shadow: 0 0 0 6px rgba(43,92,230,0.1), 0 4px 20px rgba(43,92,230,0.2);
}
.name-label { display: block; font-size: 13px; color: #6B7280; margin-bottom: 2px; }
.name-big {
  display: block;
  font-size: 26px; font-weight: 800;
  color: #1F2937;
  letter-spacing: 4px;
}
.name-readout.picked .name-big {
  background: linear-gradient(135deg, #2B5CE6, #8B5CF6);
  -webkit-background-clip: text; background-clip: text; color: transparent;
  animation: namePop 0.6s cubic-bezier(0.34, 1.56, 0.64, 1);
}
@keyframes namePop {
  0% { transform: scale(0.5); opacity: 0; }
  60% { transform: scale(1.15); }
  100% { transform: scale(1); opacity: 1; }
}

.pick-btn {
  position: relative;
  padding: 14px 48px;
  font-size: 18px; font-weight: 700;
  color: #fff;
  background: linear-gradient(135deg, #2B5CE6 0%, #1E3A8A 100%);
  border: none; border-radius: 50px;
  cursor: pointer;
  box-shadow: 0 8px 24px rgba(43, 92, 230, 0.35);
  transition: all 0.2s;
  letter-spacing: 2px;
  overflow: hidden;
}
.pick-btn::before {
  content: '';
  position: absolute; inset: -4px;
  background: conic-gradient(from 0deg, #2B5CE6, #8B5CF6, #EC4899, #2B5CE6);
  border-radius: 50px; z-index: -1;
  filter: blur(14px); opacity: 0.5;
  animation: haloSpin 3s linear infinite;
}
@keyframes haloSpin { to { transform: rotate(360deg); } }
.pick-btn:hover:not(:disabled) { transform: translateY(-2px); box-shadow: 0 12px 32px rgba(43, 92, 230, 0.45); }
.pick-btn:active:not(:disabled) { transform: translateY(0); }
.pick-btn:disabled { opacity: 0.6; cursor: not-allowed; }

.options { display: flex; align-items: center; gap: 14px; color: #6B7280; font-size: 13px; }

/* 历史 */
.history-wrap {
  margin-top: 24px;
  background: rgba(255, 255, 255, 0.7);
  backdrop-filter: blur(8px);
  border-radius: 14px;
  padding: 14px 18px;
  border: 1px solid rgba(43, 92, 230, 0.1);
}
.history-title { font-size: 13px; color: #6B7280; margin-bottom: 8px; font-weight: 500; }
.history-list { display: flex; flex-wrap: wrap; gap: 8px; }
.history-chip {
  padding: 5px 12px; background: #fff; border-radius: 20px;
  border: 1px solid #E5E9F0; font-size: 13px; color: #374151;
}
.history-chip.crown {
  background: linear-gradient(135deg, #2B5CE6, #8B5CF6);
  color: #fff; border-color: transparent; font-weight: 600;
}
</style>
