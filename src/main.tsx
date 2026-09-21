import { FormEvent, useEffect, useState } from 'react'
import { createClient, Session } from '@supabase/supabase-js'
import { createRoot } from 'react-dom/client'
import './styles.css'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

if (!supabaseUrl || !supabaseAnonKey) {
  throw new Error('Supabase environment variables are missing.')
}

const supabase = createClient(supabaseUrl, supabaseAnonKey)

function App() {
  const [session, setSession] = useState<Session | null>(null)
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [createAccount, setCreateAccount] = useState(false)
  const [message, setMessage] = useState('')
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => setSession(data.session))
    const { data: listener } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      setSession(nextSession)
    })
    return () => listener.subscription.unsubscribe()
  }, [])

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setBusy(true)
    setMessage('')
    const result = createAccount
      ? await supabase.auth.signUp({ email, password })
      : await supabase.auth.signInWithPassword({ email, password })
    setBusy(false)
    setMessage(result.error ? result.error.message : createAccount ? 'Konto erstellt. Du bist jetzt angemeldet.' : '')
  }

  if (session) {
    return (
      <main className="card">
        <p className="eyebrow">Lead Board</p>
        <h1>Willkommen</h1>
        <p>Angemeldet als <strong>{session.user.email}</strong>.</p>
        <p className="muted">Projekt- und Angebotsübersichten folgen in den Fach-Features.</p>
        <button onClick={() => supabase.auth.signOut()}>Abmelden</button>
      </main>
    )
  }

  return (
    <main className="card">
      <p className="eyebrow">Lead Board</p>
      <h1>{createAccount ? 'Lokales Konto anlegen' : 'Anmelden'}</h1>
      <form onSubmit={submit}>
        <label>E-Mail<input type="email" value={email} onChange={(event) => setEmail(event.target.value)} required /></label>
        <label>Passwort<input type="password" value={password} onChange={(event) => setPassword(event.target.value)} minLength={6} required /></label>
        {message && <p className="message">{message}</p>}
        <button disabled={busy}>{busy ? 'Bitte warten...' : createAccount ? 'Konto erstellen' : 'Anmelden'}</button>
      </form>
      <button className="link" onClick={() => { setCreateAccount(!createAccount); setMessage('') }}>
        {createAccount ? 'Bereits ein Konto? Anmelden' : 'Noch kein Konto? Konto erstellen'}
      </button>
    </main>
  )
}

createRoot(document.getElementById('root')!).render(<App />)
