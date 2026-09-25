pragma Singleton
import QtQml

// Stub of the Quickshell singleton: only what the plugin reads. `env` answers
// undefined for everything, so an env-gated debug switch is simply off in tests.
QtObject {
  function env(name) { return undefined }
}
