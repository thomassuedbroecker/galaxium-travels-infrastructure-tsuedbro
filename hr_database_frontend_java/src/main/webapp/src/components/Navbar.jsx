import { NavLink } from 'react-router-dom'

/**
 * Top navigation bar with Galaxium Travels branding.
 * Uses React Router NavLink for active-state highlighting.
 */
export default function Navbar() {
  return (
    <nav className="navbar">
      <span className="navbar-brand">
        Galaxium Travels <span>| HR Portal</span>
      </span>
      <div className="navbar-links">
        <NavLink to="/" end>
          Home
        </NavLink>
        <NavLink to="/employees">
          Employees
        </NavLink>
        <NavLink to="/employees/new">
          + Add Employee
        </NavLink>
      </div>
    </nav>
  )
}
