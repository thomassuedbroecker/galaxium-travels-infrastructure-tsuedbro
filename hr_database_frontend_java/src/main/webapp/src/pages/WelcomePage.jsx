import { useState, useEffect } from 'react'
import { Link } from 'react-router-dom'
import { getAll } from '../services/hrApiService'
import LoadingSpinner from '../components/LoadingSpinner'

/**
 * Welcome / landing page for the Galaxium Travels HR Portal.
 *
 * Shows a hero banner, quick-action cards, and live employee count.
 */
export default function WelcomePage() {
  const [employeeCount, setEmployeeCount] = useState(null)

  useEffect(() => {
    getAll()
      .then(data => setEmployeeCount(data.length))
      .catch(() => setEmployeeCount('—'))
  }, [])

  return (
    <div>
      {/* ── Hero banner ── */}
      <div className="welcome-hero">
        <p className="welcome-tagline">Galaxium Travels</p>
        <h1 className="welcome-title">
          Human Resources <em>Portal</em>
        </h1>
        <p className="welcome-subtitle">
          Manage your team across the galaxy. View, create, edit, and remove
          employee records with a single, unified interface.
        </p>
        <Link to="/employees" className="btn btn-gold btn-lg">
          View Employees →
        </Link>

        {/* ── Live stats ── */}
        <div className="welcome-stats">
          <div className="welcome-stat-item">
            <div className="stat-number">
              {employeeCount === null ? <LoadingSpinner /> : employeeCount}
            </div>
            <div className="stat-label">Active Employees</div>
          </div>
          <div className="welcome-stat-item">
            <div className="stat-number">5</div>
            <div className="stat-label">Departments</div>
          </div>
          <div className="welcome-stat-item">
            <div className="stat-number">5</div>
            <div className="stat-label">CRUD Operations</div>
          </div>
        </div>
      </div>

      {/* ── Quick-action cards ── */}
      <div className="welcome-cards">
        <Link to="/employees" className="welcome-card">
          <div className="welcome-card-icon">👥</div>
          <h3>Browse Employees</h3>
          <p>View the full employee directory with search and filter.</p>
        </Link>

        <Link to="/employees/new" className="welcome-card">
          <div className="welcome-card-icon">➕</div>
          <h3>Add Employee</h3>
          <p>Register a new team member in the HR database.</p>
        </Link>

        <a href="/q/swagger-ui" target="_blank" rel="noopener noreferrer" className="welcome-card">
          <div className="welcome-card-icon">📄</div>
          <h3>API Documentation</h3>
          <p>Explore the proxy REST API via Swagger UI.</p>
        </a>

        <a href="/q/health" target="_blank" rel="noopener noreferrer" className="welcome-card">
          <div className="welcome-card-icon">❤️</div>
          <h3>Health Check</h3>
          <p>Verify service liveness and readiness status.</p>
        </a>
      </div>
    </div>
  )
}
