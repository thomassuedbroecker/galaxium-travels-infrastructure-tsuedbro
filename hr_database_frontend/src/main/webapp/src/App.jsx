import { Routes, Route } from 'react-router-dom'
import Navbar from './components/Navbar'
import WelcomePage from './pages/WelcomePage'
import EmployeeListPage from './pages/EmployeeListPage'
import EmployeeDetailPage from './pages/EmployeeDetailPage'
import EmployeeFormPage from './pages/EmployeeFormPage'

/**
 * Root application component.
 *
 * Route map:
 *   /                    → WelcomePage (landing)
 *   /employees           → EmployeeListPage
 *   /employees/new       → EmployeeFormPage (create)
 *   /employees/:id       → EmployeeDetailPage
 *   /employees/:id/edit  → EmployeeFormPage (edit)
 */
export default function App() {
  return (
    <div className="page-shell">
      <Navbar />

      <main className="page-content">
        <Routes>
          <Route path="/" element={<WelcomePage />} />
          <Route path="/employees" element={<EmployeeListPage />} />
          {/* Create must come before :id to avoid shadowing */}
          <Route path="/employees/new" element={<EmployeeFormPage />} />
          <Route path="/employees/:id" element={<EmployeeDetailPage />} />
          <Route path="/employees/:id/edit" element={<EmployeeFormPage />} />
          {/* 404 fallback */}
          <Route path="*" element={
            <div className="card" style={{ textAlign: 'center', padding: '3rem' }}>
              <h2>404 — Page not found</h2>
              <p style={{ marginTop: '1rem', color: 'var(--color-ink-soft)' }}>
                The page you are looking for does not exist.
              </p>
              <a href="/" className="btn btn-primary" style={{ marginTop: '1.5rem' }}>
                Go to Home
              </a>
            </div>
          } />
        </Routes>
      </main>

      <footer className="footer">
        Galaxium Travels — HR Portal &nbsp;·&nbsp; Powered by Quarkus 3 + React
      </footer>
    </div>
  )
}
