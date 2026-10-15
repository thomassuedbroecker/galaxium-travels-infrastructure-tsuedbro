import { useState, useEffect } from 'react'
import { useParams, Link, useNavigate } from 'react-router-dom'
import { getById, remove } from '../services/jobsApiService'
import LoadingSpinner from '../components/LoadingSpinner'
import ErrorMessage from '../components/ErrorMessage'

/**
 * Read-only job detail view.
 *
 * Renders all fields in a labelled card.
 * Provides "Edit" and "Delete" action buttons plus a "Back to list" link.
 */
export default function JobDetailPage() {
  const { id } = useParams()
  const navigate = useNavigate()

  const [job, setJob] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [deleting, setDeleting] = useState(false)

  useEffect(() => {
    setLoading(true)
    getById(id)
      .then(data => setJob(data))
      .catch(err => setError(err.message))
      .finally(() => setLoading(false))
  }, [id])

  const handleDelete = () => {
    if (!window.confirm(`Delete ${job.job_title}? This cannot be undone.`)) return
    setDeleting(true)
    remove(id)
      .then(() => navigate('/jobs'))
      .catch(err => { setError(err.message); setDeleting(false) })
  }

  if (loading) return <LoadingSpinner />
  if (error && !job) return (
    <div className="page-content">
      <ErrorMessage message={error} />
      <Link to="/jobs" className="btn btn-secondary" style={{ marginTop: '1rem' }}>← Back to Jobs</Link>
    </div>
  )

  const { job_title, description, required_skills, salary_range } = job

  return (
    <div>
      {/* ── Breadcrumb ── */}
      <nav className="breadcrumb">
        <Link to="/">Home</Link>
        <span className="sep">›</span>
        <Link to="/jobs">Jobs</Link>
        <span className="sep">›</span>
        <span className="current">{job_title}</span>
      </nav>

      {/* ── Page header ── */}
      <div className="page-header">
        <h1>{job_title}</h1>
        <div style={{ display: 'flex', gap: '0.5rem' }}>
          <Link to="/jobs" className="btn btn-secondary">← Back</Link>
          <Link to={`/jobs/${id}/edit`} className="btn btn-primary">Edit</Link>
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
          <Field label="Job Title"      value={job_title} />
          <Field label="Description"    value={description} />
          <Field label="Required Skills" value={required_skills} />
          <Field label="Salary Range"   value={salary_range} />
          <Field label="Job ID"         value={id} />
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
