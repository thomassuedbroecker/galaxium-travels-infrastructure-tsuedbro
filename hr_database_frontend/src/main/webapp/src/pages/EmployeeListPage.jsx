import { useState, useEffect, useCallback } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { getAll, remove } from '../services/hrApiService'
import LoadingSpinner from '../components/LoadingSpinner'
import ErrorMessage from '../components/ErrorMessage'

/**
 * Employee list page.
 *
 * Features:
 * - Fetch and display all employees in a table
 * - Client-side search by name or department
 * - Navigate to detail / edit views
 * - Delete with confirmation dialog
 */
export default function EmployeeListPage() {
  const [employees, setEmployees] = useState([])
  const [filtered, setFiltered]   = useState([])
  const [query, setQuery]         = useState('')
  const [loading, setLoading]     = useState(true)
  const [error, setError]         = useState(null)
  const [deleting, setDeleting]   = useState(null) // id being deleted
  const navigate = useNavigate()

  const load = useCallback(() => {
    setLoading(true)
    setError(null)
    getAll()
      .then(data => { setEmployees(data); setFiltered(data) })
      .catch(err => setError(err.message))
      .finally(() => setLoading(false))
  }, [])

  useEffect(() => { load() }, [load])

  // Client-side filter
  useEffect(() => {
    const q = query.toLowerCase()
    if (!q) { setFiltered(employees); return }
    setFiltered(
      employees.filter(e =>
        `${e.first_name} ${e.last_name}`.toLowerCase().includes(q) ||
        (e.department || '').toLowerCase().includes(q) ||
        (e.position   || '').toLowerCase().includes(q)
      )
    )
  }, [query, employees])

  const handleDelete = (emp) => {
    if (!window.confirm(`Delete ${emp.first_name} ${emp.last_name}? This cannot be undone.`)) return
    setDeleting(emp.id)
    remove(emp.id)
      .then(() => load())
      .catch(err => { setError(err.message); setDeleting(null) })
  }

  if (loading) return <LoadingSpinner />

  return (
    <div>
      {/* ── Breadcrumb ── */}
      <nav className="breadcrumb">
        <Link to="/">Home</Link>
        <span className="sep">›</span>
        <span className="current">Employees</span>
      </nav>

      {/* ── Page header ── */}
      <div className="page-header">
        <h1>Employees</h1>
        <Link to="/employees/new" className="btn btn-primary">
          + Add Employee
        </Link>
      </div>

      <ErrorMessage message={error} onDismiss={() => setError(null)} />

      {/* ── Search ── */}
      <input
        className="search-bar"
        type="search"
        placeholder="Search by name, department, or position…"
        value={query}
        onChange={e => setQuery(e.target.value)}
        aria-label="Search employees"
      />

      {/* ── Table ── */}
      <div className="card" style={{ padding: 0, overflow: 'hidden' }}>
        {filtered.length === 0 ? (
          <div className="empty-state">
            <h3>No employees found</h3>
            <p>{query ? 'Try a different search term.' : 'Add the first employee to get started.'}</p>
          </div>
        ) : (
          <div className="table-wrapper">
            <table>
              <thead>
                <tr>
                  <th>Name</th>
                  <th>Department</th>
                  <th>Position</th>
                  <th>Hire Date</th>
                  <th>Salary</th>
                  <th style={{ width: '9rem' }}>Actions</th>
                </tr>
              </thead>
              <tbody>
                {filtered.map(emp => (
                  <tr key={emp.id}>
                    <td>
                      <Link to={`/employees/${emp.id}`} style={{ fontWeight: 500 }}>
                        {emp.first_name} {emp.last_name}
                      </Link>
                    </td>
                    <td>
                      <span className="badge badge-dept">{emp.department}</span>
                    </td>
                    <td>{emp.position}</td>
                    <td>{emp.hire_date}</td>
                    <td>${Number(emp.salary).toLocaleString()}</td>
                    <td>
                      <div style={{ display: 'flex', gap: '0.4rem' }}>
                        <button
                          className="btn btn-secondary btn-sm"
                          onClick={() => navigate(`/employees/${emp.id}/edit`)}
                          aria-label={`Edit ${emp.first_name}`}
                        >
                          Edit
                        </button>
                        <button
                          className="btn btn-danger btn-sm"
                          onClick={() => handleDelete(emp)}
                          disabled={deleting === emp.id}
                          aria-label={`Delete ${emp.first_name}`}
                        >
                          {deleting === emp.id ? '…' : 'Delete'}
                        </button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      <p style={{ marginTop: '0.75rem', fontSize: '0.8rem', color: 'var(--color-ink-soft)' }}>
        Showing {filtered.length} of {employees.length} employee{employees.length !== 1 ? 's' : ''}
      </p>
    </div>
  )
}
