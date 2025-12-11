<script setup lang="ts">
import { ref, onMounted, computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useAuthStore, api } from '../stores/auth'
import {
  Server, Globe, LogOut, ArrowLeft, Power, PowerOff, Archive, Trash2,
  LayoutDashboard, Loader2, CheckCircle, XCircle, Clock,
  Code, FileCode, Boxes, RefreshCw, ExternalLink
} from 'lucide-vue-next'

const route = useRoute()
const router = useRouter()
const authStore = useAuthStore()

const domain = route.params.domain as string
const site = ref<any>(null)
const loading = ref(true)
const actionLoading = ref('')

const defaultTypeInfo = { label: 'Static', icon: FileCode, color: 'text-blue-400' }

const siteTypes: Record<string, typeof defaultTypeInfo> = {
  php: { label: 'PHP', icon: Code, color: 'text-purple-400' },
  static: defaultTypeInfo,
  node: { label: 'Node.js', icon: Boxes, color: 'text-green-400' },
  python: { label: 'Python', icon: Code, color: 'text-yellow-400' },
  proxy: { label: 'Proxy', icon: Globe, color: 'text-orange-400' }
}

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
  if (action === 'delete') {
    if (!confirm(`Delete site ${domain}? This action cannot be undone!`)) return
  }

  actionLoading.value = action
  try {
    if (action === 'delete') {
      await api.delete(`/sites/${domain}`)
      router.push('/sites')
    } else {
      await api.post(`/sites/${domain}/${action}`)
      await fetchSite()
    }
  } catch (e) {
    console.error(`Failed to ${action} site:`, e)
    alert(`Failed to ${action} site`)
  } finally {
    actionLoading.value = ''
  }
}

function handleLogout() {
  authStore.logout()
  router.push('/login')
}

const typeInfo = computed(() => {
  const type = site.value?.type || 'static'
  return siteTypes[type] ?? defaultTypeInfo
})

