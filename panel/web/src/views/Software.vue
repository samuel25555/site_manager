<script setup lang="ts">
import { ref, onMounted, computed } from "vue"
import { api } from "../stores/auth"
import Layout from "../components/Layout.vue"
import {
  Package, Play, Square, RotateCcw, RefreshCw, CheckCircle, XCircle,
  Loader2, Server, Database, Code, Box, AlertTriangle
} from "lucide-vue-next"

interface Software {
  name: string
  version: string
  status: string
  description: string
  installed: boolean
}

const softwareList = ref<Software[]>([])
const loading = ref(true)
const actionLoading = ref<string>("")
const showStatusModal = ref(false)
const statusDetail = ref("")
const statusName = ref("")

// 软件图标映射
const iconMap: Record<string, any> = {
  nginx: Server,
  mysql: Database,
  mariadb: Database,
  postgresql: Database,
  mongodb: Database,
  redis: Database,
  php: Code,
  docker: Box,
  supervisor: Package
}

function getIcon(name: string) {
  for (const key in iconMap) {
    if (name.toLowerCase().includes(key)) {
      return iconMap[key]
    }
  }
  return Package
}

function getStatusColor(status: string) {
  if (status === "active") return "text-emerald-400"
  if (status === "inactive") return "text-amber-400"
  if (status === "not installed") return "text-slate-500"
  return "text-red-400"
}

function getStatusBg(status: string) {
  if (status === "active") return "bg-emerald-500/20"
  if (status === "inactive") return "bg-amber-500/20"
  return "bg-slate-700"
}

async function fetchSoftware() {
  try {
    const res = await api.get("/software")
    if (res.data.status) {
      softwareList.value = res.data.data || []
    }
  } catch (e) {
    console.error("Failed to fetch software:", e)
  } finally {
    loading.value = false
  }
}

async function doAction(name: string, action: string) {
  actionLoading.value = `${name}-${action}`
  try {
    const res = await api.post(`/software/${name}/${action}`)
    if (res.data.status) {
      await fetchSoftware()
    } else {
      alert("操作失败: " + (res.data.error || res.data.message))
    }
  } catch (e: any) {
    alert("操作失败: " + (e.response?.data?.error || e.message))
  } finally {
    actionLoading.value = ""
  }
}

async function viewStatus(name: string) {
  statusName.value = name
  statusDetail.value = "加载中..."
  showStatusModal.value = true
  
  try {
    const res = await api.get(`/software/${name}/status`)
    if (res.data.status) {
      statusDetail.value = res.data.data.output || "无状态信息"
    }
  } catch (e) {
    statusDetail.value = "获取状态失败"
  }
}

const installedCount = computed(() => softwareList.value.filter(s => s.installed).length)
const activeCount = computed(() => softwareList.value.filter(s => s.status === "active").length)

onMounted(fetchSoftware)
</script>

