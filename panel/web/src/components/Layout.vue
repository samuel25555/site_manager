<script setup lang="ts">
import { computed } from "vue"
import { useRouter, useRoute } from "vue-router"
import { useAuthStore } from "../stores/auth"
import {
  LayoutDashboard, Globe, FolderOpen, Terminal, Shield,
  LogOut, Server, ChevronRight, Package, FileText, Clock
} from "lucide-vue-next"

defineProps<{
  title?: string
  fullHeight?: boolean
}>()

const router = useRouter()
const route = useRoute()
const authStore = useAuthStore()

const menuItems = [
  { path: "/", name: "仪表盘", icon: LayoutDashboard },
  { path: "/sites", name: "站点管理", icon: Globe },
  { path: "/software", name: "软件管理", icon: Package },
  { path: "/files", name: "文件管理", icon: FolderOpen },
  { path: "/logs", name: "日志查看", icon: FileText },
  { path: "/cron", name: "计划任务", icon: Clock },
  { path: "/terminal", name: "终端", icon: Terminal },
  { path: "/firewall", name: "防火墙", icon: Shield },
]

const currentPath = computed(() => route.path)

function isActive(path: string) {
  if (path === "/") return currentPath.value === "/"
  return currentPath.value.startsWith(path)
}

function navigate(path: string) {
  router.push(path)
}

function handleLogout() {
  authStore.logout()
  router.push("/login")
}

const username = computed(() => authStore.user?.username || "admin")
const userInitial = computed(() => username.value[0]?.toUpperCase() || "A")
</script>

<template>
  <div class="flex h-screen bg-slate-900">
    <!-- 左侧菜单 -->
    <aside class="w-60 bg-slate-800 border-r border-slate-700 flex flex-col">
      <!-- Logo -->
      <div class="p-4 border-b border-slate-700">
        <div class="flex items-center gap-3">
          <div class="w-10 h-10 rounded-lg bg-gradient-to-br from-blue-500 to-purple-600 flex items-center justify-center">
            <Server class="w-6 h-6 text-white" />
          </div>
          <div>
            <h1 class="text-white font-bold">Site Manager</h1>
            <p class="text-slate-400 text-xs">服务器管理面板</p>
          </div>
        </div>
      </div>

      <!-- 菜单列表 -->
      <nav class="flex-1 p-3 space-y-1 overflow-y-auto">
        <button
          v-for="item in menuItems"
          :key="item.path"
          @click="navigate(item.path)"
          class="w-full flex items-center gap-3 px-3 py-2.5 rounded-lg text-left transition-all"
          :class="[isActive(item.path) ? 'bg-blue-600 text-white' : 'text-slate-400 hover:bg-slate-700 hover:text-white']"
        >
          <component :is="item.icon" class="w-5 h-5" />
          <span class="flex-1">{{ item.name }}</span>
          <ChevronRight v-if="isActive(item.path)" class="w-4 h-4" />
        </button>
      </nav>

      <!-- 用户信息 -->
      <div class="p-3 border-t border-slate-700">
        <div class="flex items-center justify-between px-3 py-2 rounded-lg bg-slate-700/50">
          <div class="flex items-center gap-2">
            <div class="w-8 h-8 rounded-full bg-blue-600 flex items-center justify-center text-white text-sm font-bold">
              {{ userInitial }}
            </div>
            <span class="text-slate-300 text-sm">{{ username }}</span>
          </div>
          <button @click="handleLogout" class="p-1.5 rounded hover:bg-slate-600 text-slate-400 hover:text-white transition" title="退出登录">
            <LogOut class="w-4 h-4" />
          </button>
        </div>
      </div>
    </aside>

    <!-- 主内容区域 -->
    <main class="flex-1 flex flex-col overflow-hidden">
      <!-- 标题栏 -->
      <header v-if="title || $slots.actions" class="flex items-center justify-between px-6 py-4 bg-slate-800/50 border-b border-slate-700">
        <h1 v-if="title" class="text-xl font-semibold text-white">{{ title }}</h1>
        <div v-if="$slots.actions" class="flex items-center gap-3">
          <slot name="actions" />
        </div>
      </header>

      <!-- 内容区 -->
      <div class="flex-1 overflow-auto" :class="[fullHeight ? 'p-4' : 'p-6']">
        <slot />
      </div>
    </main>
  </div>
</template>
