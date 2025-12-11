<script setup lang="ts">
import { ref, onMounted, onUnmounted, computed, watch } from "vue"
import { api } from "../stores/auth"
import Layout from "../components/Layout.vue"
import { Line } from "vue-chartjs"
import {
  Chart as ChartJS,
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Title,
  Tooltip,
  Legend,
  Filler
} from "chart.js"
import { Cpu, MemoryStick, HardDrive, Activity, CheckCircle2, XCircle, Clock, RefreshCw, TrendingUp } from "lucide-vue-next"

// 注册 Chart.js 组件
ChartJS.register(CategoryScale, LinearScale, PointElement, LineElement, Title, Tooltip, Legend, Filler)

const systemStatus = ref<any>(null)
const services = ref<any[]>([])
const loading = ref(true)
const refreshing = ref(false)
const autoRefresh = ref(true)
let refreshInterval: number | null = null

// 历史数据（保留最近60个点，每5秒一个点 = 5分钟数据）
const MAX_HISTORY = 60
const cpuHistory = ref<number[]>([])
const memoryHistory = ref<number[]>([])
const timeLabels = ref<string[]>([])

function formatBytes(bytes: number) {
  if (bytes === 0) return "0 B"
  const k = 1024
  const sizes = ["B", "KB", "MB", "GB", "TB"]
  const i = Math.floor(Math.log(bytes) / Math.log(k))
  return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + " " + sizes[i]
}

function getCpuColor(usage: number) {
  if (usage < 50) return "bg-emerald-500"
  if (usage < 80) return "bg-amber-500"
  return "bg-red-500"
}

function getMemoryColor(percent: number) {
  if (percent < 60) return "bg-blue-500"
  if (percent < 85) return "bg-amber-500"
  return "bg-red-500"
}

function getDiskColor(percent: number) {
  if (percent < 70) return "bg-purple-500"
  if (percent < 90) return "bg-amber-500"
  return "bg-red-500"
}

const activeServices = computed(() => services.value.filter(s => s.active).length)

// 图表配置
const chartOptions = {
  responsive: true,
  maintainAspectRatio: false,
  animation: { duration: 300 },
  scales: {
    x: {
      display: true,
      grid: { color: "rgba(100, 116, 139, 0.1)" },
      ticks: { color: "#64748b", maxRotation: 0, maxTicksLimit: 6 }
    },
    y: {
      display: true,
      min: 0,
      max: 100,
      grid: { color: "rgba(100, 116, 139, 0.1)" },
      ticks: { color: "#64748b", callback: (v: any) => v + "%" }
    }
  },
  plugins: {
    legend: { display: false },
    tooltip: {
      backgroundColor: "#1e293b",
      titleColor: "#f1f5f9",
      bodyColor: "#94a3b8",
      borderColor: "#334155",
      borderWidth: 1
    }
  },
  elements: {
    point: { radius: 0, hoverRadius: 4 },
    line: { tension: 0.3 }
  }
}

const cpuChartData = computed(() => ({
  labels: timeLabels.value,
  datasets: [{
    label: "CPU",
    data: cpuHistory.value,
    borderColor: "#10b981",
    backgroundColor: "rgba(16, 185, 129, 0.1)",
    fill: true,
    borderWidth: 2
  }]
}))

const memoryChartData = computed(() => ({
  labels: timeLabels.value,
  datasets: [{
    label: "内存",
    data: memoryHistory.value,
    borderColor: "#3b82f6",
    backgroundColor: "rgba(59, 130, 246, 0.1)",
    fill: true,
    borderWidth: 2
  }]
}))

function addHistoryPoint(cpu: number, memory: number) {
  const now = new Date()
  const timeStr = now.toLocaleTimeString("zh-CN", { hour: "2-digit", minute: "2-digit", second: "2-digit" })
  
  cpuHistory.value.push(cpu)
  memoryHistory.value.push(memory)
  timeLabels.value.push(timeStr)
  
  // 保持最大历史长度
  if (cpuHistory.value.length > MAX_HISTORY) {
    cpuHistory.value.shift()
    memoryHistory.value.shift()
    timeLabels.value.shift()
  }
}

