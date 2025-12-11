<script setup lang="ts">
import { ref, onMounted, computed } from "vue"
import { useRoute, useRouter } from "vue-router"
import { api } from "../stores/auth"
import Layout from "../components/Layout.vue"
import {
  Globe, ArrowLeft, Power, PowerOff, Archive, Trash2,
  Loader2, CheckCircle, XCircle, Clock,
  Code, FileCode, Boxes, RefreshCw, ExternalLink
} from "lucide-vue-next"

const route = useRoute()
const router = useRouter()

const domain = route.params.domain as string
const site = ref<any>(null)
const loading = ref(true)
const actionLoading = ref("")

const defaultTypeInfo = { label: "Static", icon: FileCode, color: "text-blue-400" }

const siteTypes: Record<string, typeof defaultTypeInfo> = {
  php: { label: "PHP", icon: Code, color: "text-purple-400" },
  static: defaultTypeInfo,
  node: { label: "Node.js", icon: Boxes, color: "text-green-400" },
  python: { label: "Python", icon: Code, color: "text-yellow-400" },
  proxy: { label: "Proxy", icon: Globe, color: "text-orange-400" }
}

async function fetchSite() {
  try {
    const res = await api.get(`/sites/${domain}`)
    if (res.data.status) {
      site.value = res.data.data
    }
  } catch (e) {
    console.error("Failed to fetch site:", e)
  } finally {
    loading.value = false
  }
}

async function doAction(action: string) {
  if (action === "delete") {
    if (!confirm(`确定删除站点 ${domain}？此操作不可恢复！`)) return
  }

  actionLoading.value = action
  try {
    if (action === "delete") {
      await api.delete(`/sites/${domain}`)
      router.push("/sites")
    } else {
      await api.post(`/sites/${domain}/${action}`)
      await fetchSite()
    }
  } catch (e) {
    console.error(`Failed to ${action} site:`, e)
    alert(`操作失败: ${action}`)
  } finally {
    actionLoading.value = ""
  }
}

const typeInfo = computed(() => {
  const type = site.value?.type || "static"
  return siteTypes[type] ?? defaultTypeInfo
})

onMounted(fetchSite)
</script>

