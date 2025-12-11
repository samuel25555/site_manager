<script setup lang="ts">
import { ref, onMounted, computed } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore, api } from '../stores/auth'
import {
  Server, Cpu, MemoryStick, HardDrive, Globe, LogOut, RefreshCw,
  Activity, CheckCircle2, XCircle, Clock, LayoutDashboard
} from 'lucide-vue-next'

const router = useRouter()
const authStore = useAuthStore()

const systemStatus = ref<any>(null)
const services = ref<any[]>([])
const loading = ref(true)
const refreshing = ref(false)

function formatBytes(bytes: number) {
  if (bytes === 0) return '0 B'
  const k = 1024
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB']
  const i = Math.floor(Math.log(bytes) / Math.log(k))
  return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i]
}

function getCpuColor(usage: number) {
  if (usage < 50) return 'bg-emerald-500'
  if (usage < 80) return 'bg-amber-500'
  return 'bg-red-500'
}

function getMemoryColor(percent: number) {
  if (percent < 60) return 'bg-blue-500'
  if (percent < 85) return 'bg-amber-500'
  return 'bg-red-500'
}

function getDiskColor(percent: number) {
  if (percent < 70) return 'bg-purple-500'
  if (percent < 90) return 'bg-amber-500'
  return 'bg-red-500'
}

const activeServices = computed(() => services.value.filter(s => s.active).length)

async function fetchData() {
  try {
    const [statusRes, servicesRes] = await Promise.all([
      api.get('/system/status'),
      api.get('/system/services')
    ])

    if (statusRes.data.status) {
      systemStatus.value = statusRes.data.data
    }
    if (servicesRes.data.status) {
      services.value = servicesRes.data.data
    }
  } catch (e) {
    console.error('Failed to fetch data:', e)
  } finally {
    loading.value = false
    refreshing.value = false
  }
}

async function refresh() {
  refreshing.value = true
  await fetchData()
}

function handleLogout() {
  authStore.logout()
  router.push('/login')
}

onMounted(() => {
  fetchData()
  authStore.fetchMe()
})
</script>

