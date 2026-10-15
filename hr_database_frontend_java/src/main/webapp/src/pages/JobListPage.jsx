import { useState, useEffect, useCallback } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { getAll, remove } from '../services/jobsApiService'
import LoadingSpinner from '../components/LoadingSpinner'
import ErrorMessage from '../components/ErrorMessage'

/**
 * Job list page.
 *
 * Features:
 * - Fetch and display all jobs in a table
 * - Client-side search by title or required skills
 * - Navigate to detail / edit views
 * - Delete with confirmation dialog
 */
export default function JobListPage() {
  const [jobs, setJobs] = useState([])
  const [filtered, setFiltered] = useState([])
  const [query, setQuery] = useState('')
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [deleting, setDeleting] = useState(null) // id being deleted
  const navigate = useNavigate()

  const load = useCallback(() => {
    setLoading(true)
    setError(null)
    getAll()
      .then(data => { setJobs(data); setFiltered(data) })
      .catch(err => setError(err.message))
      .finally(() => setLoading(false))
  }, [])

  useEffect(() => { load() }, [load])

  // Client-side filter
  useEffect(() => {
    const q = query.toLowerCase()
    if (!q) { setFiltered(jobs); return }
    setFiltered(
      jobs.filter(j =>
        (j.job_title || '').toLowerCase().includes(q) ||
        (j.description || '').toLowerCase().includes(q) ||
        (j.required_skills || '').toLowerCase().includes(q)
      )
    )
  }, [query, jobs])

  const handleDelete = (job) => {
    if (!window.confirm(`Delete ${job.job_title}? This cannot be undone.`)) return
    setDeleting(job.id)
    remove(job.id)
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
        <span className="current">Jobs</span>
      </nav>

      {/* ── Page header ── */}
      <div className="page-header">
        <h1>Jobs</h1>
        <Link to="/jobs/new" className="btn btn-primary">
          + Add Job
        </Link>
      </div>

      <ErrorMessage message={error} onDismiss={() => setError(null)} />

      {/* ── Search ── */}
      <input
        className="search-bar"
        type="search"
        placeholder="Search by title, description, or skills…"
        value={query}
        onChange={e => setQuery(e.target.value)}
        aria-label="Search jobs"
      />

      {/* ── Table ── */}
      <div className="card" style={{ padding: 0, overflow: 'hidden' }}>
        {filtered.length === 0 ? (
          <div className="empty-state">
            <h3>No jobs found</h3>
            <p>{query ? 'Try a different search term.' : 'Add the first job to get started.'}</p>
          </div>
        ) : (
          <div className="table-wrapper">
            <table>
              <thead>
                <tr>
                  <th>Job Title</th>
                  <th>Description</th>
                  <th>Salary Range</th>
                  <th style={{ width: '9rem' }}>Actions</th>
                </tr>
              </thead>
              <tbody>
                {filtered.map(job => (
                  <tr key={job.id}>
                    <td>
                      <Link to={`/jobs/${job.id}`} style={{ fontWeight: 500 }}>
                        {job.job_title}
                      </Link>
                    </td>
                    <td>{job.description}</td>
                    <td>{job.salary_range}</td>
                    <td>
                      <div style={{ display: 'flex', gap: '0.4rem' }}>
                        <button
                          className="btn btn-secondary btn-sm"
                          onClick={() => navigate(`/jobs/${job.id}/edit`)}
                          aria-label={`Edit ${job.job_title}`}
                        >
                          Edit
                        </button>
                        <button
                          className="btn btn-danger btn-sm"
                          onClick={() => handleDelete(job)}
                          disabled={deleting === job.id}
                          aria-label={`Delete ${job.job_title}`}
                        >
                          {deleting === job.id ? '…' : 'Delete'}
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
        Showing {filtered.length} of {jobs.length} job{jobs.length !== 1 ? 's' : ''}
      </p>
    </div>
  )
}