<template>
  <Layout :title="domain">
    <template #actions>
      <router-link to="/sites" class="flex items-center gap-2 text-slate-400 hover:text-white transition-colors">
        <ArrowLeft class="w-4 h-4" />
        <span>返回站点列表</span>
      </router-link>
      <button @click="fetchSite" class="p-2 rounded-lg bg-slate-700 hover:bg-slate-600 text-slate-400 hover:text-white transition">
        <RefreshCw class="w-4 h-4" />
      </button>
    </template>

    <!-- Loading -->
    <div v-if="loading" class="flex items-center justify-center py-20">
      <Loader2 class="w-8 h-8 text-blue-500 animate-spin" />
    </div>

    <!-- Not Found -->
    <div v-else-if="!site" class="bg-slate-800 rounded-xl p-12 text-center">
      <XCircle class="w-12 h-12 text-red-400 mx-auto mb-4" />
      <h3 class="text-lg font-medium text-white mb-2">站点不存在</h3>
      <p class="text-slate-400 mb-6">站点 "{{ domain }}" 不存在</p>
      <router-link to="/sites" class="inline-flex items-center gap-2 px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded-lg transition">
        <ArrowLeft class="w-4 h-4" />
        <span>返回站点列表</span>
      </router-link>
    </div>

    <template v-else>
      <!-- Header Card -->
      <div class="bg-slate-800 rounded-xl p-6 mb-6">
        <div class="flex items-start justify-between">
          <div class="flex items-center gap-4">
            <div
              class="w-14 h-14 rounded-xl flex items-center justify-center"
              :class="[site.status === 'enabled' ? 'bg-emerald-500/20' : 'bg-slate-700']"
            >
              <component
                :is="typeInfo.icon"
                class="w-7 h-7"
                :class="[site.status === 'enabled' ? typeInfo.color : 'text-slate-500']"
              />
            </div>
            <div>
              <div class="flex items-center gap-3">
                <h1 class="text-2xl font-bold text-white">{{ site.domain }}</h1>
                <a :href="`http://${site.domain}`" target="_blank" class="text-slate-400 hover:text-blue-400 transition-colors">
                  <ExternalLink class="w-4 h-4" />
                </a>
              </div>
              <div class="flex items-center gap-3 mt-1">
                <span
                  class="px-2 py-0.5 rounded text-xs"
                  :class="[site.status === 'enabled' ? 'bg-emerald-500/20 text-emerald-400' : 'bg-amber-500/20 text-amber-400']"
                >
                  {{ site.status === 'enabled' ? '已启用' : '已禁用' }}
                </span>
                <span class="text-slate-500">{{ typeInfo.label }}</span>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Info Grid -->
      <div class="grid grid-cols-1 md:grid-cols-2 gap-6 mb-6">
        <!-- Site Info -->
        <div class="bg-slate-800 rounded-xl">
          <div class="px-6 py-4 border-b border-slate-700/50">
            <h2 class="font-semibold text-white">站点信息</h2>
          </div>
          <div class="p-6 space-y-4">
            <div class="flex items-center justify-between">
              <span class="text-slate-400">域名</span>
              <span class="text-white font-mono">{{ site.domain }}</span>
            </div>
            <div class="flex items-center justify-between">
              <span class="text-slate-400">类型</span>
              <span class="font-medium" :class="typeInfo.color">{{ typeInfo.label }}</span>
            </div>
            <div class="flex items-center justify-between">
              <span class="text-slate-400">状态</span>
              <div class="flex items-center gap-2">
                <CheckCircle v-if="site.status === 'enabled'" class="w-4 h-4 text-emerald-400" />
                <XCircle v-else class="w-4 h-4 text-amber-400" />
                <span :class="[site.status === 'enabled' ? 'text-emerald-400' : 'text-amber-400']">
                  {{ site.status === 'enabled' ? '已启用' : '已禁用' }}
                </span>
              </div>
            </div>
            <div class="flex items-start justify-between">
              <span class="text-slate-400">路径</span>
              <span class="text-white font-mono text-sm text-right">{{ site.path }}</span>
            </div>
          </div>
        </div>

        <!-- Quick Actions -->
        <div class="bg-slate-800 rounded-xl">
          <div class="px-6 py-4 border-b border-slate-700/50">
            <h2 class="font-semibold text-white">快捷操作</h2>
          </div>
          <div class="p-6 space-y-3">
            <!-- Enable/Disable -->
            <button
              @click="doAction(site.status === 'enabled' ? 'disable' : 'enable')"
              :disabled="!!actionLoading"
              class="w-full flex items-center justify-center gap-2 px-4 py-2.5 rounded-lg transition disabled:opacity-50"
              :class="[site.status === 'enabled'
                ? 'bg-slate-700 hover:bg-slate-600 text-slate-300'
                : 'bg-emerald-600 hover:bg-emerald-700 text-white']"
            >
              <Loader2 v-if="actionLoading === 'enable' || actionLoading === 'disable'" class="w-4 h-4 animate-spin" />
              <Power v-else-if="site.status !== 'enabled'" class="w-4 h-4" />
              <PowerOff v-else class="w-4 h-4" />
              <span>{{ site.status === 'enabled' ? '禁用站点' : '启用站点' }}</span>
            </button>

            <!-- Backup -->
            <button
              @click="doAction('backup')"
              :disabled="!!actionLoading"
              class="w-full flex items-center justify-center gap-2 px-4 py-2.5 rounded-lg bg-blue-600 hover:bg-blue-700 text-white transition disabled:opacity-50"
            >
              <Loader2 v-if="actionLoading === 'backup'" class="w-4 h-4 animate-spin" />
              <Archive v-else class="w-4 h-4" />
              <span>创建备份</span>
            </button>

            <!-- Delete -->
            <button
              @click="doAction('delete')"
              :disabled="!!actionLoading"
              class="w-full flex items-center justify-center gap-2 px-4 py-2.5 rounded-lg bg-red-600 hover:bg-red-700 text-white transition disabled:opacity-50"
            >
              <Loader2 v-if="actionLoading === 'delete'" class="w-4 h-4 animate-spin" />
              <Trash2 v-else class="w-4 h-4" />
              <span>删除站点</span>
            </button>
          </div>
        </div>
      </div>

      <!-- Additional Info -->
      <div class="bg-slate-800 rounded-xl">
        <div class="px-6 py-4 border-b border-slate-700/50 flex items-center gap-3">
          <Clock class="w-5 h-5 text-slate-400" />
          <h2 class="font-semibold text-white">配置路径</h2>
        </div>
        <div class="p-6">
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div class="p-4 bg-slate-700/50 rounded-lg">
              <p class="text-sm text-slate-400 mb-1">Nginx 配置</p>
              <p class="text-white font-mono text-sm">/srv/config/nginx/{{ site.domain }}.conf</p>
            </div>
            <div class="p-4 bg-slate-700/50 rounded-lg">
              <p class="text-sm text-slate-400 mb-1">访问日志</p>
              <p class="text-white font-mono text-sm">/srv/logs/nginx/{{ site.domain }}.access.log</p>
            </div>
            <div class="p-4 bg-slate-700/50 rounded-lg">
              <p class="text-sm text-slate-400 mb-1">错误日志</p>
              <p class="text-white font-mono text-sm">/srv/logs/nginx/{{ site.domain }}.error.log</p>
            </div>
            <div class="p-4 bg-slate-700/50 rounded-lg">
              <p class="text-sm text-slate-400 mb-1">网站根目录</p>
              <p class="text-white font-mono text-sm">{{ site.path }}</p>
            </div>
          </div>
        </div>
      </div>
    </template>
  </Layout>
</template>
