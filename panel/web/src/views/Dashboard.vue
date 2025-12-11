<script setup lang="ts">
import { ref, onMounted, computed } from "vue"
import { api } from "../stores/auth"
import Layout from "../components/Layout.vue"
import { Cpu, MemoryStick, HardDrive, Activity, CheckCircle2, XCircle, Clock, RefreshCw } from "lucide-vue-next"

const systemStatus = ref<any>(null)
const services = ref<any[]>([])
const loading = ref(true)
const refreshing = ref(false)

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

async function fetchData() {
  try {
    const [statusRes, servicesRes] = await Promise.all([
      api.get("/system/status"),
      api.get("/system/services")
    ])
    if (statusRes.data.status) systemStatus.value = statusRes.data.data
    if (servicesRes.data.status) services.value = servicesRes.data.data
  } catch (e) {
    console.error("Failed to fetch data:", e)
  } finally {
    loading.value = false
    refreshing.value = false
  }
}

async function refresh() {
  refreshing.value = true
  await fetchData()
}

onMounted(fetchData)
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
        <button @click="refresh" :disabled="refreshing" class="btn-secondary">
          <RefreshCw :class="['w-4 h-4', refreshing && 'animate-spin']" />
          刷新
        </button>
      </div>

      <div v-if="loading" class="flex items-center justify-center py-20">
        <RefreshCw class="w-8 h-8 text-blue-500 animate-spin" />
      </div>

      <template v-else>
        <!-- System Stats -->
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
