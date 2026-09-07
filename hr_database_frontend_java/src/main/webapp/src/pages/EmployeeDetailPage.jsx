import { useState, useEffect } from 'react'
import { useParams, Link, useNavigate } from 'react-router-dom'
import { getById, remove } from '../services/hrApiService'
import LoadingSpinner from '../components/LoadingSpinner'
import ErrorMessage from '../components/ErrorMessage'

/**
 * Read-only employee detail view.
 *
 * Renders all fields in a labelled card.
 * Provides "Edit" and "Delete" action buttons plus a "Back to list" link.
 */
export default function EmployeeDetailPage() {
  const { id } = useParams()
  const navigate = useNavigate()

  const [employee, setEmployee] = useState(null)
  const [loading, setLoading]   = useState(true)
  const [error, setError]       = useState(null)
  const [deleting, setDeleting] = useState(false)

  useEffect(() => {
    setLoading(true)
    getById(id)
      .then(data => setEmployee(data))
      .catch(err => setError(err.message))
      .finally(() => setLoading(false))
  }, [id])

  const handleDelete = () => {
    if (!window.confirm(`Delete ${employee.first_name} ${employee.last_name}? This cannot be undone.`)) return
    setDeleting(true)
    remove(id)
      .then(() => navigate('/employees'))
      .catch(err => { setError(err.message); setDeleting(false) })
  }

  if (loading) return <LoadingSpinner />
  if (error && !employee) return (
    <div className="page-content">
      <ErrorMessage message={error} />
      <Link to="/employees" className="btn btn-secondary" style={{ marginTop: '1rem' }}>← Back to Employees</Link>
    </div>
  )

  const { first_name, last_name, department, position, hire_date, salary } = employee

  return (
    <div>
      {/* ── Breadcrumb ── */}
      <nav className="breadcrumb">
        <Link to="/">Home</Link>
        <span className="sep">›</span>
        <Link to="/employees">Employees</Link>
        <span className="sep">›</span>
        <span className="current">{first_name} {last_name}</span>
      </nav>

      {/* ── Page header ── */}
      <div className="page-header">
        <h1>{first_name} {last_name}</h1>
        <div style={{ display: 'flex', gap: '0.5rem' }}>
          <Link to="/employees" className="btn btn-secondary">← Back</Link>
          <Link to={`/employees/${id}/edit`} className="btn btn-primary">Edit</Link>
          <button
            className="btn btn-danger"
            onClick={handleDelete}
            disabled={deleting}
          >
            {deleting ? 'Deleting…' : 'Delete'}
          </button>
        </div>
      </div>

      <ErrorMessage message={error} onDismiss={() => setError(null)} />

      {/* ── Detail card ── */}
      <div className="card">
        <div className="detail-grid">
          <Field label="First Name"  value={first_name} />
          <Field label="Last Name"   value={last_name} />
          <Field label="Department"  value={department} />
          <Field label="Position"    value={position} />
          <Field label="Hire Date"   value={hire_date} />
          <Field label="Salary"      value={`$${Number(salary).toLocaleString()}`} />
          <Field label="Employee ID" value={id} />
        </div>
      </div>
    </div>
  )
}

/** Simple labelled field for the detail card. */
function Field({ label, value }) {
  return (
    <div className="detail-field">
      <label>{label}</label>
      <div className="value">{value || '—'}</div>
    </div>
  )
}
