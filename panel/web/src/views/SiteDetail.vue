<script setup lang="ts">
import { ref, onMounted, computed } from "vue"
import { useRoute, useRouter } from "vue-router"
import { api } from "../stores/auth"
import Layout from "../components/Layout.vue"
import {
  Globe, ArrowLeft, Power, PowerOff, Archive, Trash2,
  Loader2, CheckCircle, XCircle, Clock, Shield, ShieldCheck, ShieldX,
  Code, FileCode, Boxes, RefreshCw, ExternalLink, FileText, Settings,
  Save, AlertTriangle, ScrollText
} from "lucide-vue-next"

const route = useRoute()
const router = useRouter()

const domain = route.params.domain as string
const site = ref<any>(null)
const loading = ref(true)
const actionLoading = ref("")

// 当前 Tab
const activeTab = ref<'info' | 'nginx' | 'ssl' | 'logs'>('info')

// Nginx 配置
const nginxConfig = ref("")
const nginxLoading = ref(false)
const nginxSaving = ref(false)
const nginxError = ref("")

// SSL
const sslLoading = ref(false)
const sslEmail = ref("")

// 日志
const logs = ref<string[]>([])
const logsLoading = ref(false)
const logType = ref<'access' | 'error'>('access')

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

// 获取 Nginx 配置
async function fetchNginxConfig() {
  nginxLoading.value = true
  nginxError.value = ""
  try {
    const res = await api.get(`/sites/${domain}/nginx`)
    if (res.data.status) {
      nginxConfig.value = res.data.data.content
    }
  } catch (e: any) {
    nginxError.value = e.response?.data?.message || "Failed to load config"
  } finally {
    nginxLoading.value = false
  }
}

// 保存 Nginx 配置
async function saveNginxConfig() {
  nginxSaving.value = true
  nginxError.value = ""
  try {
    const res = await api.put(`/sites/${domain}/nginx`, { content: nginxConfig.value })
    if (res.data.status) {
      alert(res.data.message || "配置已保存")
      if (res.data.warning) {
        alert("警告: " + res.data.warning)
      }
    }
  } catch (e: any) {
    nginxError.value = e.response?.data?.message || "Failed to save config"
  } finally {
    nginxSaving.value = false
  }
}

// 申请 SSL 证书
async function requestSSL() {
  if (!confirm(`确定为 ${domain} 申请 Let's Encrypt 证书？`)) return

  sslLoading.value = true
  try {
    const res = await api.post(`/sites/${domain}/ssl`, { email: sslEmail.value || `admin@${domain}` })
    if (res.data.status) {
      alert("SSL 证书申请成功！")
      await fetchSite()
    } else {
      alert("申请失败: " + (res.data.error || res.data.message))
    }
  } catch (e: any) {
    alert("申请失败: " + (e.response?.data?.error || e.message))
  } finally {
    sslLoading.value = false
  }
}

// 续期 SSL
async function renewSSL() {
  if (!confirm(`确定续期 ${domain} 的 SSL 证书？`)) return

  sslLoading.value = true
  try {
    const res = await api.post(`/sites/${domain}/ssl/renew`)
    if (res.data.status) {
      alert("SSL 证书续期成功！")
      await fetchSite()
    } else {
      alert("续期失败: " + (res.data.error || res.data.message))
    }
  } catch (e: any) {
    alert("续期失败: " + (e.response?.data?.error || e.message))
  } finally {
    sslLoading.value = false
  }
}

// 获取日志
async function fetchLogs() {
  logsLoading.value = true
  try {
    const res = await api.get(`/sites/${domain}/logs?type=${logType.value}`)
    if (res.data.status) {
      logs.value = res.data.data.lines || []
    }
  } catch (e) {
    console.error("Failed to fetch logs:", e)
  } finally {
    logsLoading.value = false
  }
}

const typeInfo = computed(() => {
  const type = site.value?.type || "static"
  return siteTypes[type] ?? defaultTypeInfo
})

