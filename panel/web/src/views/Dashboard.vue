<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore, api } from '../stores/auth'

const router = useRouter()
const authStore = useAuthStore()

const systemStatus = ref<any>(null)
const services = ref<any[]>([])
const loading = ref(true)

function formatBytes(bytes: number) {
  if (bytes === 0) return '0 B'
  const k = 1024
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB']
  const i = Math.floor(Math.log(bytes) / Math.log(k))
  return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i]
}

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
  }
}

function handleLogout() {
  authStore.logout()
  router.push('/login')
}

onMounted(fetchData)
</script>

<template>
  <div class="min-h-screen bg-gray-100">
    <!-- Header -->
    <header class="bg-white shadow">
      <div class="max-w-7xl mx-auto px-4 py-4 flex justify-between items-center">
        <h1 class="text-xl font-bold text-gray-800">Site Manager</h1>
        <div class="flex items-center gap-4">
          <router-link to="/sites" class="text-blue-600 hover:text-blue-800">Sites</router-link>
          <span class="text-gray-600">{{ authStore.user?.username }}</span>
          <button @click="handleLogout" class="text-red-600 hover:text-red-800">Logout</button>
        </div>
      </div>
    </header>

    <!-- Main Content -->
    <main class="max-w-7xl mx-auto px-4 py-8">
      <div v-if="loading" class="text-center py-8">Loading...</div>
      
      <template v-else>
        <!-- System Status Cards -->
        <div class="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
          <!-- CPU -->
          <div class="bg-white rounded-lg shadow p-6">
            <h3 class="text-sm font-medium text-gray-500 mb-2">CPU Usage</h3>
            <div class="text-3xl font-bold text-gray-900">
              {{ systemStatus?.cpu?.usage?.toFixed(1) }}%
            </div>
            <div class="text-sm text-gray-500 mt-1">{{ systemStatus?.cpu?.cores }} cores</div>
            <div class="mt-3 bg-gray-200 rounded-full h-2">
              <div
                class="bg-blue-600 rounded-full h-2"
                :style="{ width: `${systemStatus?.cpu?.usage || 0}%` }"
              ></div>
            </div>
          </div>

          <!-- Memory -->
          <div class="bg-white rounded-lg shadow p-6">
            <h3 class="text-sm font-medium text-gray-500 mb-2">Memory Usage</h3>
            <div class="text-3xl font-bold text-gray-900">
              {{ systemStatus?.memory?.percent?.toFixed(1) }}%
            </div>
            <div class="text-sm text-gray-500 mt-1">
              {{ formatBytes(systemStatus?.memory?.used || 0) }} / {{ formatBytes(systemStatus?.memory?.total || 0) }}
            </div>
            <div class="mt-3 bg-gray-200 rounded-full h-2">
              <div
                class="bg-green-600 rounded-full h-2"
                :style="{ width: `${systemStatus?.memory?.percent || 0}%` }"
              ></div>
            </div>
          </div>

          <!-- Disk -->
          <div class="bg-white rounded-lg shadow p-6">
            <h3 class="text-sm font-medium text-gray-500 mb-2">Disk Usage</h3>
            <div class="text-3xl font-bold text-gray-900">
              {{ systemStatus?.disk?.percent?.toFixed(1) }}%
            </div>
            <div class="text-sm text-gray-500 mt-1">
              {{ formatBytes(systemStatus?.disk?.used || 0) }} / {{ formatBytes(systemStatus?.disk?.total || 0) }}
            </div>
            <div class="mt-3 bg-gray-200 rounded-full h-2">
              <div
                class="bg-yellow-600 rounded-full h-2"
                :style="{ width: `${systemStatus?.disk?.percent || 0}%` }"
              ></div>
            </div>
          </div>
        </div>

        <!-- Services -->
        <div class="bg-white rounded-lg shadow">
          <div class="px-6 py-4 border-b">
            <h2 class="text-lg font-semibold text-gray-800">Services</h2>
          </div>
          <div class="p-6">
            <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
              <div
                v-for="service in services"
                :key="service.name"
                class="flex items-center justify-between p-4 bg-gray-50 rounded-lg"
              >
                <span class="font-medium text-gray-700">{{ service.name }}</span>
                <span
                  :class="service.active ? 'bg-green-100 text-green-800' : 'bg-red-100 text-red-800'"
                  class="px-2 py-1 text-xs rounded-full"
                >
                  {{ service.status }}
                </span>
              </div>
            </div>
          </div>
        </div>

        <!-- Uptime -->
        <div class="mt-6 text-center text-gray-500">
          Uptime: {{ systemStatus?.uptime }}
        </div>
      </template>
    </main>
  </div>
</template>
