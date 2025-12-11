<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import Layout from "../components/Layout.vue"
import { useRouter } from 'vue-router'
import { useAuthStore, api } from '../stores/auth'
import {
  Globe, Plus, Trash2, Power, PowerOff, ExternalLink,
  Loader2, FolderOpen, X, Code, FileCode, Boxes,
  Search, AlertTriangle
} from 'lucide-vue-next'

const router = useRouter()
const authStore = useAuthStore()

const sites = ref<any[]>([])
const loading = ref(true)
const showCreateModal = ref(false)
const createLoading = ref(false)
const createError = ref('')

// 搜索
const searchQuery = ref('')

// 删除确认 Modal
const showDeleteModal = ref(false)
const deleteTarget = ref('')
const deleteLoading = ref(false)

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

// 过滤后的站点列表
const filteredSites = computed(() => {
  if (!searchQuery.value.trim()) return sites.value
  const q = searchQuery.value.toLowerCase()
  return sites.value.filter(site =>
    site.domain.toLowerCase().includes(q) ||
    site.type.toLowerCase().includes(q) ||
    site.path?.toLowerCase().includes(q)
  )
})

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

function confirmDelete(domain: string) {
  deleteTarget.value = domain
  showDeleteModal.value = true
}

async function deleteSite() {
  deleteLoading.value = true
  try {
    await api.delete(`/sites/${deleteTarget.value}`)
    showDeleteModal.value = false
    deleteTarget.value = ''
    await fetchSites()
  } catch (e) {
    console.error('Failed to delete site:', e)
  } finally {
    deleteLoading.value = false
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

// Keep authStore for potential future use
void authStore
void router

onMounted(fetchSites)
</script>

<template>
  <Layout>
  <div>

    <!-- Main -->
    <main class="p-6">
      <!-- Title & Actions -->
      <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4 mb-8">
        <div>
          <h1 class="text-2xl font-bold text-white">Sites</h1>
          <p class="text-slate-400 mt-1">Manage your websites and applications</p>
        </div>
        <div class="flex items-center gap-3">
          <!-- Search -->
          <div class="relative">
            <Search class="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-500 pointer-events-none" />
            <input
              v-model="searchQuery"
              type="text"
              placeholder="Search sites..."
              class="w-48 sm:w-64 pl-9 pr-4 py-2 bg-slate-800/50 border border-slate-700 rounded-lg text-white text-sm placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-blue-500/50 focus:border-blue-500 transition-all"
            />
          </div>
          <button @click="showCreateModal = true" class="btn btn-primary">
            <Plus class="w-4 h-4" />
            <span class="hidden sm:inline">Create Site</span>
          </button>
        </div>
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

      <!-- No Results -->
      <div v-else-if="filteredSites.length === 0" class="card p-12 text-center">
        <div class="w-16 h-16 mx-auto mb-4 rounded-full bg-slate-800 flex items-center justify-center">
          <Search class="w-8 h-8 text-slate-600" />
        </div>
        <h3 class="text-lg font-medium text-white mb-2">No results found</h3>
        <p class="text-slate-400">No sites match "{{ searchQuery }}"</p>
      </div>

      <!-- Sites Grid -->
      <div v-else class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <div
          v-for="site in filteredSites"
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

          <div class="flex items-center gap-2 text-xs text-slate-500 mb-4" :title="site.path">
            <FolderOpen class="w-3.5 h-3.5 flex-shrink-0" />
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
              @click="confirmDelete(site.domain)"
              class="btn btn-ghost py-1.5 px-3 text-red-400 hover:text-red-300 hover:bg-red-500/10"
            >
              <Trash2 class="w-3.5 h-3.5" />
            </button>
          </div>
        </div>
      </div>

      <!-- Site Count -->
      <div v-if="!loading && sites.length > 0" class="mt-6 text-center text-sm text-slate-500">
        Showing {{ filteredSites.length }} of {{ sites.length }} sites
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

    <!-- Delete Confirmation Modal -->
    <Teleport to="body">
      <div v-if="showDeleteModal" class="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-black/60 backdrop-blur-sm" @click="showDeleteModal = false"></div>
        <div class="relative card w-full max-w-md animate-fadeIn">
          <div class="p-6 text-center">
            <div class="w-14 h-14 mx-auto mb-4 rounded-full bg-red-500/20 flex items-center justify-center">
              <AlertTriangle class="w-7 h-7 text-red-400" />
            </div>
            <h3 class="text-lg font-semibold text-white mb-2">Delete Site</h3>
            <p class="text-slate-400 mb-2">Are you sure you want to delete</p>
            <p class="text-white font-mono mb-4">{{ deleteTarget }}</p>
            <p class="text-sm text-red-400 mb-6">This action cannot be undone!</p>

            <div class="flex justify-center gap-3">
              <button @click="showDeleteModal = false" class="btn btn-ghost px-6">
                Cancel
              </button>
              <button @click="deleteSite" :disabled="deleteLoading" class="btn btn-danger px-6">
                <Loader2 v-if="deleteLoading" class="w-4 h-4 animate-spin" />
                <Trash2 v-else class="w-4 h-4" />
                <span>{{ deleteLoading ? 'Deleting...' : 'Delete' }}</span>
              </button>
            </div>
          </div>
        </div>
      </div>
    </Teleport>
  </div>
  </Layout>
</template>