// 切换 Tab
function switchTab(tab: 'info' | 'nginx' | 'ssl' | 'logs') {
  activeTab.value = tab
  if (tab === 'nginx' && !nginxConfig.value) {
    fetchNginxConfig()
  } else if (tab === 'logs') {
    fetchLogs()
  }
}

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
                <span v-if="site.ssl_info?.enabled" class="flex items-center gap-1 text-emerald-400 text-xs">
                  <ShieldCheck class="w-3 h-3" />
                  SSL
                </span>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Tabs -->
      <div class="flex items-center gap-1 mb-6 bg-slate-800 rounded-lg p-1">
        <button
          @click="switchTab('info')"
          :class="['flex items-center gap-2 px-4 py-2 rounded-lg text-sm transition', activeTab === 'info' ? 'bg-slate-700 text-white' : 'text-slate-400 hover:text-white']"
        >
          <FileText class="w-4 h-4" />
          基本信息
        </button>
        <button
          @click="switchTab('nginx')"
          :class="['flex items-center gap-2 px-4 py-2 rounded-lg text-sm transition', activeTab === 'nginx' ? 'bg-slate-700 text-white' : 'text-slate-400 hover:text-white']"
        >
          <Settings class="w-4 h-4" />
          Nginx 配置
        </button>
        <button
          @click="switchTab('ssl')"
          :class="['flex items-center gap-2 px-4 py-2 rounded-lg text-sm transition', activeTab === 'ssl' ? 'bg-slate-700 text-white' : 'text-slate-400 hover:text-white']"
        >
          <Shield class="w-4 h-4" />
          SSL 证书
        </button>
        <button
          @click="switchTab('logs')"
          :class="['flex items-center gap-2 px-4 py-2 rounded-lg text-sm transition', activeTab === 'logs' ? 'bg-slate-700 text-white' : 'text-slate-400 hover:text-white']"
        >
          <ScrollText class="w-4 h-4" />
          访问日志
        </button>
      </div>

      <!-- Info Tab -->
      <div v-if="activeTab === 'info'" class="grid grid-cols-1 md:grid-cols-2 gap-6">
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

            <button
              @click="doAction('backup')"
              :disabled="!!actionLoading"
              class="w-full flex items-center justify-center gap-2 px-4 py-2.5 rounded-lg bg-blue-600 hover:bg-blue-700 text-white transition disabled:opacity-50"
            >
              <Loader2 v-if="actionLoading === 'backup'" class="w-4 h-4 animate-spin" />
              <Archive v-else class="w-4 h-4" />
              <span>创建备份</span>
            </button>

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

        <!-- Config Paths -->
        <div class="md:col-span-2 bg-slate-800 rounded-xl">
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
      </div>

      <!-- Nginx Config Tab -->
      <div v-if="activeTab === 'nginx'" class="bg-slate-800 rounded-xl">
        <div class="px-6 py-4 border-b border-slate-700/50 flex items-center justify-between">
          <h2 class="font-semibold text-white flex items-center gap-2">
            <Settings class="w-5 h-5 text-slate-400" />
            Nginx 配置
          </h2>
          <button
            @click="saveNginxConfig"
            :disabled="nginxSaving || nginxLoading"
            class="flex items-center gap-2 px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded-lg text-sm transition disabled:opacity-50"
          >
            <Loader2 v-if="nginxSaving" class="w-4 h-4 animate-spin" />
            <Save v-else class="w-4 h-4" />
            保存配置
          </button>
        </div>
        <div class="p-6">
          <div v-if="nginxLoading" class="flex items-center justify-center py-12">
            <Loader2 class="w-6 h-6 text-blue-500 animate-spin" />
          </div>
          <div v-else-if="nginxError" class="p-4 bg-red-500/10 border border-red-500/30 rounded-lg text-red-400">
            {{ nginxError }}
          </div>
          <div v-else>
            <textarea
              v-model="nginxConfig"
              class="w-full h-96 bg-slate-900 border border-slate-700 rounded-lg p-4 text-sm font-mono text-slate-300 focus:outline-none focus:ring-2 focus:ring-blue-500/50"
              spellcheck="false"
            ></textarea>
            <p class="mt-2 text-xs text-slate-500">
              修改后点击「保存配置」，系统将自动测试并重载 Nginx
            </p>
          </div>
        </div>
      </div>

      <!-- SSL Tab -->
      <div v-if="activeTab === 'ssl'" class="bg-slate-800 rounded-xl">
        <div class="px-6 py-4 border-b border-slate-700/50">
          <h2 class="font-semibold text-white flex items-center gap-2">
            <Shield class="w-5 h-5 text-slate-400" />
            SSL 证书管理
          </h2>
        </div>
        <div class="p-6">
          <div v-if="site.ssl_info?.enabled" class="space-y-6">
            <div class="p-4 bg-emerald-500/10 border border-emerald-500/30 rounded-lg">
              <div class="flex items-center gap-3 mb-3">
                <ShieldCheck class="w-6 h-6 text-emerald-400" />
                <span class="text-emerald-400 font-medium">SSL 已启用</span>
              </div>
              <div class="space-y-2 text-sm">
                <div class="flex justify-between">
                  <span class="text-slate-400">颁发机构</span>
                  <span class="text-white">{{ site.ssl_info.issuer || "Let's Encrypt" }}</span>
                </div>
                <div class="flex justify-between">
                  <span class="text-slate-400">生效日期</span>
                  <span class="text-white">{{ site.ssl_info.valid_from || '-' }}</span>
                </div>
                <div class="flex justify-between">
                  <span class="text-slate-400">过期日期</span>
                  <span class="text-white">{{ site.ssl_info.valid_to || '-' }}</span>
                </div>
              </div>
            </div>

            <button
              @click="renewSSL"
              :disabled="sslLoading"
              class="w-full flex items-center justify-center gap-2 px-4 py-2.5 rounded-lg bg-blue-600 hover:bg-blue-700 text-white transition disabled:opacity-50"
            >
              <Loader2 v-if="sslLoading" class="w-4 h-4 animate-spin" />
              <RefreshCw v-else class="w-4 h-4" />
              <span>续期证书</span>
            </button>
          </div>

          <div v-else class="space-y-6">
            <div class="p-4 bg-amber-500/10 border border-amber-500/30 rounded-lg">
              <div class="flex items-center gap-3 mb-2">
                <ShieldX class="w-6 h-6 text-amber-400" />
                <span class="text-amber-400 font-medium">SSL 未启用</span>
              </div>
              <p class="text-slate-400 text-sm">
                为您的站点申请免费的 Let's Encrypt SSL 证书，启用 HTTPS 加密访问
              </p>
            </div>

            <div>
              <label class="block text-sm text-slate-400 mb-2">邮箱地址（用于证书通知）</label>
              <input
                v-model="sslEmail"
                type="email"
                :placeholder="`admin@${domain}`"
                class="w-full px-4 py-2 bg-slate-900 border border-slate-700 rounded-lg text-white placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-blue-500/50"
              />
            </div>

            <div class="p-4 bg-slate-700/50 rounded-lg">
              <div class="flex items-start gap-3">
                <AlertTriangle class="w-5 h-5 text-amber-400 flex-shrink-0 mt-0.5" />
                <div class="text-sm text-slate-400">
                  <p class="mb-2">申请证书前请确保：</p>
                  <ul class="list-disc list-inside space-y-1">
                    <li>域名已正确解析到此服务器</li>
                    <li>80 端口已开放（用于验证）</li>
                    <li>站点已启用且可访问</li>
                  </ul>
                </div>
              </div>
            </div>

            <button
              @click="requestSSL"
              :disabled="sslLoading"
              class="w-full flex items-center justify-center gap-2 px-4 py-2.5 rounded-lg bg-emerald-600 hover:bg-emerald-700 text-white transition disabled:opacity-50"
            >
              <Loader2 v-if="sslLoading" class="w-4 h-4 animate-spin" />
              <ShieldCheck v-else class="w-4 h-4" />
              <span>申请 SSL 证书</span>
            </button>
          </div>
        </div>
      </div>

      <!-- Logs Tab -->
      <div v-if="activeTab === 'logs'" class="bg-slate-800 rounded-xl">
        <div class="px-6 py-4 border-b border-slate-700/50 flex items-center justify-between">
          <h2 class="font-semibold text-white flex items-center gap-2">
            <ScrollText class="w-5 h-5 text-slate-400" />
            访问日志
          </h2>
          <div class="flex items-center gap-2">
            <select
              v-model="logType"
              @change="fetchLogs"
              class="px-3 py-1.5 bg-slate-700 border border-slate-600 rounded-lg text-sm text-white focus:outline-none"
            >
              <option value="access">访问日志</option>
              <option value="error">错误日志</option>
            </select>
            <button
              @click="fetchLogs"
              :disabled="logsLoading"
              class="p-2 bg-slate-700 hover:bg-slate-600 rounded-lg transition"
            >
              <RefreshCw :class="['w-4 h-4 text-slate-400', logsLoading && 'animate-spin']" />
            </button>
          </div>
        </div>
        <div class="p-4">
          <div v-if="logsLoading" class="flex items-center justify-center py-12">
            <Loader2 class="w-6 h-6 text-blue-500 animate-spin" />
          </div>
          <div v-else-if="logs.length === 0" class="text-center py-12 text-slate-500">
            暂无日志记录
          </div>
          <div v-else class="bg-slate-900 rounded-lg p-4 max-h-96 overflow-auto">
            <pre class="text-xs font-mono text-slate-400 whitespace-pre-wrap break-all">{{ logs.join('\n') }}</pre>
          </div>
          <p class="mt-2 text-xs text-slate-500">
            显示最近 100 条日志记录
          </p>
        </div>
      </div>
    </template>
  </Layout>
</template>