async function fetchData(isAuto = false) {
  if (!isAuto) refreshing.value = true
  try {
    const [statusRes, servicesRes] = await Promise.all([
      api.get("/system/status"),
      api.get("/system/services")
    ])
    if (statusRes.data.status) {
      systemStatus.value = statusRes.data.data
      // 添加历史数据点
      addHistoryPoint(
        statusRes.data.data.cpu?.usage || 0,
        statusRes.data.data.memory?.percent || 0
      )
    }
    if (servicesRes.data.status) services.value = servicesRes.data.data
  } catch (e) {
    console.error("Failed to fetch data:", e)
  } finally {
    loading.value = false
    refreshing.value = false
  }
}

async function refresh() {
  await fetchData(false)
}

function toggleAutoRefresh() {
  autoRefresh.value = !autoRefresh.value
}

// 自动刷新逻辑
watch(autoRefresh, (enabled) => {
  if (enabled) {
    refreshInterval = window.setInterval(() => fetchData(true), 5000)
  } else if (refreshInterval) {
    clearInterval(refreshInterval)
    refreshInterval = null
  }
}, { immediate: true })

onMounted(() => {
  fetchData()
  // 启动自动刷新
  if (autoRefresh.value) {
    refreshInterval = window.setInterval(() => fetchData(true), 5000)
  }
})

onUnmounted(() => {
  if (refreshInterval) {
    clearInterval(refreshInterval)
  }
})
</script>

