import { Socket } from 'phoenix'
import { getCsrfToken } from '@/lib/csrf'

let socket: Socket | null = null

export function getSocket(): Socket {
  if (socket) return socket

  const params: Record<string, string> = {}
  const token = getCsrfToken()
  if (token) params._csrf_token = token

  socket = new Socket('/socket', { params })
  socket.connect()
  return socket
}
