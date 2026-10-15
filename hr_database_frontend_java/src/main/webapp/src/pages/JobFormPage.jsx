import { useState, useEffect } from 'react'
import { useParams, useNavigate, Link } from 'react-router-dom'
import { getById, create, update } from '../services/jobsApiService'
import LoadingSpinner from '../components/LoadingSpinner'
import ErrorMessage from '../components/ErrorMessage'

const EMPTY_FORM = {
  job_title:        '',
  description:      '',
  required_skills:  '',
  salary_range:     '',
}

const REQUIRED_FIELDS = Object.keys(EMPTY_FORM)

/**
 * Job form page — handles both Create and Edit modes.
 *
 * - **Create** (`/jobs/new`): `id` param is undefined; submits POST
 * - **Edit**   (`/jobs/:id/edit`): fetches existing data; submits PUT
 *
 * Validates all required fields before submission.
 * On success, redirects to the job detail page (create) or back (edit).
 */
export default function JobFormPage() {
  const { id } = useParams()           // undefined on create
  const isEdit = Boolean(id)
  const navigate = useNavigate()

  const [form, setForm]         = useState(EMPTY_FORM)
  const [errors, setErrors]     = useState({})
  const [loading, setLoading]   = useState(isEdit)
  const [saving, setSaving]     = useState(false)
  const [apiError, setApiError] = useState(null)

  // Load existing data when editing
  useEffect(() => {
    if (!isEdit) return
    setLoading(true)
    getById(id)
      .then(job => {
        setForm({
          job_title:       job.job_title       || '',
          description:     job.description     || '',
          required_skills: job.required_skills || '',
          salary_range:    job.salary_range    || '',
        })
      })
      .catch(err => setApiError(err.message))
      .finally(() => setLoading(false))
  }, [id, isEdit])

  const handleChange = (e) => {
    const { name, value } = e.target
    setForm(prev => ({ ...prev, [name]: value }))
    if (errors[name]) setErrors(prev => ({ ...prev, [name]: undefined }))
  }

  const validate = () => {
    const next = {}
    REQUIRED_FIELDS.forEach(field => {
      if (!form[field].trim()) next[field] = 'This field is required'
    })
    return next
  }

  const handleSubmit = async (e) => {
    e.preventDefault()
    const validationErrors = validate()
    if (Object.keys(validationErrors).length > 0) {
      setErrors(validationErrors)
      return
    }
    setSaving(true)
    setApiError(null)
    try {
      if (isEdit) {
        await update(id, form)
        navigate(`/jobs/${id}`)
      } else {
        const created = await create(form)
        navigate(`/jobs/${created.id}`)
      }
    } catch (err) {
      setApiError(err.message)
      setSaving(false)
    }
  }

  if (loading) return <LoadingSpinner />

  const title  = isEdit ? 'Edit Job' : 'Add Job'
  const submit = isEdit ? 'Save Changes'  : 'Create Job'

  return (
    <div>
      {/* ── Breadcrumb ── */}
      <nav className="breadcrumb">
        <Link to="/">Home</Link>
        <span className="sep">›</span>
        <Link to="/jobs">Jobs</Link>
        <span className="sep">›</span>
        <span className="current">{title}</span>
      </nav>

      {/* ── Page header ── */}
      <div className="page-header">
        <h1>{title}</h1>
        <Link
          to={isEdit ? `/jobs/${id}` : '/jobs'}
          className="btn btn-secondary"
        >
          Cancel
        </Link>
      </div>

      <ErrorMessage message={apiError} onDismiss={() => setApiError(null)} />

      {/* ── Form card ── */}
      <div className="card">
        <form onSubmit={handleSubmit} noValidate>
          <div className="form-grid">
            <FormField
              label="Job Title"
              name="job_title"
              value={form.job_title}
              error={errors.job_title}
              onChange={handleChange}
              placeholder="e.g. Software Architect"
            />
            <FormField
              label="Description"
              name="description"
              value={form.description}
              error={errors.description}
              onChange={handleChange}
              placeholder="e.g. Designs system architecture…"
            />
            <FormField
              label="Required Skills"
              name="required_skills"
              value={form.required_skills}
              error={errors.required_skills}
              onChange={handleChange}
              placeholder="e.g. System design, Cloud, Leadership"
            />
            <FormField
              label="Salary Range"
              name="salary_range"
              value={form.salary_range}
              error={errors.salary_range}
              onChange={handleChange}
              placeholder="e.g. $130,000–$170,000"
            />

            {/* Actions row */}
            <div className="form-actions">
              <button
                type="submit"
                className="btn btn-primary"
                disabled={saving}
              >
                {saving ? 'Saving…' : submit}
              </button>
              <Link
                to={isEdit ? `/jobs/${id}` : '/jobs'}
                className="btn btn-secondary"
              >
                Cancel
              </Link>
            </div>
          </div>
        </form>
      </div>
    </div>
  )
}

/** Controlled form field with label and inline error. */
function FormField({ label, name, value, error, onChange, type = 'text', placeholder, min }) {
  return (
    <div className="form-group">
      <label htmlFor={name}>{label}</label>
      <input
        id={name}
        name={name}
        type={type}
        value={value}
        onChange={onChange}
        placeholder={placeholder}
        className={error ? 'error' : ''}
        min={min}
        aria-describedby={error ? `${name}-error` : undefined}
        required
      />
      {error && (
        <span id={`${name}-error`} className="field-error" role="alert">
          {error}
        </span>
      )}
    </div>
  )
}