<template>
  <div class="min-h-screen bg-slate-900">
    <!-- Header -->
    <header class="sticky top-0 z-50 bg-slate-900/80 backdrop-blur-xl border-b border-slate-800">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div class="flex items-center justify-between h-16">
          <!-- Logo -->
          <div class="flex items-center gap-3">
            <div class="w-9 h-9 rounded-lg bg-gradient-primary flex items-center justify-center">
              <Server class="w-5 h-5 text-white" />
            </div>
            <span class="text-lg font-semibold text-white">Site Manager</span>
          </div>

          <!-- Nav -->
          <nav class="flex items-center gap-1">
            <router-link to="/" class="nav-item nav-item-active">
              <LayoutDashboard class="w-4 h-4" />
              <span>Dashboard</span>
            </router-link>
            <router-link to="/sites" class="nav-item">
              <Globe class="w-4 h-4" />
              <span>Sites</span>
            </router-link>
          </nav>

          <!-- User -->
          <div class="flex items-center gap-4">
            <span class="text-sm text-slate-400">{{ authStore.user?.username }}</span>
            <button @click="handleLogout" class="btn btn-ghost py-1.5 px-3">
              <LogOut class="w-4 h-4" />
              <span>Logout</span>
            </button>
          </div>
        </div>
      </div>
    </header>

    <!-- Main -->
    <main class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <!-- Title -->
      <div class="flex items-center justify-between mb-8">
        <div>
          <h1 class="text-2xl font-bold text-white">Dashboard</h1>
          <p class="text-slate-400 mt-1">Monitor your server status</p>
        </div>
        <button @click="refresh" :disabled="refreshing" class="btn btn-ghost">
          <RefreshCw :class="['w-4 h-4', refreshing && 'animate-spin']" />
          <span>Refresh</span>
        </button>
      </div>

      <div v-if="loading" class="flex items-center justify-center py-20">
        <RefreshCw class="w-8 h-8 text-blue-500 animate-spin" />
      </div>

      <template v-else>
        <!-- System Stats -->
        <div class="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
          <!-- CPU -->
          <div class="card p-6 card-hover">
            <div class="flex items-center justify-between mb-4">
              <div class="flex items-center gap-3">
                <div class="w-10 h-10 rounded-lg bg-emerald-500/20 flex items-center justify-center">
                  <Cpu class="w-5 h-5 text-emerald-400" />
                </div>
                <div>
                  <p class="text-sm text-slate-400">CPU Usage</p>
                  <p class="text-2xl font-bold text-white">
                    {{ systemStatus?.cpu?.usage?.toFixed(1) }}%
                  </p>
                </div>
              </div>
            </div>
            <div class="progress-bar">
              <div
                :class="['progress-bar-fill', getCpuColor(systemStatus?.cpu?.usage || 0)]"
                :style="{ width: `${systemStatus?.cpu?.usage || 0}%` }"
              ></div>
            </div>
            <p class="text-xs text-slate-500 mt-2">{{ systemStatus?.cpu?.cores }} CPU cores</p>
          </div>

          <!-- Memory -->
          <div class="card p-6 card-hover">
            <div class="flex items-center justify-between mb-4">
              <div class="flex items-center gap-3">
                <div class="w-10 h-10 rounded-lg bg-blue-500/20 flex items-center justify-center">
                  <MemoryStick class="w-5 h-5 text-blue-400" />
                </div>
                <div>
                  <p class="text-sm text-slate-400">Memory</p>
                  <p class="text-2xl font-bold text-white">
                    {{ systemStatus?.memory?.percent?.toFixed(1) }}%
                  </p>
                </div>
              </div>
            </div>
            <div class="progress-bar">
              <div
                :class="['progress-bar-fill', getMemoryColor(systemStatus?.memory?.percent || 0)]"
                :style="{ width: `${systemStatus?.memory?.percent || 0}%` }"
              ></div>
            </div>
            <p class="text-xs text-slate-500 mt-2">
              {{ formatBytes(systemStatus?.memory?.used || 0) }} / {{ formatBytes(systemStatus?.memory?.total || 0) }}
            </p>
          </div>

          <!-- Disk -->
          <div class="card p-6 card-hover">
            <div class="flex items-center justify-between mb-4">
              <div class="flex items-center gap-3">
                <div class="w-10 h-10 rounded-lg bg-purple-500/20 flex items-center justify-center">
                  <HardDrive class="w-5 h-5 text-purple-400" />
                </div>
                <div>
                  <p class="text-sm text-slate-400">Disk Usage</p>
                  <p class="text-2xl font-bold text-white">
                    {{ systemStatus?.disk?.percent?.toFixed(1) }}%
                  </p>
                </div>
              </div>
            </div>
            <div class="progress-bar">
              <div
                :class="['progress-bar-fill', getDiskColor(systemStatus?.disk?.percent || 0)]"
                :style="{ width: `${systemStatus?.disk?.percent || 0}%` }"
              ></div>
            </div>
            <p class="text-xs text-slate-500 mt-2">
              {{ formatBytes(systemStatus?.disk?.used || 0) }} / {{ formatBytes(systemStatus?.disk?.total || 0) }}
            </p>
          </div>
        </div>

        <!-- Services -->
        <div class="card">
          <div class="px-6 py-4 border-b border-slate-700/50 flex items-center justify-between">
            <div class="flex items-center gap-3">
              <Activity class="w-5 h-5 text-slate-400" />
              <h2 class="text-lg font-semibold text-white">Services</h2>
            </div>
            <span class="badge badge-success">{{ activeServices }}/{{ services.length }} Active</span>
          </div>
          <div class="p-6">
            <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
              <div
                v-for="service in services"
                :key="service.name"
                class="flex items-center justify-between p-4 bg-slate-800/50 rounded-lg border border-slate-700/50"
              >
                <div class="flex items-center gap-3">
                  <div :class="['w-2 h-2 rounded-full', service.active ? 'bg-emerald-400' : 'bg-red-400']"></div>
                  <span class="font-medium text-white">{{ service.name }}</span>
                </div>
                <div class="flex items-center gap-2">
                  <CheckCircle2 v-if="service.active" class="w-4 h-4 text-emerald-400" />
                  <XCircle v-else class="w-4 h-4 text-red-400" />
                  <span :class="service.active ? 'text-emerald-400' : 'text-red-400'" class="text-sm">
                    {{ service.status }}
                  </span>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Uptime -->
        <div class="mt-6 flex items-center justify-center gap-2 text-slate-500">
          <Clock class="w-4 h-4" />
          <span>{{ systemStatus?.uptime }}</span>
        </div>
      </template>
    </main>
  </div>
</template>
