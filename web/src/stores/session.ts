import { defineStore } from 'pinia'
import { computed, ref } from 'vue'
import { api, getToken, setToken } from '@/api/client'
import type { components } from '@/api/schema'

type Session = components['schemas']['Session']
type Account = components['schemas']['Account']
type UserProfile = components['schemas']['UserProfile']

const PROFILE_KEY = 'argosy.profileName'
const DEVICE_KEY = 'argosy.deviceName'

// The account/device session. Auth is a two-step flow (sign in → pair device);
// the per-device token is what authorizes every later call.
export const useSessionStore = defineStore('session', () => {
  const session = ref<Session | null>(null)
  const account = ref<Account | null>(null)
  const profiles = ref<UserProfile[]>([])
  const profileName = ref(localStorage.getItem(PROFILE_KEY) ?? '')
  const deviceName = ref(localStorage.getItem(DEVICE_KEY) ?? '')
  const ready = ref(false)

  const isAuthenticated = computed(() => session.value !== null)

  // Validate any persisted token against the server on first load. Only a real
  // 401 invalidates the token — a transient failure (server restart/deploy, a
  // proxy 5xx, a network blip) must NOT log the user out, so we keep the token
  // and retry a few times to ride out a brief outage.
  async function restore(): Promise<void> {
    if (ready.value) return
    if (getToken()) {
      for (let attempt = 0; attempt < 3; attempt++) {
        try {
          const { data, response } = await api.GET('/api/v1/auth/me')
          if (data) {
            session.value = data
            break
          }
          if (response?.status === 401) {
            setToken(null) // token genuinely revoked/expired
            break
          }
          // Any other non-200 (5xx/proxy error) is transient — fall through to retry.
        } catch {
          // Network error reaching the server — keep the token and retry.
        }
        await new Promise((r) => setTimeout(r, 400 * (attempt + 1)))
      }
    }
    ready.value = true
  }

  // Step 1: authenticate the account and list its profiles.
  async function login(username: string, password: string): Promise<UserProfile[]> {
    const { data, error } = await api.POST('/api/v1/auth/login', {
      body: { username, password },
    })
    if (error || !data) throw new Error('Invalid email or password.')
    account.value = data.account
    profiles.value = data.profiles
    return data.profiles
  }

  // Step 2: bind this device to a profile and capture the bearer token.
  async function pairDevice(
    username: string,
    password: string,
    userId: string,
    name: string,
  ): Promise<void> {
    const { data, error } = await api.POST('/api/v1/auth/devices', {
      body: { username, password, userId, deviceName: name, platform: 'web' },
    })
    if (error || !data) throw new Error('Could not pair this device.')
    setToken(data.token)
    deviceName.value = name
    localStorage.setItem(DEVICE_KEY, name)
    const picked = profiles.value.find((p) => p.id === userId)
    if (picked) {
      profileName.value = picked.name
      localStorage.setItem(PROFILE_KEY, picked.name)
    }
    ready.value = false
    await restore()
  }

  function logout(): void {
    setToken(null)
    localStorage.removeItem(PROFILE_KEY)
    localStorage.removeItem(DEVICE_KEY)
    session.value = null
    account.value = null
    profiles.value = []
    profileName.value = ''
    deviceName.value = ''
  }

  return {
    session,
    account,
    profiles,
    profileName,
    deviceName,
    ready,
    isAuthenticated,
    restore,
    login,
    pairDevice,
    logout,
  }
})