onMounted(fetchSite)
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
      <!-- Back -->
      <router-link to="/sites" class="inline-flex items-center gap-2 text-slate-400 hover:text-white transition-colors mb-6">
        <ArrowLeft class="w-4 h-4" />
        <span>Back to Sites</span>
      </router-link>

      <!-- Loading -->
      <div v-if="loading" class="flex items-center justify-center py-20">
        <Loader2 class="w-8 h-8 text-blue-500 animate-spin" />
      </div>

      <!-- Not Found -->
      <div v-else-if="!site" class="card p-12 text-center">
        <XCircle class="w-12 h-12 text-red-400 mx-auto mb-4" />
        <h3 class="text-lg font-medium text-white mb-2">Site not found</h3>
        <p class="text-slate-400 mb-6">The site "{{ domain }}" does not exist</p>
        <router-link to="/sites" class="btn btn-primary mx-auto">
          <ArrowLeft class="w-4 h-4" />
          <span>Back to Sites</span>
        </router-link>
      </div>

      <template v-else>
        <!-- Header Card -->
        <div class="card p-6 mb-6">
          <div class="flex items-start justify-between">
            <div class="flex items-center gap-4">
              <div :class="['w-14 h-14 rounded-xl flex items-center justify-center', site.status === 'enabled' ? 'bg-emerald-500/20' : 'bg-slate-700']">
                <component :is="typeInfo.icon" :class="['w-7 h-7', site.status === 'enabled' ? typeInfo.color : 'text-slate-500']" />
              </div>
              <div>
                <div class="flex items-center gap-3">
                  <h1 class="text-2xl font-bold text-white">{{ site.domain }}</h1>
                  <a :href="`http://${site.domain}`" target="_blank" class="text-slate-400 hover:text-blue-400 transition-colors">
                    <ExternalLink class="w-4 h-4" />
                  </a>
                </div>
                <div class="flex items-center gap-3 mt-1">
                  <span :class="['badge', site.status === 'enabled' ? 'badge-success' : 'badge-warning']">
                    {{ site.status }}
                  </span>
                  <span class="text-slate-500">{{ typeInfo.label }}</span>
                </div>
              </div>
            </div>
            <button @click="fetchSite" class="btn btn-ghost py-1.5">
              <RefreshCw class="w-4 h-4" />
            </button>
          </div>
        </div>

        <!-- Info Grid -->
        <div class="grid grid-cols-1 md:grid-cols-2 gap-6 mb-6">
          <!-- Site Info -->
          <div class="card">
            <div class="px-6 py-4 border-b border-slate-700/50">
              <h2 class="font-semibold text-white">Site Information</h2>
            </div>
            <div class="p-6 space-y-4">
              <div class="flex items-center justify-between">
                <span class="text-slate-400">Domain</span>
                <span class="text-white font-mono">{{ site.domain }}</span>
              </div>
              <div class="flex items-center justify-between">
                <span class="text-slate-400">Type</span>
                <span :class="['font-medium', typeInfo.color]">{{ typeInfo.label }}</span>
              </div>
              <div class="flex items-center justify-between">
                <span class="text-slate-400">Status</span>
                <div class="flex items-center gap-2">
                  <CheckCircle v-if="site.status === 'enabled'" class="w-4 h-4 text-emerald-400" />
                  <XCircle v-else class="w-4 h-4 text-amber-400" />
                  <span :class="site.status === 'enabled' ? 'text-emerald-400' : 'text-amber-400'">{{ site.status }}</span>
                </div>
              </div>
              <div class="flex items-start justify-between">
                <span class="text-slate-400">Path</span>
                <span class="text-white font-mono text-sm text-right">{{ site.path }}</span>
              </div>
            </div>
          </div>

          <!-- Quick Actions -->
          <div class="card">
            <div class="px-6 py-4 border-b border-slate-700/50">
              <h2 class="font-semibold text-white">Quick Actions</h2>
            </div>
            <div class="p-6 space-y-3">
              <!-- Enable/Disable -->
              <button
                @click="doAction(site.status === 'enabled' ? 'disable' : 'enable')"
                :disabled="!!actionLoading"
                :class="site.status === 'enabled' ? 'btn-ghost' : 'btn-success'"
                class="btn w-full justify-center"
              >
                <Loader2 v-if="actionLoading === 'enable' || actionLoading === 'disable'" class="w-4 h-4 animate-spin" />
                <Power v-else-if="site.status !== 'enabled'" class="w-4 h-4" />
                <PowerOff v-else class="w-4 h-4" />
                <span>{{ site.status === 'enabled' ? 'Disable Site' : 'Enable Site' }}</span>
              </button>

              <!-- Backup -->
              <button
                @click="doAction('backup')"
                :disabled="!!actionLoading"
                class="btn btn-primary w-full justify-center"
              >
                <Loader2 v-if="actionLoading === 'backup'" class="w-4 h-4 animate-spin" />
                <Archive v-else class="w-4 h-4" />
                <span>Create Backup</span>
              </button>

              <!-- Delete -->
              <button
                @click="doAction('delete')"
                :disabled="!!actionLoading"
                class="btn btn-danger w-full justify-center"
              >
                <Loader2 v-if="actionLoading === 'delete'" class="w-4 h-4 animate-spin" />
                <Trash2 v-else class="w-4 h-4" />
                <span>Delete Site</span>
              </button>
            </div>
          </div>
        </div>

        <!-- Additional Info -->
        <div class="card">
          <div class="px-6 py-4 border-b border-slate-700/50 flex items-center gap-3">
            <Clock class="w-5 h-5 text-slate-400" />
            <h2 class="font-semibold text-white">Configuration Paths</h2>
          </div>
          <div class="p-6">
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div class="p-4 bg-slate-800/50 rounded-lg">
                <p class="text-sm text-slate-400 mb-1">Nginx Config</p>
                <p class="text-white font-mono text-sm">/srv/config/nginx/{{ site.domain }}.conf</p>
              </div>
              <div class="p-4 bg-slate-800/50 rounded-lg">
                <p class="text-sm text-slate-400 mb-1">Access Log</p>
                <p class="text-white font-mono text-sm">/srv/logs/nginx/{{ site.domain }}.access.log</p>
              </div>
              <div class="p-4 bg-slate-800/50 rounded-lg">
                <p class="text-sm text-slate-400 mb-1">Error Log</p>
                <p class="text-white font-mono text-sm">/srv/logs/nginx/{{ site.domain }}.error.log</p>
              </div>
              <div class="p-4 bg-slate-800/50 rounded-lg">
                <p class="text-sm text-slate-400 mb-1">Document Root</p>
                <p class="text-white font-mono text-sm">{{ site.path }}</p>
              </div>
            </div>
          </div>
        </div>
      </template>
    </main>
  </div>
</template>
