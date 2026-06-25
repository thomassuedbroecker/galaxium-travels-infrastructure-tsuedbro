/**
 * hrApiService.js
 *
 * Thin fetch wrapper for the HR Database CRUD API.
 * All calls go to the Quarkus proxy at /api/employees (same-origin),
 * which forwards to the Python HR Database service.
 *
 * The base URL is set at Vite build time via the __HR_API_URL__ define.
 * In development (npm run dev) the Vite proxy rewrites /api → Quarkus :8088.
 */

// __HR_API_URL__ is replaced by Vite at build time; falls back to '/api' in dev
const BASE_URL = (typeof __HR_API_URL__ !== 'undefined' ? __HR_API_URL__ : '/api') + '/employees'

/**
 * Generic fetch helper — throws a descriptive Error on non-OK responses.
 * @param {string} url
 * @param {RequestInit} [options]
 * @returns {Promise<any>}
 */
async function request(url, options = {}) {
  const res = await fetch(url, {
    headers: { 'Content-Type': 'application/json', ...options.headers },
    ...options,
  })
  if (!res.ok) {
    let message = `HTTP ${res.status}`
    try {
      const body = await res.json()
      message = body.detail || body.message || body.error || message
    } catch (_) {
      // ignore parse error — use status text
      message = res.statusText || message
    }
    throw new Error(message)
  }
  // DELETE returns a JSON message object; everything else returns an employee/list
  const contentType = res.headers.get('content-type') || ''
  if (contentType.includes('application/json')) {
    return res.json()
  }
  return null
}

/**
 * Retrieve all employees.
 * @returns {Promise<Employee[]>}
 */
export function getAll() {
  return request(BASE_URL)
}

/**
 * Retrieve a single employee by ID.
 * @param {string} id
 * @returns {Promise<Employee>}
 */
export function getById(id) {
  return request(`${BASE_URL}/${id}`)
}

/**
 * Create a new employee.
 * @param {Omit<Employee, 'id'>} employee
 * @returns {Promise<Employee>}
 */
export function create(employee) {
  return request(BASE_URL, {
    method: 'POST',
    body: JSON.stringify(employee),
  })
}

/**
 * Update an existing employee.
 * @param {string} id
 * @param {Employee} employee
 * @returns {Promise<Employee>}
 */
export function update(id, employee) {
  return request(`${BASE_URL}/${id}`, {
    method: 'PUT',
    body: JSON.stringify(employee),
  })
}

/**
 * Delete an employee by ID.
 * @param {string} id
 * @returns {Promise<void>}
 */
export function remove(id) {
  return request(`${BASE_URL}/${id}`, { method: 'DELETE' })
}
