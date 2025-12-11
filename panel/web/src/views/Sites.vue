<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore, api } from '../stores/auth'
import {
  Server, Globe, LogOut, Plus, Trash2, Power, PowerOff, ExternalLink,
  LayoutDashboard, Loader2, FolderOpen, X, Code, FileCode, Boxes
} from 'lucide-vue-next'

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
  { value: 'php', label: 'PHP', icon: Code, color: 'text-purple-400' },
  { value: 'static', label: 'Static', icon: FileCode, color: 'text-blue-400' },
  { value: 'node', label: 'Node.js', icon: Boxes, color: 'text-green-400' },
  { value: 'python', label: 'Python', icon: Code, color: 'text-yellow-400' },
  { value: 'proxy', label: 'Proxy', icon: Globe, color: 'text-orange-400' }
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
    createError.value = e.response?.data?.error || e.response?.data?.message || 'Failed to create site'
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

function getTypeIcon(type: string) {
  const t = siteTypes.find(st => st.value === type)
  return t?.icon || Globe
}

function getTypeColor(type: string) {
  const t = siteTypes.find(st => st.value === type)
  return t?.color || 'text-slate-400'
}

function handleLogout() {
  authStore.logout()
  router.push('/login')
}

onMounted(fetchSites)
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
            <router-link to="/" class="nav-item">
              <LayoutDashboard class="w-4 h-4" />
              <span>Dashboard</span>
            </router-link>
            <router-link to="/sites" class="nav-item nav-item-active">
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
          <h1 class="text-2xl font-bold text-white">Sites</h1>
          <p class="text-slate-400 mt-1">Manage your websites and applications</p>
        </div>
        <button @click="showCreateModal = true" class="btn btn-primary">
          <Plus class="w-4 h-4" />
          <span>Create Site</span>
        </button>
      </div>

      <!-- Loading -->
      <div v-if="loading" class="flex items-center justify-center py-20">
        <Loader2 class="w-8 h-8 text-blue-500 animate-spin" />
      </div>

      <!-- Empty State -->
      <div v-else-if="sites.length === 0" class="card p-12 text-center">
        <div class="w-16 h-16 mx-auto mb-4 rounded-full bg-slate-800 flex items-center justify-center">
          <Globe class="w-8 h-8 text-slate-600" />
        </div>
        <h3 class="text-lg font-medium text-white mb-2">No sites yet</h3>
        <p class="text-slate-400 mb-6">Create your first site to get started</p>
        <button @click="showCreateModal = true" class="btn btn-primary mx-auto">
          <Plus class="w-4 h-4" />
          <span>Create Site</span>
        </button>
      </div>

      <!-- Sites Grid -->
      <div v-else class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <div
          v-for="site in sites"
          :key="site.domain"
          class="card p-5 card-hover group"
        >
          <div class="flex items-start justify-between mb-4">
            <div class="flex items-center gap-3">
              <div :class="['w-10 h-10 rounded-lg flex items-center justify-center', site.status === 'enabled' ? 'bg-emerald-500/20' : 'bg-slate-700']">
                <component :is="getTypeIcon(site.type)" :class="['w-5 h-5', site.status === 'enabled' ? getTypeColor(site.type) : 'text-slate-500']" />
              </div>
              <div>
                <router-link :to="`/sites/${site.domain}`" class="font-semibold text-white hover:text-blue-400 transition-colors flex items-center gap-1">
                  {{ site.domain }}
                  <ExternalLink class="w-3 h-3 opacity-0 group-hover:opacity-100 transition-opacity" />
                </router-link>
                <p class="text-sm text-slate-500">{{ site.type }}</p>
              </div>
            </div>
            <span :class="site.status === 'enabled' ? 'badge-success' : 'badge-warning'" class="badge">
              {{ site.status }}
            </span>
          </div>

          <div class="flex items-center gap-2 text-xs text-slate-500 mb-4">
            <FolderOpen class="w-3.5 h-3.5" />
            <span class="truncate">{{ site.path }}</span>
          </div>

          <div class="flex items-center gap-2 pt-4 border-t border-slate-700/50">
            <button
              @click="toggleSite(site.domain, site.status === 'enabled')"
              :class="site.status === 'enabled' ? 'btn-ghost' : 'btn-success'"
              class="btn flex-1 py-1.5 justify-center text-sm"
            >
              <Power v-if="site.status !== 'enabled'" class="w-3.5 h-3.5" />
              <PowerOff v-else class="w-3.5 h-3.5" />
              <span>{{ site.status === 'enabled' ? 'Disable' : 'Enable' }}</span>
            </button>
            <button
              @click="deleteSite(site.domain)"
              class="btn btn-ghost py-1.5 px-3 text-red-400 hover:text-red-300 hover:bg-red-500/10"
            >
              <Trash2 class="w-3.5 h-3.5" />
            </button>
          </div>
        </div>
      </div>
    </main>

    <!-- Create Modal -->
    <Teleport to="body">
      <div v-if="showCreateModal" class="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-black/60 backdrop-blur-sm" @click="showCreateModal = false"></div>
        <div class="relative card w-full max-w-lg animate-fadeIn">
          <div class="px-6 py-4 border-b border-slate-700/50 flex items-center justify-between">
            <h3 class="text-lg font-semibold text-white">Create New Site</h3>
            <button @click="showCreateModal = false" class="text-slate-400 hover:text-white transition-colors">
              <X class="w-5 h-5" />
            </button>
          </div>

          <form @submit.prevent="createSite" class="p-6 space-y-5">
            <!-- Domain -->
            <div>
              <label class="block text-sm font-medium text-slate-300 mb-2">Domain</label>
              <input
                v-model="newSite.domain"
                type="text"
                required
                placeholder="example.com"
                class="input"
              />
            </div>

            <!-- Type -->
            <div>
              <label class="block text-sm font-medium text-slate-300 mb-2">Site Type</label>
              <div class="grid grid-cols-5 gap-2">
                <button
                  v-for="t in siteTypes"
                  :key="t.value"
                  type="button"
                  @click="newSite.type = t.value"
                  :class="[
                    'flex flex-col items-center gap-1.5 p-3 rounded-lg border transition-all',
                    newSite.type === t.value
                      ? 'border-blue-500 bg-blue-500/10 text-blue-400'
                      : 'border-slate-700 hover:border-slate-600 text-slate-400'
                  ]"
                >
                  <component :is="t.icon" class="w-5 h-5" />
                  <span class="text-xs">{{ t.label }}</span>
                </button>
              </div>
            </div>

            <!-- PHP Version -->
            <div v-if="newSite.type === 'php'">
              <label class="block text-sm font-medium text-slate-300 mb-2">PHP Version</label>
              <select v-model="newSite.php" class="input">
                <option value="7.4">PHP 7.4</option>
                <option value="8.0">PHP 8.0</option>
                <option value="8.1">PHP 8.1</option>
                <option value="8.3">PHP 8.3</option>
              </select>
            </div>

            <!-- Port -->
            <div v-if="newSite.type === 'node' || newSite.type === 'python'">
              <label class="block text-sm font-medium text-slate-300 mb-2">Port</label>
              <input
                v-model.number="newSite.port"
                type="number"
                min="1000"
                max="65535"
                class="input"
              />
            </div>

            <!-- Target -->
            <div v-if="newSite.type === 'proxy'">
              <label class="block text-sm font-medium text-slate-300 mb-2">Target URL</label>
              <input
                v-model="newSite.target"
                type="text"
                placeholder="http://localhost:8080"
                class="input"
              />
            </div>

            <!-- Error -->
            <div v-if="createError" class="p-3 bg-red-500/10 border border-red-500/30 rounded-lg text-red-400 text-sm">
              {{ createError }}
            </div>

            <!-- Actions -->
            <div class="flex justify-end gap-3 pt-2">
              <button type="button" @click="showCreateModal = false" class="btn btn-ghost">
                Cancel
              </button>
              <button type="submit" :disabled="createLoading" class="btn btn-primary">
                <Loader2 v-if="createLoading" class="w-4 h-4 animate-spin" />
                <span>{{ createLoading ? 'Creating...' : 'Create Site' }}</span>
              </button>
            </div>
          </form>
        </div>
      </div>
    </Teleport>
  </div>
</template>
