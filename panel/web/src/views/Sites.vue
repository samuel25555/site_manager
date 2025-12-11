<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore, api } from '../stores/auth'

const router = useRouter()
const authStore = useAuthStore()

const sites = ref<any[]>([])
const loading = ref(true)
const showCreateModal = ref(false)
const createLoading = ref(false)
const createError = ref('')

const newSite = ref({
  domain: '',
  type: 'php',
  php: '8.3',
  port: 3000,
  target: ''
})

const siteTypes = [
  { value: 'php', label: 'PHP' },
  { value: 'static', label: 'Static' },
  { value: 'node', label: 'Node.js' },
  { value: 'python', label: 'Python' },
  { value: 'proxy', label: 'Proxy' }
]

async function fetchSites() {
  try {
    const res = await api.get('/sites')
    if (res.data.status) {
      sites.value = res.data.data || []
    }
  } catch (e) {
    console.error('Failed to fetch sites:', e)
  } finally {
    loading.value = false
  }
}

async function createSite() {
  createError.value = ''
  createLoading.value = true

  try {
    const payload: any = {
      domain: newSite.value.domain,
      type: newSite.value.type
    }

    if (newSite.value.type === 'php') {
      payload.php = newSite.value.php
    } else if (newSite.value.type === 'node' || newSite.value.type === 'python') {
      payload.port = newSite.value.port
    } else if (newSite.value.type === 'proxy') {
      payload.target = newSite.value.target
    }

    const res = await api.post('/sites', payload)
    if (res.data.status) {
      showCreateModal.value = false
      newSite.value = { domain: '', type: 'php', php: '8.3', port: 3000, target: '' }
      await fetchSites()
    } else {
      createError.value = res.data.message || 'Failed to create site'
    }
  } catch (e: any) {
    createError.value = e.response?.data?.message || 'Failed to create site'
  } finally {
    createLoading.value = false
  }
}

async function deleteSite(domain: string) {
  if (!confirm(`Delete site ${domain}? This cannot be undone!`)) return

  try {
    await api.delete(`/sites/${domain}`)
    await fetchSites()
  } catch (e) {
    console.error('Failed to delete site:', e)
  }
}

async function toggleSite(domain: string, isEnabled: boolean) {
  try {
    const action = isEnabled ? 'disable' : 'enable'
    await api.post(`/sites/${domain}/${action}`)
    await fetchSites()
  } catch (e) {
    console.error('Failed to toggle site:', e)
  }
}

function handleLogout() {
  authStore.logout()
  router.push('/login')
}

onMounted(fetchSites)
</script>

<template>
  <div class="min-h-screen bg-gray-100">
    <!-- Header -->
    <header class="bg-white shadow">
      <div class="max-w-7xl mx-auto px-4 py-4 flex justify-between items-center">
        <h1 class="text-xl font-bold text-gray-800">Site Manager</h1>
        <div class="flex items-center gap-4">
          <router-link to="/" class="text-blue-600 hover:text-blue-800">Dashboard</router-link>
          <router-link to="/sites" class="text-blue-600 hover:text-blue-800 font-semibold">Sites</router-link>
          <button @click="handleLogout" class="text-red-600 hover:text-red-800">Logout</button>
        </div>
      </div>
    </header>

    <!-- Main Content -->
    <main class="max-w-7xl mx-auto px-4 py-8">
      <div class="flex justify-between items-center mb-6">
        <h2 class="text-2xl font-bold text-gray-800">Sites</h2>
        <button
          @click="showCreateModal = true"
          class="px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700"
        >
          + Create Site
        </button>
      </div>

      <div v-if="loading" class="text-center py-8">Loading...</div>

      <div v-else-if="sites.length === 0" class="bg-white rounded-lg shadow p-8 text-center text-gray-500">
        No sites yet. Create your first site!
      </div>

      <div v-else class="bg-white rounded-lg shadow overflow-hidden">
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-50">
            <tr>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Domain</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Type</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Status</th>
              <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">Actions</th>
            </tr>
          </thead>
          <tbody class="bg-white divide-y divide-gray-200">
            <tr v-for="site in sites" :key="site.domain">
              <td class="px-6 py-4">
                <router-link :to="`/sites/${site.domain}`" class="text-blue-600 hover:text-blue-800 font-medium">
                  {{ site.domain }}
                </router-link>
              </td>
              <td class="px-6 py-4 text-gray-500">{{ site.type }}</td>
              <td class="px-6 py-4">
                <span
                  :class="site.status === 'enabled' ? 'bg-green-100 text-green-800' : 'bg-gray-100 text-gray-800'"
                  class="px-2 py-1 text-xs rounded-full"
                >
                  {{ site.status }}
                </span>
              </td>
              <td class="px-6 py-4 text-right space-x-2">
                <button
                  @click="toggleSite(site.domain, site.status === 'enabled')"
                  class="text-sm text-blue-600 hover:text-blue-800"
                >
                  {{ site.status === 'enabled' ? 'Disable' : 'Enable' }}
                </button>
                <button
                  @click="deleteSite(site.domain)"
                  class="text-sm text-red-600 hover:text-red-800"
                >
                  Delete
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </main>

    <!-- Create Modal -->
    <div v-if="showCreateModal" class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center p-4">
      <div class="bg-white rounded-lg shadow-xl w-full max-w-md">
        <div class="px-6 py-4 border-b flex justify-between items-center">
          <h3 class="text-lg font-semibold">Create Site</h3>
          <button @click="showCreateModal = false" class="text-gray-500 hover:text-gray-700 text-2xl">&times;</button>
        </div>

        <form @submit.prevent="createSite" class="p-6 space-y-4">
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">Domain</label>
            <input
              v-model="newSite.domain"
              type="text"
              required
              placeholder="example.com"
              class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
            />
          </div>

          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">Type</label>
            <select
              v-model="newSite.type"
              class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
            >
              <option v-for="t in siteTypes" :key="t.value" :value="t.value">{{ t.label }}</option>
            </select>
          </div>

          <div v-if="newSite.type === 'php'">
            <label class="block text-sm font-medium text-gray-700 mb-1">PHP Version</label>
            <select
              v-model="newSite.php"
              class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
            >
              <option value="7.4">7.4</option>
              <option value="8.0">8.0</option>
              <option value="8.1">8.1</option>
              <option value="8.3">8.3</option>
            </select>
          </div>

          <div v-if="newSite.type === 'node' || newSite.type === 'python'">
            <label class="block text-sm font-medium text-gray-700 mb-1">Port</label>
            <input
              v-model.number="newSite.port"
              type="number"
              min="1000"
              max="65535"
              class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
            />
          </div>

          <div v-if="newSite.type === 'proxy'">
            <label class="block text-sm font-medium text-gray-700 mb-1">Target URL</label>
            <input
              v-model="newSite.target"
              type="text"
              placeholder="http://localhost:8080"
              class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
            />
          </div>

          <div v-if="createError" class="text-red-500 text-sm">{{ createError }}</div>

          <div class="flex justify-end gap-2">
            <button
              type="button"
              @click="showCreateModal = false"
              class="px-4 py-2 border border-gray-300 rounded-md hover:bg-gray-50"
            >
              Cancel
            </button>
            <button
              type="submit"
              :disabled="createLoading"
              class="px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 disabled:opacity-50"
            >
              {{ createLoading ? 'Creating...' : 'Create' }}
            </button>
          </div>
        </form>
      </div>
    </div>
  </div>
</template>
