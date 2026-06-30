/**
 * Dismissable error alert.
 *
 * @param {{ message: string, onDismiss?: () => void }} props
 */
export default function ErrorMessage({ message, onDismiss }) {
  if (!message) return null
  return (
    <div className="alert alert-error" role="alert">
      <strong>Error: </strong>{message}
      {onDismiss && (
        <button
          onClick={onDismiss}
          style={{
            marginLeft: '1rem',
            background: 'none',
            border: 'none',
            cursor: 'pointer',
            color: 'inherit',
            fontWeight: 600,
          }}
          aria-label="Dismiss error"
        >
          ✕
        </button>
      )}
    </div>
  )
}
