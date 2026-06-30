import { useState, useEffect } from 'react'
import { useParams, useNavigate, Link } from 'react-router-dom'
import { getById, create, update } from '../services/hrApiService'
import LoadingSpinner from '../components/LoadingSpinner'
import ErrorMessage from '../components/ErrorMessage'

const EMPTY_FORM = {
  first_name: '',
  last_name:  '',
  department: '',
  position:   '',
  hire_date:  '',
  salary:     '',
}

const REQUIRED_FIELDS = Object.keys(EMPTY_FORM)

/**
 * Employee form page — handles both Create and Edit modes.
 *
 * - **Create** (`/employees/new`): `id` param is undefined; submits POST
 * - **Edit**   (`/employees/:id/edit`): fetches existing data; submits PUT
 *
 * Validates all required fields before submission.
 * On success, redirects to the employee detail page (create) or back (edit).
 */
export default function EmployeeFormPage() {
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
      .then(emp => {
        setForm({
          first_name: emp.first_name || '',
          last_name:  emp.last_name  || '',
          department: emp.department || '',
          position:   emp.position   || '',
          hire_date:  emp.hire_date  || '',
          salary:     emp.salary     || '',
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
    if (form.salary && isNaN(Number(form.salary))) {
      next.salary = 'Salary must be a number'
    }
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
        navigate(`/employees/${id}`)
      } else {
        const created = await create(form)
        navigate(`/employees/${created.id}`)
      }
    } catch (err) {
      setApiError(err.message)
      setSaving(false)
    }
  }

  if (loading) return <LoadingSpinner />

  const title  = isEdit ? 'Edit Employee' : 'Add Employee'
  const submit = isEdit ? 'Save Changes'  : 'Create Employee'

  return (
    <div>
      {/* ── Breadcrumb ── */}
      <nav className="breadcrumb">
        <Link to="/">Home</Link>
        <span className="sep">›</span>
        <Link to="/employees">Employees</Link>
        <span className="sep">›</span>
        <span className="current">{title}</span>
      </nav>

      {/* ── Page header ── */}
      <div className="page-header">
        <h1>{title}</h1>
        <Link
          to={isEdit ? `/employees/${id}` : '/employees'}
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
              label="First Name"
              name="first_name"
              value={form.first_name}
              error={errors.first_name}
              onChange={handleChange}
              placeholder="e.g. Jane"
            />
            <FormField
              label="Last Name"
              name="last_name"
              value={form.last_name}
              error={errors.last_name}
              onChange={handleChange}
              placeholder="e.g. Smith"
            />
            <FormField
              label="Department"
              name="department"
              value={form.department}
              error={errors.department}
              onChange={handleChange}
              placeholder="e.g. Engineering"
            />
            <FormField
              label="Position"
              name="position"
              value={form.position}
              error={errors.position}
              onChange={handleChange}
              placeholder="e.g. Senior Developer"
            />
            <FormField
              label="Hire Date"
              name="hire_date"
              type="date"
              value={form.hire_date}
              error={errors.hire_date}
              onChange={handleChange}
            />
            <FormField
              label="Salary"
              name="salary"
              type="number"
              min="0"
              value={form.salary}
              error={errors.salary}
              onChange={handleChange}
              placeholder="e.g. 75000"
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
                to={isEdit ? `/employees/${id}` : '/employees'}
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
