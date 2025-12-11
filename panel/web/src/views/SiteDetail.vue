<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useAuthStore, api } from '../stores/auth'

const route = useRoute()
const router = useRouter()
const authStore = useAuthStore()

const domain = route.params.domain as string
const site = ref<any>(null)
const loading = ref(true)
const actionLoading = ref(false)

async function fetchSite() {
  try {
    const res = await api.get(`/sites/${domain}`)
    if (res.data.status) {
      site.value = res.data.data
    }
  } catch (e) {
    console.error('Failed to fetch site:', e)
  } finally {
    loading.value = false
  }
}

async function doAction(action: string) {
  actionLoading.value = true
  try {
    await api.post(`/sites/${domain}/${action}`)
    await fetchSite()
  } catch (e) {
    console.error(`Failed to ${action} site:`, e)
  } finally {
    actionLoading.value = false
  }
}

async function deleteSite() {
  if (!confirm(`Delete site ${domain}? This cannot be undone!`)) return

  actionLoading.value = true
  try {
    await api.delete(`/sites/${domain}`)
    router.push('/sites')
  } catch (e) {
    console.error('Failed to delete site:', e)
    actionLoading.value = false
  }
}

function handleLogout() {
  authStore.logout()
  router.push('/login')
}

onMounted(fetchSite)
</script>

<template>
  <div class="min-h-screen bg-gray-100">
    <!-- Header -->
    <header class="bg-white shadow">
      <div class="max-w-7xl mx-auto px-4 py-4 flex justify-between items-center">
        <h1 class="text-xl font-bold text-gray-800">Site Manager</h1>
        <div class="flex items-center gap-4">
          <router-link to="/" class="text-blue-600 hover:text-blue-800">Dashboard</router-link>
          <router-link to="/sites" class="text-blue-600 hover:text-blue-800">Sites</router-link>
          <button @click="handleLogout" class="text-red-600 hover:text-red-800">Logout</button>
        </div>
      </div>
    </header>

    <!-- Main Content -->
    <main class="max-w-7xl mx-auto px-4 py-8">
      <div class="mb-6">
        <router-link to="/sites" class="text-blue-600 hover:text-blue-800">&larr; Back to Sites</router-link>
      </div>

      <div v-if="loading" class="text-center py-8">Loading...</div>

      <div v-else-if="!site" class="bg-white rounded-lg shadow p-8 text-center text-gray-500">
        Site not found
      </div>

      <template v-else>
        <div class="bg-white rounded-lg shadow">
          <div class="px-6 py-4 border-b flex justify-between items-center">
            <h2 class="text-2xl font-bold text-gray-800">{{ domain }}</h2>
            <div class="flex gap-2">
              <button
                v-if="site.status === 'enabled'"
                @click="doAction('disable')"
                :disabled="actionLoading"
                class="px-3 py-1 bg-yellow-500 text-white rounded hover:bg-yellow-600 disabled:opacity-50"
              >
                Disable
              </button>
              <button
                v-else
                @click="doAction('enable')"
                :disabled="actionLoading"
                class="px-3 py-1 bg-green-500 text-white rounded hover:bg-green-600 disabled:opacity-50"
              >
                Enable
              </button>
              <button
                @click="doAction('backup')"
                :disabled="actionLoading"
                class="px-3 py-1 bg-blue-500 text-white rounded hover:bg-blue-600 disabled:opacity-50"
              >
                Backup
              </button>
              <button
                @click="deleteSite"
                :disabled="actionLoading"
                class="px-3 py-1 bg-red-500 text-white rounded hover:bg-red-600 disabled:opacity-50"
              >
                Delete
              </button>
            </div>
          </div>

          <div class="p-6">
            <dl class="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div>
                <dt class="text-sm font-medium text-gray-500">Type</dt>
                <dd class="mt-1 text-lg text-gray-900">{{ site.type || 'N/A' }}</dd>
              </div>
              <div>
                <dt class="text-sm font-medium text-gray-500">Status</dt>
                <dd class="mt-1">
                  <span
                    :class="site.status === 'enabled' ? 'bg-green-100 text-green-800' : 'bg-gray-100 text-gray-800'"
                    class="px-2 py-1 text-sm rounded-full"
                  >
                    {{ site.status }}
                  </span>
                </dd>
              </div>
              <div>
                <dt class="text-sm font-medium text-gray-500">Directory</dt>
                <dd class="mt-1 text-gray-900 font-mono text-sm">{{ site.path || 'N/A' }}</dd>
              </div>
              <div>
                <dt class="text-sm font-medium text-gray-500">Size</dt>
                <dd class="mt-1 text-gray-900">{{ site.size || 'N/A' }}</dd>
              </div>
              <div>
                <dt class="text-sm font-medium text-gray-500">SSL</dt>
                <dd class="mt-1 text-gray-900">{{ site.ssl || 'Not configured' }}</dd>
              </div>
              <div>
                <dt class="text-sm font-medium text-gray-500">Config</dt>
                <dd class="mt-1 text-gray-900 font-mono text-sm">{{ site.config || 'N/A' }}</dd>
              </div>
            </dl>
          </div>
        </div>
      </template>
    </main>
  </div>
</template>
