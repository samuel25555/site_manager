import { createRouter, createWebHistory } from "vue-router"
import { useAuthStore } from "../stores/auth"

const router = createRouter({
  history: createWebHistory(),
  routes: [
    {
      path: "/login",
      name: "login",
      component: () => import("../views/Login.vue")
    },
    {
      path: "/",
      name: "dashboard",
      component: () => import("../views/Dashboard.vue"),
      meta: { requiresAuth: true }
    },
    {
      path: "/sites",
      name: "sites",
      component: () => import("../views/Sites.vue"),
      meta: { requiresAuth: true }
    },
    {
      path: "/sites/:domain",
      name: "site-detail",
      component: () => import("../views/SiteDetail.vue"),
      meta: { requiresAuth: true }
    },
    {
      path: "/files",
      name: "files",
      component: () => import("../views/Files.vue"),
      meta: { requiresAuth: true }
    },
    {
      path: "/terminal",
      name: "terminal",
      component: () => import("../views/Terminal.vue"),
      meta: { requiresAuth: true }
    },
    {
      path: "/firewall",
      name: "firewall",
      component: () => import("../views/Firewall.vue"),
      meta: { requiresAuth: true }
    }
  ]
})

router.beforeEach((to, _from, next) => {
  const authStore = useAuthStore()
  
  if (to.meta.requiresAuth && !authStore.isAuthenticated) {
    next("/login")
  } else if (to.path === "/login" && authStore.isAuthenticated) {
    next("/")
  } else {
    next()
  }
})

export default router