<template>
  <Layout>
    <div class="p-6">
      <!-- Title -->
      <div class="flex items-center justify-between mb-6">
        <div>
          <h1 class="text-2xl font-bold text-white">仪表盘</h1>
          <p class="text-slate-400 mt-1">服务器状态监控</p>
        </div>
        <div class="flex items-center gap-3">
          <button
            @click="toggleAutoRefresh"
            :class="['px-3 py-2 rounded-lg text-sm transition flex items-center gap-2', autoRefresh ? 'bg-emerald-600 hover:bg-emerald-700 text-white' : 'bg-slate-700 hover:bg-slate-600 text-slate-300']"
          >
            <TrendingUp class="w-4 h-4" />
            {{ autoRefresh ? "实时监控中" : "已暂停" }}
          </button>
          <button @click="refresh" :disabled="refreshing" class="btn-secondary">
            <RefreshCw :class="['w-4 h-4', refreshing && 'animate-spin']" />
            刷新
          </button>
        </div>
      </div>

      <div v-if="loading" class="flex items-center justify-center py-20">
        <RefreshCw class="w-8 h-8 text-blue-500 animate-spin" />
      </div>

      <template v-else>
        <!-- System Stats Cards -->
        <div class="grid grid-cols-1 md:grid-cols-3 gap-6 mb-6">
          <!-- CPU -->
          <div class="bg-slate-800 rounded-lg p-6">
            <div class="flex items-center gap-3 mb-4">
              <div class="w-10 h-10 rounded-lg bg-emerald-500/20 flex items-center justify-center">
                <Cpu class="w-5 h-5 text-emerald-400" />
              </div>
              <div>
                <p class="text-sm text-slate-400">CPU 使用率</p>
                <p class="text-2xl font-bold text-white">{{ systemStatus?.cpu?.usage?.toFixed(1) }}%</p>
              </div>
            </div>
            <div class="h-2 bg-slate-700 rounded-full overflow-hidden">
              <div :class="['h-full transition-all', getCpuColor(systemStatus?.cpu?.usage || 0)]" :style="{ width: (systemStatus?.cpu?.usage || 0) + '%' }"></div>
            </div>
            <p class="text-xs text-slate-500 mt-2">{{ systemStatus?.cpu?.cores }} 核心</p>
          </div>

          <!-- Memory -->
          <div class="bg-slate-800 rounded-lg p-6">
            <div class="flex items-center gap-3 mb-4">
              <div class="w-10 h-10 rounded-lg bg-blue-500/20 flex items-center justify-center">
                <MemoryStick class="w-5 h-5 text-blue-400" />
              </div>
              <div>
                <p class="text-sm text-slate-400">内存使用</p>
                <p class="text-2xl font-bold text-white">{{ systemStatus?.memory?.percent?.toFixed(1) }}%</p>
              </div>
            </div>
            <div class="h-2 bg-slate-700 rounded-full overflow-hidden">
              <div :class="['h-full transition-all', getMemoryColor(systemStatus?.memory?.percent || 0)]" :style="{ width: (systemStatus?.memory?.percent || 0) + '%' }"></div>
            </div>
            <p class="text-xs text-slate-500 mt-2">{{ formatBytes(systemStatus?.memory?.used || 0) }} / {{ formatBytes(systemStatus?.memory?.total || 0) }}</p>
          </div>

          <!-- Disk -->
          <div class="bg-slate-800 rounded-lg p-6">
            <div class="flex items-center gap-3 mb-4">
              <div class="w-10 h-10 rounded-lg bg-purple-500/20 flex items-center justify-center">
                <HardDrive class="w-5 h-5 text-purple-400" />
              </div>
              <div>
                <p class="text-sm text-slate-400">磁盘使用</p>
                <p class="text-2xl font-bold text-white">{{ systemStatus?.disk?.percent?.toFixed(1) }}%</p>
              </div>
            </div>
            <div class="h-2 bg-slate-700 rounded-full overflow-hidden">
              <div :class="['h-full transition-all', getDiskColor(systemStatus?.disk?.percent || 0)]" :style="{ width: (systemStatus?.disk?.percent || 0) + '%' }"></div>
            </div>
            <p class="text-xs text-slate-500 mt-2">{{ formatBytes(systemStatus?.disk?.used || 0) }} / {{ formatBytes(systemStatus?.disk?.total || 0) }}</p>
          </div>
        </div>

        <!-- Real-time Charts -->
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
          <!-- CPU Chart -->
          <div class="bg-slate-800 rounded-lg p-6">
            <div class="flex items-center gap-3 mb-4">
              <div class="w-8 h-8 rounded-lg bg-emerald-500/20 flex items-center justify-center">
                <Cpu class="w-4 h-4 text-emerald-400" />
              </div>
              <h3 class="text-lg font-semibold text-white">CPU 使用率趋势</h3>
            </div>
            <div class="h-48">
              <Line v-if="cpuHistory.length > 0" :data="cpuChartData" :options="chartOptions" />
              <div v-else class="h-full flex items-center justify-center text-slate-500">
                收集数据中...
              </div>
            </div>
          </div>

          <!-- Memory Chart -->
          <div class="bg-slate-800 rounded-lg p-6">
            <div class="flex items-center gap-3 mb-4">
              <div class="w-8 h-8 rounded-lg bg-blue-500/20 flex items-center justify-center">
                <MemoryStick class="w-4 h-4 text-blue-400" />
              </div>
              <h3 class="text-lg font-semibold text-white">内存使用率趋势</h3>
            </div>
            <div class="h-48">
              <Line v-if="memoryHistory.length > 0" :data="memoryChartData" :options="chartOptions" />
              <div v-else class="h-full flex items-center justify-center text-slate-500">
                收集数据中...
              </div>
            </div>
          </div>
        </div>

        <!-- Services -->
        <div class="bg-slate-800 rounded-lg">
          <div class="px-6 py-4 border-b border-slate-700 flex items-center justify-between">
            <div class="flex items-center gap-3">
              <Activity class="w-5 h-5 text-slate-400" />
              <h2 class="text-lg font-semibold text-white">服务状态</h2>
            </div>
            <span class="px-2 py-1 rounded text-xs bg-green-600/20 text-green-400">{{ activeServices }}/{{ services.length }} 运行中</span>
          </div>
          <div class="p-6">
            <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
              <div v-for="service in services" :key="service.name" class="flex items-center justify-between p-4 bg-slate-700/50 rounded-lg">
                <div class="flex items-center gap-3">
                  <div :class="['w-2 h-2 rounded-full', service.active ? 'bg-emerald-400' : 'bg-red-400']"></div>
                  <span class="font-medium text-white">{{ service.name }}</span>
                </div>
                <div class="flex items-center gap-2">
                  <CheckCircle2 v-if="service.active" class="w-4 h-4 text-emerald-400" />
                  <XCircle v-else class="w-4 h-4 text-red-400" />
                  <span :class="service.active ? 'text-emerald-400' : 'text-red-400'" class="text-sm">{{ service.status }}</span>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Uptime -->
        <div class="mt-6 flex items-center justify-center gap-2 text-slate-500">
          <Clock class="w-4 h-4" />
          <span>运行时间: {{ systemStatus?.uptime }}</span>
        </div>
      </template>
    </div>
  </Layout>
</template>

<style scoped>
.btn-secondary { @apply px-4 py-2 bg-slate-700 hover:bg-slate-600 text-white rounded-lg text-sm transition flex items-center gap-2; }
</style>