<template>
  <Layout title="软件管理">
    <template #actions>
      <button @click="fetchSoftware" :disabled="loading" class="p-2 rounded-lg bg-slate-700 hover:bg-slate-600 text-slate-400 hover:text-white transition">
        <RefreshCw :class="['w-4 h-4', loading && 'animate-spin']" />
      </button>
    </template>

    <div class="p-6">
      <!-- Stats -->
      <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
        <div class="bg-slate-800 rounded-lg p-4">
          <div class="flex items-center gap-3">
            <div class="w-10 h-10 rounded-lg bg-blue-500/20 flex items-center justify-center">
              <Package class="w-5 h-5 text-blue-400" />
            </div>
            <div>
              <p class="text-sm text-slate-400">总软件数</p>
              <p class="text-xl font-bold text-white">{{ softwareList.length }}</p>
            </div>
          </div>
        </div>
        <div class="bg-slate-800 rounded-lg p-4">
          <div class="flex items-center gap-3">
            <div class="w-10 h-10 rounded-lg bg-emerald-500/20 flex items-center justify-center">
              <CheckCircle class="w-5 h-5 text-emerald-400" />
            </div>
            <div>
              <p class="text-sm text-slate-400">已安装</p>
              <p class="text-xl font-bold text-white">{{ installedCount }}</p>
            </div>
          </div>
        </div>
        <div class="bg-slate-800 rounded-lg p-4">
          <div class="flex items-center gap-3">
            <div class="w-10 h-10 rounded-lg bg-green-500/20 flex items-center justify-center">
              <Play class="w-5 h-5 text-green-400" />
            </div>
            <div>
              <p class="text-sm text-slate-400">运行中</p>
              <p class="text-xl font-bold text-white">{{ activeCount }}</p>
            </div>
          </div>
        </div>
        <div class="bg-slate-800 rounded-lg p-4">
          <div class="flex items-center gap-3">
            <div class="w-10 h-10 rounded-lg bg-amber-500/20 flex items-center justify-center">
              <Square class="w-5 h-5 text-amber-400" />
            </div>
            <div>
              <p class="text-sm text-slate-400">已停止</p>
              <p class="text-xl font-bold text-white">{{ installedCount - activeCount }}</p>
            </div>
          </div>
        </div>
      </div>

      <!-- Loading -->
      <div v-if="loading" class="flex items-center justify-center py-20">
        <Loader2 class="w-8 h-8 text-blue-500 animate-spin" />
      </div>

      <!-- Software Grid -->
      <div v-else class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <div
          v-for="sw in softwareList"
          :key="sw.name"
          class="bg-slate-800 rounded-xl p-5"
          :class="{ 'opacity-50': !sw.installed }"
        >
          <div class="flex items-start justify-between mb-4">
            <div class="flex items-center gap-3">
              <div :class="['w-12 h-12 rounded-xl flex items-center justify-center', getStatusBg(sw.status)]">
                <component :is="getIcon(sw.name)" :class="['w-6 h-6', sw.installed ? getStatusColor(sw.status) : 'text-slate-500']" />
              </div>
              <div>
                <h3 class="font-semibold text-white">{{ sw.name }}</h3>
                <p class="text-xs text-slate-500">{{ sw.description }}</p>
              </div>
            </div>
          </div>

          <div class="flex items-center justify-between mb-4">
            <div class="flex items-center gap-2">
              <CheckCircle v-if="sw.status === 'active'" class="w-4 h-4 text-emerald-400" />
              <XCircle v-else-if="sw.installed" class="w-4 h-4 text-amber-400" />
              <AlertTriangle v-else class="w-4 h-4 text-slate-500" />
              <span :class="getStatusColor(sw.status)" class="text-sm">
                {{ sw.status === 'active' ? '运行中' : sw.status === 'inactive' ? '已停止' : '未安装' }}
              </span>
            </div>
            <span v-if="sw.version" class="text-xs text-slate-500 font-mono">v{{ sw.version }}</span>
          </div>

          <div v-if="sw.installed" class="flex items-center gap-2">
            <button
              v-if="sw.status !== 'active'"
              @click="doAction(sw.name, 'start')"
              :disabled="!!actionLoading"
              class="flex-1 flex items-center justify-center gap-1.5 px-3 py-2 bg-emerald-600 hover:bg-emerald-700 text-white rounded-lg text-sm transition disabled:opacity-50"
            >
              <Loader2 v-if="actionLoading === `${sw.name}-start`" class="w-4 h-4 animate-spin" />
              <Play v-else class="w-4 h-4" />
              启动
            </button>
            <button
              v-if="sw.status === 'active'"
              @click="doAction(sw.name, 'stop')"
              :disabled="!!actionLoading"
              class="flex-1 flex items-center justify-center gap-1.5 px-3 py-2 bg-amber-600 hover:bg-amber-700 text-white rounded-lg text-sm transition disabled:opacity-50"
            >
              <Loader2 v-if="actionLoading === `${sw.name}-stop`" class="w-4 h-4 animate-spin" />
              <Square v-else class="w-4 h-4" />
              停止
            </button>
            <button
              @click="doAction(sw.name, 'restart')"
              :disabled="!!actionLoading"
              class="flex items-center justify-center gap-1.5 px-3 py-2 bg-slate-700 hover:bg-slate-600 text-white rounded-lg text-sm transition disabled:opacity-50"
              title="重启"
            >
              <Loader2 v-if="actionLoading === `${sw.name}-restart`" class="w-4 h-4 animate-spin" />
              <RotateCcw v-else class="w-4 h-4" />
            </button>
            <button
              @click="viewStatus(sw.name)"
              class="flex items-center justify-center gap-1.5 px-3 py-2 bg-slate-700 hover:bg-slate-600 text-white rounded-lg text-sm transition"
              title="查看状态"
            >
              <Server class="w-4 h-4" />
            </button>
          </div>
          <div v-else class="text-center py-2 text-slate-500 text-sm">
            软件未安装
          </div>
        </div>
      </div>
    </div>

    <!-- Status Modal -->
    <Teleport to="body">
      <div v-if="showStatusModal" class="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-black/60 backdrop-blur-sm" @click="showStatusModal = false"></div>
        <div class="relative bg-slate-800 rounded-xl w-full max-w-2xl max-h-[80vh] flex flex-col">
          <div class="px-6 py-4 border-b border-slate-700 flex items-center justify-between">
            <h3 class="text-lg font-semibold text-white">{{ statusName }} 状态</h3>
            <button @click="showStatusModal = false" class="text-slate-400 hover:text-white">
              <XCircle class="w-5 h-5" />
            </button>
          </div>
          <div class="p-4 overflow-auto flex-1">
            <pre class="text-xs font-mono text-slate-300 whitespace-pre-wrap">{{ statusDetail }}</pre>
          </div>
        </div>
      </div>
    </Teleport>
  </Layout>
</template>
